# Kick chat — Godot component

Owner branch: `twitch-chat`. Provider: **Kick**. Godot 4.7.2 standard.

This feature now runs inside the shared Godot project. The standalone native Mac
app sources and build entry point have been removed. No separate desktop chat
app needs to be launched. The public Kick webhook relay remains necessary for
receiving events from Kick.

## User behavior

- Chat starts at the bottom right of the game viewport.
- Each message displays `username: message`, using the actual Kick sender name.
- A black panel sits behind the text. Background opacity is adjustable from
  0% (fully transparent) to 100% (solid black), with a default of 35%.
- Text stays opaque at every background setting. Both names and message bodies
  are literal text, so user-supplied markup cannot alter the UI.
- Hold Option/Alt and drag the chat to move it. Ordinary clicks pass through to
  gameplay. Position remains inside the viewport on resize.
- Shared Streamer Mode and CHAT preference show/hide the overlay.
- Account sign-in, status, opacity slider and reset position are in an embedded
  Godot settings panel. Sign-in opens the normal Kick consent page in a browser;
  reception and rendering then run inside Godot.

## Integration after merge

Instantiate `addons/streamer_mode/chat/kick_chat.tscn` as a child of your game's
root (it already has a CanvasLayer), bind the shared controller, and open its
settings from the game's UI:

```gdscript
const KickChat = preload("res://addons/streamer_mode/chat/kick_chat.tscn")
var chat = KickChat.instantiate()
chat.relay_url = your_team_relay_https_origin
chat.bind_controller(controller) # Also works after add_child().
add_child(chat)
chat.open_settings()
```

Public API:

- `bind_controller(controller)` — synchronize shared master/CHAT state.
- `open_settings()` / `close_settings()` — show/hide embedded settings.
- `connect_account(address)` — clear previous messages and start Kick OAuth.
- `disconnect_chat()` — stop polling, remove the relay session and clear chat.
- `set_background_opacity(value)` — 0.0–1.0, synchronized with the settings slider.
- `overlay.reset_position()` — return to the lower-right corner.
- `client.status_changed(state, detail)` — connection feedback for a host UI.
- `client.message_received(author, message)` — parsed Kick message signal.

Appearance/position preferences are session-only. The host may persist them in
its own settings. Hiding Streamer Mode does not sign the account out; use
`disconnect_chat()` if background reception is unwanted. Bind an existing
controller explicitly; the addon does not create a global autoload.

The integration owner still owns `demo/` and `project.godot`. This branch changes
only the chat addon and its tests, and does not merge other branches. The main
foundation demo remains unchanged until integration. This embedded component
renders inside the host Godot game, rather than above arbitrary external games.

## Test now, without merging

Import the repository's `project.godot`. Open `tests/chat/playground.tscn` and run
that scene with F6 (not F5, which starts the unchanged foundation demo).

1. Click **Add OFFLINE test messages** for labeled samples with two usernames.
2. Open **Kick chat settings / background opacity**.
3. Move the opacity slider through 0%, 50% and 100%; only the panel changes.
4. Close settings, drag the chat with Option/Alt, and test Streamer Mode off/on.
5. For live chat, enter the relay HTTPS origin and click **Connect my Kick account**.
   Complete Kick consent and return to Godot. Send a real channel message and
   verify the sender name and content. Offline samples are cleared on login.

`KICK_RELAY_URL` may prefill the test scene's address through the launch
process environment; no tunnel address or credentials are hardcoded in source.

## Kick webhook relay

Run `kick/relay/server.mjs` using Node 22+. Register a Kick application with
`user:read events:subscribe`, enable webhooks, and set:

- Redirect URI: `https://your-relay.example/oauth/callback`
- Webhook URL: `https://your-relay.example/webhooks/kick`

Set `KICK_CLIENT_ID`, `KICK_CLIENT_SECRET`, `KICK_RELAY_PUBLIC_URL`, `HOST` and
`PORT` in private server configuration. A tracked `.env.example` and Dockerfile
are provided. Actual `.env` files, access tokens and secrets are ignored by git.

```sh
cd addons/streamer_mode/chat/kick/relay
node --env-file=.env server.mjs
```

The relay uses PKCE and single-use OAuth state. Kick access/refresh tokens stay
on the server; Godot receives only a temporary bearer session key. Webhooks are
verified against Kick's RSA public key and timestamp, deduplicated and routed
by the authenticated broadcaster ID. Sender names come from `sender.username`.
A missing sender is labeled `Unknown user`, never inferred from the broadcaster.

Subscriptions are checked and tokens refreshed while the session is active.
Relay sessions expire after 30 minutes idle and are lost on server restart.
At most 100 recent messages are retained per session in memory. No chat is stored
on disk. Disconnect removes the local session; Kick app subscriptions can remain
and be reused. Users may revoke the app through Kick account settings.

The relay needs HTTPS or a development tunnel for Kick to reach it. The server
and tunnel must stay running during tests. Do not publish secret values, session
keys or OAuth query strings in logs. Before public deployment, configure TLS and
proxy rate limits. This is a bounded single-process hackathon relay (100 sessions),
not a horizontally scaled service. Emotes appear as names; moderation deletion
and unlimited history replay are not implemented.

## Automated checks

```sh
node --test tests/chat/kick/relay.test.mjs
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/chat/test_chat.gd
godot --headless --path . --script res://tests/test_foundation.gd
```

Checks cover names, literal text, opacity limits/slider wiring/text opacity,
bounded history, controller binding, scene settings, viewport clamping, cursor
filtering, OAuth replay rejection, signed webhook delivery, channel isolation,
credential isolation and disconnect. Live Kick delivery was user-confirmed on
the earlier native prototype; the new embedded Godot flow needs its own live
sign-in verification.

Official protocol references:
- https://docs.kick.com/getting-started/generating-tokens-oauth2-flow
- https://docs.kick.com/events/webhook-security
- https://docs.kick.com/events/event-types
- https://api.kick.com/swagger/doc.yaml
