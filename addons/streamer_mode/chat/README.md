# Kick chat — macOS companion and optional Godot adapter

Branch remains `twitch-chat`; the requested provider is now **Kick**.
This branch's product is a standalone macOS overlay for messages over other
applications. The shared foundation remains a Godot SDK demo. Both can live in
the repository and be shipped together, but merging does not turn the SDK's
privacy/audio features into system-wide features.

## Implemented

- Native AppKit `.app`: transparent, borderless, message-only panel, bottom right.
- White outlined text; no names, avatars, chat background or browser page.
- Click-through while locked. Use **Çatın yerini dəyiş** to drag, then lock it.
- Saved position, monitor clamping, show/hide, reset and menu-bar controls.
- Floating panel joins Spaces and requests macOS fullscreen auxiliary behavior.
- Browser-based Kick OAuth with PKCE; each streamer signs in to their own account.
- Node relay verifies Kick RSA signatures and timestamp freshness, routes only to
  the authenticated broadcaster, deduplicates and bounds messages.
- Provider access/refresh tokens and app secret remain on the relay; desktop gets
  a temporary, unguessable session key. No credentials are committed.
- Token refresh, subscription rechecks, reconnecting polling and honest status.

## Run the Mac app first

From the repository root (Apple Command Line Tools required):

```sh
sh addons/streamer_mode/chat/kick/macos/build.sh
open 'addons/streamer_mode/chat/kick/macos/builds/XP Farmers Kick Chat.app'
```

Click **Sınaq mesajı (OFFLINE)** to test transparency and placement without any
Kick account. This disconnects live chat and explicitly labels the sample text.
Switch to a game and check the lower-right corner. Use **Çatın yerini dəyiş** to
drag the outlined area, then **Yeri sabitlə** so mouse clicks reach the game.
The settings window can be closed; the menu-bar item reopens it or quits.

The native panel is designed for other apps, including fullscreen Spaces, but
real games and OBS must be tested on the target Mac. Exclusive fullscreen or
unusual game compositors may prevent overlays. Windowed/borderless mode is the
fallback. A game-window-only OBS capture may omit a separate overlay; verify
Display Capture or explicitly compose the overlay. No claim of universal game
compatibility is made. Build is local and unsigned/unnotarized; distribution
signing and notarization are a separate release step.

## Configure live Kick once for the team

Kick's official chat event is a webhook, so a public HTTPS relay is required.
This source does not scrape Kick or pretend that entering a channel name alone
establishes a live connection.

1. Register the team's application in Kick developer settings.
2. Deploy `kick/relay/server.mjs` with Node 22+ behind HTTPS. A Dockerfile is included.
   Put `KICK_CLIENT_ID`, `KICK_CLIENT_SECRET`, and `KICK_RELAY_PUBLIC_URL` into the
   hosting provider's private environment settings. The public URL is an origin
   such as `https://chat.example.com`, without a path or trailing slash.
3. Register the exact redirect URI `https://chat.example.com/oauth/callback`.
4. Enable webhooks and set the callback URL to
   `https://chat.example.com/webhooks/kick` in the Kick application settings.
5. Put `https://chat.example.com` into the Mac application's server field and
   click **Kick hesabımı qoş**. Sign in as the broadcaster and approve the
   `user:read events:subscribe` permissions. No chat-writing permission is used.
6. Send a message in that broadcaster's Kick chat. The app initially reports a
   registered subscription and waits for delivery; only a real webhook changes
   the status to **Receiving Kick chat**.

Local relay startup (the `.env` file must stay untracked):

```sh
cd addons/streamer_mode/chat/kick/relay
cp .env.example .env
# Fill the local file or supply private environment variables through your host.
node --env-file=.env server.mjs
```

A development tunnel may forward a public HTTPS URL to port 8787. Register its
exact HTTPS origin in both Kick and the relay. No tunnel or public deployment
is automatically started by this branch.

## Relay lifetime and limits

Sessions and a maximum of 100 recent messages per session are in memory. Restart
requires users to sign in again. Idle sessions expire after 30 minutes; an active
app polls once per second. Disconnect removes the relay session and stops its
delivery. Kick app-level webhook subscriptions can remain and are reused on the
next login; users can revoke the app in Kick account settings. No chat is written
to disk. Session keys are bearer credentials and should not be put into URLs or
logs. Configure TLS, request/session-creation rate limits and redacted proxy logs
before making the relay public. This small single-process relay caps 100 sessions;
it is a hackathon deployment, not a horizontally scaled hosted service.

Webhook signatures use the official public-key endpoint, cached for an hour.
Events more than five minutes from server time are rejected, so keep the host's
clock synchronized. Text is rendered literally; emote markup is reduced to its
name. Images, moderation deletions and message replay outside the bounded buffer
are not implemented.

## Merge and bundle handoff

Changes stay under `addons/streamer_mode/chat/` and `tests/chat/`; shared
`project.godot`, `demo/`, audio and privacy files are untouched. The old Twitch
client has been replaced by Kick. Native/server sources are behind `.gdignore`
and are not automatically exported by Godot.

The integration owner can ship the generated `.app` beside the Godot app in the
release bundle. Launch it through a bundled-app action or Finder. The relay is a
separately hosted service; never bundle its application secret in the desktop app.
No changes to another game's source are needed for the native chat overlay.

For teams that ALSO want chat embedded in the foundation demo, the optional
`chat_overlay.tscn` and `kick_relay_client.gd` are retained. Instantiate the overlay
under CanvasLayer and pass the shared controller with `bind_controller(controller)`.
Bind the relay client with `bind_client(client)`. Its `connect_session(https_origin,
session_key)` accepts a session established through the relay OAuth flow.
`message_received(author, message)` emits an empty author because this feature
shows only message text. `status_changed(state, detail)` belongs in settings.
The master/CHAT preference hides the in-game Control; it does not control the
separate native app. The integration owner must design any shared desktop toggle
explicitly. `disconnect_chat()` stops the optional adapter's local polling;
DELETE `/session` also removes the server session when appropriate.

`tests/chat/playground.tscn` is the optional Godot preview, not the native desktop
app. Its live test button reads `KICK_RELAY_URL` and `KICK_SESSION_KEY` from the
local environment. Tests are explicitly offline until a valid session is supplied.

## Verification

```sh
node --test tests/chat/kick/relay.test.mjs
sh addons/streamer_mode/chat/kick/macos/build.sh
'addons/streamer_mode/chat/kick/macos/builds/XP Farmers Kick Chat.app/Contents/MacOS/KickChat' --smoke-test
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/chat/test_chat.gd
godot --headless --path . --script res://tests/test_foundation.gd
```

Relay tests use generated signing keys and mocked Kick endpoints: OAuth state
replay, signatures/tampering/staleness, channel isolation, duplicate delivery,
history bounds, cursors, credential isolation and disconnect are checked.
Native build and window-property smoke checks do not prove live Kick delivery,
fullscreen game compatibility or OBS capture. Those need manual verification.

## Official references

- https://docs.kick.com/getting-started/generating-tokens-oauth2-flow
- https://docs.kick.com/events/webhook-security
- https://docs.kick.com/events/event-types
- https://api.kick.com/swagger/doc.yaml
