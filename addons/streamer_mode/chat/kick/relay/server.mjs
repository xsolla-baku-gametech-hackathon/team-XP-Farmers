import http from 'node:http';
import { createHash, randomBytes, verify } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const random = () => randomBytes(32).toString('base64url');
const API = 'https://api.kick.com/public/v1';
const OAUTH = 'https://id.kick.com/oauth';
const MAX_BODY = 64 * 1024;
const IDLE_TTL = 30 * 60 * 1000;

export function verifyWebhook(headers, raw, publicKey, now = Date.now()) {
  const id = headers['kick-event-message-id'];
  const timestamp = headers['kick-event-message-timestamp'];
  const signature = headers['kick-event-signature'];
  if (![id, timestamp, signature].every(v => typeof v === 'string' && v.length < 2048)) return false;
  const age = Math.abs(now - Date.parse(timestamp));
  if (!Number.isFinite(age) || age > 5 * 60 * 1000) return false;
  try {
    return verify('RSA-SHA256', Buffer.concat([Buffer.from(`${id}.${timestamp}.`), raw]), publicKey, Buffer.from(signature, 'base64'));
  } catch { return false; }
}

export function chatMessage(payload) {
  if (!Number.isSafeInteger(payload?.broadcaster?.user_id) || typeof payload.content !== 'string' || typeof payload.message_id !== 'string') return null;
  return { id: payload.message_id.slice(0, 200), broadcaster: payload.broadcaster.user_id,
    text: payload.content.replace(/\[emote:\d+:([^\]]+)\]/g, '$1').slice(0, 2000) };
}

