import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { random, defaults, settingsPatch, addMessage } from './common.mjs';
import { createKick, chatMessage } from './providers/kick.mjs';
import { createTwitch } from './providers/twitch.mjs';
import { createStorage } from './storage.mjs';

const IDLE_TTL = 7 * 24 * 3600000;
const files = { '/': 'index.html', '/overlay': 'overlay.html', '/styles.css': 'styles.css',
  '/studio.mjs': 'studio.mjs', '/overlay.mjs': 'overlay.mjs', '/chat.mjs': 'chat.mjs', '/favicon.svg': 'favicon.svg' };
const mime = { html: 'text/html; charset=utf-8', css: 'text/css; charset=utf-8', mjs: 'text/javascript; charset=utf-8', svg: 'image/svg+xml' };

export function createApp(config, dependencies = {}) {
  const publicURL = new URL(config.publicURL).origin;
  const secure = publicURL.startsWith('https:');
  const providers = dependencies.providers || {
    kick: createKick({ publicURL, ...config.kick }), twitch: createTwitch({ publicURL, ...config.twitch }),
  };
  const storage = createStorage(config.dataFile, config.sessionSecret);
  const sessions = new Map(), rates = new Map(), deliveries = new Map();
  const persist = () => storage.save(sessions);
  function cookie(key, age = IDLE_TTL / 1000) {
    return `xp_session=${key}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${age}${secure ? '; Secure' : ''}`;
  }
  function owner(req) {
    const match = req.headers.cookie?.match(/(?:^|;\s*)xp_session=([A-Za-z0-9_-]{43})(?:;|$)/);
    return match?.[1];
  }
  function remove(key) {
    const session = sessions.get(key);
    if (session) { session.stop?.(); session.tokens = null; session.messages = []; sessions.delete(key); }
  }
  function hooks(session) {
    return {
      status(state, detail) { session.state = state; session.detail = detail; },
      message(message) { if (session.settings.enabled && message?.broadcaster === session.user) addMessage(session, message); },
      remove({ id, userId, all }) { session.messages = session.messages.filter(m => !(all || (id && m.id === id) || (userId && m.userId === userId))); },
    };
  }
  async function maintain(session) {
    if (!session.tokens || session.maintenance || session.state === 'error') return;
    session.maintenance = true;
    try { await providers[session.provider].maintain(session); }
    catch { session.stop?.(); session.state = 'error'; session.detail = 'Channel access expired. Disconnect and connect again.'; session.tokens = null; session.messages = []; }
    finally { session.maintenance = false; }
  }
  for (const [key, saved] of storage.load()) {
    if (Date.now() - saved.touched > IDLE_TTL || !providers[saved.provider]?.configured) continue;
    const session = { ...saved, state: 'connecting', detail: 'Restoring channel connection…', messages: [] };
    sessions.set(key, session);
    void maintain(session).then(() => {
      if (sessions.get(key) === session && session.tokens) session.stop = providers[session.provider].start(session, hooks(session));
    });
  }
  function cleanup() {
    for (const [key, session] of sessions) {
      if (Date.now() - session.touched > IDLE_TTL || (!session.tokens && Date.now() - (session.created || session.touched) > 600000)) remove(key);
    }
    for (const [key, value] of rates) if (Date.now() > value.until) rates.delete(key);
    for (const [key, until] of deliveries) if (Date.now() > until) deliveries.delete(key);
  }
  const timer = setInterval(() => {
    cleanup();
    void Promise.all([...sessions.values()].map(maintain)).then(persist).catch(() => {
      // No credentials, callback query strings or chat content in logs.
      console.error('Session persistence failed; check storage permissions and free space.');
    });
  }, 30000);
  timer.unref();
  function snapshot(session, control = false) {
    session.messages = session.messages.filter(m => Date.now() - m.receivedAt < 120000);
    return { provider: session.provider, channel: session.channel, state: session.state, detail: session.detail,
      settings: session.settings, messages: session.settings.enabled && session.state === 'connected' ? session.messages : [],
      ...(control ? { overlayURL: session.user ? `${publicURL}/overlay#${session.overlayKey}` : null } : {}),
    };
  }
  function send(res, status, value, headers = {}) {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', ...headers });
    res.end(JSON.stringify(value));
  }
  async function body(req) {
    const chunks = []; let length = 0;
    for await (const chunk of req) {
      length += chunk.length;
      if (length > 64 * 1024) throw Object.assign(new Error('Request too large'), { status: 413 });
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
    if (secure) res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    try {
      cleanup();
      const url = new URL(req.url, publicURL), path = url.pathname;
      if (req.method === 'GET' && path === '/health') return send(res, 200, { ok: true });
      if (req.method === 'GET' && files[path]) {
        const file = files[path], content = await readFile(fileURLToPath(new URL(`../public/${file}`, import.meta.url)));
        res.writeHead(200, { 'Content-Type': mime[file.split('.').pop()] }); return res.end(content);
      }
      if (req.method === 'GET' && path === '/api/config') return send(res, 200, {
        providers: Object.fromEntries(Object.entries(providers).map(([name, provider]) => [name, provider.configured])),
      });
      if (path.startsWith('/api/') && !['GET', 'HEAD'].includes(req.method)) {
        if (req.headers['x-chat-studio'] !== '1' || (req.headers.origin && req.headers.origin !== publicURL)) return send(res, 403, { error: 'Open Chat Studio on its configured address and try again.' });
      }
      if (req.method === 'POST' && path === '/api/session') {
        let values;
        try { values = JSON.parse(await body(req)); } catch (error) { if (error.status) throw error; return send(res, 400, { error: 'Invalid JSON' }); }
        const provider = providers[values?.provider];
        if (!Object.hasOwn(providers, values?.provider || '') || !provider) return send(res, 400, { error: 'Choose Kick or Twitch.' });
        if (!provider.configured) return send(res, 503, { error: `${values.provider === 'kick' ? 'Kick' : 'Twitch'} is not configured. The service owner needs to add app credentials on the server.` });
        const ip = req.socket.remoteAddress;
        const rate = rates.get(ip) || { count: 0, until: Date.now() + 60000 };
        rates.set(ip, rate);
        if (++rate.count > 20 || rates.size > 10000) return send(res, 429, { error: 'Too many connection attempts. Try again in one minute.' });
        const old = owner(req);
        if (sessions.has(old)) return send(res, 409, { error: 'Disconnect the current channel before connecting another.' });
        if (sessions.size >= (config.maxSessions || 100)) return send(res, 429, { error: 'The service is at capacity. Try again later.' });
        let settings;
        try { settings = { ...defaults, ...settingsPatch(values.settings || {}) }; } catch { return send(res, 400, { error: 'Invalid settings' }); }
        const key = random(), state = random(), verifier = random();
        const session = { provider: values.provider, state: 'connecting', detail: 'Finish connecting your account in the sign-in window.',
          channel: '', user: null, created: Date.now(), touched: Date.now(), oauth: { state, verifier }, overlayKey: random(), settings, messages: [] };
        sessions.set(key, session);
        return send(res, 201, { authorizeURL: provider.authorizeURL(state, verifier) }, { 'Set-Cookie': cookie(key) });
      }
      const callback = path.match(/^\/oauth\/(kick|twitch)\/callback$/);
      if (req.method === 'GET' && callback) {
        const key = owner(req), session = sessions.get(key);
        if (!session?.oauth || session.provider !== callback[1] || session.oauth.state !== url.searchParams.get('state') || Date.now() - session.created > 600000) return send(res, 400, { error: 'This sign-in expired or belongs to another browser. Connect again from Chat Studio.' });
        const { verifier } = session.oauth; session.oauth = null;
        try {
          if (url.searchParams.has('error') || !url.searchParams.get('code')) throw new Error('Sign-in cancelled');
          await providers[session.provider].authorize(session, url.searchParams.get('code'), verifier);
          if (sessions.get(key) !== session) return send(res, 400, { error: 'Connection was cancelled.' });
          session.stop = providers[session.provider].start(session, hooks(session));
          persist();
        } catch {
          session.stop?.(); session.tokens = null; session.state = 'error'; session.detail = 'Account connection failed or was cancelled. Disconnect and try again.';
        }
        res.writeHead(303, { Location: '/' }); return res.end();
      }
      if (path === '/api/session' || path === '/api/settings' || path === '/api/overlay/rotate') {
        const key = owner(req), session = sessions.get(key);
        if (!session) return send(res, 401, { error: 'No active session. Connect a channel.' });
        session.touched = Date.now();
        if (req.method === 'DELETE' && path === '/api/session') {
          remove(key); persist(); return send(res, 200, { ok: true }, { 'Set-Cookie': cookie('', 0) });
        }
        if (req.method === 'PATCH' && path === '/api/settings') {
          try { Object.assign(session.settings, settingsPatch(JSON.parse(await body(req)))); }
          catch (error) { if (error.status) throw error; return send(res, 400, { error: 'Invalid settings' }); }
          if (!session.settings.enabled) session.messages = [];
          persist(); return send(res, 200, snapshot(session, true));
        }
        if (req.method === 'POST' && path === '/api/overlay/rotate') {
          session.overlayKey = random(); persist(); return send(res, 200, snapshot(session, true));
        }
        if (req.method === 'GET' && path === '/api/session') return send(res, 200, snapshot(session, true), { 'Set-Cookie': cookie(key) });
        return send(res, 405, { error: 'Method not allowed' });
      }
      if (req.method === 'GET' && path === '/api/overlay') {
        const key = req.headers.authorization?.replace(/^Bearer /, '');
        const session = /^[A-Za-z0-9_-]{43}$/.test(key || '') ? [...sessions.values()].find(s => s.overlayKey === key) : null;
        if (!session || !session.user) return send(res, 401, { error: 'Overlay link expired. Create a new link in Chat Studio.' });
        session.touched = Date.now();
        return send(res, 200, snapshot(session));
      }
      if (req.method === 'POST' && path === '/webhooks/kick') {
        if (!providers.kick?.configured) return send(res, 503, { error: 'Kick is not configured' });
        const raw = await body(req);
        if (!await providers.kick.verify(req.headers, raw)) return send(res, 401, { error: 'Invalid signature or timestamp' });
        if (req.headers['kick-event-type'] !== 'chat.message.sent' || req.headers['kick-event-version'] !== '1') return send(res, 200, { ignored: true });
        let message;
        try { message = chatMessage(JSON.parse(raw)); } catch { /* Invalid signed event */ }
        if (!message) return send(res, 400, { error: 'Invalid chat event' });
        const id = req.headers['kick-event-message-id'];
        if (deliveries.has(id)) return send(res, 200, { ok: true });
        if (deliveries.size >= 20000) return send(res, 503, { error: 'Delivery capacity reached; retry later.' });
        deliveries.set(id, Date.now() + 300000);
        for (const session of sessions.values()) if (session.provider === 'kick' && session.state === 'connected') hooks(session).message(message);
        return send(res, 200, { ok: true });
      }
      return send(res, 404, { error: 'Not found' });
    } catch (error) {
      if (!res.headersSent) send(res, error.status || 503, { error: error.status === 413 ? 'Request too large' : 'Service temporarily unavailable. Try again.' });
      else res.end();
    }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000;
  server.on('close', () => { clearInterval(timer); for (const session of sessions.values()) session.stop?.(); });
  return server;
}
