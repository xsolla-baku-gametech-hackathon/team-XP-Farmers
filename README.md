# XP Farmers — Chat Studio

Standalone **Kick + Twitch + YouTube live chat overlay** for streamers. Open Chat Studio,
connect your own channel, enable **Streamer Mode**, and show chat directly above
your games with the **XP Farmers Chat desktop app**. OBS and Godot are not required.

This `twitch-chat` branch replaces the previous Godot addon. It has **not been
merged** into `main` or the other feature branches.

## Run the studio locally

Install Node.js 22 or newer, then run from the repository root:

```sh
node server/index.mjs
```

Open **http://localhost:8787**. The studio works immediately with clearly labeled
sample messages for styling. Live connections require the service owner's provider
configuration below. The server has no npm dependencies or frontend build steps.
The optional browser preview stays in a browser window; use the desktop app for
a transparent, always-on-top overlay.

To load a private `.env` file:

```sh
cp .env.example .env
node --env-file=.env server/index.mjs
```

`npm start`, `npm run dev`, and `npm test` are optional shortcuts.

## Streamer workflow

1. Install **XP Farmers Chat** on Windows or macOS. Development installers are
   available as artifacts from [Desktop app builds](https://github.com/xsolla-baku-gametech-hackathon/team-XP-Farmers/actions/workflows/desktop.yml).
2. Open your service's Chat Studio in your normal browser. Choose **Kick**,
   **Twitch** or **YouTube**, then authorize your own channel.
3. Set background opacity (0–100%), text size and corner. Default opacity is **35%**.
4. Enable **Streamer Mode** and click **Show on screen**. This opens the installed
   desktop app with your private link. Choose a display, then click **Start overlay**.
5. If the browser cannot open the app, click **Copy link**, paste it into the desktop
   app's **Private overlay link** field and click **Start overlay**.
6. Send a message in your channel's chat. The actual sender's name and message
   appear above your other windows. The surrounding desktop stays transparent,
   text remains opaque, and mouse clicks pass through the chat to the game.

Adjust appearance in the browser studio. Keep the desktop app running; its controls
can be minimized. **Stop overlay** stops the local window. **Streamer Mode off**
hides chat and discards new messages; **Disconnect** ends the provider connection.
Replacing the private link invalidates the old one, so use **Show on screen** again.
Desktop overlay links stay in memory and must be supplied again after quitting the app.

For YouTube, select the Google/Brand Account that owns the channel and allow the
read-only YouTube permission. Start a broadcast with chat enabled; the studio finds
it within about 30 seconds. Each message includes the viewer's API-provided display
name. The studio returns to waiting when the broadcast ends.

Each session connects **one platform/channel**. The desktop app displays one overlay
at a time. Combining three chats into one feed is not implemented. When a YouTube
channel has multiple live broadcasts, the first eligible broadcast returned by
YouTube is used until it ends.

The app displays chat on **your desktop**; it does not transmit video or audio.
For viewers to see that same chat, your broadcasting platform/tool must capture
that desktop/display, including the overlay. A capture of only the game window
may exclude it. Use borderless/windowed games; exclusive fullscreen and individual
game/OS restrictions can prevent other windows from appearing above a game.

## Run or build the desktop app

With Node 22+ and npm installed:

```sh
cd desktop
npm ci
npm start
```

Open the studio in a browser, copy its overlay link, and paste it into the desktop
app. URL launching through **Show on screen** is registered by packaged apps;
development mode deliberately does not change OS protocol associations.

To package for the current OS, run `npm run dist` from `desktop/`. The desktop CI
builds Windows x64 and macOS ARM64/x64 artifacts without publishing a release or
merging any branch. These are unsigned development builds; distribution signing
and macOS notarization must be configured before a commercial release. See the
[desktop deployment notes](docs/DEPLOYMENT.md#desktop-distribution).

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
link revocation, encrypted restart persistence, desktop URL boundaries and sandbox
configuration, Twitch EventSub subscriptions,
reconnect and moderation, YouTube offline OAuth/refresh, broadcast discovery,
cursors, polling intervals, history filtering, stream transitions and quota errors.
Provider calls are mocked in automated tests.

Before selling access, configure real provider apps and run the live acceptance
steps in [deployment instructions](docs/DEPLOYMENT.md), including the desktop overlay and your actual broadcast capture.
Passing mocked tests does not certify real-account delivery.

## Azərbaycanca qısa istifadə

OBS və Godot lazım deyil. XP Farmers Chat tətbiqini açın → brauzerdə panelə daxil
olub Kick/Twitch/YouTube hesabınızı qoşun → **Streamer Mode** aktiv edin →
**Show on screen** → tətbiqdə ekranı seçin və **Start overlay** basın.
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