export function createRelay(config, fetchImpl = fetch) {
  const sessions = new Map();
  let publicKey = config.publicKey || '';
  let keyUpdated = publicKey ? Date.now() : 0;
  let keyPending;
  async function getKey() {
    if (publicKey && Date.now() - keyUpdated < 3600000) return publicKey;
    if (!keyPending) keyPending = (async () => {
      const reply = await fetchImpl(`${API}/public-key`, { signal: AbortSignal.timeout(10000) });
      if (!reply.ok) throw new Error('Kick public key unavailable');
      const body = await reply.json();
      if (!body.data?.public_key) throw new Error('Invalid public key');
      publicKey = body.data.public_key;
      keyUpdated = Date.now();
      return publicKey;
    })().finally(() => { keyPending = undefined; });
    return keyPending;
  }
  function cleanup() {
    for (const [key, session] of sessions) {
      if (Date.now() - session.touched > IDLE_TTL) sessions.delete(key);
    }
  }
  async function kick(path, token, method = 'GET', body) {
    const reply = await fetchImpl(`${API}${path}`, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000) });
    if (!reply.ok) throw new Error(`Kick API request failed (${reply.status})`);
    return reply.json();
  }
  async function tokenRequest(values) {
    const reply = await fetchImpl(`${OAUTH}/token`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, ...values }), signal: AbortSignal.timeout(10000) });
    if (!reply.ok) throw new Error('Kick authorization expired or was refused. Please connect again.');
    const result = await reply.json();
    if (!result.access_token || !result.refresh_token || !(Number(result.expires_in) > 0)) throw new Error('Invalid Kick token response');
    return { access: result.access_token, refresh: result.refresh_token, expires: Date.now() + Number(result.expires_in) * 1000 };
  }
  async function ensureSubscription(session) {
    const existing = await kick(`/events/subscriptions?broadcaster_user_id=${session.user}`, session.tokens.access);
    if (!existing.data?.some(s => s.event === 'chat.message.sent' && s.broadcaster_user_id === session.user && s.method === 'webhook')) {
      const created = await kick('/events/subscriptions', session.tokens.access, 'POST', { events: [{ name: 'chat.message.sent', version: 1 }], method: 'webhook' });
      if (!created.data?.some(s => s.name === 'chat.message.sent' && s.subscription_id && !s.error)) throw new Error('Kick chat subscription was not accepted. Check webhook setup.');
    }
    session.checked = Date.now();
  }
  async function maintain(session) {
    if (session.state !== 'connected') return;
    if (session.maintenance) return session.maintenance;
    session.maintenance = (async () => {
      try {
        if (session.tokens.expires - Date.now() < 60000) session.tokens = await tokenRequest({ grant_type: 'refresh_token', refresh_token: session.tokens.refresh });
        if (Date.now() - session.checked > 60000) await ensureSubscription(session);
      } catch {
        session.state = 'error'; session.detail = 'Kick access needs attention. Disconnect and connect again.';
        session.tokens = null;
      }
    })().finally(() => { session.maintenance = null; });
    return session.maintenance;
  }
  function send(res, status, value) {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(JSON.stringify(value));
  }
  async function readBody(req) {
    const chunks = []; let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > MAX_BODY) throw new Error('Request too large');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }
  const server = http.createServer(async (req, res) => {
    try {
      cleanup();
      const url = new URL(req.url, 'http://relay.local');
      if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });
      if (req.method === 'POST' && url.pathname === '/sessions') {
        // Native clients only; deny browser-origin session creation. Configure proxy rate limits too.
        if (req.headers.origin) return send(res, 403, { error: 'Native client required' });
        if (!config.clientId || !config.clientSecret || !config.publicURL) return send(res, 503, { error: 'Relay needs Kick application configuration' });
        if (sessions.size >= 100) return send(res, 429, { error: 'Relay at capacity. Try later.' });
        const key = random(), state = random(), verifier = random();
        sessions.set(key, { state: 'connecting', detail: 'Finish signing in to Kick in your browser.', oauthState: state, verifier,
          created: Date.now(), touched: Date.now(), user: null, channel: '', messages: [], seen: new Set(), sequence: 0, checked: 0 });
        const authorize = new URL(`${OAUTH}/authorize`);
        authorize.search = new URLSearchParams({ client_id: config.clientId, response_type: 'code', redirect_uri: `${config.publicURL}/oauth/callback`,
          scope: 'user:read events:subscribe', state, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
        return send(res, 201, { session_key: key, authorize_url: authorize.href });
      }
      if (req.method === 'GET' && url.pathname === '/oauth/callback') {
        const state = url.searchParams.get('state');
        const session = [...sessions.values()].find(s => s.oauthState && s.oauthState === state);
        if (!session || Date.now() - session.created > 600000) return send(res, 400, { error: 'Expired authorization. Connect again from the app.' });
        session.oauthState = null; // Consume state once, even on failure.
        try {
          if (url.searchParams.has('error') || !url.searchParams.get('code')) throw new Error('Authorization cancelled');
          session.tokens = await tokenRequest({ grant_type: 'authorization_code', code: url.searchParams.get('code'), code_verifier: session.verifier, redirect_uri: `${config.publicURL}/oauth/callback` });
          session.verifier = null;
          const user = (await kick('/users', session.tokens.access)).data?.[0];
          if (!Number.isSafeInteger(user?.user_id)) throw new Error('Kick user not found');
          session.user = user.user_id; session.channel = String(user.name || user.user_id);
          await ensureSubscription(session);
          session.state = 'connected'; session.detail = 'Kick subscribed. Waiting for a chat message.';
          return send(res, 200, { message: 'Kick connected. Return to XP Farmers Chat.' });
        } catch {
          session.state = 'error'; session.detail = 'Kick connection failed. Check app permissions and webhook settings, then reconnect.';
          session.tokens = null; session.verifier = null;
          return send(res, 400, { error: session.detail });
        }
      }
      if (url.pathname === '/session') {
        const key = req.headers.authorization?.replace(/^Bearer /, '');
        const session = sessions.get(key);
        if (!session) return send(res, 401, { error: 'Session expired. Connect again.' });
        if (req.method === 'DELETE') { sessions.delete(key); return send(res, 200, { ok: true }); }
        if (req.method !== 'GET') return send(res, 405, { error: 'Method not allowed' });
        session.touched = Date.now();
        if (session.state === 'connecting' && Date.now() - session.created > 600000) {
          session.state = 'error'; session.detail = 'Sign-in timed out. Connect again.';
        }
        await maintain(session);
        const after = Number(url.searchParams.get('after') || 0);
        if (!Number.isSafeInteger(after) || after < 0) return send(res, 400, { error: 'Invalid cursor' });
        return send(res, 200, { state: session.state, detail: session.detail, channel: session.channel, cursor: session.sequence,
          messages: session.messages.filter(m => m.sequence > after) });
      }
      if (req.method === 'POST' && url.pathname === '/webhooks/kick') {
        const raw = await readBody(req);
        if (!verifyWebhook(req.headers, raw, await getKey())) return send(res, 401, { error: 'Invalid webhook signature or timestamp' });
        if (req.headers['kick-event-type'] !== 'chat.message.sent' || req.headers['kick-event-version'] !== '1') return send(res, 200, { ignored: true });
        const message = chatMessage(JSON.parse(raw));
        if (!message) return send(res, 400, { error: 'Invalid chat event' });
        for (const session of sessions.values()) {
          if (session.state !== 'connected' || session.user !== message.broadcaster || session.seen.has(message.id)) continue;
          session.seen.add(message.id);
          if (session.seen.size > 1000) session.seen.delete(session.seen.values().next().value);
          session.messages.push({ id: message.id, text: message.text, sequence: ++session.sequence });
          if (session.messages.length > 100) session.messages.shift();
          session.detail = 'Receiving Kick chat';
        }
        return send(res, 200, { ok: true });
      }
      send(res, 404, { error: 'Not found' });
    } catch {
      // Never echo provider responses, authorization codes, tokens, or user content.
      if (!res.headersSent) send(res, 503, { error: 'Relay request failed. Try again.' });
      else res.end();
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const publicURL = (process.env.KICK_RELAY_PUBLIC_URL || '').replace(/\/$/, '');
  if (publicURL && !/^https:\/\/[^/?#]+$/.test(publicURL)) throw new Error('KICK_RELAY_PUBLIC_URL must be an HTTPS origin');
  const server = createRelay({ publicURL, clientId: process.env.KICK_CLIENT_ID, clientSecret: process.env.KICK_CLIENT_SECRET });
  server.listen(Number(process.env.PORT || 8787), process.env.HOST || '127.0.0.1', () => console.log('Kick relay listening. Credentials are never logged.'));
}
