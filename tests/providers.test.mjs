import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { verifyWebhook, chatMessage, createKick } from '../server/providers/kick.mjs';
import { createTwitch, twitchMessage } from '../server/providers/twitch.mjs';

test('Kick verifies raw-body RSA signatures, timestamp and payload names', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const raw = Buffer.from('{"content":"hello"}'), time = new Date().toISOString();
  const headers = { 'kick-event-message-id': 'id', 'kick-event-message-timestamp': time,
    'kick-event-signature': sign('RSA-SHA256', Buffer.concat([Buffer.from(`id.${time}.`), raw]), privateKey).toString('base64') };
  assert.equal(verifyWebhook(headers, raw, publicKey), true);
  assert.equal(verifyWebhook(headers, Buffer.from('{}'), publicKey), false);
  assert.equal(verifyWebhook(headers, raw, publicKey, Date.now() + 600000), false);
  assert.equal(verifyWebhook({}, raw, publicKey), false);
  assert.equal(chatMessage({ broadcaster: { user_id: 42 }, message_id: '1', content: 'hello' }).author, 'Unknown user');
  assert.equal(chatMessage({ content: 'hello' }), null);
});

test('Kick OAuth PKCE, subscription acceptance and refresh', async () => {
  const grants = [], subscriptions = [];
  const provider = createKick({ publicURL: 'https://studio.example', clientId: 'app', clientSecret: 'PRIVATE' }, async (url, options) => {
    if (url.endsWith('/token')) { grants.push(options.body); return Response.json({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600 }); }
    if (url.endsWith('/users')) return Response.json({ data: [{ user_id: 42, name: 'Azra' }] });
    if (url.includes('/events/subscriptions?')) return Response.json({ data: [] });
    if (url.endsWith('/events/subscriptions')) { subscriptions.push(JSON.parse(options.body)); return Response.json({ data: [{ name: 'chat.message.sent', subscription_id: 'sub' }] }); }
    throw new Error('Unexpected provider request');
  });
  const url = new URL(provider.authorizeURL('state', 'verifier'));
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  assert.equal(url.searchParams.get('redirect_uri'), 'https://studio.example/oauth/kick/callback');
  const session = {}; await provider.authorize(session, 'code', 'verifier');
  assert.equal(session.channel, 'Azra'); assert.equal(session.user, '42');
  assert.equal(grants[0].get('code_verifier'), 'verifier');
  assert.equal(subscriptions[0].events[0].name, 'chat.message.sent');
  session.tokens.expires = 0; await provider.maintain(session);
  assert.equal(grants[1].get('grant_type'), 'refresh_token');
});

class FakeSocket extends EventTarget {
  static instances = [];
  constructor(url) { super(); this.url = url; FakeSocket.instances.push(this); }
  message(body) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(body) })); }
  close() { if (!this.closed) { this.closed = true; this.dispatchEvent(new Event('close')); } }
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const welcome = id => ({ metadata: { message_type: 'session_welcome' }, payload: { session: { id, keepalive_timeout_seconds: 10 } } });

test('Twitch uses authenticated EventSub with names, isolation, moderation, reconnect and revocation', async t => {
  FakeSocket.instances = [];
  const requests = [], messages = [], removed = [], statuses = [];
  const provider = createTwitch({ publicURL: 'https://studio.example', clientId: 'app', clientSecret: 'PRIVATE' }, async (url, options) => {
    if (url.endsWith('/token')) return Response.json({ access_token: 'PRIVATE-ACCESS', refresh_token: 'PRIVATE-REFRESH', expires_in: 3600 });
    if (url.endsWith('/users')) return Response.json({ data: [{ id: '42', login: 'azra', display_name: 'Azra' }] });
    if (url.endsWith('/validate')) return Response.json({ client_id: 'app', user_id: '42', scopes: ['user:read:chat'] });
    if (url.endsWith('/eventsub/subscriptions')) { requests.push(JSON.parse(options.body)); return Response.json({ data: [{ id: 'sub' }] }, { status: 202 }); }
    throw new Error('Unexpected provider request');
  }, FakeSocket);
  const session = {}; await provider.authorize(session, 'code');
  assert.equal(session.user, '42');
  const stop = provider.start(session, { status: (...value) => statuses.push(value), message: value => messages.push(value), remove: value => removed.push(value) });
  t.after(stop);
  const socket = FakeSocket.instances[0]; socket.message(welcome('socket-1')); await tick();
  assert.equal(requests.length, 4);
  assert.ok(requests.every(r => r.condition.broadcaster_user_id === '42' && r.condition.user_id === '42' && r.transport.session_id === 'socket-1'));
  const message = { broadcaster_user_id: '42', chatter_user_id: '7', chatter_user_name: 'Nərmin', message_id: 'message-1', message: { text: '<b>Hello</b>' } };
  const notification = (type, event) => ({ metadata: { message_type: 'notification', subscription_type: type }, payload: { event } });
  socket.message(notification('channel.chat.message', message));
  socket.message(notification('channel.chat.message', { ...message, broadcaster_user_id: '99' }));
  assert.equal(messages.length, 1); assert.equal(messages[0].author, 'Nərmin'); assert.equal(messages[0].text, '<b>Hello</b>');
  socket.message(notification('channel.chat.message_delete', { broadcaster_user_id: '42', message_id: 'message-1' }));
  socket.message(notification('channel.chat.clear_user_messages', { broadcaster_user_id: '42', target_user_id: '7' }));
  socket.message(notification('channel.chat.clear', { broadcaster_user_id: '42' }));
  assert.deepEqual(removed, [{ id: 'message-1' }, { userId: '7' }, { all: true }]);
  socket.message({ metadata: { message_type: 'session_reconnect' }, payload: { session: { reconnect_url: 'wss://eventsub.wss.twitch.tv/ws?reconnect=abc' } } });
  const replacement = FakeSocket.instances[1];
  assert.equal(socket.closed, undefined, 'old socket survives until new welcome');
  replacement.message(welcome('socket-2')); await tick();
  assert.equal(socket.closed, true); assert.equal(requests.length, 4, 'migration reuses subscriptions');
  replacement.message({ metadata: { message_type: 'revocation' }, payload: {} });
  assert.equal(replacement.closed, true); assert.equal(statuses.at(-1)[0], 'error');
  assert.equal(twitchMessage({ message: { text: 'bad' } }), null);
});
