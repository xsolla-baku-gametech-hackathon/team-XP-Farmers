# Optional settings panel

Instance `streamer_mode_panel.tscn` under a Control/Container/CanvasLayer in the
host game. Its root is a PanelContainer; no positioning is forced. Minimum width
is 320 pixels. The accent color is configurable in the Inspector. Controls are
built at runtime, so the panel appears when the scene runs.

## Bind

```gdscript
panel.bind(controller)
panel.set_feature_available(StreamerModeController.AUDIO, true)
panel.set_feature_status(StreamerModeController.AUDIO, music.get_status())
```

Bind and set availability before or after adding the panel to the tree. The panel
synchronizes immediately; controller changes also update it. Each instance owns its
own UI and can be rebound or removed without changing game preferences.

All features default to unavailable. A feature checkbox is enabled only when the
host marks that component available and a controller is attached to the tree.
The master button is disabled without any available feature. An enabled mode with
no available features selected is reported explicitly.

Availability is UI metadata, not a switch for the component. To disable actual
behavior, use controller.set_feature_enabled(feature, false), or stop/remove the
component. A disconnected Twitch client can still be an installed component;
report its connection state with set_feature_status rather than pretending it is
connected. No chat connection is implemented by this panel.

The shared controller API is unchanged. Privacy/chat developers keep subscribing
to state_changed and querying is_feature_active; the integration owner adds their
completed components to the shared demo and marks them available on this panel.

No preferences are persisted to disk by the panel. Games own persistence and
keyboard shortcuts. Privacy values and access tokens must not be used as status
messages.
