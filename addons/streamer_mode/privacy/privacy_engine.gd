class_name PrivacyEngine
extends CanvasLayer
## Automated privacy masking, gated by StreamerModeController.
##
## Automation is the default. As soon as setup() binds a controller the scanner
## starts; a host that wants manual-only control can set auto_scan_on_setup to
## false or call set_scanning(false).
##
## Two detection strategies feed one pool of blur masks:
##
##   Strategy A - Node scanner (on by default)
##     Walks Label / RichTextLabel / LineEdit nodes under one or more scan roots
##     and RegEx-matches their visible text against enabled pattern packs. Where
##     the text layout can be measured it masks only the matched substring, not
##     the whole control. It cannot see text drawn with _draw(), text in
##     textures, or strings that match no pattern.
##
##   Strategy B - Registered regions (explicit, exact)
##     register_node() / register_rect_provider(), or a Control in the
##     "privacy_sensitive" group. Always masked while the feature is active.
##
## PrivacyDrawTool supplements both for anything the scanner cannot reach.

signal active_changed(active: bool)

signal region_masked(id: StringName, rect: Rect2)
signal region_cleared(id: StringName)
signal match_found(text: String, rect: Rect2)

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const BlurMask := preload("res://addons/streamer_mode/privacy/privacy_blur_mask.gd")
const Locator := preload("res://addons/streamer_mode/privacy/privacy_text_locator.gd")

const OVERLAY_LAYER := 127
const KIND_NODE := 0
const KIND_PROVIDER := 1
const KIND_SCAN := 2
const KIND_RETIRED := -1

## --- Pattern packs -------------------------------------------------------
## A pattern may expose a capture group named "secret" (or group 1) to mask
## only that part of the match, leaving the surrounding label text readable.

const PACK_LOBBY_CODES := &"lobby_codes"
const PACK_NETWORK := &"network"
const PACK_CONTACT := &"contact"
const PACK_IDENTIFIERS := &"identifiers"

const PATTERN_PACKS := {
	PACK_LOBBY_CODES: [
		# GAME-2231, XP4829
		"\\b[A-Z]{2,6}-?[0-9]{3,6}\\b",
		# KX7Q-22F1: two alphanumeric blocks, at least one digit somewhere
		"\\b(?=[A-Z0-9]*[0-9])[A-Z0-9]{4,8}-[A-Z0-9]{4,8}\\b",
		# "Room: abc123" - explicit separator, mask only the value
		"(?i)\\b(?:room|lobby|invite|party)\\s*(?:code|id)?\\s*[:#]\\s*(?<secret>[A-Za-z0-9][A-Za-z0-9\\-]{2,})",
		# "Room 4512" - no separator, so require a digit in the value
		"(?i)\\b(?:room|lobby|invite|party)\\s*(?:code|id)?\\s+(?<secret>(?=[A-Za-z0-9\\-]*[0-9])[A-Za-z0-9][A-Za-z0-9\\-]{3,})",
	],
	PACK_NETWORK: [
		# IPv4 with optional port
		"\\b(?:(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(?::[0-9]{1,5})?\\b",
		# IPv6, full eight groups
		"\\b(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}\\b",
		# IPv6, compressed - must contain "::" so clock times never match
		"\\b[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,5}::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,5})?",
		# bracketed IPv6 with port
		"\\[[0-9A-Fa-f:]{2,45}\\]:[0-9]{1,5}",
		# Discord invite links
		"(?i)\\b(?:https?://)?(?:www\\.)?discord(?:\\.gg|app\\.com/invite)/[A-Za-z0-9\\-]{2,32}\\b",
		# Steam IDs and friend codes
		"\\bSTEAM_[0-5]:[01]:[0-9]{1,12}\\b",
		"(?i)\\bfriend\\s*code\\s*[:#]?\\s*(?<secret>[0-9]{6,12})\\b",
		# explicit port callouts
		"(?i)\\bport\\s*[:#]?\\s*(?<secret>[0-9]{2,5})\\b",
	],
	PACK_CONTACT: [
		# email
		"\\b[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}\\b",
		# phone, three-group form
		"\\b(?:\\+[0-9]{1,3}[ .\\-])?\\(?[0-9]{3}\\)?[ .\\-][0-9]{3}[ .\\-][0-9]{4}\\b",
		# phone, international
		"\\+[0-9]{1,3}[ .\\-]?[0-9]{2,4}(?:[ .\\-][0-9]{2,4}){2,3}",
	],
	PACK_IDENTIFIERS: [
		# UUID
		"\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b",
		# JWT
		"\\beyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\b",
		# license / serial keys
		"\\b[A-Z0-9]{4,5}(?:-[A-Z0-9]{4,5}){3,4}\\b",
		# long opaque tokens
		"\\b[A-Za-z0-9_\\-]{28,}\\b",
	],
}

