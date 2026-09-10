# Godot chat integration

`StreamerChat` is a native CanvasLayer containing settings, a read-only HTTP
client, and a transparent chat Control. Bind the game's existing
`StreamerModeController`; do not create a second controller for chat.

- `bind(controller)` (also available as `bind_controller(controller)`) works before or after adding to the scene tree.
- `open_settings()` / `close_settings()` do not change master mode.
- `connect_link(link) -> bool` validates and starts polling; true means the URL
  was accepted, not that the provider is connected. Observe `status_changed`.
- `disconnect_chat()` stops local reading and clears the private link.
- `overlay.background_opacity` is 0..1; text stays opaque.
- `get_status()` returns the latest connection detail for initial panel sync.
- `status_changed(state, detail)` can feed the host's existing status panel.

Only `controller.is_feature_active(StreamerModeController.CHAT)` enables display.
The relay's delivery switch must also remain enabled. Credentials are never
exported into scenes or saved in Godot settings. Each HTTP request uses the
private link's key as a Bearer capability to `/api/overlay`; redirects are disabled.
History is bounded to 100 relay records and 30 rendered lines. First snapshots
are skipped after enabling; repeated snapshots don't duplicate messages and
moderated messages disappear. Transient failures clear stale chat and retry;
revoked links stop polling and request reconnection.

The companion desktop implementation has been removed. The Node relay is a
server integration dependency, not a separate streamer desktop application.

## Shared host structure

`chat_client.gd` owns transport, `chat_overlay.gd` owns message rendering,
`chat_settings.gd` owns connection/appearance controls, and `streamer_chat.gd`
composes them. Settings contain no duplicate master or feature switches.
`demo/demo_services.gd` installs chat and forwards status; `demo/main.gd` uses
`ui/streamer_mode_panel.tscn` for all three feature slots, matching the audio demo.
The UI files are copied unchanged from audio commit `0fbc00f`; no audio/privacy
implementation or branch history was merged. The shared controller is unchanged.

Keep StreamerChat and its controller under a persistent host root when changing
levels. The component uses PROCESS_MODE_ALWAYS so game pause does not pause chat
or its settings. Removing/re-adding chat restores its subscriptions; removing the
controller disables delivery and display. A scene change that destroys the host
also destroys chat, so persistence is an explicit host responsibility.

For later integration, set CHAT available in the common panel and forward
`status_changed` to `set_feature_status(CHAT, detail)`. Connect your Chat settings
button to `open_settings()`. Keep one shared controller and install audio/privacy
through their own feature APIs. Do not create additional master switches.
