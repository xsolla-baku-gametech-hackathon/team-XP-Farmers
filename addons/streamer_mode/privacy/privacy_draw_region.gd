class_name PrivacyDrawRegion
extends Control
## One user-placed blur region.
##
## This node is only the interaction frame: drag the body to move it, drag the
## bottom-right handle to resize, press the small x to delete. The blur itself
## is drawn by PrivacyEngine, which reads this node's global rect every frame.
##
## Position and size are always clamped to the parent Surface, so a region can
## never be dragged or resized off screen.

signal remove_requested
signal changed

const MIN_SIZE := Vector2(48.0, 32.0)
const HANDLE_SIZE := 16.0
const ACTIVE := Color(0.70, 0.93, 0.58, 0.95)
const IDLE := Color(0.70, 0.93, 0.58, 0.50)
const WASH := Color(0.70, 0.93, 0.58, 0.06)

## When false the frame draws nothing and stops intercepting the mouse, so a
## finished layout does not show handles on stream or block gameplay clicks.
var show_chrome := true:
	set(value):
		show_chrome = value
		_apply_chrome()

var _handle: ColorRect
var _delete: Button
var _dragging := false
var _resizing := false
var _hovered := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_handle = ColorRect.new()
	_handle.name = "Resize"
	_handle.color = ACTIVE
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_handle.tooltip_text = "Drag to resize"
	_handle.anchor_left = 1.0
	_handle.anchor_top = 1.0
	_handle.anchor_right = 1.0
	_handle.anchor_bottom = 1.0
	_handle.offset_left = -HANDLE_SIZE
	_handle.offset_top = -HANDLE_SIZE
	_handle.offset_right = 0.0
	_handle.offset_bottom = 0.0
	_handle.gui_input.connect(_on_handle_gui_input)
	add_child(_handle)

	_delete = Button.new()
	_delete.name = "Remove"
	_delete.text = "x"
	_delete.focus_mode = Control.FOCUS_NONE
	_delete.tooltip_text = "Remove this blur region"
	_delete.anchor_left = 1.0
	_delete.anchor_right = 1.0
	_delete.offset_left = -26.0
	_delete.offset_right = -2.0
	_delete.offset_top = 2.0
	_delete.offset_bottom = 24.0
	_delete.pressed.connect(func() -> void: remove_requested.emit())
	add_child(_delete)

	_apply_chrome()


func _draw() -> void:
	if not show_chrome:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var line := ACTIVE if (_hovered or _dragging or _resizing) else IDLE
	draw_rect(rect, WASH, true)
	draw_rect(rect, line, false, 2.0)


## --- placement, always clamped on screen --------------------------------

func set_region_rect(rect: Rect2) -> void:
	_set_size(_fit_size(rect.size))
	position = _clamp_position(rect.position)
	queue_redraw()
	changed.emit()


func clamp_into_bounds() -> void:
	_set_size(_fit_size(size))
	position = _clamp_position(position)
	queue_redraw()


## --- drag to move -----------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not show_chrome:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		queue_redraw()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		position = _clamp_position(position + motion.relative)
		changed.emit()
		accept_event()


## --- drag the corner to resize ---------------------------------------

func _on_handle_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_resizing = button.pressed
		queue_redraw()
		_handle.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _resizing:
		var room := (_bounds_size() - position).max(MIN_SIZE)
		var next := size + motion.relative
		next.x = clampf(next.x, MIN_SIZE.x, room.x)
		next.y = clampf(next.y, MIN_SIZE.y, room.y)
		_set_size(next)
		queue_redraw()
		changed.emit()
		_handle.accept_event()


## --- helpers ---------------------------------------------------------

func _apply_chrome() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if show_chrome else Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_handle):
		_handle.visible = show_chrome
	if is_instance_valid(_delete):
		_delete.visible = show_chrome
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size


func _fit_size(desired: Vector2) -> Vector2:
	var bounds := _bounds_size()
	return Vector2(
		clampf(desired.x, MIN_SIZE.x, maxf(MIN_SIZE.x, bounds.x)),
		clampf(desired.y, MIN_SIZE.y, maxf(MIN_SIZE.y, bounds.y)),
	)


func _clamp_position(p: Vector2) -> Vector2:
	var limit := _bounds_size() - size
	return Vector2(
		clampf(p.x, 0.0, maxf(0.0, limit.x)),
		clampf(p.y, 0.0, maxf(0.0, limit.y)),
	)


func _set_size(s: Vector2) -> void:
	custom_minimum_size = s
	size = s
