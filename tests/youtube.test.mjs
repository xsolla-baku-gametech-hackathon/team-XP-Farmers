import test from 'node:test';
import assert from 'node:assert/strict';
import { createYouTube, youtubeMessage } from '../server/providers/youtube.mjs';

const config = { publicURL: 'https://studio.example', clientId: 'app', clientSecret: 'PRIVATE' };
const scope = 'https://www.googleapis.com/auth/youtube.readonly';
const tick = () => new Promise(resolve => setImmediate(resolve));
const channel = { id: 'owner', snippet: { title: 'Nərmin Live' } };
const broadcast = (id = 'chat', owner = 'owner') => ({ snippet: { liveChatId: id, channelId: owner }, status: { lifeCycleStatus: 'live' } });
const event = (id, time, snippet = {}, author = {}) => ({ id,
  snippet: { liveChatId: 'chat', type: 'textMessageEvent', hasDisplayContent: true, publishedAt: new Date(time).toISOString(), displayMessage: '<b>Salam</b>', ...snippet },
  authorDetails: { channelId: 'viewer', displayName: 'Zərifə<script>', ...author },
});
function fakeClock() {
  let now = Date.parse('2026-09-10T12:00:00Z'), timer;
  return { now: () => now, setTimeout(fn, delay) { assert.equal(timer, undefined, 'only one polling timer'); timer = { fn, delay }; return timer; },
    clearTimeout() { timer = undefined; }, get delay() { return timer?.delay; },
    async run() { assert.ok(timer, 'scheduled poll'); const job = timer; timer = undefined; now += job.delay; await job.fn(); await tick(); },
  };
}
function fixture(t, route) {
  const clock = fakeClock(), calls = [], messages = [], removed = [], statuses = [];
  const session = { user: 'owner', channel: 'Nərmin Live', tokens: { access: 'PRIVATE-ACCESS', refresh: 'PRIVATE-REFRESH', expires: clock.now() + 3600000 } };
  const provider = createYouTube(config, async (address, options) => {
    const url = new URL(address); calls.push({ url, options });
    assert.equal(options.headers?.Authorization, 'Bearer PRIVATE-ACCESS');
    return route(url, options, clock);
  }, clock);
  const stop = provider.start(session, { status: (...value) => statuses.push(value), message: value => messages.push(value), remove: value => removed.push(value) });
  t.after(stop);
  return { clock, calls, messages, removed, statuses, session, stop };
}

test('YouTube OAuth requests read-only offline access and refreshes once without losing refresh tokens', async () => {
  const grants = [];
  const provider = createYouTube(config, async (url, options) => {
    if (url.endsWith('/token')) {
      grants.push(options.body);
      return Response.json({ access_token: `access-${grants.length}`, expires_in: 3600, scope,
        ...(grants.length === 1 ? { refresh_token: 'refresh' } : {}) });
    }
    const address = new URL(url);
    assert.equal(address.pathname, '/youtube/v3/channels'); assert.equal(address.searchParams.get('mine'), 'true');
    return Response.json({ items: [channel] });
  });
  const url = new URL(provider.authorizeURL('state'));
  assert.equal(url.origin, 'https://accounts.google.com');
  assert.equal(url.searchParams.get('scope'), scope); assert.equal(url.searchParams.get('state'), 'state');
  assert.equal(url.searchParams.get('redirect_uri'), `${config.publicURL}/oauth/youtube/callback`);
  assert.equal(url.searchParams.get('access_type'), 'offline'); assert.equal(url.searchParams.get('prompt'), 'consent');
  assert.equal(url.searchParams.has('client_secret'), false);
  const session = {}; await provider.authorize(session, 'code');
  assert.equal(session.channel, 'Nərmin Live'); assert.equal(session.user, 'owner');
  assert.equal(grants[0].get('grant_type'), 'authorization_code');
  session.tokens.expires = 0;
  await Promise.all([provider.maintain(session), provider.maintain(session)]);
  assert.equal(grants.length, 2); assert.equal(grants[1].get('grant_type'), 'refresh_token');
  assert.equal(session.tokens.refresh, 'refresh'); assert.equal(session.tokens.access, 'access-2');
  const rejected = createYouTube(config, async () => Response.json({ access_token: 'a', refresh_token: 'r', expires_in: 3600, scope: 'unrelated' }));
  await assert.rejects(rejected.authorize({}, 'code'));
  const missingChannel = createYouTube(config, async url => Response.json(url.endsWith('/token') ? { access_token: 'a', refresh_token: 'r', expires_in: 3600 } : { items: [] }));
  await assert.rejects(missingChannel.authorize({}, 'code'), /No YouTube channel/);
  assert.equal(createYouTube({ publicURL: config.publicURL }).configured, false);
});

