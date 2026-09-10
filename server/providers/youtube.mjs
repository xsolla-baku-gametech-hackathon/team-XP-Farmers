import { literal } from '../common.mjs';

const API = 'https://www.googleapis.com/youtube/v3';
const SCOPE = 'https://www.googleapis.com/auth/youtube.readonly';
const WAIT = 30000;

export function youtubeMessage(item, broadcaster, liveChatId) {
  const snippet = item?.snippet;
  if (!item?.id || snippet?.liveChatId !== liveChatId || !snippet.hasDisplayContent ||
      !item.authorDetails?.channelId || !Number.isFinite(Date.parse(snippet.publishedAt))) return null;
  const text = literal(snippet.displayMessage || snippet.textMessageDetails?.messageText, 2000);
  if (!text || ['messageDeletedEvent', 'userBannedEvent', 'chatEndedEvent', 'tombstone'].includes(snippet.type)) return null;
  return { id: literal(item.id, 200), broadcaster, userId: literal(item.authorDetails.channelId, 100),
    author: literal(item.authorDetails.displayName, 100) || 'Unknown user', text, sentAt: Date.parse(snippet.publishedAt) };
}

export function createYouTube(config, fetchImpl = fetch, clock = { setTimeout, clearTimeout, now: Date.now }) {
  const redirect = `${config.publicURL}/oauth/youtube/callback`;
  const refreshing = new WeakMap();
  async function request(url, options = {}, signal) {
    const timeout = AbortSignal.timeout(10000);
    const response = await fetchImpl(url, { ...options, signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
    const body = await response.json();
    if (!response.ok) throw Object.assign(new Error('YouTube request failed'), {
      status: response.status, reason: body.error?.errors?.[0]?.reason || body.error,
    });
    return body;
  }
  const api = (path, params, session, signal) => request(`${API}/${path}?${new URLSearchParams(params)}`, {
    headers: { Authorization: `Bearer ${session.tokens.access}` },
  }, signal);
  async function tokens(values, previous) {
    const body = await request('https://oauth2.googleapis.com/token', { method: 'POST',
      body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, ...values }),
    });
    const refresh = body.refresh_token || previous?.refresh;
    if (!body.access_token || !refresh || !(Number(body.expires_in) > 0) ||
        (body.scope && !body.scope.split(' ').includes(SCOPE))) throw new Error('Invalid YouTube grant');
    return { access: body.access_token, refresh, expires: clock.now() + Number(body.expires_in) * 1000 };
  }
  async function maintain(session, force = false) {
    if (refreshing.has(session)) return refreshing.get(session);
    if (!session.tokens) throw new Error('Missing YouTube grant');
    if (!force && session.tokens.expires - clock.now() >= 120000) return;
    const previous = session.tokens;
    const pending = tokens({ grant_type: 'refresh_token', refresh_token: previous.refresh }, previous).then(next => {
      // Disconnect may have cleared the session while the exchange was in flight.
      if (session.tokens === previous) session.tokens = next;
    }).finally(() => refreshing.delete(session));
    refreshing.set(session, pending);
    return pending;
  }
  return {
    configured: Boolean(config.clientId && config.clientSecret),
    authorizeURL(state) {
      return `https://accounts.google.com/o/oauth2/v2/auth?${new URLSearchParams({ client_id: config.clientId,
        response_type: 'code', redirect_uri: redirect, scope: SCOPE, state, access_type: 'offline', prompt: 'consent' })}`;
    },
    async authorize(session, code) {
      session.tokens = await tokens({ grant_type: 'authorization_code', code, redirect_uri: redirect });
      const channel = (await api('channels', { part: 'id,snippet', mine: 'true' }, session)).items?.[0];
      if (typeof channel?.id !== 'string' || !channel.id) throw new Error('No YouTube channel');
      session.user = channel.id; session.channel = literal(channel.snippet?.title, 100) || channel.id;
    },
    maintain,
    start(session, hooks) {
      let stopped = false, timer, liveChatId = '', pageToken = '', failures = 0, refreshedAfter401 = false;
      let interval = 5000, since = clock.now();
      const controller = new AbortController(), unavailable = new Map();
      const schedule = delay => { if (!stopped) { timer = clock.setTimeout(poll, delay); timer?.unref?.(); } };
      const waiting = detail => { hooks.remove({ all: true }); hooks.status('waiting', detail); };
      function reset(detail, duration = 300000) {
        if (liveChatId) unavailable.set(liveChatId, clock.now() + duration);
        liveChatId = ''; pageToken = ''; since = clock.now(); waiting(detail);
      }
      async function discover() {
        for (const [id, until] of unavailable) if (until <= clock.now()) unavailable.delete(id);
        let next = '';
        do {
          const data = await api('liveBroadcasts', { part: 'id,snippet,status', broadcastStatus: 'active',
            broadcastType: 'all', maxResults: '50', ...(next ? { pageToken: next } : {}) }, session, controller.signal);
          if (stopped) return;
          // Never accept another channel's chat, including unexpected API results.
          const broadcast = data.items?.find(item => item.snippet?.channelId === session.user &&
            item.status?.lifeCycleStatus === 'live' && item.snippet.liveChatId && !unavailable.has(item.snippet.liveChatId));
          if (broadcast) { liveChatId = broadcast.snippet.liveChatId; pageToken = ''; return; }
          next = data.nextPageToken;
        } while (next && !stopped);
      }
      async function poll() {
        try {
          await maintain(session);
          if (stopped) return;
          if (!liveChatId) await discover();
          if (stopped) return;
          if (!liveChatId) { failures = 0; waiting('YouTube connected. Start a live broadcast with chat enabled; checking every 30 seconds.'); schedule(WAIT); return; }
          const data = await api('liveChat/messages', { liveChatId, part: 'id,snippet,authorDetails', maxResults: '2000',
            ...(pageToken ? { pageToken } : {}) }, session, controller.signal);
          if (stopped) return;
          if (data.offlineAt || data.items?.some(item => item.snippet?.liveChatId === liveChatId && item.snippet.type === 'chatEndedEvent')) {
            reset('YouTube broadcast ended. Waiting for your next live broadcast.'); schedule(WAIT); return;
          }
          interval = Math.max(5000, Number(data.pollingIntervalMillis) || 5000);
          pageToken = typeof data.nextPageToken === 'string' ? data.nextPageToken : '';
          failures = 0; refreshedAfter401 = false;
          hooks.status('connected', 'YouTube live chat connected.');
          for (const item of data.items || []) {
            if (item.snippet?.liveChatId !== liveChatId) continue;
            if (item.snippet.type === 'messageDeletedEvent') {
              // Some API responses provide deletion details; tombstones identify the original item directly.
              hooks.remove({ id: literal(item.snippet.messageDeletedDetails?.deletedMessageId, 200) });
            } else if (item.snippet.type === 'tombstone') hooks.remove({ id: literal(item.id, 200) });
            else if (item.snippet.type === 'userBannedEvent') {
              hooks.remove({ userId: literal(item.snippet.userBannedDetails?.bannedUserDetails?.channelId, 100) });
            } else {
              const message = youtubeMessage(item, session.user, liveChatId);
              if (message && message.sentAt >= Math.max(since, session.messagesAfter || 0)) hooks.message(message);
            }
          }
          schedule(interval);
        } catch (error) {
          if (stopped) return;
          hooks.remove({ all: true });
          if (['liveChatEnded', 'liveChatNotFound', 'liveChatDisabled'].includes(error.reason)) {
            reset('YouTube live chat is unavailable. Waiting for a broadcast with chat enabled.', error.reason === 'liveChatDisabled' ? WAIT : 300000);
            schedule(WAIT);
          } else if (error.status === 401 && !refreshedAfter401) {
            refreshedAfter401 = true;
            try { await maintain(session, true); if (!stopped) { hooks.status('connecting', 'Reconnecting to YouTube…'); schedule(interval); } }
            catch { if (!stopped) { stopped = true; hooks.status('error', 'YouTube access expired. Disconnect and connect again.'); } }
          } else if (error.reason === 'quotaExceeded' || error.reason === 'dailyLimitExceeded') {
            stopped = true; hooks.status('error', 'YouTube API quota is exhausted. Contact the service owner, then reconnect when quota is available.');
          } else if ([400, 401, 403].includes(error.status) && !['rateLimitExceeded', 'userRateLimitExceeded'].includes(error.reason)) {
            stopped = true; hooks.status('error', 'YouTube access is unavailable. Enable live streaming and allow channel access, then disconnect and connect again.');
          } else {
            const delay = Math.max(interval, Math.min(60000, 5000 * 2 ** Math.min(failures++, 4)));
            hooks.status('connecting', 'YouTube connection interrupted. Retrying automatically…'); schedule(delay);
          }
        }
      }
      hooks.status('connecting', 'Looking for your YouTube live broadcast…');
      void poll();
      return () => { stopped = true; clock.clearTimeout(timer); controller.abort(); };
    },
  };
}
