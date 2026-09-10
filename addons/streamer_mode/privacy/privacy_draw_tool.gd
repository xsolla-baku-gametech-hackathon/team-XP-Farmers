class_name PrivacyDrawTool
extends CanvasLayer
## Manual blur regions - the "draw it yourself" alternative to the scanner.
##
##   1. set_armed(true)  (wire this to a button)
##   2. the streamer drags a rectangle anywhere on screen
##   3. on release that area becomes a blur region
##
## Each region can then be dragged to move, resized from its bottom-right
## corner, and deleted. Nothing is detected automatically; regions live until
## they are removed. The blur is still drawn by PrivacyEngine, so it respects
## the Streamer Mode / Privacy toggles exactly like every other region.

signal armed_changed(armed: bool)
signal region_added(id: StringName, rect: Rect2)
signal region_removed(id: StringName)
signal regions_changed(count: int)

const DrawRegion := preload("res://addons/streamer_mode/privacy/privacy_draw_region.gd")

const TOOL_LAYER := 128            ## above PrivacyEngine's masks (127)
const MIN_DRAG := Vector2(24.0, 18.0)
const GUIDE := Color(0.70, 0.93, 0.58, 0.95)
const GUIDE_FILL := Color(0.70, 0.93, 0.58, 0.10)
const SCRIM := Color(0.04, 0.06, 0.09, 0.25)

## Shader overrides applied to regions this tool creates.
@export var region_params: Dictionary = {}
## Arm again automatically after each region, for drawing several in a row.
@export var stay_armed := false
@export var show_chrome := true:
	set(value):
		show_chrome = value
		for entry in _regions:
			if is_instance_valid(entry["node"]):
				entry["node"].show_chrome = value

var _engine: PrivacyEngine
var _surface: Control
var _catcher: Control
var _regions: Array = []           # [{ id: StringName, node: PrivacyDrawRegion }]
var _armed := false
var _drawing := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _next_id := 1


func _ready() -> void:
	layer = TOOL_LAYER

	_surface = Control.new()
	_surface.name = "Surface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_catcher = Control.new()
	_catcher.name = "DrawCatcher"
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_catcher.gui_input.connect(_on_catcher_gui_input)
	_catcher.draw.connect(_on_catcher_draw)
	_surface.add_child(_catcher)
	_surface.move_child(_catcher, 0)     # regions draw above the scrim

	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


## Bind the engine that will blur these regions.
func setup(engine: PrivacyEngine) -> void:
	_engine = engine
	if not is_instance_valid(_engine):
		return
	_engine.exclude_subtree(self)
	for entry in _regions:
		_register(entry["id"], entry["node"])


## --- arming ------------------------------------------------------------

func set_armed(value: bool) -> void:
	if _armed == value:
		return
	_armed = value
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if not value:
		_drawing = false
	_catcher.queue_redraw()
	armed_changed.emit(_armed)


func is_armed() -> bool:
	return _armed


## --- regions -----------------------------------------------------------

## Add a region directly, in viewport pixels. Returns its region id.
func add_region(rect: Rect2) -> StringName:
	var id := StringName("draw:%d" % _next_id)
	_next_id += 1
	var region := DrawRegion.new()
	region.name = "Region%d" % _next_id
	region.show_chrome = show_chrome
	_surface.add_child(region)
	region.set_region_rect(rect)
	region.remove_requested.connect(_on_remove_requested.bind(id))
	_regions.append({"id": id, "node": region})
	_register(id, region)
	region_added.emit(id, Rect2(region.position, region.size))
	regions_changed.emit(_regions.size())
	return id


func remove_region(id: StringName) -> void:
	for i in range(_regions.size() - 1, -1, -1):
		if _regions[i]["id"] != id:
			continue
		if is_instance_valid(_engine):
			_engine.unregister(id)
		if is_instance_valid(_regions[i]["node"]):
			_regions[i]["node"].queue_free()
		_regions.remove_at(i)
		region_removed.emit(id)
		regions_changed.emit(_regions.size())
		return


func clear_regions() -> void:
	for entry in _regions.duplicate():
		remove_region(entry["id"])


func get_region_count() -> int:
	return _regions.size()


func get_region_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for entry in _regions:
		if is_instance_valid(entry["node"]):
			out.append(Rect2(entry["node"].position, entry["node"].size))
	return out


## --- drawing -----------------------------------------------------------

func _on_catcher_gui_input(event: InputEvent) -> void:
	if not _armed:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_drawing = true
			_drag_start = button.position
			_drag_current = button.position
		else:
			_finish_draw()
		_catcher.queue_redraw()
		_catcher.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _drawing:
		_drag_current = motion.position
		_catcher.queue_redraw()
		_catcher.accept_event()


func _finish_draw() -> void:
	if not _drawing:
		return
	_drawing = false
	var rect := _pending_rect()
	if not stay_armed:
		set_armed(false)
	if rect.size.x >= MIN_DRAG.x and rect.size.y >= MIN_DRAG.y:
		add_region(rect)


func _pending_rect() -> Rect2:
	return Rect2(_drag_start, _drag_current - _drag_start).abs()


func _on_catcher_draw() -> void:
	if not _armed:
		return
	# Dim the screen while armed so it is obvious the next drag draws a box.
	_catcher.draw_rect(Rect2(Vector2.ZERO, _catcher.size), SCRIM, true)
	if not _drawing:
		return
	var rect := _pending_rect()
	_catcher.draw_rect(rect, GUIDE_FILL, true)
	_catcher.draw_rect(rect, GUIDE, false, 2.0)


## --- plumbing ----------------------------------------------------------

func _register(id: StringName, region: Control) -> void:
	if not is_instance_valid(_engine):
		return
	# Report the frame's live rect, minus the engine's global margin, so the
	# blur matches what the streamer actually drew.
	var provider := func() -> Rect2:
		if not is_instance_valid(region) or not is_instance_valid(_engine):
			return Rect2()
		var r := region.get_global_rect()
		var m: float = minf(_engine.target_margin, minf(r.size.x, r.size.y) * 0.4)
		return r.grow(-m)
	_engine.register_rect_provider(id, provider, region_params)


func _on_remove_requested(id: StringName) -> void:
	remove_region(id)


func _on_viewport_resized() -> void:
	if is_instance_valid(_surface):
		_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for entry in _regions:
		if is_instance_valid(entry["node"]):
			entry["node"].clamp_into_bounds()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (_armed or _drawing):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_drawing = false
		set_armed(false)
		_catcher.queue_redraw()
		get_viewport().set_input_as_handled()
