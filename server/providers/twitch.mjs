import { literal, jsonRequest } from '../common.mjs';

const OAUTH = 'https://id.twitch.tv/oauth2';
const SOCKET = 'wss://eventsub.wss.twitch.tv/ws';
const TYPES = ['channel.chat.message', 'channel.chat.message_delete', 'channel.chat.clear_user_messages', 'channel.chat.clear'];
export function twitchMessage(event) {
  if (typeof event?.message_id !== 'string' || typeof event.message?.text !== 'string' || typeof event.broadcaster_user_id !== 'string') return null;
  return { id: literal(event.message_id, 200), broadcaster: event.broadcaster_user_id,
    author: literal(event.chatter_user_name || event.chatter_user_login, 100) || 'Unknown user',
    userId: literal(event.chatter_user_id, 100), text: literal(event.message.text, 2000) };
}
export function createTwitch(config, fetchImpl = fetch, WebSocketImpl = WebSocket) {
  const redirect = `${config.publicURL}/oauth/twitch/callback`;
  const api = (path, token, method = 'GET', body) => jsonRequest(fetchImpl, `https://api.twitch.tv/helix${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Client-Id': config.clientId, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  async function tokens(values) {
    const body = await jsonRequest(fetchImpl, `${OAUTH}/token`, { method: 'POST',
      body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, ...values }),
    });
    if (!body.access_token || !body.refresh_token || !(Number(body.expires_in) > 0)) throw new Error('Invalid token response');
    return { access: body.access_token, refresh: body.refresh_token, expires: Date.now() + Number(body.expires_in) * 1000 };
  }
  async function validate(session) {
    const result = await jsonRequest(fetchImpl, `${OAUTH}/validate`, { headers: { Authorization: `OAuth ${session.tokens.access}` } });
    if (result.client_id !== config.clientId || result.user_id !== session.user || !result.scopes?.includes('user:read:chat')) throw new Error('Authorization revoked');
    session.validated = Date.now();
  }
  return {
    configured: Boolean(config.clientId && config.clientSecret),
    authorizeURL(state) {
      return `${OAUTH}/authorize?${new URLSearchParams({ client_id: config.clientId, response_type: 'code', redirect_uri: redirect,
        scope: 'user:read:chat', state, force_verify: 'true' })}`;
    },
    async authorize(session, code) {
      session.tokens = await tokens({ grant_type: 'authorization_code', code, redirect_uri: redirect });
      const user = (await api('/users', session.tokens.access)).data?.[0];
      if (!user?.id || !user.login) throw new Error('Invalid user');
      session.user = user.id; session.channel = literal(user.display_name || user.login, 100);
      await validate(session);
    },
    async maintain(session) {
      if (session.tokens.expires - Date.now() < 120000) session.tokens = await tokens({ grant_type: 'refresh_token', refresh_token: session.tokens.refresh });
      if (Date.now() - (session.validated || 0) > 3600000) await validate(session);
    },
    start(session, hooks) {
      let stopped = false, active, migrating, retryTimer, attempts = 0;
      const sockets = new Set();
      function stop() {
        stopped = true; clearTimeout(retryTimer);
        for (const ws of sockets) { clearTimeout(ws.watchdog); ws.close(); }
        sockets.clear();
      }
      function retry() {
        if (stopped || retryTimer) return;
        hooks.status('connecting', 'Twitch connection interrupted. Reconnecting…');
        retryTimer = setTimeout(() => { retryTimer = null; connect(SOCKET); }, Math.min(30000, 1000 * 2 ** Math.min(attempts++, 5)));
        retryTimer.unref?.();
      }
      function connect(address, previous) {
        if (stopped) return;
        let ws;
        try { ws = new WebSocketImpl(address); } catch { retry(); return; }
        sockets.add(ws);
        if (previous) migrating = ws; else active = ws;
        let heartbeat = 15000;
        const watchdog = () => {
          clearTimeout(ws.watchdog);
          ws.watchdog = setTimeout(() => ws.close(), heartbeat);
          ws.watchdog.unref?.();
        };
        watchdog();
        ws.addEventListener('message', async ({ data }) => {
          if (stopped || !sockets.has(ws)) return;
          try {
            const body = JSON.parse(data), type = body.metadata?.message_type;
            if (type === 'session_welcome') {
              const info = body.payload?.session;
              if (!info?.id) throw new Error('Missing socket session');
              heartbeat = (Number(info.keepalive_timeout_seconds) || 10) * 1000 + 2000;
              if (!previous) {
                // Subscribe immediately; Twitch closes unused connections after ten seconds.
                await Promise.all(TYPES.map(type => api('/eventsub/subscriptions', session.tokens.access, 'POST', {
                  type, version: '1', condition: { broadcaster_user_id: session.user, user_id: session.user },
                  transport: { method: 'websocket', session_id: info.id },
                })));
              }
              if (stopped || !sockets.has(ws)) return;
              if (previous) { active = ws; migrating = null; sockets.delete(previous); clearTimeout(previous.watchdog); previous.close(); }
              attempts = 0;
              hooks.status('connected', 'Twitch connected. Waiting for live chat.');
            } else if (type === 'session_reconnect') {
              const address = new URL(body.payload?.session?.reconnect_url);
              if (address.protocol !== 'wss:' || address.hostname !== 'eventsub.wss.twitch.tv' || address.port || address.username || address.password) throw new Error('Invalid reconnect host');
              if (!migrating) connect(address.href, ws);
            } else if (type === 'revocation') {
              hooks.status('error', 'Twitch permission was revoked. Disconnect and connect again.'); stop(); return;
            } else if (type === 'notification') {
              const event = body.payload?.event;
              if (event?.broadcaster_user_id !== session.user) return;
              switch (body.metadata.subscription_type) {
                case 'channel.chat.message': hooks.message(twitchMessage(event)); break;
                case 'channel.chat.message_delete': hooks.remove({ id: event.message_id }); break;
                case 'channel.chat.clear_user_messages': hooks.remove({ userId: event.target_user_id }); break;
                case 'channel.chat.clear': hooks.remove({ all: true }); break;
              }
            }
            watchdog();
          } catch {
            if (!stopped) { hooks.status('error', 'Twitch subscription failed. Check permissions and reconnect.'); stop(); }
          }
        });
        ws.addEventListener('error', () => ws.close());
        ws.addEventListener('close', () => {
          clearTimeout(ws.watchdog); sockets.delete(ws);
          if (stopped) return;
          if (ws === migrating) { migrating = null; if (!sockets.has(active)) retry(); }
          else if (ws === active && !migrating) retry();
        });
      }
      hooks.status('connecting', 'Connecting to Twitch live chat…');
      connect(SOCKET);
      return stop;
    },
  };
}
