# Privacy components

Owner branch: `privacy-mask-copy`.

Everything here renders **inside the game's own viewport** on a high
`CanvasLayer`. Nothing is an OS-level overlay window, so there are no
per-pixel-transparency, borderless or always-on-top settings and the behaviour
is identical under the Compatibility and Forward+ renderers.

| File | Role |
| --- | --- |
| `privacy_engine.gd` | `PrivacyEngine` (`CanvasLayer`). **Automated** masking. Scans text nodes and/or takes explicit region registrations, snaps a blur mask over each active target, fades masks out when the target goes away. Gated by `StreamerModeController`. |
| `privacy_blur.gdshader` | `canvas_item` shader. Pixelates + box-blurs `hint_screen_texture` and tints it. |
| `privacy_blur_mask.gd` | `PrivacyBlurMask` (`Control`). Non-interactive; carries the shader, eases its rect toward a target, fades in/out, frees itself when gone. Instances are owned by `PrivacyEngine`. |
| `privacy_mask.gd` | `PrivacyMaskComponent` (`CanvasLayer`). **Manual** mask: one translucent rectangle the streamer drags, resizes and fades. Kept for direct-control use; not mounted in the demo. |
| `mask_region.gd` | `PrivacyMaskRegion` (`Control`). The draggable/resizable rectangle used by `PrivacyMaskComponent`. |

## PrivacyEngine

```gdscript
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")

var engine := PrivacyEngine.new()
ui_root.add_child(engine)
engine.setup(controller)

# Strategy B - reliable: explicit private regions.
engine.register_node(&"lobby", lobby_card, {"pixel_size": 18.0})
engine.register_rect_provider(&"hud", func(): return $Hud/Seed.get_global_rect())

# Strategy A - opt-in assist: RegEx scan of Label/RichTextLabel/LineEdit text.
engine.set_scan_root(ui_root)
engine.set_scanning(true)
engine.add_pattern("\\bSEED [0-9A-F]{8}\\b")
engine.allow_text("XP FARMERS")
```

### Public API

| Member | Purpose |
| --- | --- |
| `setup(controller)` | Bind/rebind the controller. Idempotent. Disconnects on `_exit_tree()`. |
| `register_node(id, Control, params={})` | Strategy B: mask this node while the feature is active; the mask follows its global rect. |
| `register_rect_provider(id, Callable, params={})` | Strategy B: mask a `Rect2` returned each frame by `Callable`; return a zero-size rect to hide it. |
| `unregister(id)` | Retire a region; its mask fades out. |
| `set_scanning(bool)` / `set_scan_root(Node)` | Enable Strategy A and choose the subtree it walks. |
| `add_pattern(String)` / `allow_text(String)` | Extra RegEx pattern / exact string that is never masked. |
| `refresh()` | Force an immediate scan pass (e.g. right after a game state change). |
| `active_region_count()` / `is_active()` | State for tests and host UI. |
| `mask_params`, `target_margin`, `scan_interval`, `scan_names`, `name_keywords` | Exports. |
| signals `region_masked(id, rect)`, `region_cleared(id)`, `match_found(text, rect)` | For host UI / auditing. |

Default patterns: code-like `AB-1234`, IPv4 with optional port, and
`room`/`lobby`/`invite` followed by a value. Scanner runs on `scan_interval`
(0.25 s), keeps its node set live via `SceneTree.node_added`/`node_removed`, and
skips matches whose rect is already inside a registered region.

### Reliability

Strategy A is **best effort**. It cannot see text drawn with `_draw()`, text
baked into textures, or strings that do not match a pattern, and it can
over-match incidental text. Register anything that must not leak with
Strategy B. This mirrors the addon's stated scope: the developer identifies
private UI; the tool reduces specific exposures, it does not guarantee them.

## Screen-read setup

`PrivacyEngine` adds a `BackBufferCopy` (`COPY_MODE_RECT`, tracking the union of
active mask rects; `DISABLED` when none) as its first child, so
`hint_screen_texture` has fresh contents on every renderer and only the needed
area is copied. Masks are drawn after the copy, so they never sample
themselves or each other.

## Demo wiring (`demo/main.gd`)

The "Protect sensitive information" checkbox is enabled and bound to
`set_feature_enabled(PRIVACY, ...)`. `PrivacyEngine` registers the sample lobby
card (Strategy B) and scans the demo UI (Strategy A), which also masks the
`MATCH SERVER 203.0.113.42:7777` line. Sidebar and lobby text update live.

## Still open

The completion criterion "conceal private text while preserving Copy" needs a
private-field widget with a `DisplayServer.clipboard_set()` Copy button, masked
by one of these components. Not implemented yet.