## Packs on unless the host says otherwise. contact and identifiers are opt-in
## because they misfire more often in game UI.
const DEFAULT_PACKS := [PACK_LOBBY_CODES, PACK_NETWORK]

## --- Exports -------------------------------------------------------------

## Shader defaults for every spawned mask; per-region params override these.
## Use set_mask_param() to also update masks already on screen.
@export var mask_params: Dictionary = {
	"pixel_size": 14.0,
	"blur_spread": 1.6,
	"tint_amount": 0.30,
	"feather": 0.05,
}
@export var target_margin := 10.0     ## grow whole-node masked rects by this many px
@export var substring_margin := 3.0   ## grow measured substring rects by this many px
@export var precise_substrings := true ## mask the matched run, not the whole node
@export var auto_scan_on_setup := true ## automation is the default
@export var scan_interval := 0.25     ## seconds between scanner passes
@export var scan_names := true        ## also treat a keyword in a node's NAME as private
@export var name_keywords: PackedStringArray = ["room", "lobby", "invite"]
@export var scan_node_budget := 400   ## nodes checked per pass before round-robin batching
@export var auto_register_from_group := true
@export var privacy_group: StringName = &"privacy_sensitive"
@export var rebind_scan_root_on_scene_change := true

var _controller: StreamerModeController
var _surface: Control
var _backbuffer: BackBufferCopy

var _scanning := false
var _scan_roots: Array = []          # [{ node: Node, to_screen: Callable }]
var _bound_scene: Node = null
var _scene_dirty := false
var _scan_accum := 0.0
var _scan_cursor := 0
var _sweep_matched: Dictionary = {}  # region id -> true, accumulated over one sweep
var _pack_regex: Dictionary = {}     # pack -> Array[RegEx]
var _enabled_packs: Dictionary = {}  # pack -> bool
var _custom_patterns: Array[RegEx] = []
var _active_cache: Array = []
var _active_dirty := true
var _text_nodes: Dictionary = {}     # instance_id -> { node: Node, to_screen: Callable }
var _allow: Dictionary = {}          # exact trimmed string -> true
var _excluded: Array = []
var _regions: Dictionary = {}        # StringName -> _Region


func _ready() -> void:
	layer = OVERLAY_LAYER

	_backbuffer = BackBufferCopy.new()
	_backbuffer.name = "ScreenCopy"
	_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_backbuffer)

	_surface = Control.new()
	_surface.name = "Surface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_compile_packs()

	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	tree.node_removed.connect(_on_node_removed)
	tree.tree_changed.connect(_on_tree_changed)
	_bound_scene = tree.current_scene
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)

	if auto_register_from_group:
		_sweep_group.call_deferred()


func _exit_tree() -> void:
	if _controller and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	var tree := get_tree()
	if tree:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		if tree.node_removed.is_connected(_on_node_removed):
			tree.node_removed.disconnect(_on_node_removed)
		if tree.tree_changed.is_connected(_on_tree_changed):
			tree.tree_changed.disconnect(_on_tree_changed)


## --- Public API -----------------------------------------------------------

## Bind (or rebind) the shared controller. Starts the scanner unless
## auto_scan_on_setup was turned off. Idempotent.
func setup(controller: StreamerModeController) -> void:
	if _controller == controller:
		return
	if _controller and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	_controller = controller
	if _controller:
		_controller.state_changed.connect(_sync)
	if auto_scan_on_setup and _controller != null:
		set_scanning(true)
	_sync()


