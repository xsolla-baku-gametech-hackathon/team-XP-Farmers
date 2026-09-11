import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server/app.mjs';
import { createStorage } from '../server/storage.mjs';

const origin = 'https://studio.example';
test('all three built-in providers are advertised and missing YouTube credentials fail clearly', async t => {
  const server = createApp({ publicURL: origin });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.deepEqual(await (await fetch(`${base}/api/config`)).json(), { providers: { kick: false, twitch: false, youtube: false } });
  const reply = await fetch(`${base}/api/session`, { method: 'POST', headers: { 'X-Chat-Studio': '1', Origin: origin }, body: JSON.stringify({ provider: 'youtube' }) });
  assert.equal(reply.status, 503); assert.match((await reply.json()).error, /^YouTube is not configured/);
});

async function fixture(t, extra = {}) {
  const streams = [];
  const fake = { configured: true, authorizeURL: state => `https://id.kick.com/oauth/authorize?state=${state}`,
    async authorize(session, code) { session.user = code; session.channel = `Channel ${code}`; session.tokens = { access: 'PRIVATE-ACCESS', refresh: 'PRIVATE-REFRESH', expires: Date.now() + 3600000 }; },
    async maintain() {}, async verify(headers) { return headers['test-signature'] === 'valid'; },
    start(session, hooks) { streams.push({ session, hooks }); hooks.status('connected', 'Connected'); return () => { session.stopped = true; }; },
  };
  const server = createApp({ publicURL: origin, ...extra }, { providers: { kick: fake, twitch: fake, youtube: fake } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, method = 'GET', cookie, body, headers = {}) => fetch(`${base}${path}`, {
    method, redirect: 'manual', headers: { 'X-Chat-Studio': '1', Origin: origin, ...(cookie ? { Cookie: cookie } : {}), ...headers },
    ...(body !== undefined ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
  });
  async function login(user = '42', provider = 'kick') {
    const created = await request('/api/session', 'POST', null, { provider });
    assert.equal(created.status, 201);
    assert.match(created.headers.get('set-cookie'), /HttpOnly; SameSite=Lax.*Secure/);
    const cookie = created.headers.get('set-cookie').split(';')[0];
    const state = new URL((await created.json()).authorizeURL).searchParams.get('state');
    const callback = `/oauth/${provider}/callback?state=${state}&code=${user}`;
    assert.equal((await request(callback, 'GET', cookie)).status, 303);
    const snapshot = await (await request('/api/session', 'GET', cookie)).json();
    const overlay = new URL(snapshot.overlayURL).hash.slice(1);
    return { cookie, callback, overlay, snapshot };
  }
  return { server, request, login, streams };
}

test('OAuth is browser-bound, one-use, and never reveals provider or owner credentials', async t => {
  const { request, login } = await fixture(t);
  const created = await request('/api/session', 'POST', null, { provider: 'kick' });
  const cookie = created.headers.get('set-cookie').split(';')[0];
  const state = new URL((await created.json()).authorizeURL).searchParams.get('state');
  assert.equal((await request(`/oauth/kick/callback?state=${state}&code=42`)).status, 400);
  assert.equal((await request(`/oauth/twitch/callback?state=${state}&code=42`, 'GET', cookie)).status, 400);
  assert.equal((await request(`/oauth/kick/callback?state=${state}&code=42`, 'GET', cookie)).status, 303);
  assert.equal((await request(`/oauth/kick/callback?state=${state}&code=42`, 'GET', cookie)).status, 400);
  const a = await login();
  assert.equal(JSON.stringify(a.snapshot).includes('PRIVATE'), false);
  assert.notEqual(a.overlay, a.cookie.split('=')[1]);
  assert.equal((await request('/api/session', 'GET', null, undefined, { Authorization: `Bearer ${a.overlay}` })).status, 401);
  assert.equal((await request('/api/settings', 'PATCH', null, { opacity: 0 }, { Authorization: `Bearer ${a.overlay}` })).status, 401);
  const publicView = await (await request('/api/overlay', 'GET', null, undefined, { Authorization: `Bearer ${a.overlay}` })).json();
  assert.equal('overlayURL' in publicView, false);
  assert.equal(JSON.stringify(publicView).includes('PRIVATE'), false);
});

test('multi-streamer channel isolation, names, bounded messages, settings, mode off and link revocation', async t => {
  const { request, login, streams } = await fixture(t);
  const a = await login('42'), b = await login('99'), twitch = await login('42', 'twitch'), youtube = await login('42', 'youtube');
  const readOverlay = key => request('/api/overlay', 'GET', null, undefined, { Authorization: `Bearer ${key}` });
  const post = (id, broadcaster = 42) => request('/webhooks/kick', 'POST', null,
    { message_id: id, broadcaster: { user_id: broadcaster }, sender: { username: 'Zərifə<script>', user_id: 77 }, content: '<img src=x onerror=alert(1)> [emote:123:HELLO]' },
    { 'test-signature': 'valid', 'kick-event-message-id': id, 'kick-event-type': 'chat.message.sent', 'kick-event-version': '1' });
  assert.equal((await post('one')).status, 200); await post('one');
  let data = await (await readOverlay(a.overlay)).json();
  assert.equal(data.messages.length, 1);
  assert.equal(data.messages[0].author, 'Zərifə<script>');
  assert.equal(data.messages[0].text, '<img src=x onerror=alert(1)> HELLO');
  assert.equal((await (await readOverlay(b.overlay)).json()).messages.length, 0);
  assert.equal((await (await readOverlay(twitch.overlay)).json()).messages.length, 0);
  assert.equal((await (await readOverlay(youtube.overlay)).json()).messages.length, 0);
  streams[3].hooks.message({ id: 'yt', broadcaster: '42', author: 'YouTube viewer', text: 'Hello' });
  assert.equal((await (await readOverlay(youtube.overlay)).json()).messages[0].author, 'YouTube viewer');
  assert.equal((await (await readOverlay(a.overlay)).json()).messages.length, 1);
  assert.equal((await (await readOverlay(twitch.overlay)).json()).messages.length, 0);
  await request('/api/settings', 'PATCH', youtube.cookie, { enabled: false });
  assert.ok(streams[3].session.messagesAfter > 0);
  assert.equal((await (await readOverlay(youtube.overlay)).json()).messages.length, 0);
  for (let n = 0; n < 105; n++) await post(`m${n}`);
  assert.equal((await (await readOverlay(a.overlay)).json()).messages.length, 100);
  for (const opacity of [0, 35, 100]) {
    assert.equal((await request('/api/settings', 'PATCH', a.cookie, { opacity, fontSize: 28, position: 'top-left' })).status, 200);
    data = await (await readOverlay(a.overlay)).json(); assert.equal(data.settings.opacity, opacity);
  }
  for (const settings of [{ opacity: -1 }, { opacity: 101 }, { opacity: '20' }, { enabled: 1 }, { position: 'center' }, { fontSize: 100 }, { tokens: 'bad' }]) {
    assert.equal((await request('/api/settings', 'PATCH', a.cookie, settings)).status, 400);
  }
  await request('/api/settings', 'PATCH', a.cookie, { enabled: false });
  await post('while-disabled');
  assert.equal((await (await readOverlay(a.overlay)).json()).messages.length, 0);
  await request('/api/settings', 'PATCH', a.cookie, { enabled: true });
  assert.equal((await (await readOverlay(a.overlay)).json()).messages.length, 0, 'old messages do not reappear');
  const replaced = await (await request('/api/overlay/rotate', 'POST', a.cookie)).json();
  assert.equal((await readOverlay(a.overlay)).status, 401);
  const newKey = new URL(replaced.overlayURL).hash.slice(1);
  assert.equal((await readOverlay(newKey)).status, 200);
  await request('/api/session', 'DELETE', a.cookie);
  assert.equal((await readOverlay(newKey)).status, 401);
  assert.equal(streams[0].session.stopped, true);
});

test('request boundaries: origin/CSRF, unknown providers, JSON, size and static allowlist', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/api/session', 'POST', null, { provider: 'kick' }, { Origin: 'https://evil.example' })).status, 403);
  assert.equal((await request('/api/session', 'POST', null, { provider: 'kick' }, { 'X-Chat-Studio': '' })).status, 403);
  assert.equal((await request('/api/session', 'POST', null, 'malformed')).status, 400);
  assert.equal((await request('/api/session', 'POST', null, { provider: '__proto__' })).status, 400);
  assert.equal((await request('/api/session', 'POST', null, 'a'.repeat(66000))).status, 413);
  for (const path of ['/.env', '/server/index.mjs', '/data/sessions.enc', '/project.godot']) assert.equal((await request(path)).status, 404);
  for (const path of ['/', '/overlay', '/studio.mjs', '/styles.css']) {
    const reply = await request(path); assert.equal(reply.status, 200);
    assert.match(reply.headers.get('content-security-policy'), /script-src 'self'/);
    assert.equal(reply.headers.get('referrer-policy'), 'no-referrer');
  }
});

test('encrypted persistence restores owner settings and overlay links without saving chat', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'xp-chat-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const dataFile = join(directory, 'sessions.enc'), sessionSecret = 'ab'.repeat(32);
  const first = await fixture(t, { dataFile, sessionSecret });
  const account = await first.login('42');
  first.streams[0].hooks.message({ id: 'message', broadcaster: '42', author: 'PRIVATE-CHAT-USER', text: 'PRIVATE-CHAT' });
  await first.request('/api/settings', 'PATCH', account.cookie, { opacity: 73 });
  const bytes = readFileSync(dataFile).toString();
  assert.equal(bytes.includes('PRIVATE'), false);
  const saved = createStorage(dataFile, sessionSecret).load();
  assert.equal(JSON.stringify(saved).includes('PRIVATE-CHAT'), false);
  assert.throws(() => createStorage(dataFile, 'cd'.repeat(32)).load());
  const second = await fixture(t, { dataFile, sessionSecret });
  const restored = await (await second.request('/api/session', 'GET', account.cookie)).json();
  assert.equal(restored.settings.opacity, 73); assert.equal(restored.overlayURL, account.snapshot.overlayURL);
  assert.equal(restored.messages.length, 0);
});

