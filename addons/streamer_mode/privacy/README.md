# Privacy component

Owner branch: `privacy-mask-copy`.

## What ships here

A reusable **in-game** privacy mask. It renders inside the game's own viewport
on a high `CanvasLayer`; it is not an OS-level overlay window, so it needs no
per-pixel transparency, borderless or always-on-top settings and behaves the
same under the Compatibility and Forward+ renderers.

| File | Role |
| --- | --- |
| `privacy_mask.gd` | `PrivacyMaskComponent` (`CanvasLayer`). Binds the controller, owns a full-rect `Surface`, shows/hides the mask from `state_changed`, follows the live viewport, handles the Escape panic-hide. |
| `mask_region.gd` | `PrivacyMaskRegion` (`Control`). One translucent rectangle: drag body, bottom-right resize handle, floating opacity toolbar. All movement and sizing is clamped to the parent `Surface`, so it can never leave the screen. |

## Integration

```gdscript
const PrivacyMask := preload("res://addons/streamer_mode/privacy/privacy_mask.gd")

var mask := PrivacyMask.new()
ui_root.add_child(mask)          # anywhere under the game's UI root
mask.setup(controller)           # syncs immediately, even if mode is already on
mask.cover_node(private_card)    # optional: initial coverage target (lazy rect)
```

`setup()` connects `StreamerModeController.state_changed` and applies
`is_feature_active(StreamerModeController.PRIVACY)`. It disconnects on
`_exit_tree()` and on rebinding. No autoload required.

### Public API

| Member | Purpose |
| --- | --- |
| `setup(controller)` | Bind or rebind the shared controller. Idempotent. |
| `cover_rect(Rect2)` / `cover_node(Control)` | Set where the mask opens the next time it becomes visible. `cover_node` resolves the rectangle lazily, after layout. |
| `panic_hide()` | Hide the mask and clear the Privacy selection. Streamer Mode stays on. |
| `is_mask_visible()` / `get_mask_rect()` | State for tests and host UI. |
| `emergency_keycode` (export, default `KEY_ESCAPE`) | While a mask is on screen this key panic-hides it and the event is consumed. With no mask on screen the key is left alone for the host's own handler. |
| `default_opacity` (export, default `0.8`) | Starting fill opacity, 0.05-1.0. |

## Demo wiring (`demo/main.gd`)

The "Protect sensitive information" checkbox is enabled and bound to
`set_feature_enabled(PRIVACY, ...)`. The mask defaults to covering the sample
lobby card. The sidebar status line and the lobby card text update live.

## Still open

The completion criterion "conceal private text while preserving Copy" needs a
separate private-field widget with a `DisplayServer.clipboard_set()` Copy
button, masked by this component. Not implemented yet.
