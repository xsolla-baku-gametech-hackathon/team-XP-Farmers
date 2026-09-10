# XP Farmers — Chat Studio

Standalone **Kick + Twitch + YouTube live chat overlay** for streamers. Open Chat Studio,
connect your own channel, enable **Streamer Mode**, and add your private overlay
link to OBS. No Godot, game integration, extension or desktop build is required.

This `twitch-chat` branch replaces the previous Godot addon. It has **not been
merged** into `main` or the other feature branches.

## Run locally

Install Node.js 22 or newer, then run from the repository root:

```sh
node server/index.mjs
```

Open **http://localhost:8787**. The studio works immediately with clearly labeled
sample messages for styling. Live connections require the service owner's provider
configuration below. There are no npm dependencies or frontend build steps.

To load a private `.env` file:

```sh
cp .env.example .env
node --env-file=.env server/index.mjs
```

`npm start`, `npm run dev`, and `npm test` are optional shortcuts.

## Streamer workflow

1. Open the service's Chat Studio URL and choose **Kick**, **Twitch** or **YouTube**.
2. Click **Connect** and authorize your own account on the platform's sign-in page.
3. Set background opacity (0–100%), text size and corner position. Default opacity is **35%**.
4. Leave **Streamer Mode** on and click **Copy link**.
5. In OBS, add **Sources → Browser**, paste the link, and set width **1920**, height **1080**.
6. Send a message in your platform's chat. The overlay shows the actual sender's
   username and message. The page surrounding the chat is transparent; changing
   background opacity does not dim usernames or text.

For YouTube, choose the Google/Brand Account that owns the channel and allow the
read-only YouTube permission. Start a live broadcast with chat enabled. The studio
automatically discovers it within about 30 seconds; before then it shows a waiting
state. Each message includes the viewer’s YouTube display name supplied by the API.

Each session connects **one platform/channel**. To run several overlays, use separate
browser profiles and add each generated URL as its own OBS source. Simultaneous
aggregation of three platforms into one chat feed is not included. If a YouTube
channel has several active broadcasts, the first eligible broadcast returned by
YouTube is used until it ends.

The overlay keeps working when the studio tab is closed. Changing settings updates
existing OBS sources within about a second. Streamer Mode off hides the overlay and
clears history; messages sent while off are not replayed. Disconnect stops reception
and invalidates the overlay. **Replace overlay link** revokes a shared link without
disconnecting the channel; update OBS afterwards.

The overlay appears in the **OBS scene and resulting stream**. This version does
not create an always-on-top window over a game on the streamer's desktop. Use an
OBS preview or a second display to see it locally.

## Service owner setup

Run one Node service behind an HTTPS reverse proxy. Set `PUBLIC_URL` to its exact
public origin and configure any or all three platforms. Each streamer uses their own
OAuth session; provider secrets belong only on your server.

| Provider | Application configuration |
| --- | --- |
| Kick | Set `KICK_CLIENT_ID` and `KICK_CLIENT_SECRET`. Enable webhooks. Redirect URI: `https://YOUR-DOMAIN/oauth/kick/callback`. Webhook: `https://YOUR-DOMAIN/webhooks/kick`. Scopes: `user:read events:subscribe`. |
| YouTube | Enable YouTube Data API v3 and register a Google OAuth **Web application**. Set `YOUTUBE_CLIENT_ID` and `YOUTUBE_CLIENT_SECRET`. Redirect URI: `https://YOUR-DOMAIN/oauth/youtube/callback`. Scope: `https://www.googleapis.com/auth/youtube.readonly`. |
| Twitch | Register a confidential application. Set `TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET`. Redirect URI: `https://YOUR-DOMAIN/oauth/twitch/callback`. Scope: `user:read:chat`. EventSub WebSockets receive the connected broadcaster's own chat. |

