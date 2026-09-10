# Team workflow

`twitch-chat` is aligned with the native Godot feature structure. No branches
have been merged; do not merge until the product owner requests it.

## Reviewed branch snapshots

- Chat baseline: `a8a7f92` (already had Godot chat and three-provider relay).
- Audio: `0fbc00f` (`stream-safe-audio`), reusable shared UI and audio adapter.
- Privacy: `0dc76e8` (`privacy-mask-copy`), privacy addon and separate control panel.

All three use `addons/streamer_mode/` and the same core controller. Chat now uses
`demo/main.tscn` as its default, installs its component in `demo/demo_services.gd`,
and displays all feature slots through audio's unchanged shared UI files.
`demo/main.gd` follows audio's shared layout with chat-specific wiring added.
Only chat is marked available in this branch. Audio and privacy implementation
files are not copied. `demo/chat_integration.tscn` remains a small chat example.

## Later integration

1. Fetch latest branches; these hashes are reviewed snapshots, not live status.
2. Combine audio/privacy/chat setup in `demo/demo_services.gd` while retaining one
   controller. Keep each feature's status forwarding and gameplay hooks.
3. In `demo/main.gd`, keep one StreamerModePanel, mark each installed feature
   available, and forward its status. Keep Chat settings wired to open_settings.
4. Keep the chosen game's main scene. Preserve the shared UI files unchanged
   unless the integration owner intentionally updates them across branches.
5. Place the controller/services under a persistent root for level changes.
   Chat processes while paused; the host decides whether a settings menu pauses
   gameplay. This demo pauses arena movement while chat settings are open.
6. Run each feature suite and test all three together before merging. Combined
   audio/privacy/chat behavior has not been runtime-tested by this branch.

## Ownership and capture scope

- `addons/streamer_mode/chat/`: native Godot client, overlay, settings, composition.
- `addons/streamer_mode/core/`: unchanged shared mode state.
- `addons/streamer_mode/ui/`: shared audio-compatible feature panel.
- `server/`: platform OAuth, subscriptions, sessions and read-only chat API.
- `public/`: browser authorization and relay preview.
- `tests/`: Godot integration and Node provider tests.

The overlay appears in captured Godot gameplay. It is not an OS-wide always-on-top
window over other apps. A connected channel and enabled chat are required; simply
starting a livestream does not authorize or connect it. Never commit provider
keys, private chat links, OAuth callbacks or runtime data.