## Strategy B: mask this Control whenever the feature is active.
func register_node(id: StringName, node: Control, params: Dictionary = {}, to_screen := Callable()) -> void:
	var r := _ensure_region(id, KIND_NODE)
	r.node = node
	r.params = params
	r.to_screen = to_screen


## Strategy B: mask a rect returned by `provider` (a Callable -> Rect2).
func register_rect_provider(id: StringName, provider: Callable, params: Dictionary = {}) -> void:
	var r := _ensure_region(id, KIND_PROVIDER)
	r.provider = provider
	r.params = params


func unregister(id: StringName) -> void:
	if _regions.has(id):
		var r: _Region = _regions[id]
		r.kind = KIND_RETIRED
		if is_instance_valid(r.mask):
			r.mask.dismiss()


## Turning scanning off retires every scanner-found region (their masks fade);
## registered regions are untouched. Turning it on re-indexes.
func set_scanning(enabled: bool) -> void:
	if _scanning == enabled:
		return
	_scanning = enabled
	_scan_accum = scan_interval
	if not enabled:
		_drop_scan_regions()
		return
	if _scan_roots.is_empty():
		set_scan_root(get_tree().current_scene)
	else:
		_reindex()


func is_scanning() -> bool:
	return _scanning


func set_scan_root(node: Node) -> void:
	set_scan_roots([node] if node != null else [])


## Entries are a Node, or { node, to_screen } where to_screen: Callable(Rect2)
## -> Rect2 maps a rect from that subtree's viewport into main-viewport pixels.
func set_scan_roots(roots: Array) -> void:
	_scan_roots.clear()
	for entry in roots:
		_append_root(entry)
	_reindex()


func add_scan_root(node: Node, to_screen := Callable()) -> void:
	_append_root({"node": node, "to_screen": to_screen})
	if is_instance_valid(node):
		_index_subtree(node, to_screen)


func exclude_subtree(node: Node) -> void:
	if is_instance_valid(node) and not _excluded.has(node):
		_excluded.append(node)


## --- pattern packs ------------------------------------------------------

func set_pack_enabled(pack: StringName, enabled: bool) -> void:
	if not PATTERN_PACKS.has(pack):
		push_warning("PrivacyEngine: unknown pattern pack %s" % pack)
		return
	if _enabled_packs.get(pack, false) == enabled:
		return
	_enabled_packs[pack] = enabled
	_active_dirty = true


func is_pack_enabled(pack: StringName) -> bool:
	return bool(_enabled_packs.get(pack, false))


func get_packs() -> Array:
	return PATTERN_PACKS.keys()


func get_enabled_packs() -> Array:
	var out: Array = []
	for pack in PATTERN_PACKS:
		if is_pack_enabled(pack):
			out.append(pack)
	return out


## Extra pattern, always active regardless of pack toggles.
func add_pattern(source: String) -> void:
	var rx := RegEx.new()
	if rx.compile(source) == OK:
		_custom_patterns.append(rx)
		_active_dirty = true
	else:
		push_warning("PrivacyEngine: could not compile pattern %s" % source)


func allow_text(value: String) -> void:
	_allow[value.strip_edges()] = true


func remove_allowed_text(value: String) -> void:
	_allow.erase(value.strip_edges())


func clear_allowed_texts() -> void:
	_allow.clear()


func get_allowed_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _allow.keys():
		out.append(k)
	return out


## Update a shader default and push it to every mask already on screen.
func set_mask_param(key: String, value) -> void:
	mask_params[key] = value
	for id in _regions:
		var r: _Region = _regions[id]
		if is_instance_valid(r.mask):
			r.mask.configure(_merged_params(r.params))


func refresh_group() -> void:
	_sweep_group()


## Force a full scanner pass and refresh every rect immediately.
func refresh() -> void:
	if _scanning and _feature_active():
		_run_scan(true)


func active_region_count() -> int:
	var n := 0
	for id in _regions:
		var r: _Region = _regions[id]
		if is_instance_valid(r.mask) and not r.mask.is_dismissing():
			n += 1
	return n


func is_active() -> bool:
	return _feature_active()


