# Deploy Chat Studio

## Requirements

- One Node 22+ process, persistent writable storage and an HTTPS domain.
- Kick, Twitch and/or YouTube registered applications. Only configured providers can connect.
- Outbound HTTPS to configured platforms (including `accounts.google.com`,
  `oauth2.googleapis.com` and `www.googleapis.com` for YouTube) and WSS to `eventsub.wss.twitch.tv:443`.
- Public access to the Kick webhook and OAuth callbacks through the same domain.

Copy `.env.example` to `.env`, fill provider keys and set `PUBLIC_URL` to the exact
HTTPS origin (no path, query, fragment or trailing slash). Register the URLs from
the README exactly. Kick cannot deliver webhooks to an unexposed localhost service;
use an HTTPS development tunnel for live tests.

Generate a private persistence key and append it to the local configuration:

```sh
node --input-type=module -e 'import {appendFileSync} from "node:fs"; import {randomBytes} from "node:crypto"; appendFileSync(".env", "\nSESSION_SECRET=" + randomBytes(32).toString("hex") + "\n");'
```

Keep this key stable and backed up securely. Losing it loses access to stored
sessions. Changing it without migrating the file fails startup rather than
silently discarding connections. Remove the empty example assignment if your
environment-file parser does not accept duplicate keys.

## YouTube / Google setup

1. In Google Cloud, enable **YouTube Data API v3** for your project.
2. Configure the OAuth consent screen and create an OAuth client of type
   **Web application**. Add `https://YOUR-DOMAIN/oauth/youtube/callback` as an
   authorized redirect URI. For local testing, register
   `http://localhost:8787/oauth/youtube/callback` separately.
3. Add `YOUTUBE_CLIENT_ID` and `YOUTUBE_CLIENT_SECRET` to your server secrets.
   The app requests only `https://www.googleapis.com/auth/youtube.readonly`, with
   offline access. Grant that permission and select the account/channel that owns
   the stream. No API key, chat-writing scope or viewer sign-in is needed.
4. In Google's testing mode, add the streamers as test users. Before general
   availability, configure the production consent screen, domain and privacy
   policy, and complete any verification required by your declared scopes.
   See [Google's verification guidance](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification).
5. Enable live streaming on the connected YouTube channel. Start a broadcast with
   live chat enabled. The studio checks for an active broadcast every 30 seconds,
   receives new messages and returns to waiting after a broadcast ends. Initial
   chat history and messages published while Streamer Mode was off are excluded.

This dependency-free adapter uses the supported
[`liveChatMessages.list` endpoint](https://developers.google.com/youtube/v3/live/docs/liveChatMessages/list).
It requests up to 2,000 events per response, follows continuation tokens and waits
at least five seconds (or YouTube's longer requested interval) between polls.
Network/rate-limit failures back off automatically; exhausted quota or revoked
access produces an actionable error and stops polling. Reconnect after resolving
it. YouTube quota is shared across the entire Google Cloud project, including
broadcast discovery while waiting. Disconnect unused sessions to stop API usage.

Monitor actual quota use during full-length broadcasts and provision capacity for
the number of streamers sold. See [YouTube's quota extension process](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits).
For larger deployments, YouTube recommends the more efficient
[`streamList` streaming API](https://developers.google.com/youtube/v3/live/streaming-live-chat);
that gRPC transport is not implemented here.

## Docker

```sh
docker compose up --build -d
```

The compose file exposes port 8787 on **127.0.0.1 only**. Terminate TLS in your
existing reverse proxy and forward the configured domain to `127.0.0.1:8787`.
Redirects and origin checks always use `PUBLIC_URL`; forwarded host values are
not trusted. The Docker volume retains encrypted sessions.

For a reverse proxy in another container, place it on the compose network and
forward to `chat:8787`. Keep the chat container off direct public HTTP. Disable
query-string and Authorization/Cookie header logging in the proxy, because OAuth
callbacks include authorization codes.

Apply request-size, connection and per-client rate limits at the edge. The app
also enforces a 64 KiB body limit, a 100-session cap and 20 session creations per
minute per direct peer address. Behind a reverse proxy the peer address is shared,
so the in-process limit acts as an aggregate fallback.

The image runs as the `node` user. Do not share its volume between replicas.
`GET /health` is a process check, not a guarantee of provider health. Monitor
connection failures and disk space as well.

## Direct Node hosting

Set `NODE_ENV=production`, `DATA_FILE=/your-private-data/sessions.enc`,
`SESSION_SECRET`, `PUBLIC_URL` and provider credentials in the host's secret
configuration. The directory must be writable only by the service account.
Run `node server/index.mjs` with a supervisor and HTTPS in front of it.

Sign-in uses an HttpOnly SameSite=Lax cookie with Secure enabled under HTTPS.
Streamers must return through the same browser used to start sign-in. Studio and
overlay use the same origin, but the Godot client uses a cookie-free read-only connection.
Keep overlay links private; replace a link if exposed.

## Live acceptance before release

1. Configure real Kick, Twitch and YouTube apps; repeat these checks on each platform. Connect two streamer accounts in separate
   browser profiles. Verify consent, callback and connected status.
2. Send a real viewer message. Confirm the username/content appears only in the
   correct studio and overlay. Include Unicode and a long message.
3. Run the Godot demo and paste the private link in Settings → Streamer Mode.
   Enable master mode and chat; send a new message after the first snapshot.
   Check background opacity 0/35/100%, opaque text and Alt-drag positioning.
4. Toggle the game's master mode and individual chat preference. Closing settings
   must leave chat enabled; enabling again must not replay old messages.
5. Close the browser tab, keep the game running and send another message.
6. On Twitch, delete a message, clear a user's messages and clear chat. Confirm
   the overlay follows. On YouTube, test viewer bans and message deletions when
   delivered by the API. Kick moderation deletion is not yet implemented.
7. Restart Node with the same data file and secret. Confirm saved links/settings
   survive and reception resumes. No old chat should be restored.
8. Disconnect/reconnect the network. Check stale text is hidden and reception
   recovers. Revoke access and confirm actionable error feedback.
9. Replace the link: the old link must go blank. Disconnect: the active link must
   go blank too. To revoke the provider grant, also remove the app in platform
   account settings; Kick subscriptions may remain and be reused.
10. On YouTube, connect before going live; confirm waiting → live chat → waiting
    → next broadcast. Check no old chat reappears after mode off/on, restart or
    stream changes. Verify quota exhaustion, revoked consent and token refresh.
11. Check the overlay on each supported operating system, target Godot game. If viewers should see it, record a clip using your actual
    broadcasting platform and display-capture setup.

Automated tests mock platform traffic. Real-account OAuth, delivery, rate limits,
token expiry during a full broadcast and Godot integration and broadcast capture remain live release checks.
Do not advertise these as certified until completed.

## Godot distribution

Distribute the chat addon as part of the participating Godot game. No standalone
chat desktop installer is required. The game owner integrates the shared controller
and chat settings; streamers authorize their channel in the relay's browser page
and paste the private link into the game. See the root README for instructions.

## Commercial scope

This supplies a reusable service and self-service streamer interface. Payment
processing, subscriptions, customer entitlements, support tooling and a license
agreement are not included. Decide whether to sell managed access or self-hosted
installations before adding those features. Load-test the concurrency you plan to
sell; in-memory routing and encrypted snapshots target a small single instance.
