# Streamer Mode SDK — Team XP Farmers
Reusable Godot components for music replacement, private UI protection and native in-game chat.

## Run the integrated demo
Import project.godot with Godot 4.7.2 standard and press F5.
Move with WASD/arrows. Settings / Escape opens a modal menu.
Enable Streamer Mode, select features, then Resume game. Closing settings keeps protection active.

For chat, choose **Connect channel / Chat settings**, select a platform and authorize in your browser. A running configured relay is required. No messages or provider connections are simulated in normal gameplay.

## Integration status
- Audio: managed-stream replacement and a dedicated music-bus adapter; effects stay on their own routes.
- Privacy: registered fields, pattern scanning, manual-region components and Copy support. Critical demo codes hide their source text immediately.
- Chat: native Godot overlay using the same controller; connection/appearance settings are inside the shared demo menu.
- External examples: two third-party Godot source projects have tested audio integrations and track/silence selection.
- Chat history remains updated while hidden. Disconnect clears history. Master off hides chat but does not disconnect the provider session.

The chat merge is a local integration checkpoint. Targeted merge checks are separate from the full combined regression/build milestone. Real-account authorization/delivery, recording/listening acceptance, and the large-scene scanner performance target remain open.

Privacy scanning in this demo covers the game HUD, not chat history or connection controls. Chat visibility is not a privacy scrubber: previously received messages can reappear when chat is enabled again.

## Relay
Use Node 22+ and configure the desired providers in a private .env file based on .env.example.
For the default local demo use PORT=8788. Run npm start.
The host can configure streamer_mode/chat/relay_url in project settings; the component defaults to http://localhost:8788.
Provider secrets remain on the server. Public provider callbacks, especially Kick webhooks, need the setup described in [deployment](docs/DEPLOYMENT.md).
The relay is separate from the exported game executable.

## Reuse
Copy addons/streamer_mode into your Godot project and bind components to one StreamerModeController.
Your game owns settings, scene lifetime, music routing and the selection of sensitive fields.
Chat's StreamerChat.bind(controller) and bind_controller(controller) accept that same controller.
Privacy's advanced controls remain optional addon components; the shared demo shows its basic feature toggle.

See [integration guide](docs/INTEGRATION.md), [external games](docs/EXTERNAL_GAMES.md), and [team workflow](docs/TEAM_WORKFLOW.md).

## Checks
The existing SDK runner checks its 12 functional suites:

~~~sh
node tools/verify.cjs "PATH_TO_GODOT_CONSOLE"
~~~

Additional targeted chat/merge checks:

~~~sh
godot --headless --path . --script tests/test_chat.gd
godot --headless --path . --script tests/test_combined_chat.gd
node --test tests/*.test.mjs
node tests/godot_relay.mjs
node tests/godot_pairing.mjs
~~~

The HTTP and pairing fixtures accept GODOT as the executable environment variable.
Provider tests use mocked traffic and do not certify live-account delivery.
The strict scanner benchmark remains available with -- --strict-performance on tests/privacy/test_privacy_engine_churn.gd; its 16 ms target was exceeded in this environment.

## Scope
This is source-level integration for participating Godot games, not automatic protection for arbitrary installed games.
Both player and captured game receive the same modified UI/audio.
Supplied tracks must have appropriate usage rights; the SDK does not guarantee prevention of copyright claims or stream sniping.
Demo music is synthesized locally; it is not commercial music recognition or filtering.

Windows build tooling is documented in [build instructions](docs/BUILD_AND_DEMO.md). Previously exported binaries predate this local chat merge until the next full build.