func get_scan_stats() -> Dictionary:
	return {
		"scanning": _scanning,
		"indexed": _text_nodes.size(),
		"budget": scan_node_budget,
		"cursor": _scan_cursor,
		"roots": _scan_roots.size(),
		"scan_regions": _count_kind(KIND_SCAN),
		"registered_regions": _count_kind(KIND_NODE) + _count_kind(KIND_PROVIDER),
		"packs": get_enabled_packs(),
	}


## --- Frame loop ---------------------------------------------------------

func _process(delta: float) -> void:
	if _scene_dirty:
		_scene_dirty = false
		_maybe_rebind_scene()

	if not _feature_active():
		_update_backbuffer()
		return

	if _scanning:
		_scan_accum += delta
		if _scan_accum >= scan_interval:
			_scan_accum = 0.0
			_run_scan(false)

	for id in _regions.keys():
		var r: _Region = _regions[id]
		var rect := _region_rect(r)
		var wanted := r.kind >= 0 and (r.kind != KIND_SCAN or r.alive) \
			and rect.size.x > 1.0 and rect.size.y > 1.0

		if wanted:
			if not is_instance_valid(r.mask):
				r.mask = _spawn_mask(r.params)
				r.mask.move_to(rect, true)
				region_masked.emit(id, rect)
			else:
				r.mask.move_to(rect)
		elif is_instance_valid(r.mask):
			r.mask.dismiss()

		if not is_instance_valid(r.mask) and (r.kind == KIND_RETIRED \
				or (r.kind == KIND_SCAN and not r.alive)):
			_regions.erase(id)
			region_cleared.emit(id)

	_update_backbuffer()


## --- Strategy A: scanner ----------------------------------------------

func _run_scan(force_full: bool) -> void:
	if _scan_roots.is_empty():
		set_scan_root(get_tree().current_scene)
	if _text_nodes.is_empty():
		_reindex()

	var keys := _text_nodes.keys()
	if keys.is_empty():
		return

	var full := force_full or keys.size() <= scan_node_budget
	var batch: Array = keys
	if not full:
		if _scan_cursor >= keys.size():
			_scan_cursor = 0
		var stop: int = mini(_scan_cursor + scan_node_budget, keys.size())
		batch = keys.slice(_scan_cursor, stop)
		_scan_cursor = stop
	else:
		_scan_cursor = 0
		_sweep_matched.clear()

	for key in batch:
		var entry = _text_nodes[key]
		var node = entry["node"]
		if not is_instance_valid(node):
			_text_nodes.erase(key)
			continue
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		if _is_excluded(node):
			continue
		var ctrl := node as Control
		var text := Locator.text_of(ctrl)
		var ranges := _match_ranges(text, ctrl)
		if ranges.is_empty():
			continue
		for frag in _fragments_for(ctrl, ranges, entry["to_screen"]):
			var id: StringName = frag["id"]
			_sweep_matched[id] = true
			if _regions.has(id):
				(_regions[id] as _Region).alive = true
				continue
			if _covered_by_registered(frag["screen_rect"]):
				continue
			var r := _ensure_region(id, KIND_SCAN)
			r.node = ctrl
			r.to_screen = entry["to_screen"]
			r.text_range = frag["range"]
			r.frag_index = frag["frag"]
			r.whole_node = frag["whole"]
			r.local_rect = frag["local_rect"]
			r.measure_sig = _measure_sig(ctrl, text)
			match_found.emit(frag["label"], frag["screen_rect"])

	var sweep_done := full or _scan_cursor >= keys.size()
	if sweep_done:
		_scan_cursor = 0
		for id in _regions.keys():
			var r: _Region = _regions[id]
			if r.kind != KIND_SCAN:
				continue
			r.alive = _sweep_matched.has(id)
		_sweep_matched.clear()


