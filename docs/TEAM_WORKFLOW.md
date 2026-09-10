# Team workflow

`twitch-chat` now restores Godot and supplies an in-game chat addon. No branches
have been merged. Do not merge until the product owner explicitly requests it.

The shared foundation files were restored from common ancestor `c79fda9`.
`StreamerModeController`, `demo/main.gd`, `demo/demo_services.gd` and the arena retain
that foundation's implementation. The new default scene is
`demo/chat_integration.tscn`, a runnable chat integration example. Original
`demo/main.tscn` remains available for foundation regression checks.

## Later integration with audio/privacy

Review and combine features only when authorized. Restore no desktop companion.
Keep one controller, instantiate `StreamerChat`, and bind it to that controller.
The chat addon does not depend on either feature branch. When using audio's
`StreamerModePanel`, call `set_feature_available(Controller.CHAT, true)` and route
`chat.status_changed` to `set_feature_status(Controller.CHAT, detail)`. Add a Chat
settings button wired to `chat.open_settings()`. Keep the chosen final game's
main scene when resolving the root `project.godot` main-scene setting.

The default chat demo pauses movement while its settings panel is open; the
reusable addon leaves gameplay/pause control to its host. Test master mode,
individual preferences, closing settings, masking, audio switching and new chat
messages together before merging. This branch does not claim those combined
features have been runtime-tested.

## Ownership

- `addons/streamer_mode/chat/`: native Godot chat UI/client.
- `addons/streamer_mode/core/`: shared mode state.
- `server/`: platform OAuth, subscriptions, encrypted sessions, read-only chat API.
- `public/`: browser account connection and relay preview.
- `tests/`: Godot regression tests and Node provider tests.

Never commit provider keys, private chat links, OAuth callbacks or runtime data.
See README for automated checks and DEPLOYMENT for live acceptance.
