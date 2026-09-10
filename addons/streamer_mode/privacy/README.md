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
| `privacy_text_locator.gd` | `PrivacyTextLocator` | Measures where a matched substring actually renders, so the mask covers the code and not the whole line. |
| `privacy_draw_tool.gd` | `PrivacyDrawTool` (`CanvasLayer`) | **Supplemental** manual regions: arm a button, drag a box, that area blurs. For what detection cannot reach. |
| `privacy_draw_region.gd` | `PrivacyDrawRegion` (`Control`) | One drawn region's interaction frame: drag body, corner resize handle, delete button, clamped on screen. |
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
engine.setup(controller)           # scanning starts here - automation is the default
engine.set_scan_root(ui_root)      # just tell it which subtree to watch
```

**Automation is the default.** `setup()` starts the scanner. There is no extra
opt-in step and no button to press. A host that genuinely wants manual-only
control sets `auto_scan_on_setup = false` before `setup()`, or calls
`set_scanning(false)` later.

### Detection

**Strategy A - node scanner (on by default).** Walks
`Label`/`RichTextLabel`/`LineEdit` under one or more scan roots and RegEx-matches
visible text against the enabled pattern packs. Where the layout can be
measured it masks **only the matched substring**, not the whole control. It
cannot see text drawn with `_draw()`, text in textures, or strings that match no
pattern, so anything that must not leak should also be registered explicitly.

**Strategy B - registered regions (explicit, exact).** Always masked while the
feature is active; the mask follows the target's global rect through layout and
window resizes.

```gdscript
engine.register_node(&"lobby", $Hud/LobbyCard)
engine.register_rect_provider(&"seed", func(): return $Hud/Seed.get_global_rect())
# ...or tag a Control into the "privacy_sensitive" group (auto-registered).
```

`PrivacyDrawTool` supplements both for the cases the scanner cannot reach.

### Substring precision

A label reading `Player: xXx_Shadow_xXx | Room: GAME-2231` masks only
`GAME-2231`; the name and the word `Room:` stay readable.
`PrivacyTextLocator` rebuilds the node's `TextParagraph` from its font, size,
width, alignment, wrap mode and `normal` stylebox, then asks `TextServer` for
the shaped selection bounds of the matched character range. A match that wraps
produces one mask per line fragment.

Measured accuracy against `tests/privacy/fixtures/scan_corpus.gd` (62 entries):
**precision 1.0000, recall 1.0000**; masked widths land within ~0.5 px of the
rendered substring width.

Where exact measurement is **not** attempted, and the mask falls back to the
full control rect (`PrivacyTextLocator.PRECISION_NOTES` carries these in code):

| Case | Behaviour |
| --- | --- |
| `RichTextLabel` | Narrowed to the matched **line band** at full width. BBCode can change font and size mid-line and insert images, so per-character x offsets are not derivable from the public API. Not approximated. |
| `LineEdit` with overflowing text | Full control rect. The visible window depends on the caret-driven scroll offset, which is not exposed. |
| Control with no resolvable theme font | Full control rect. |
| Any other Control type | Full control rect. |
| A node-name keyword hit (`scan_names`) | Full control rect by definition - there is no text range. |

Set `precise_substrings = false` to force whole-node masking everywhere.
`substring_margin` (default 3 px) pads measured runs; `target_margin`
(default 10 px) pads whole-node rects.

### Pattern packs

| Pack | Default | Covers |
| --- | --- | --- |
| `lobby_codes` | **on** | `GAME-2231`, `XP4829`, `KX7Q-22F1`, and `Room:` / `Lobby:` / `Invite:` / `Party:` followed by a value |
| `network` | **on** | IPv4 with optional port, IPv6 (full, compressed and bracketed), `discord.gg/...` invites, `STEAM_0:1:...`, friend codes, explicit `Port:` callouts |
| `contact` | off, opt-in | email addresses, phone numbers |
| `identifiers` | off, opt-in | UUIDs, JWTs, license/serial keys, long opaque tokens |

`contact` and `identifiers` are off because they misfire more often in game UI.

```gdscript
engine.set_pack_enabled(PrivacyEngine.PACK_CONTACT, true)
engine.is_pack_enabled(PrivacyEngine.PACK_NETWORK)   # -> true
engine.get_packs()                                   # all four names
engine.add_pattern("\\bSEED [0-9A-F]{8}\\b")         # custom, always active
engine.allow_text("PRESS START")                     # exact strings to ignore
```

A pattern may expose a capture group named `secret` (or group 1) to mask only
that part of the match. That is how `Room: GAME-2231` blurs the code but not the
label. Packs overlap by design: a license key contains a code-shaped run that
`lobby_codes` also catches, which is a correct privacy outcome rather than a
false positive.

### Full API

| Member | Purpose |
| --- | --- |
| `setup(controller)` | Bind/rebind the controller **and start the scanner**. Idempotent. |
| `set_pack_enabled(pack, bool)` / `is_pack_enabled(pack)` / `get_packs()` / `get_enabled_packs()` | Pattern packs. |
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

Exports: `mask_params`, `target_margin`, `substring_margin`,
`precise_substrings` (default `true`), `auto_scan_on_setup` (default `true`),
`scan_interval`, `scan_names`, `name_keywords`, `scan_node_budget` (round-robin
batch size, default 400), `auto_register_from_group` (default `true`),
`privacy_group` (default `&"privacy_sensitive"`),
`rebind_scan_root_on_scene_change` (default `true`).

`scan_names` matches `name_keywords` against a node's **name only**. It
deliberately does not scan the node's text for those words, so conversational
chat like "this room is huge!" is not masked.

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

## PrivacyDrawTool (manual regions)

A **supplement** to the scanner, not a replacement for it. Use it for the cases
detection genuinely cannot reach: text drawn with `_draw()`, text baked into a
texture or sprite, a webcam or capture feed, or a third-party overlay. The
scanner remains the first line of defence.

```gdscript
const PrivacyDrawTool := preload("res://addons/streamer_mode/privacy/privacy_draw_tool.gd")

