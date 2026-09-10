class_name PrivacyEngine
extends CanvasLayer
## Automated privacy masking, gated by StreamerModeController.
##
## Two detection strategies feed one pool of blur masks:
##
##   Strategy A - Node scanner (opt-in, best effort)
##     Walks Label / RichTextLabel / LineEdit nodes under one or more scan roots
##     and RegEx-matches their visible text against code, IP and keyword
##     patterns. It cannot see text drawn with _draw(), text in textures, or
##     strings that do not match a pattern. Do not rely on it for anything that
##     must not leak.
##
##   Strategy B - Registered regions (reliable)
##     The game explicitly marks a node or a rect provider as private, either by
##     calling register_node()/register_rect_provider() or by putting a Control
##     in the "privacy_sensitive" group. It is masked whenever the feature is
##     active and the mask follows the target through layout and window resizes.
##
## For every active target a PrivacyBlurMask is snapped over its global rect.
## When the target disappears - node freed or hidden, text no longer matches,
## region unregistered, or the feature switched off - the mask fades and frees.

signal region_masked(id: StringName, rect: Rect2)
signal region_cleared(id: StringName)
signal match_found(text: String, rect: Rect2)

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const BlurMask := preload("res://addons/streamer_mode/privacy/privacy_blur_mask.gd")

const OVERLAY_LAYER := 127
const KIND_NODE := 0
const KIND_PROVIDER := 1
const KIND_SCAN := 2
const KIND_RETIRED := -1

## Shader defaults for every spawned mask; per-region params override these.
## Assign through set_mask_param() to also update masks that are already on
## screen; a bare `mask_params[...] =` only affects masks spawned afterwards.
@export var mask_params: Dictionary = {
	"pixel_size": 14.0,
	"blur_spread": 1.6,
	"tint_amount": 0.30,
	"feather": 0.05,
}
@export var target_margin := 10.0     ## grow every masked rect by this many px
@export var scan_interval := 0.25     ## seconds between scanner passes
@export var scan_names := true        ## also match on a node's name
@export var name_keywords: PackedStringArray = ["room", "lobby", "invite"]
@export var scan_node_budget := 400   ## nodes checked per pass before round-robin batching
@export var auto_register_from_group := true
@export var privacy_group: StringName = &"privacy_sensitive"
@export var rebind_scan_root_on_scene_change := true

const _DEFAULT_PATTERNS := [
	"\\b[A-Z]{2,6}-?[0-9]{3,6}\\b",                            # lobby / match codes
	"\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?::[0-9]{2,5})?\\b",    # IPv4 with optional port
	"(?i)\\b(?:room|lobby|invite)\\b[ :#\\-]*[A-Za-z0-9]{3,}", # keyword followed by a value
]

var _controller: StreamerModeController
var _surface: Control
var _backbuffer: BackBufferCopy

var _scanning := false
var _scan_roots: Array = []          # [{ node: Node, to_screen: Callable }]
var _bound_scene: Node = null
var _scene_dirty := false
var _scan_accum := 0.0
var _scan_cursor := 0
var _sweep_matched: Dictionary = {}  # instance_id -> Node, accumulates over one sweep
var _patterns: Array[RegEx] = []
var _text_nodes: Dictionary = {}     # instance_id -> { node: Node, to_screen: Callable }
var _allow: Dictionary = {}          # exact trimmed string -> true
var _excluded: Array = []            # subtrees the scanner and group auto-register ignore
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

	for src in _DEFAULT_PATTERNS:
		add_pattern(src)

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

## Bind (or rebind) the shared controller. Idempotent.
func setup(controller: StreamerModeController) -> void:
	if _controller == controller:
		return
	if _controller and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	_controller = controller
	if _controller:
		_controller.state_changed.connect(_sync)
	_sync()


## Strategy B: mask this Control whenever the feature is active.
## `to_screen` optionally maps the node's rect into main-viewport pixels (for a
## node that lives inside a SubViewport shown elsewhere on screen).
func register_node(id: StringName, node: Control, params: Dictionary = {}, to_screen := Callable()) -> void:
	var r := _ensure_region(id, KIND_NODE)
	r.node = node
	r.params = params
	r.to_screen = to_screen


