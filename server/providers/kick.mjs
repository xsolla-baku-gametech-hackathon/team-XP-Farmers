import { createHash, verify } from 'node:crypto';
import { literal, jsonRequest } from '../common.mjs';

const API = 'https://api.kick.com/public/v1';
const OAUTH = 'https://id.kick.com/oauth';
export function verifyWebhook(headers, raw, publicKey, now = Date.now()) {
  const id = headers['kick-event-message-id'], timestamp = headers['kick-event-message-timestamp'];
  const signature = headers['kick-event-signature'];
  if (![id, timestamp, signature].every(v => typeof v === 'string' && v.length < 2048)) return false;
  const age = Math.abs(now - Date.parse(timestamp));
  if (!Number.isFinite(age) || age > 300000) return false;
  try {
    return verify('RSA-SHA256', Buffer.concat([Buffer.from(`${id}.${timestamp}.`), raw]), publicKey, Buffer.from(signature, 'base64'));
  } catch { return false; }
}
export function chatMessage(payload) {
  if (!Number.isSafeInteger(payload?.broadcaster?.user_id) || typeof payload.content !== 'string' || typeof payload.message_id !== 'string') return null;
  return { id: literal(payload.message_id, 200), broadcaster: String(payload.broadcaster.user_id),
    author: literal(payload.sender?.username, 100) || 'Unknown user', userId: String(payload.sender?.user_id || ''),
    text: literal(payload.content.replace(/\[emote:\d+:([^\]]+)\]/g, '$1'), 2000) };
}
export function createKick(config, fetchImpl = fetch) {
  let publicKey = config.publicKey || '', updated = publicKey ? Date.now() : 0, pending;
  const redirect = `${config.publicURL}/oauth/kick/callback`;
  const api = (path, token, method = 'GET', body) => jsonRequest(fetchImpl, `${API}${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  async function tokens(values) {
    const body = await jsonRequest(fetchImpl, `${OAUTH}/token`, { method: 'POST',
      body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, ...values }),
    });
    if (!body.access_token || !body.refresh_token || !(Number(body.expires_in) > 0)) throw new Error('Invalid token response');
    return { access: body.access_token, refresh: body.refresh_token, expires: Date.now() + Number(body.expires_in) * 1000 };
  }
  async function subscribe(session) {
    const current = await api(`/events/subscriptions?broadcaster_user_id=${session.user}`, session.tokens.access);
    if (!current.data?.some(s => s.event === 'chat.message.sent' && String(s.broadcaster_user_id) === session.user && s.method === 'webhook')) {
      const created = await api('/events/subscriptions', session.tokens.access, 'POST', { events: [{ name: 'chat.message.sent', version: 1 }], method: 'webhook' });
      if (!created.data?.some(s => s.name === 'chat.message.sent' && s.subscription_id && !s.error)) throw new Error('Subscription failed');
    }
    session.checked = Date.now();
  }
  return {
    configured: Boolean(config.clientId && config.clientSecret && config.publicURL.startsWith('https://')),
    authorizeURL(state, verifier) {
      return `${OAUTH}/authorize?${new URLSearchParams({ client_id: config.clientId, response_type: 'code', redirect_uri: redirect,
        scope: 'user:read events:subscribe', state, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' })}`;
    },
    async authorize(session, code, verifier) {
      session.tokens = await tokens({ grant_type: 'authorization_code', code, code_verifier: verifier, redirect_uri: redirect });
      const user = (await api('/users', session.tokens.access)).data?.[0];
      if (!Number.isSafeInteger(user?.user_id)) throw new Error('Invalid user');
      session.user = String(user.user_id); session.channel = literal(user.name, 100) || session.user;
      await subscribe(session);
    },
    start(session, hooks) { hooks.status('connected', 'Kick connected. Waiting for live chat.'); return () => {}; },
    async maintain(session) {
      if (session.tokens.expires - Date.now() < 120000) session.tokens = await tokens({ grant_type: 'refresh_token', refresh_token: session.tokens.refresh });
      if (Date.now() - (session.checked || 0) > 60000) await subscribe(session);
    },
    async verify(headers, raw) {
      if (!publicKey || Date.now() - updated > 3600000) {
        if (!pending) pending = jsonRequest(fetchImpl, `${API}/public-key`).then(body => {
          if (!body.data?.public_key) throw new Error('Missing public key');
          publicKey = body.data.public_key; updated = Date.now();
        }).finally(() => { pending = null; });
        await pending;
      }
      return verifyWebhook(headers, raw, publicKey);
    },
  };
}
