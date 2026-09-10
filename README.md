# XP Farmers · Godot Streamer Mode

`twitch-chat` provides **in-game chat for Godot games**, using the shared
`StreamerModeController`. Twitch, Kick and YouTube connect through a Node relay.
There is no Electron companion or OBS dependency. No feature branches have been merged.

## Run the Godot demo

1. Check out `twitch-chat` and import root `project.godot` in Godot 4.7.2.
2. Press F5. The playable demo opens its **Settings → Streamer Mode** panel.
3. Connect your channel through the relay browser page (setup below), copy the
   private chat link, and paste it into the game's chat field. Click **Connect chat**.
4. Enable **Streamer Mode** and **In-game chat**, then select **Back to game**.
   New messages appear with usernames. WASD/arrows move; Escape opens settings.
5. Adjust background opacity in the game. Alt + drag moves chat. Closing settings
   preserves Streamer Mode. Turning off master mode or chat clears/hides messages.

The first snapshot after connection/enabling is discarded to avoid replaying history.
Only subsequent messages are displayed. Moderation removals update the panel too.
No sample messages are injected into the game. A real channel and running relay
are required for live delivery. The browser is for account authorization and relay
setup; the actual game renders chat with native Godot controls.

## Add to another Godot game

Copy `addons/streamer_mode/`, instantiate `chat/streamer_chat.tscn`, and bind the
**same controller** used by audio/privacy:

```gdscript
var chat = preload("res://addons/streamer_mode/chat/streamer_chat.tscn").instantiate()
chat.bind_controller(streamer_mode_controller)
add_child(chat)
# Your Settings → Streamer Mode → Chat button:
chat.open_settings()
```

The addon never reads gameplay input except Alt-drag on the visible chat panel.
Your game owns menu opening, pause behavior, and its existing master controller.
See [addon API](addons/streamer_mode/chat/README.md) and
[branch integration notes](docs/TEAM_WORKFLOW.md).

## Relay setup (developer / service owner)

Use Node 22+. Copy `.env.example` to `.env` and configure the desired providers.
Run `npm start`, then open `http://localhost:8787`. For production use an HTTPS
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
```

Automated provider tests use mocked platform traffic. Real-account OAuth and live
broadcast delivery across all three platforms still require release acceptance.
The existing audio/privacy foundation remains available; their feature branches
are not incorporated yet. Billing, licensing and customer entitlements are not implemented.
