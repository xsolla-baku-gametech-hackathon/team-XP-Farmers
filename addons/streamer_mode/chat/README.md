# Godot chat integration

`StreamerChat` is a native CanvasLayer containing settings, a read-only HTTP
client, and a transparent chat Control in a native always-on-top Window on desktop. Bind the game's existing
`StreamerModeController`; do not create a second controller for chat.

- `bind(controller)` (also available as `bind_controller(controller)`) works before or after adding to the scene tree.
- `open_settings()` / `close_settings()` do not change master mode.
- `connect_link(link) -> bool` validates and starts polling; true means the URL
  was accepted, not that the provider is connected. Observe `status_changed`.
- `disconnect_chat()` stops local reading and clears the private link.
- `overlay.background_opacity` is 0..1; text stays opaque.
- `get_status()` returns the latest connection detail for initial panel sync.
- `status_changed(state, detail)` can feed the host's existing status panel.

Display requires an explicit `enable_chat()` after connecting a channel, plus
`controller.is_feature_active(StreamerModeController.CHAT)`.
The relay's delivery switch must also remain enabled. Credentials are never
exported into scenes or saved in Godot settings. Each HTTP request uses the
private link's key as a Bearer capability to `/api/overlay`; redirects are disabled.
History is bounded to 100 relay records and 30 rendered lines. First snapshots
are skipped after connecting; mode/feature toggles preserve history and only
change visibility. Connected snapshots still update while hidden; repeated snapshots don't duplicate messages and
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
The UI structure comes from audio commit `0fbc00f` with a platform-neutral chat label; no audio/privacy
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

## Connect from the game

Set `relay_url` on StreamerChat before adding it, or configure the project setting
`streamer_mode/chat/relay_url`. Local fallback: http://localhost:8788. Never put
provider credentials in the game. The server owns PUBLIC_URL and OAuth settings.

`connect_channel(provider)` begins native browser pairing. `channel_connection.gd`
creates a game-only polling capability, opens a separate one-use browser ticket,
and polls until OAuth completes. The user confirms the platform account in their
system browser. Godot obtains the read-only overlay link automatically; the UI
contains no private-link field. `enable_chat()` requires the master to already be ON and a connected channel,
then enables the CHAT preference and opens the overlay. `disconnect_chat()` also revokes the paired session.
The original `connect_link()` remains available for existing host integrations.

Pending pairing expires after ten minutes and is not persisted across relay
restarts. Connected sessions expire under the relay's normal idle lifetime.
Capabilities stay in memory; restarting the game requires connecting again.
The component's browser_requested signal belongs to the connection client;
StreamerChat handles it through OS.shell_open. No embedded platform login form
or provider password storage is involved.

## History and panel controls

In-game chat and master-mode toggles hide/show the same message buffer. Polling
continues while hidden; moderation and the relay's bounded/expiring snapshot still
apply. Disconnecting or switching channels clears history. Scroll inside the chat
panel to read older messages. Repeated snapshots preserve your reading position;
new messages follow automatically only when you are already at the bottom.

Drag the top-left or bottom-right corner to resize (minimum 240 × 140, bounded by the screen in desktop mode),
or call `overlay.set_panel_size(Vector2(width, height))`. Hold the left mouse button on the chat body or header and drag to move the panel;
no modifier key is needed. The scrollbar remains independently draggable.
Mouse-wheel and trackpad scrolling over messages read history.
Size and position stay in memory through mode toggles, not application restarts.


## Desktop overlay

Desktop builds default to `desktop_overlay = true`, with a compact 360 × 220
pixel panel. Channel controls are disabled until Streamer Mode is ON; connecting
a channel does not show the panel until the user presses Enable chat. The chat lives in a separate,
non-modal, borderless native Window (`force_native`, `always_on_top`), so it is not
clipped to the game or dismissed when another application is focused. The window
cannot take keyboard focus, while its scrollbar and resize handle accept mouse
input. Window movement and resizing use native OS drag operations. Master/feature
toggles hide this same window without destroying its message buffer. Closing the
host application closes chat as well; the relay alone does not display it.

Set `display/window/per_pixel_transparency/allowed = true` in the host project
before launching (already set in this demo). Set `desktop_overlay = false` before
adding StreamerChat to keep rendering inside the game; non-desktop exports also
use the in-game Control. Use a screen/display capture to include this separate
window in a broadcast; a capture of only the game window may omit it.

Always-on-top covers ordinary windows on the current desktop. macOS fullscreen
Spaces, switching desktops, and exclusive fullscreen applications are not
promised by this implementation. Native GUI validation is still needed for each
supported OS; headless tests validate composition, visibility, history and sizing,
not the compositor's actual stacking behavior.
