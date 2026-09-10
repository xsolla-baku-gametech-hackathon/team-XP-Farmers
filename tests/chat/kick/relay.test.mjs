import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { createRelay, verifyWebhook, chatMessage } from '../../../addons/streamer_mode/chat/kick/relay/server.mjs';

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = publicKey.export({ type: 'spki', format: 'pem' });
function signed(payload, time = new Date().toISOString()) {
  const raw = Buffer.from(JSON.stringify(payload));
  const headers = { 'kick-event-message-id': 'delivery-id', 'kick-event-message-timestamp': time,
    'kick-event-type': 'chat.message.sent', 'kick-event-version': '1' };
  headers['kick-event-signature'] = sign('RSA-SHA256', Buffer.concat([Buffer.from(`delivery-id.${time}.`), raw]), privateKey).toString('base64');
  return { raw, headers };
}
const event = id => ({ message_id: id, broadcaster: { user_id: 42 }, sender: { username: 'Zarifa235' }, content: 'Salam [emote:123:HELLO] <b>literal</b>' });

test('Kick signatures reject tampering and stale deliveries', () => {
  const { raw, headers } = signed(event('1'));
  assert.equal(verifyWebhook(headers, raw, pem), true);
  assert.equal(verifyWebhook(headers, Buffer.from('{}'), pem), false);
  assert.equal(verifyWebhook({}, raw, pem), false);
  const stale = signed(event('1'), new Date(Date.now() - 600000).toISOString());
  assert.equal(verifyWebhook(stale.headers, stale.raw, pem), false);
  assert.equal(chatMessage(event('1')).text, 'Salam HELLO <b>literal</b>');
  assert.equal(chatMessage({ content: 'missing channel' }), null);
});

test('OAuth, isolated sessions, signed delivery, deduplication, bounded history and disconnect', async t => {
  let subscriptions = 0;
  const fakeFetch = async (url, options) => {
    if (url.endsWith('/oauth/token')) {
      assert.equal(options.body.get('grant_type'), 'authorization_code');
      assert.ok(options.body.get('code_verifier'));
      return Response.json({ access_token: 'PRIVATE-ACCESS', refresh_token: 'PRIVATE-REFRESH', expires_in: 3600 });
    }
    if (url.endsWith('/users')) return Response.json({ data: [{ user_id: 42, name: 'My channel' }] });
    if (url.includes('/events/subscriptions?')) return Response.json({ data: [] });
    if (url.endsWith('/events/subscriptions')) {
      subscriptions++;
      assert.deepEqual(JSON.parse(options.body), { events: [{ name: 'chat.message.sent', version: 1 }], method: 'webhook' });
      return Response.json({ data: [{ name: 'chat.message.sent', subscription_id: 'sub', version: 1 }] });
    }
    throw new Error('Unexpected external request');
  };
  const server = createRelay({ clientId: 'test-app', clientSecret: 'PRIVATE-SECRET', publicURL: 'https://relay.example', publicKey: pem }, fakeFetch);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(`${base}/session`)).status, 401);
  assert.equal((await fetch(`${base}/sessions`, { method: 'POST', headers: { Origin: 'https://other.example' } })).status, 403);
  const login = await (await fetch(`${base}/sessions`, { method: 'POST' })).json();
  assert.ok(login.session_key);
  const authorize = new URL(login.authorize_url);
  assert.equal(authorize.hostname, 'id.kick.com');
  assert.equal(authorize.searchParams.get('code_challenge_method'), 'S256');
  assert.equal(authorize.searchParams.get('scope'), 'user:read events:subscribe');
  const auth = { Authorization: `Bearer ${login.session_key}` };
  assert.equal((await (await fetch(`${base}/session`, { headers: auth })).json()).state, 'connecting');
  const callback = `${base}/oauth/callback?code=code&state=${authorize.searchParams.get('state')}`;
  assert.equal((await fetch(callback)).status, 200);
  assert.equal((await fetch(callback)).status, 400, 'OAuth state cannot be replayed');
  assert.equal(subscriptions, 1);
  const pending = await (await fetch(`${base}/sessions`, { method: 'POST' })).json();
  const post = async payload => {
    const { raw, headers } = signed(payload);
    return fetch(`${base}/webhooks/kick`, { method: 'POST', headers, body: raw });
  };
  assert.equal((await post(event('one'))).status, 200);
  await post(event('one'));
  await post({ ...event('other'), broadcaster: { user_id: 99 } });
  let snapshot = await (await fetch(`${base}/session`, { headers: auth })).json();
  assert.equal(snapshot.state, 'connected');
  assert.equal(snapshot.messages.length, 1);
  assert.equal(snapshot.messages[0].author, 'Zarifa235');
  assert.equal(snapshot.messages[0].text, 'Salam HELLO <b>literal</b>');
  assert.equal(JSON.stringify(snapshot).includes('PRIVATE'), false, 'Provider credentials never reach clients');
  const isolated = await (await fetch(`${base}/session`, { headers: { Authorization: `Bearer ${pending.session_key}` } })).json();
  assert.equal(isolated.messages.length, 0);
  assert.equal((await fetch(`${base}/webhooks/kick`, { method: 'POST', body: '{}' })).status, 401);
  for (let i = 0; i < 105; i++) await post(event(`message-${i}`));
  snapshot = await (await fetch(`${base}/session`, { headers: auth })).json();
  assert.equal(snapshot.messages.length, 100);
  assert.equal(snapshot.cursor, 106);
  const next = await (await fetch(`${base}/session?after=105`, { headers: auth })).json();
  assert.equal(next.messages.length, 1);
  assert.equal((await fetch(`${base}/session`, { method: 'DELETE', headers: auth })).status, 200);
  assert.equal((await fetch(`${base}/session`, { headers: auth })).status, 401);
});
