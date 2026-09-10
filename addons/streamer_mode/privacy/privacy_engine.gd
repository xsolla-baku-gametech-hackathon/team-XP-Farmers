class_name PrivacyEngine
extends CanvasLayer
## Automated privacy masking, gated by StreamerModeController.
##
## Two detection strategies feed one pool of blur masks:
##
##   Strategy A - Node scanner (opt-in, best effort)
##     Walks Label / RichTextLabel / LineEdit nodes under a chosen root and
##     RegEx-matches their visible text against code, IP and keyword patterns.
##     It cannot see text drawn with _draw(), text in textures, or strings that
##     do not match a pattern. Do not rely on it for anything that must not leak.
##
##   Strategy B - Registered regions (reliable)
##     The game explicitly marks a node or a rect provider as private. It is
##     masked whenever the feature is active and the mask follows the target
##     through layout changes and window resizes.
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
@export var mask_params: Dictionary = {
	"pixel_size": 14.0,
	"blur_spread": 1.6,
	"tint_amount": 0.30,
	"feather": 0.05,
}
@export var target_margin := 10.0    ## grow every masked rect by this many px
@export var scan_interval := 0.25    ## seconds between scanner passes
@export var scan_names := true       ## also match on a node's name
@export var name_keywords: PackedStringArray = ["room", "lobby", "invite"]

const _DEFAULT_PATTERNS := [
	"\\b[A-Z]{2,6}-?[0-9]{3,6}\\b",                            # lobby / match codes
	"\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?::[0-9]{2,5})?\\b",    # IPv4 with optional port
	"(?i)\\b(?:room|lobby|invite)\\b[ :#\\-]*[A-Za-z0-9]{3,}", # keyword followed by a value
]

var _controller: StreamerModeController
var _surface: Control
var _backbuffer: BackBufferCopy

var _scanning := false
var _scan_root: Node
var _scan_accum := 0.0
var _patterns: Array[RegEx] = []
var _text_nodes: Dictionary = {}   # instance_id -> Node
var _allow: Dictionary = {}        # exact trimmed string -> true
var _regions: Dictionary = {}      # StringName -> _Region


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
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


func _exit_tree() -> void:
	if _controller and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	var tree := get_tree()
	if tree:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		if tree.node_removed.is_connected(_on_node_removed):
			tree.node_removed.disconnect(_on_node_removed)


## --- Public API -------------------------------------------------------------

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
func register_node(id: StringName, node: Control, params: Dictionary = {}) -> void:
	var r := _ensure_region(id, KIND_NODE)
	r.node = node
	r.params = params


## Strategy B: mask a rect returned by `provider` (a Callable -> Rect2).
## Return a zero-size Rect2 to hide it.
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


func set_scanning(enabled: bool) -> void:
	_scanning = enabled
	_scan_accum = scan_interval
	if enabled and _scan_root == null:
		set_scan_root(get_tree().current_scene)


func set_scan_root(node: Node) -> void:
	_scan_root = node
	_text_nodes.clear()
	if is_instance_valid(node):
		_index_subtree(node)


func add_pattern(source: String) -> void:
	var rx := RegEx.new()
	if rx.compile(source) == OK:
		_patterns.append(rx)
	else:
		push_warning("PrivacyEngine: could not compile pattern %s" % source)


func allow_text(value: String) -> void:
	_allow[value.strip_edges()] = true


## Run a scanner pass and refresh every rect immediately.
func refresh() -> void:
	if _scanning and _feature_active():
		_run_scan()


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


## --- Frame loop ------------------------------------------------------------

func _process(delta: float) -> void:
	if not _feature_active():
		_update_backbuffer()
		return

	if _scanning:
		_scan_accum += delta
		if _scan_accum >= scan_interval:
			_scan_accum = 0.0
			_run_scan()

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


## --- Strategy A: scanner -------------------------------------------------

func _run_scan() -> void:
	if not is_instance_valid(_scan_root):
		_scan_root = get_tree().current_scene
	if not is_instance_valid(_scan_root):
		return
	if _text_nodes.is_empty():
		_index_subtree(_scan_root)

	var matched: Dictionary = {}
	for key in _text_nodes.keys():
		var node = _text_nodes[key]
		if not is_instance_valid(node):
			_text_nodes.erase(key)
			continue
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		if _is_sensitive(_node_text(node), node):
			matched[key] = node

	for key in matched:
		var id := StringName("scan:%d" % key)
		if _regions.has(id):
			(_regions[id] as _Region).alive = true
			continue
		var global_rect: Rect2 = (matched[key] as Control).get_global_rect()
		if _covered_by_registered(global_rect):
			continue
		var r := _ensure_region(id, KIND_SCAN)
		r.node = matched[key]
		match_found.emit(_node_text(matched[key]), _to_surface(global_rect))

	for id in _regions.keys():
		var r: _Region = _regions[id]
		if r.kind != KIND_SCAN:
			continue
		r.alive = matched.has(int(String(id).trim_prefix("scan:")))


func _index_subtree(node: Node) -> void:
	if _is_text_node(node):
		_text_nodes[node.get_instance_id()] = node
	for child in node.get_children():
		_index_subtree(child)


func _on_node_added(node: Node) -> void:
	if _scanning and _is_text_node(node) and is_instance_valid(_scan_root) \
			and _scan_root.is_ancestor_of(node):
		_text_nodes[node.get_instance_id()] = node


func _on_node_removed(node: Node) -> void:
	_text_nodes.erase(node.get_instance_id())


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


func _covered_by_registered(global_rect: Rect2) -> bool:
	var target := _to_surface(global_rect)
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


## --- Rects and masks ---------------------------------------------------

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
		return _to_surface(gr).grow(target_margin)
	if r.kind == KIND_PROVIDER:
		if not r.provider.is_valid():
			return Rect2()
		var out = r.provider.call()
		if out is Rect2 and out.size.x > 0.0 and out.size.y > 0.0:
			return _to_surface(out).grow(target_margin)
	return Rect2()


func _to_surface(global_rect: Rect2) -> Rect2:
	if not is_instance_valid(_surface):
		return global_rect
	var inv := _surface.get_global_transform().affine_inverse()
	return Rect2(inv * global_rect.position, global_rect.size)


func _spawn_mask(params: Dictionary) -> PrivacyBlurMask:
	var m := BlurMask.new()
	_surface.add_child(m)
	var merged := mask_params.duplicate()
	for key in params:
		merged[key] = params[key]
	m.configure(merged)
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


## --- Lifecycle helpers ------------------------------------------------

func _feature_active() -> bool:
	return _controller != null and _controller.is_feature_active(Controller.PRIVACY)


func _sync() -> void:
	if _feature_active():
		return
	for id in _regions.keys():
		var r: _Region = _regions[id]
		if is_instance_valid(r.mask):
			r.mask.dismiss()
		if r.kind == KIND_SCAN:
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


func _on_viewport_resized() -> void:
	if is_instance_valid(_surface):
		_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


class _Region:
	var id: StringName
	var kind := PrivacyEngine.KIND_NODE
	var alive := true
	var node: Node = null
	var provider := Callable()
	var params: Dictionary = {}
	var mask: PrivacyBlurMask = null
