# Privacy feature tests

Headless suites for `addons/streamer_mode/privacy/`. Each is a `SceneTree`
script; run with `--script` and check for `... checks: PASS`.

```sh
godot --headless --path . --script res://tests/test_foundation.gd
godot --headless --path . --script res://tests/privacy/test_privacy_mask.gd
godot --headless --path . --script res://tests/privacy/test_privacy_engine.gd
godot --headless --path . --script res://tests/privacy/test_privacy_copy_field.gd
godot --headless --path . --script res://tests/privacy/test_privacy_engine_churn.gd
```

| Suite | Covers |
| --- | --- |
| `test_foundation.gd` | Controller behaviour + demo wiring, including `privacy_engine` masking on toggle. |
| `test_privacy_mask.gd` | The manual `PrivacyMaskComponent`: visibility vs. state, on-screen clamping for drag and resize, opacity, Escape panic-hide, real input routing, viewport shrink. |
| `test_privacy_engine.gd` | `PrivacyEngine` core: feature gating, register-node snapping/following, hidden-node release, scanner pattern matches, allow-list, dedupe against registered regions, clear-on-text-change. |
| `test_privacy_copy_field.gd` | `PrivacyCopyField`: value masked while the Copy button stays outside the blur, `copy()` returns the real value on the `copied` signal (and the clipboard where the display server supports it) with Streamer Mode both on and off, value changes reflected. |
| `test_privacy_engine_churn.gd` | Scene-swap re-binding of the scanner, multiple scan roots + `to_screen` mapping for SubViewports, round-robin batch scanning with a 300-node stress pass over 50 mutation cycles, and `privacy_sensitive` group auto-registration. |

Headless note: `DisplayServer` has no clipboard, so `test_privacy_copy_field.gd`
skips the `clipboard_get()` assertions and verifies the `copied` signal payload
instead. On a desktop display server the clipboard assertions run.
