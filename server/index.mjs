import { createApp } from './app.mjs';

const port = Number(process.env.PORT || 8787);
const publicURL = (process.env.PUBLIC_URL || `http://localhost:${port}`).replace(/\/$/, '');
const url = new URL(publicURL);
if (url.origin !== publicURL || (url.protocol !== 'https:' && !['http://localhost', 'http://127.0.0.1'].some(prefix => publicURL === prefix || publicURL.startsWith(`${prefix}:`)))) {
  throw new Error('PUBLIC_URL must be an HTTPS origin, or an HTTP localhost origin for development');
}
if (process.env.NODE_ENV === 'production' && (!process.env.DATA_FILE || !process.env.SESSION_SECRET || url.protocol !== 'https:')) {
  throw new Error('Production requires HTTPS PUBLIC_URL, DATA_FILE and SESSION_SECRET');
}
const server = createApp({ publicURL, dataFile: process.env.DATA_FILE, sessionSecret: process.env.SESSION_SECRET,
  kick: { clientId: process.env.KICK_CLIENT_ID, clientSecret: process.env.KICK_CLIENT_SECRET },
  twitch: { clientId: process.env.TWITCH_CLIENT_ID, clientSecret: process.env.TWITCH_CLIENT_SECRET },
});
server.listen(port, process.env.HOST || '127.0.0.1', () => console.log(`Chat Studio listening on port ${port}.`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.close(); server.closeAllConnections(); });
