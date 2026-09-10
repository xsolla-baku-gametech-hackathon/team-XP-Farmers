# Privacy module

Part of the **Streamer Mode SDK** addon (`addons/streamer_mode/`). Everything
renders inside the game's own viewport on a high `CanvasLayer`; nothing is an
OS-level overlay window, so it works the same under the Compatibility and
Forward+ renderers with no window settings.

| File | Class | Role |
| --- | --- | --- |
| `privacy_engine.gd` | `PrivacyEngine` (`CanvasLayer`) | Automated masking. Scans text and/or takes registered regions, snaps a blur mask over each active target, fades masks when the target goes away. Gated by `StreamerModeController`. |
| `privacy_blur.gdshader` | - | `canvas_item` shader: pixelate + 5x5 box blur of `hint_screen_texture` with a tint. |
| `privacy_blur_mask.gd` | `PrivacyBlurMask` (`Control`) | Non-interactive mask instance; eases to a target rect, fades, frees itself. Owned by the engine. |
| `privacy_copy_field.gd` | `PrivacyCopyField` (`Control`) | Labelled value + Copy button. The value is masked; Copy always writes the real string to the clipboard. |
| `privacy_control_panel.gd` | `PrivacyControlPanel` (`PanelContainer`) | Dev/streamer panel: active-mask list, scan toggle + interval, live blur sliders, allow-list editor. |
| `privacy_mask.gd` / `mask_region.gd` | `PrivacyMaskComponent` / `PrivacyMaskRegion` | The earlier **manual** drag/resize/opacity mask. Kept for direct-control use; not in the demo. |

The `plugin.cfg` / `plugin.gd` at the addon root add an optional editor tool
(see "Tagging nodes as Private" below). The runtime classes work whether or not
the plugin is enabled.

## PrivacyEngine

```gdscript
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")

var engine := PrivacyEngine.new()
ui_root.add_child(engine)          # or an autoload, to survive scene changes
engine.setup(controller)
```

### Detection

**Strategy B - registered regions (reliable).** Explicit and always masked
while the feature is active; the mask follows the target's global rect through
layout and window resizes.

```gdscript
engine.register_node(&"lobby", $Hud/LobbyCard)
engine.register_rect_provider(&"seed", func(): return $Hud/Seed.get_global_rect())
# ...or tag a Control into the "privacy_sensitive" group (auto-registered).
```

**Strategy A - node scanner (opt-in, best effort).** Walks
`Label`/`RichTextLabel`/`LineEdit` under one or more scan roots and RegEx-matches
visible text. **It cannot see text drawn with `_draw()`, text in textures, or
strings that match no pattern, and it can over-match incidental text.** Register
anything that must not leak with Strategy B.

```gdscript
engine.set_scan_root(ui_root)          # single root
engine.set_scan_roots([hud, {"node": minimap_root, "to_screen": _map_minimap}])
engine.add_pattern("\\bSEED [0-9A-F]{8}\\b")
engine.allow_text("PRESS START")       # exact strings the scanner ignores
engine.set_scanning(true)
```

Default patterns: `AB-1234`-style codes, IPv4 with optional port, and
`room`/`lobby`/`invite` followed by a value.

### Full API

| Member | Purpose |
| --- | --- |
| `setup(controller)` | Bind/rebind the controller. Idempotent. |
| `register_node(id, control, params={}, to_screen:=Callable())` | Region from a node. `to_screen(Rect2)->Rect2` maps a rect from a SubViewport into main-viewport pixels. |
| `register_rect_provider(id, callable, params={})` | Region from a `Rect2` (main-viewport pixels) returned each frame. |
| `unregister(id)` | Retire a region; its mask fades. |
| `set_scan_root(node)` / `set_scan_roots(array)` / `add_scan_root(node, to_screen:=Callable())` | One or many scan roots. Array entries are `Node` or `{node, to_screen}`. |
| `set_scanning(bool)` / `is_scanning()` | Enable/disable Strategy A. Turning it **off retires every scanner-found region** (masks fade); registered regions are untouched. Turning it **on re-indexes**, so nodes added while it was off are picked up. |
| `add_pattern(str)` | Extra RegEx. |
| `allow_text(str)` / `remove_allowed_text(str)` / `clear_allowed_texts()` / `get_allowed_texts()` | Allow-list. |
| `set_mask_param(key, value)` | Update a shader default **and every mask already on screen**. |
| `refresh()` | Force one full scan pass + rect refresh now. |
| `refresh_group()` | Re-scan the `privacy_sensitive` group (after code-built tagging). |
| `exclude_subtree(node)` | Never scan or mask anything under this node. |
| `active_region_count()` / `is_active()` / `get_scan_stats()` | State for tests and the control panel. |
| signals `region_masked(id, rect)`, `region_cleared(id)`, `match_found(text, rect)` | Unchanged. |