## Character ranges of every private run in `text`. A single Vector2i(-1, -1)
## means "private, but no measurable range" (mask the whole node).
func _match_ranges(text: String, node: Node) -> Array:
	if scan_names and _name_matches(node):
		return [Vector2i(-1, -1)]
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _allow.has(trimmed):
		return []
	var found: Array = []
	for rx in _active_patterns():
		var offset := 0
		while offset <= text.length():
			var m: RegExMatch = rx.search(text, offset)
			if m == null:
				break
			var s := _match_start(m)
			var e := _match_end(m)
			if e > s:
				var piece := text.substr(s, e - s).strip_edges()
				if not _allow.has(piece):
					found.append(Vector2i(s, e))
			offset = maxi(m.get_end(0), offset + 1)
	return _merge_ranges(found)


func _fragments_for(ctrl: Control, ranges: Array, to_screen: Callable) -> Array:
	var out: Array = []
	var base := ctrl.get_instance_id()
	var text := Locator.text_of(ctrl)
	var global_rect := ctrl.get_global_rect()
	for ri in ranges.size():
		var rng: Vector2i = ranges[ri]
		var rects: Array[Rect2] = []
		if precise_substrings and rng.x >= 0 and Locator.supports(ctrl):
			rects = Locator.locate(ctrl, rng.x, rng.y)
		if rects.is_empty():
			out.append({
				"id": StringName("scan:%d:%d:w" % [base, ri]),
				"range": rng, "frag": 0, "whole": true, "local_rect": Rect2(),
				"screen_rect": _map_rect(global_rect, to_screen),
				"label": text,
			})
			continue
		var piece := text.substr(rng.x, rng.y - rng.x)
		for fi in rects.size():
			out.append({
				"id": StringName("scan:%d:%d:%d" % [base, ri, fi]),
				"range": rng, "frag": fi, "whole": false, "local_rect": rects[fi],
				"screen_rect": _map_rect(Rect2(global_rect.position + rects[fi].position, rects[fi].size), to_screen),
				"label": piece,
			})
	return out


func _active_patterns() -> Array:
	if not _active_dirty:
		return _active_cache
	_active_cache = []
	for pack in PATTERN_PACKS:
		if is_pack_enabled(pack):
			_active_cache.append_array(_pack_regex.get(pack, []))
	_active_cache.append_array(_custom_patterns)
	_active_dirty = false
	return _active_cache


func _compile_packs() -> void:
	for pack in PATTERN_PACKS:
		var arr: Array[RegEx] = []
		for src in PATTERN_PACKS[pack]:
			var rx := RegEx.new()
			if rx.compile(src) == OK:
				arr.append(rx)
			else:
				push_warning("PrivacyEngine: bad pattern in pack %s: %s" % [pack, src])
		_pack_regex[pack] = arr
		if not _enabled_packs.has(pack):
			_enabled_packs[pack] = DEFAULT_PACKS.has(pack)
	_active_dirty = true


## Prefer a "secret" capture group, then group 1, then the whole match.
func _match_start(m: RegExMatch) -> int:
	if m.names.has("secret"):
		var s := m.get_start("secret")
		if s >= 0:
			return s
	if m.get_group_count() >= 1:
		var g := m.get_start(1)
		if g >= 0:
			return g
	return m.get_start(0)


func _match_end(m: RegExMatch) -> int:
	if m.names.has("secret"):
		var e := m.get_end("secret")
		if e >= 0:
			return e
	if m.get_group_count() >= 1:
		var g := m.get_end(1)
		if g >= 0:
			return g
	return m.get_end(0)


func _merge_ranges(ranges: Array) -> Array:
	if ranges.size() <= 1:
		return ranges
	ranges.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x)
	var out: Array = [ranges[0]]
	for i in range(1, ranges.size()):
		var cur: Vector2i = ranges[i]
		var last: Vector2i = out[out.size() - 1]
		if cur.x <= last.y:
			out[out.size() - 1] = Vector2i(last.x, maxi(last.y, cur.y))
		else:
			out.append(cur)
	return out


func _name_matches(node: Node) -> bool:
	var name_l := String(node.name).to_lower()
	for kw in name_keywords:
		if not kw.is_empty() and name_l.contains(kw.to_lower()):
			return true
	return false


func _measure_sig(ctrl: Control, text: String) -> String:
	return "%s|%.1f|%.1f" % [text, ctrl.size.x, ctrl.size.y]