test('native game pairing uses separate one-use browser and private polling capabilities', async t => {
  const { request } = await fixture(t);
  const created = await request('/api/device', 'POST', null, { provider: 'kick' });
  assert.equal(created.status, 201);
  const { token, browserURL } = await created.json();
  const ticket = new URL(browserURL).hash.slice(1);
  assert.notEqual(token, ticket);
  const poll = secret => request('/api/device', 'GET', null, undefined, { Authorization: `Bearer ${secret}` });
  assert.equal((await poll(ticket)).status, 401);
  assert.equal((await poll('wrong')).status, 401);
  assert.equal((await (await poll(token)).json()).state, 'connecting');
  const claim = await request('/api/device/authorize', 'POST', null, { ticket });
  assert.equal(claim.status, 200);
  const cookie = claim.headers.get('set-cookie').split(';')[0];
  const { authorizeURL } = await claim.json();
  assert.equal((await request('/api/device/authorize', 'POST', null, { ticket })).status, 400);
  const state = new URL(authorizeURL).searchParams.get('state');
  const callback = `/oauth/kick/callback?state=${state}&code=42`;
  assert.equal((await request(callback)).status, 400);
  assert.equal((await request(callback, 'GET', cookie)).status, 303);
  const paired = await (await poll(token)).json();
  assert.equal(paired.channel, 'Channel 42');
  assert.equal(paired.state, 'connected');
  assert.ok(paired.overlayURL);
  assert.equal(JSON.stringify(paired).includes('PRIVATE'), false);
  assert.equal((await request('/api/session', 'GET', null, undefined, { Authorization: `Bearer ${token}` })).status, 401);
  const overlay = new URL(paired.overlayURL).hash.slice(1);
  assert.equal((await request('/api/device', 'DELETE', null, undefined, { Authorization: `Bearer ${overlay}` })).status, 401);
  assert.equal((await request('/api/device', 'DELETE', null, undefined, { Authorization: `Bearer ${token}` })).status, 200);
  assert.equal((await poll(token)).status, 401);
  assert.equal((await request('/api/overlay', 'GET', null, undefined, { Authorization: `Bearer ${overlay}` })).status, 401);
});

test('game pairing fails closed on unsupported providers, foreign origins and cancelled OAuth', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/api/device', 'POST', null, { provider: 'invalid' })).status, 400);
  assert.equal((await request('/api/device', 'POST', null, { provider: 'kick' }, { Origin: 'https://other.example' })).status, 403);
  const { token, browserURL } = await (await request('/api/device', 'POST', null, { provider: 'youtube' })).json();
  const claimed = await request('/api/device/authorize', 'POST', null, { ticket: new URL(browserURL).hash.slice(1) });
  const cookie = claimed.headers.get('set-cookie').split(';')[0];
  const state = new URL((await claimed.json()).authorizeURL).searchParams.get('state');
  await request(`/oauth/youtube/callback?state=${state}&error=access_denied`, 'GET', cookie);
  const failed = await (await request('/api/device', 'GET', null, undefined, { Authorization: `Bearer ${token}` })).json();
  assert.equal(failed.state, 'error');
  assert.equal('overlayURL' in failed, false);
});
