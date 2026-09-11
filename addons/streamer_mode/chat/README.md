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
The combined host integrates audio, privacy and chat through the same controller and panel.

Keep StreamerChat and its controller under a persistent host root when changing
levels. The component uses PROCESS_MODE_ALWAYS so game pause does not pause chat
or its settings. Removing/re-adding chat restores its subscriptions; removing the
controller disables delivery and display. A scene change that destroys the host
also destroys chat, so persistence is an explicit host responsibility.

For your host integration, set CHAT available in the common panel and forward
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
contains no private-link field. `enable_chat()` explicitly enables the shared
master and CHAT preference. `disconnect_chat()` also revokes the paired session.
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

Drag the bottom-right corner to resize (minimum 240 × 140, bounded by viewport),
or call `overlay.set_panel_size(Vector2(width, height))`. Alt-drag moves the panel.
Size and position stay in memory through mode toggles, not application restarts.

## Fill connection details in the game
Chat settings now include a Chat service URL field. Enter the relay HTTPS address (or localhost HTTP), choose Kick, and Connect channel. The address is retained for the current game session; project settings supply the initial default on restart. RTMP/RTMPS ingest addresses are rejected before changing the current service or attempting a connection. Sign in through the browser; provider secrets belong in the relay server configuration, not this field.