var draw := PrivacyDrawTool.new()
ui_root.add_child(draw)
draw.setup(engine)

# wire to a toggle button
button.toggled.connect(func(on): draw.set_armed(on))
draw.armed_changed.connect(func(on): button.set_pressed_no_signal(on))
```

Flow: `set_armed(true)` dims the screen and switches the cursor to a crosshair;
the next left-drag rubber-bands a rectangle; on release that rect becomes a
region and the tool disarms (set `stay_armed` to keep drawing). Drags shorter
than 24x18 px are ignored so a stray click does nothing. Escape cancels.

Each region is a `PrivacyDrawRegion` frame: drag the body to move, drag the
bottom-right handle to resize, press the small **x** to delete. Position and
size are clamped to the viewport, so a region can never be lost off screen, and
they re-clamp when the window resizes.

| Member | Purpose |
| --- | --- |
| `setup(engine)` | Bind the engine that draws the blur; also excludes the tool from scanning/masking. |
| `set_armed(bool)` / `is_armed()` | Arm the next drag. |
| `add_region(Rect2)` / `remove_region(id)` / `clear_regions()` | Programmatic control. |
| `get_region_count()` / `get_region_rects()` | State. |
| `show_chrome` | Hide the frames and handles for a clean stream look. The blur stays; regions stop intercepting the mouse so gameplay clicks pass through. |
| `stay_armed`, `region_params` | Exports: keep drawing after each region; per-region shader overrides. |
| signals `armed_changed`, `region_added(id, rect)`, `region_removed(id)`, `regions_changed(count)` | For host UI. |

Regions are registered with the engine through `register_rect_provider`, so they
obey the Streamer Mode / Privacy toggles like every other region. The provider
subtracts the engine's `target_margin` so the blur matches the drawn box exactly.

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
its own rect, so the game and the masks stay usable while it is open. Its
content scrolls, so give it whatever height suits the host.

`close()` hides it and emits `close_requested`; the header's **X** button calls
it. `open()` shows it and re-syncs the controls with the engine first. Connect
`close_requested` so the button that opened the panel follows it:

```gdscript
panel.close_requested.connect(func(): panel_button.set_pressed_no_signal(false))
```

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

## Demo wiring (`demo/main.gd`)

Turning on Streamer Mode is the only step: scanning is already running.
The demo shows all three paths side by side:

| Line | Masked by | Result |
| --- | --- | --- |
| `Player: xXx_Shadow_xXx \| Room: GAME-2231` | scanner, `lobby_codes` | only `GAME-2231` blurs |
| `MATCH SERVER 203.0.113.42:7777` | scanner, `network` | only the address blurs |
| `SESSION KX7Q-22F1` | `privacy_sensitive` group | whole node blurs |
| JOIN CODE | `PrivacyCopyField` + `register_node` | value blurs, Copy still works |

**+ Blur region** / **Handles** / **Clear** drive the supplemental draw tool.
The **PANEL** button opens the control panel, where scanning can be switched off
and pattern packs toggled.

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