func _refresh_measure(r: _Region, ctrl: Control) -> void:
	var text := Locator.text_of(ctrl)
	var sig := _measure_sig(ctrl, text)
	if r.measure_sig == sig:
		return
	r.measure_sig = sig
	if r.text_range.x < 0 or r.text_range.y > text.length():
		r.local_rect = Rect2()
		return
	var rects := Locator.locate(ctrl, r.text_range.x, r.text_range.y)
	r.local_rect = rects[r.frag_index] if r.frag_index < rects.size() else Rect2()


func _reindex() -> void:
	_text_nodes.clear()
	_scan_cursor = 0
	for root in _scan_roots:
		if is_instance_valid(root["node"]):
			_index_subtree(root["node"], root["to_screen"])


func _index_subtree(node: Node, to_screen: Callable) -> void:
	if Locator.supports(node) and not _is_excluded(node):
		_text_nodes[node.get_instance_id()] = {"node": node, "to_screen": to_screen}
	for child in node.get_children():
		_index_subtree(child, to_screen)


func _on_node_added(node: Node) -> void:
	if _scanning and Locator.supports(node) and not _is_excluded(node):
		var to_screen = _root_transform_for(node)
		if to_screen != null:
			_text_nodes[node.get_instance_id()] = {"node": node, "to_screen": to_screen}
	if auto_register_from_group and node is Control and node.is_in_group(privacy_group):
		_group_register(node)


func _on_node_removed(node: Node) -> void:
	_text_nodes.erase(node.get_instance_id())
	unregister(StringName("group:%d" % node.get_instance_id()))


func _on_tree_changed() -> void:
	_scene_dirty = true


func _drop_scan_regions() -> void:
	_sweep_matched.clear()
	_scan_cursor = 0
	for id in _regions.keys():
		var r: _Region = _regions[id]
		if r.kind != KIND_SCAN:
			continue
		r.alive = false
		if is_instance_valid(r.mask):
			r.mask.dismiss()
		else:
			_regions.erase(id)
			region_cleared.emit(id)


func _covered_by_registered(target: Rect2) -> bool:
	if target.get_area() <= 0.0:
		return false
	for id in _regions:
		var r: _Region = _regions[id]
		if r.kind != KIND_NODE and r.kind != KIND_PROVIDER:
			continue
		var rr := _region_rect(r)
		if rr.get_area() <= 0.0:
			continue
		if rr.intersection(target).get_area() >= target.get_area() * 0.6:
			return true
	return false


## --- Group auto-registration -----------------------------------------

func _sweep_group() -> void:
	if not auto_register_from_group or not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(privacy_group):
		if node is Control:
			_group_register(node)


func _group_register(node: Control) -> void:
	if not auto_register_from_group or _is_excluded(node):
		return
	register_node(StringName("group:%d" % node.get_instance_id()), node)


## --- Rects and masks ------------------------------------------------

func _region_rect(r: _Region) -> Rect2:
	if r.kind == KIND_NODE or r.kind == KIND_SCAN:
		if not is_instance_valid(r.node) or not (r.node is Control):
			return Rect2()
		var ctrl := r.node as Control
		if not ctrl.is_visible_in_tree():
			return Rect2()
		var gr := ctrl.get_global_rect()
		if gr.size.x <= 0.0 or gr.size.y <= 0.0:
			return Rect2()
		if r.kind == KIND_SCAN and not r.whole_node:
			_refresh_measure(r, ctrl)
			if r.local_rect.size.x > 0.0 and r.local_rect.size.y > 0.0:
				var sub := Rect2(gr.position + r.local_rect.position, r.local_rect.size)
				return _map_rect(sub, r.to_screen).grow(substring_margin)
		return _map_rect(gr, r.to_screen).grow(target_margin)
	if r.kind == KIND_PROVIDER:
		if not r.provider.is_valid():
			return Rect2()
		var out = r.provider.call()
		if out is Rect2 and out.size.x > 0.0 and out.size.y > 0.0:
			return _to_surface(out).grow(target_margin)
	return Rect2()


func _map_rect(rect: Rect2, to_screen: Callable) -> Rect2:
	if to_screen.is_valid():
		var mapped = to_screen.call(rect)
		if mapped is Rect2:
			return _to_surface(mapped)
	return _to_surface(rect)


