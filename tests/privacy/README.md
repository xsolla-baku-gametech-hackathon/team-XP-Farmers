# Privacy feature tests

The isolated movable-mask prototype that used to live in
`tests/privacy/standalone/` (its own Forward+ project with a borderless,
transparent, always-on-top window) has been replaced. Its behaviour now lives
inside the root game as a reusable in-game component:

- `addons/streamer_mode/privacy/mask_region.gd` - one draggable, resizable,
  translucent rectangle with an opacity control.
- `addons/streamer_mode/privacy/privacy_mask.gd` - `PrivacyMaskComponent`, a
  `CanvasLayer` that owns the region, follows the live viewport, and shows or
  hides it from `StreamerModeController` state.

Removing the second `project.godot` also removes the "Detected another
project.godot" warning during import.

## Run the checks

```sh
godot --headless --path . --script res://tests/privacy/test_privacy_mask.gd
godot --headless --path . --script res://tests/test_foundation.gd
```

`test_privacy_mask.gd` covers visibility vs. controller state, on-screen
clamping for both dragging and resizing, the opacity control, the Escape
panic-hide, real mouse-event routing through a viewport, and re-clamping when
the viewport shrinks. `test_foundation.gd` additionally checks the demo wiring.

## Still open on this branch

The repo's completion criteria also ask to "conceal private text while
preserving Copy". That is a separate control: a private-field widget with a
`DisplayServer.clipboard_set()` Copy button, which the movable mask would sit
on top of. It is not implemented here yet.