GitHub stores and distributes the code. **GitHub Pages alone cannot run this
service**: OAuth token exchange, Kick webhooks, Twitch/YouTube connections and persistence
require the Node server. See [deployment instructions](docs/DEPLOYMENT.md).

For durable sessions, set `DATA_FILE` and `SESSION_SECRET`. The service encrypts
provider tokens, settings and overlay keys using AES-256-GCM. Without `DATA_FILE`,
development sessions are memory-only and links expire on restart. Production mode
refuses to start without HTTPS and encrypted persistence.

## Behavior and limits

- Separate owner cookies and read-only overlay keys; OAuth tokens never reach the browser.
- Overlay keys are URL fragments, so they are not sent in page URLs or referrers.
  The overlay sends its key only in the authorization header to this service.
- Settings survive reloads. With encrypted storage, sessions and links survive
  server restarts. Chat contents and pending sign-ins are never saved to disk.
- Up to **100 active sessions**, seven-day idle expiry, 100 messages in memory per
  session, last 12 rendered, and messages age out after two minutes. This is a
  single-process service; do not run replicas against the same data file.
- Automatic provider-token refresh, Twitch hourly token validation, EventSub
  reconnect/keepalive handling, Kick signature verification and delivery deduplication.
- Twitch message deletion, user-message clearing and chat clearing remove visible messages.
  YouTube ban events and deletion/tombstone events remove messages when supplied by the API.
  **Kick moderation deletion is not implemented**; messages expire after two minutes.
- Text and usernames render literally, including HTML-like content. Emotes render
  as text. No chat-sending capability is requested.
- Browser polling adds about one second of latency. YouTube uses the documented
  `liveChatMessages.list` API, polling no faster than five seconds and respecting
  any longer `pollingIntervalMillis` returned by YouTube. API quota is shared by all
  YouTube sessions; plan capacity before selling access (see deployment guide).
  Network interruptions blank the overlay until reconnection; messages missed during downtime cannot be recovered.
- This is a deployable product foundation. Billing, license enforcement, account
  recovery, multi-replica storage, commercial support and load certification are not included.

## Validation

```sh
node --test tests/*.test.mjs
```

Tests cover OAuth browser binding/replay, token isolation, multiple streamers,
malformed input/CSRF, signed Kick events, message limits, opacity/mode settings,
link revocation, encrypted restart persistence, Twitch EventSub subscriptions,
reconnect and moderation, YouTube offline OAuth/refresh, broadcast discovery,
cursors, polling intervals, history filtering, stream transitions and quota errors.
Provider calls are mocked in automated tests.

Before selling access, configure real provider apps and run the live acceptance
steps in [deployment instructions](docs/DEPLOYMENT.md), including an OBS recording.
Passing mocked tests does not certify real-account delivery.

## Azərbaycanca qısa istifadə

Godot lazım deyil. Paneli açın → Kick/Twitch/YouTube hesabınızı qoşun → **Streamer Mode**
aktiv edin → **Copy link** → OBS-də **Browser Source** əlavə edib linki yapışdırın.
Çata yazan şəxsin username-i hər mesajda görünür. Fonun şəffaflığını **Background
opacity** ilə dəyişin; yazıların görünməsi dəyişmir. Kod GitHub-dadır, canlı xidmət
üçün isə HTTPS üzərindən işləyən Node server və platforma tətbiq açarları lazımdır.

## Protocol references

- [Kick OAuth](https://docs.kick.com/getting-started/generating-tokens-oauth2-flow)
- [Kick webhook security](https://docs.kick.com/events/webhook-security)
- [Twitch EventSub WebSockets](https://dev.twitch.tv/docs/eventsub/handling-websocket-events/)
- [Twitch chat events](https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/#channelchatmessage)
- [Twitch token validation](https://dev.twitch.tv/docs/authentication/validate-tokens/)
- [YouTube live broadcasts](https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/list)
- [YouTube live chat polling](https://developers.google.com/youtube/v3/live/docs/liveChatMessages/list)
- [Google server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server)
