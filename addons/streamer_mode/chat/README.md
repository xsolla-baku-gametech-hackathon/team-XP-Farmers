# Godot chat integration

`StreamerChat` is a native CanvasLayer containing settings, a read-only HTTP
client, and a transparent chat Control. Bind the game's existing
`StreamerModeController`; do not create a second controller for chat.

- `bind_controller(controller)` works before or after adding to the scene tree.
- `open_settings()` / `close_settings()` do not change master mode.
- `connect_link(link) -> bool` validates and starts polling; true means the URL
  was accepted, not that the provider is connected. Observe `status_changed`.
- `client.disconnect_chat()` stops local reading and clears the private link.
- `overlay.background_opacity` is 0..1; text stays opaque.
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