Exports: `mask_params`, `target_margin`, `scan_interval`, `scan_names`,
`name_keywords`, `scan_node_budget` (round-robin batch size, default 400),
`auto_register_from_group` (default `true`), `privacy_group` (default
`&"privacy_sensitive"`), `rebind_scan_root_on_scene_change` (default `true`).

### Robustness

- **Scene swaps.** The engine listens to `SceneTree.tree_changed`. When
  `current_scene` changes and `rebind_scan_root_on_scene_change` is on, any scan
  root that was the old scene is replaced with the new one and re-indexed. Put
  the engine in an autoload for this to matter; an engine inside the swapped
  scene is recreated with it.
- **Many text nodes.** Above `scan_node_budget` the scanner processes nodes in
  round-robin batches, one batch per `scan_interval`, so a pass stays cheap
  regardless of scene size. A match that stops matching is reaped at the end of
  its sweep (`ceil(indexed / budget)` ticks) instead of the next tick.
- **Multiple viewports.** Pass several roots; supply `to_screen` per SubViewport
  root so masks land in the right place on the composited screen. Without it a
  SubViewport root's rects are assumed to be in main-viewport space.

### Screen-read setup

The engine adds a `BackBufferCopy` (`COPY_MODE_RECT`, tracking the union of
active mask rects; `DISABLED` when none) as its first child. Masks are drawn
after it, so they never sample themselves or each other.

## PrivacyCopyField

```gdscript
var field := PrivacyCopyField.new()
field.caption = "JOIN CODE"
field.value = "XP-4829"
container.add_child(field)
field.bind(engine, &"join_code")   # registers only the value sub-rect
field.copied.connect(_on_code_copied)
```

Only `get_mask_target()` (the value) is registered, so the Copy button and
caption are never blurred. `copy()` calls `DisplayServer.clipboard_set()` with
the stored `value` - never the rendered text - and emits `copied(value)` with a
short "Copied!" button state. Works identically whether the value is masked or
not.

## PrivacyControlPanel

```gdscript
var panel := PrivacyControlPanel.new()
ui_root.add_child(panel)
panel.setup(engine)   # calls engine.exclude_subtree(panel) so it is never masked
```

Drives only the public API. As a `PanelContainer` it blocks input only inside
its own rect, so the game and the masks stay usable while it is open.

## Tagging nodes as Private (editor tool)

1. In **Project Settings > Plugins**, enable **Streamer Mode SDK**.
2. Select one or more `Control` nodes in the scene tree.
3. **Project > Tools > "Privacy: tag selected node(s) as Private"** adds them to
   the `privacy_sensitive` group (persisted in the `.tscn`). Untag with the
   sibling menu item.
4. At runtime a `PrivacyEngine` with `auto_register_from_group` on (default)
   calls `register_node` for every node in that group - no code per node.
   `register_node` / `register_rect_provider` remain the API for dynamic cases.
   For a node tagged from code *after* it entered the tree, call
   `engine.refresh_group()`.

## Installing in another project

Copy the whole `addons/streamer_mode/` folder in. `plugin.cfg` makes it a normal
installable plugin. `class_name` globals (`PrivacyEngine`, `PrivacyBlurMask`,
`PrivacyCopyField`, `PrivacyControlPanel`, `StreamerModeController`, ...) are
registered by the editor's project scan regardless of whether the plugin is
enabled; enabling it only adds the tagging menu items. Nothing here depends on
`res://demo/`.

## Deviations from the earlier contract

- `TEAM_WORKFLOW.md` said "No autoload or editor plugin is required." Still true
  at runtime: the plugin is optional and only adds an editor convenience. An
  autoload is only needed if you want the engine to outlive scene swaps.
- `set_mask_param()` is the way to change blur on live masks. Assigning
  `engine.mask_params[...]` directly still works but only affects masks spawned
  afterwards.
- `set_scan_root(node)` is unchanged; internally it is now
  `set_scan_roots([node])`.

## Still open

"Conceal but keep Copy" is done (`PrivacyCopyField`). No known gaps remain in
the privacy module for the hackathon scope.