test('YouTube discovers only the owner’s active chat, respects cursors/intervals, filters history and handles moderation', async t => {
  let discovered = 0, batch = 0;
  const f = fixture(t, (url, options, clock) => {
    if (url.pathname.endsWith('/liveBroadcasts')) {
      assert.equal(url.searchParams.has('mine'), false, 'broadcastStatus is the sole filter');
      assert.equal(url.searchParams.get('broadcastStatus'), 'active');
      assert.equal(url.searchParams.get('broadcastType'), 'all');
      discovered++;
      if (discovered === 1) return Response.json({ items: [broadcast('foreign', 'other')] });
      if (!url.searchParams.has('pageToken')) return Response.json({ items: [], nextPageToken: 'broadcast-page-2' });
      assert.equal(url.searchParams.get('pageToken'), 'broadcast-page-2');
      return Response.json({ items: [broadcast()] });
    }
    assert.equal(url.searchParams.get('liveChatId'), 'chat');
    assert.equal(url.searchParams.get('part'), 'id,snippet,authorDetails');
    assert.equal(url.searchParams.get('maxResults'), '2000');
    batch++;
    if (batch === 1) {
      assert.equal(url.searchParams.has('pageToken'), false);
      return Response.json({ nextPageToken: 'cursor-1', pollingIntervalMillis: 9000, items: [
        event('old', clock.now() - 60000), event('new', clock.now()), event('wrong-chat', clock.now(), { liveChatId: 'foreign' }),
      ] });
    }
    assert.equal(url.searchParams.get('pageToken'), 'cursor-1');
    return Response.json({ nextPageToken: 'cursor-2', pollingIntervalMillis: 12000, items: [
      event('while-off', clock.now() - 5000), event('after-mode-on', clock.now()),
      event('deletion', clock.now(), { type: 'messageDeletedEvent', messageDeletedDetails: { deletedMessageId: 'new' } }),
      event('tombstone', clock.now(), { type: 'tombstone' }),
      event('ban', clock.now(), { type: 'userBannedEvent', userBannedDetails: { bannedUserDetails: { channelId: 'viewer' } } }),
    ] });
  });
  await tick(); assert.equal(f.statuses.at(-1)[0], 'waiting'); assert.equal(f.clock.delay, 30000);
  await f.clock.run();
  assert.equal(f.statuses.at(-1)[0], 'connected'); assert.equal(f.clock.delay, 9000);
  assert.deepEqual(f.messages.map(m => m.id), ['new']);
  assert.equal(f.messages[0].author, 'Zərifə<script>'); assert.equal(f.messages[0].text, '<b>Salam</b>');
  f.session.messagesAfter = f.clock.now() + 8000;
  await f.clock.run(); assert.equal(f.clock.delay, 12000);
  assert.deepEqual(f.messages.map(m => m.id), ['new', 'after-mode-on']);
  assert.deepEqual(f.removed.slice(-3), [{ id: 'new' }, { id: 'tombstone' }, { userId: 'viewer' }]);
  assert.equal(youtubeMessage(event('x', 0, {}, { channelId: '' }), 'owner', 'chat'), null);
  assert.equal(youtubeMessage(event('x', 0, { publishedAt: 'bad' }), 'owner', 'chat'), null);
});

test('YouTube clears ended broadcasts, switches chats without reusing cursors, and stops in-flight delivery', async t => {
  let batch = 0, finish, inflightSignal;
  const f = fixture(t, (url, options, clock) => {
    if (url.pathname.endsWith('/liveBroadcasts')) return Response.json({ items: [broadcast(), broadcast('next-chat')] });
    batch++;
    if (batch === 1) return Response.json({ nextPageToken: 'old-cursor', items: [event('first', clock.now())] });
    if (batch === 2) return Response.json({ offlineAt: new Date(clock.now()).toISOString(), items: [] });
    assert.equal(url.searchParams.get('liveChatId'), 'next-chat');
    assert.equal(url.searchParams.has('pageToken'), false);
    inflightSignal = options.signal;
    return new Promise(resolve => { finish = () => resolve(Response.json({ items: [event('late', clock.now(), { liveChatId: 'next-chat' })] })); });
  });
  await tick(); await f.clock.run();
  assert.equal(f.statuses.at(-1)[0], 'waiting'); assert.deepEqual(f.removed.at(-1), { all: true });
  const running = f.clock.run(); await tick(); f.stop();
  assert.equal(inflightSignal.aborted, true); finish(); await running;
  assert.deepEqual(f.messages.map(m => m.id), ['first']); assert.equal(f.clock.delay, undefined);
});

test('YouTube backs off transient failures and exposes quota exhaustion without endless retries', async t => {
  let batch = 0;
  const f = fixture(t, url => {
    if (url.pathname.endsWith('/liveBroadcasts')) return Response.json({ items: [broadcast()] });
    batch++;
    if (batch === 1) return Response.json({ pollingIntervalMillis: 15000, nextPageToken: 'cursor', items: [] });
    return Response.json({ error: { errors: [{ reason: batch < 4 ? 'rateLimitExceeded' : 'quotaExceeded' }] } }, { status: 403 });
  });
  await tick(); await f.clock.run(); assert.equal(f.clock.delay, 15000);
  assert.equal(f.statuses.at(-1)[0], 'connecting');
  await f.clock.run(); assert.equal(f.clock.delay, 15000);
  await f.clock.run(); assert.equal(f.statuses.at(-1)[0], 'error');
  assert.match(f.statuses.at(-1)[1], /quota/); assert.equal(f.clock.delay, undefined);
});

test('YouTube retries a rejected access token once, then stops on revoked access', async t => {
  const clock = fakeClock(), statuses = [];
  let refreshes = 0, requests = 0;
  const session = { user: 'owner', tokens: { access: 'old', refresh: 'refresh', expires: clock.now() + 3600000 } };
  const provider = createYouTube(config, async url => {
    if (url.endsWith('/token')) { refreshes++; return Response.json({ access_token: 'new', expires_in: 3600 }); }
    requests++;
    return Response.json({ error: { errors: [{ reason: 'authError' }] } }, { status: 401 });
  }, clock);
  t.after(provider.start(session, { status: (...value) => statuses.push(value), message() {}, remove() {} }));
  await tick(); assert.equal(refreshes, 1); assert.equal(session.tokens.refresh, 'refresh');
  await clock.run(); assert.equal(requests, 2); assert.equal(refreshes, 1);
  assert.equal(statuses.at(-1)[0], 'error'); assert.equal(clock.delay, undefined);
});