func _to_surface(global_rect: Rect2) -> Rect2:
	if not is_instance_valid(_surface):
		return global_rect
	var inv := _surface.get_global_transform().affine_inverse()
	return Rect2(inv * global_rect.position, global_rect.size)


func _merged_params(region_params: Dictionary) -> Dictionary:
	var merged := mask_params.duplicate()
	for key in region_params:
		merged[key] = region_params[key]
	return merged


func _spawn_mask(params: Dictionary) -> PrivacyBlurMask:
	var m := BlurMask.new()
	_surface.add_child(m)
	m.configure(_merged_params(params))
	return m


func _update_backbuffer() -> void:
	var union := Rect2()
	var any := false
	for id in _regions:
		var r: _Region = _regions[id]
		if not is_instance_valid(r.mask):
			continue
		var mr := Rect2(r.mask.position, r.mask.size)
		union = mr if not any else union.merge(mr)
		any = true
	if any:
		_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_RECT
		_backbuffer.rect = union.grow(4.0)
	else:
		_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_DISABLED


## --- Lifecycle helpers --------------------------------------------

func _feature_active() -> bool:
	return _controller != null and _controller.is_feature_active(Controller.PRIVACY)


func _sync() -> void:
	active_changed.emit(_feature_active())
	if _feature_active():
		return
	for id in _regions.keys():
		var r: _Region = _regions[id]
		if is_instance_valid(r.mask):
			r.mask.dismiss()
		if r.kind == KIND_SCAN or (r.kind == KIND_RETIRED and not is_instance_valid(r.mask)):
			_regions.erase(id)
	_update_backbuffer()


func _ensure_region(id: StringName, kind: int) -> _Region:
	var r: _Region
	if _regions.has(id):
		r = _regions[id]
	else:
		r = _Region.new()
		r.id = id
		_regions[id] = r
	r.kind = kind
	r.alive = true
	return r


func _count_kind(kind: int) -> int:
	var n := 0
	for id in _regions:
		if (_regions[id] as _Region).kind == kind:
			n += 1
	return n


func _append_root(entry) -> void:
	var record := {"node": null, "to_screen": Callable()}
	if entry is Dictionary:
		record["node"] = entry.get("node", null)
		record["to_screen"] = entry.get("to_screen", Callable())
	else:
		record["node"] = entry
	if is_instance_valid(record["node"]):
		_scan_roots.append(record)


func _root_transform_for(node: Node):
	for root in _scan_roots:
		var rn = root["node"]
		if is_instance_valid(rn) and (rn == node or rn.is_ancestor_of(node)):
			return root["to_screen"]
	return null


func _is_excluded(node: Node) -> bool:
	for ex in _excluded:
		if is_instance_valid(ex) and (ex == node or ex.is_ancestor_of(node)):
			return true
	return false


func _maybe_rebind_scene() -> void:
	var scene := get_tree().current_scene
	if scene == _bound_scene:
		return
	var old_scene := _bound_scene
	_bound_scene = scene
	if not rebind_scan_root_on_scene_change:
		return
	var swapped := false
	for root in _scan_roots:
		if root["node"] == old_scene or not is_instance_valid(root["node"]):
			root["node"] = scene
			swapped = true
	if swapped or _scan_roots.is_empty():
		if _scan_roots.is_empty() and is_instance_valid(scene):
			_scan_roots.append({"node": scene, "to_screen": Callable()})
		_reindex()
	if auto_register_from_group:
		_sweep_group()


func _on_viewport_resized() -> void:
	if is_instance_valid(_surface):
		_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


class _Region:
	var id: StringName
	var kind := PrivacyEngine.KIND_NODE
	var alive := true
	var node: Node = null
	var provider := Callable()
	var to_screen := Callable()
	var params: Dictionary = {}
	var mask: PrivacyBlurMask = null
	# Scanner sub-rect bookkeeping.
	var text_range := Vector2i(-1, -1)
	var frag_index := 0
	var whole_node := true
	var local_rect := Rect2()
	var measure_sig := ""
