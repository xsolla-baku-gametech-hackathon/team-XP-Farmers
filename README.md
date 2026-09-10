# XP Farmers · Godot Streamer Mode

`twitch-chat` provides **in-game chat for Godot games**, using the shared
`StreamerModeController`. Twitch, Kick and YouTube connect through a Node relay.
There is no Electron companion or OBS dependency. No feature branches have been merged.

## Run the Godot demo

1. Check out `twitch-chat` and import root `project.godot` in Godot 4.7.2.
2. Press F5 and click **Connect channel / Chat settings**.
3. Select Kick, Twitch or YouTube and click **Connect channel**. Your normal
   browser opens. Click **Continue to platform**, check the signed-in account,
   and approve access. Return to Godot: the channel connects automatically.
4. Click **Enable chat** in the same panel, then **Back to game**. This activates
   the shared Streamer Mode controller and its CHAT preference. New messages
   appear with usernames; no private-link copy/paste is needed.
5. Adjust background opacity in the game. Scroll inside chat to read earlier messages; Alt + drag moves it. Drag the
   bottom-right corner to resize it. Closing settings
   preserves Streamer Mode. **Disconnect channel** removes this game's relay
   session. Escape closes settings when open, otherwise toggles Streamer Mode.

The host developer configures `StreamerChat.relay_url` (or project setting
`streamer_mode/chat/relay_url`) to the deployed relay origin. The local demo
fallback is `http://localhost:8788`; start the relay on that port for this demo.
For Kick, the relay's PUBLIC_URL must still be its public HTTPS tunnel/domain.
Ordinary streamers only choose a platform and approve it in their browser.

Toggling Streamer Mode or In-game chat only hides/shows the overlay; it preserves
message history and continues updating it while hidden.
The first snapshot after a new connection is discarded to avoid replaying history.
Only subsequent messages are displayed. Moderation removals update the panel too.
No sample messages are injected into the game. A real channel and running relay
are required for live delivery. The browser is for account authorization and relay
setup; the actual game renders chat with native Godot controls.

## Add to another Godot game

Copy `addons/streamer_mode/`, instantiate `chat/streamer_chat.tscn`, and bind the
**same controller** used by audio/privacy:

```gdscript
var chat = preload("res://addons/streamer_mode/chat/streamer_chat.tscn").instantiate()
chat.bind(streamer_mode_controller)
persistent_root.add_child(chat)
# Your Settings → Streamer Mode → Chat button:
chat.open_settings()
```

Keep the controller and chat under a persistent root (or your existing autoload)
so changing gameplay scenes does not destroy the connection. Chat continues
polling while the scene tree is paused. This is an in-game overlay: capturing
the Godot game includes chat, but switching to another desktop application does
not put this overlay over that application. Starting a broadcast does not
automatically authorize a channel; connect it and enable Streamer Mode first.

The visible chat panel handles scrolling, Alt-drag movement, and corner resizing.
Your game owns menu opening, pause behavior, and its existing master controller.
See [addon API](addons/streamer_mode/chat/README.md) and
[branch integration notes](docs/TEAM_WORKFLOW.md).

## Relay setup (developer / service owner)

Use Node 22+. Copy `.env.example` to `.env` and configure the desired providers.
Set `PORT=8788` for the local Godot demo and run `npm start`. Set `PUBLIC_URL`
to your public HTTPS origin for Kick (or `http://localhost:8788` for local tests). For production use an HTTPS
origin and persistent encrypted storage; see [deployment](docs/DEPLOYMENT.md).
Streamers using a hosted relay do not install Node or the server.

Register these exact URLs using your `PUBLIC_URL`:

| Platform | OAuth callback | Other configuration |
| --- | --- | --- |
| Kick | `/oauth/kick/callback` | Public webhook `/webhooks/kick` |
| Twitch | `/oauth/twitch/callback` | EventSub WebSocket connection |
| YouTube | `/oauth/youtube/callback` | Enable YouTube Data API v3; Web application OAuth client |

Provider secrets and refresh tokens stay on the relay. The game receives a
read-only private link, held only in memory. HTTPS is required except HTTP
`localhost`/`127.0.0.1` for development. Replace an exposed link in the browser;
reconnect the game with the new link. Disconnecting in the game stops local
reading; disconnect in the browser to stop the provider session.

## Verification

```sh
node --test tests/*.test.mjs
godot --headless --editor --import --quit
godot --headless --script tests/test_foundation.gd
godot --headless --script tests/test_chat.gd
node tests/godot_relay.mjs
node tests/godot_pairing.mjs
```

Automated provider tests use mocked platform traffic. Real-account OAuth and live
broadcast delivery across all three platforms still require release acceptance.
The existing audio/privacy foundation remains available; their feature branches
are not incorporated yet. Billing, licensing and customer entitlements are not implemented.