## Strategy B: mask a rect returned by `provider` (a Callable -> Rect2 in
## main-viewport pixels). Return a zero-size Rect2 to hide it.
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


## Turn Strategy A on or off. Turning it off retires every region the scanner
## found (their masks fade out); registered regions are untouched. Turning it on
## re-indexes, so nodes added while it was off are picked up.
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


## Retire every scanner-found region. Registered regions are left alone.
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


## Single scan root (kept for API stability). Sugar for set_scan_roots([node]).
func set_scan_root(node: Node) -> void:
	set_scan_roots([node] if node != null else [])


## Replace the scan roots. Each entry is a Node, or { node, to_screen } where
## to_screen: Callable(Rect2) -> Rect2 maps a rect from that subtree's viewport
## into main-viewport pixels (needed for SubViewport / split-screen roots).
func set_scan_roots(roots: Array) -> void:
	_scan_roots.clear()
	for entry in roots:
		_append_root(entry)
	_reindex()


func add_scan_root(node: Node, to_screen := Callable()) -> void:
	_append_root({"node": node, "to_screen": to_screen})
	if _is_scan_node_root(node):
		_index_subtree(node, to_screen)


## Never mask, and never scan, anything inside this subtree (e.g. a dev panel).
func exclude_subtree(node: Node) -> void:
	if is_instance_valid(node) and not _excluded.has(node):
		_excluded.append(node)


func add_pattern(source: String) -> void:
	var rx := RegEx.new()
	if rx.compile(source) == OK:
		_patterns.append(rx)
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


## Re-scan the "privacy_sensitive" group now (e.g. after building UI in code).
func refresh_group() -> void:
	_sweep_group()


## Force a full scanner pass and refresh every rect immediately.
func refresh() -> void:
	if _scanning and _feature_active():
		_run_scan(true)


## Number of regions currently showing a (non-dismissing) mask.
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
		if not _is_sensitive(_node_text(node), node):
			continue
		_sweep_matched[key] = node
		var id := StringName("scan:%d" % key)
		if _regions.has(id):
			(_regions[id] as _Region).alive = true
			continue
		var gr: Rect2 = (node as Control).get_global_rect()
		if _covered_by_registered(_map_rect(gr, entry["to_screen"])):
			continue
		var r := _ensure_region(id, KIND_SCAN)
		r.node = node
		r.to_screen = entry["to_screen"]
		match_found.emit(_node_text(node), _map_rect(gr, entry["to_screen"]))

	var sweep_done := full or _scan_cursor >= keys.size()
	if sweep_done:
		_scan_cursor = 0
		for id in _regions.keys():
			var r: _Region = _regions[id]
			if r.kind != KIND_SCAN:
				continue
			r.alive = _sweep_matched.has(int(String(id).trim_prefix("scan:")))
		_sweep_matched.clear()


func _reindex() -> void:
	_text_nodes.clear()
	_scan_cursor = 0
	for root in _scan_roots:
		if _is_scan_node_root(root["node"]):
			_index_subtree(root["node"], root["to_screen"])


func _index_subtree(node: Node, to_screen: Callable) -> void:
	if _is_text_node(node) and not _is_excluded(node):
		_text_nodes[node.get_instance_id()] = {"node": node, "to_screen": to_screen}
	for child in node.get_children():
		_index_subtree(child, to_screen)


func _on_node_added(node: Node) -> void:
	if _scanning and _is_text_node(node) and not _is_excluded(node):
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


func _is_text_node(node: Node) -> bool:
	return node is Label or node is RichTextLabel or node is LineEdit


func _node_text(node: Node) -> String:
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	if node is Label:
		return (node as Label).text
	if node is LineEdit:
		return (node as LineEdit).text
	return ""


func _is_sensitive(text: String, node: Node) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _allow.has(trimmed):
		return false
	for rx in _patterns:
		if rx.search(trimmed) != null:
			return true
	if scan_names:
		var hay := (trimmed + " " + String(node.name)).to_lower()
		for kw in name_keywords:
			if not kw.is_empty() and hay.contains(kw.to_lower()):
				return true
	return false


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


func _is_scan_node_root(node) -> bool:
	return is_instance_valid(node)


func _root_transform_for(node: Node):
	# Returns the to_screen Callable of the first root that contains `node`,
	# or null when no root does.
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
