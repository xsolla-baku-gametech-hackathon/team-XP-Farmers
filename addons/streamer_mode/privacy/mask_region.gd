class_name PrivacyMaskRegion
extends Control
## One draggable, resizable, translucent mask rectangle.
##
## Lives inside PrivacyMaskComponent's full-rect Surface, so this node's
## position is expressed in viewport pixels. Every path that changes position
## or size routes through _clamp_position() or the size clamps below, so the
## rectangle can never leave the visible viewport, however hard it is dragged.

signal changed(rect: Rect2)
signal hide_requested
signal grabbed

const MIN_SIZE := Vector2(64.0, 40.0)
const HANDLE_SIZE := 18.0
const TOOLBAR_GAP := 8.0
const TOOLBAR_MIN_WIDTH := 236.0
const TOOLBAR_MIN_HEIGHT := 34.0
const MIN_OPACITY := 0.05
const MAX_OPACITY := 1.0

@export var base_color := Color(0.0, 0.0, 0.0):
	set(value):
		base_color = value
		_apply_opacity()

@export_range(0.05, 1.0, 0.01) var opacity := 0.55:
	set(value):
		opacity = clampf(value, MIN_OPACITY, MAX_OPACITY)
		_apply_opacity()

@export var show_caption := true:
	set(value):
		show_caption = value
		if is_instance_valid(_caption):
			_caption.visible = value

## True once the mask has been given a real rectangle by the component.
var has_been_placed := false

var _fill: ColorRect
var _caption: Label
var _handle: ColorRect
var _toolbar: PanelContainer
var _opacity_slider: HSlider
var _percent_label: Label
var _dragging := false
var _resizing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_opacity()
	_reflow_toolbar.call_deferred()


func _build() -> void:
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.mouse_filter = Control.MOUSE_FILTER_STOP
	_fill.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_fill.gui_input.connect(_on_fill_gui_input)
	add_child(_fill)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.text = "HIDDEN ON STREAM"
	_caption.visible = show_caption
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.72))
	_fill.add_child(_caption)

	_handle = ColorRect.new()
	_handle.name = "ResizeHandle"
	_handle.color = Color(1.0, 1.0, 1.0, 0.55)
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

	_build_toolbar()


func _build_toolbar() -> void:
	_toolbar = PanelContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14232e")
	style.border_color = Color("293d49")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_toolbar.add_theme_stylebox_override("panel", style)
	add_child(_toolbar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_toolbar.add_child(row)

	var caption := Label.new()
	caption.text = "MASK"
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color("8fa4b0"))
	row.add_child(caption)

	_opacity_slider = HSlider.new()
	_opacity_slider.name = "Opacity"
	_opacity_slider.min_value = MIN_OPACITY
	_opacity_slider.max_value = MAX_OPACITY
	_opacity_slider.step = 0.01
	_opacity_slider.set_value_no_signal(opacity)
	_opacity_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opacity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_opacity_slider.tooltip_text = "Mask opacity"
	_opacity_slider.value_changed.connect(_on_opacity_slider_changed)
	row.add_child(_opacity_slider)

	_percent_label = Label.new()
	_percent_label.custom_minimum_size = Vector2(38.0, 0.0)
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_percent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_percent_label.add_theme_font_size_override("font_size", 11)
	_percent_label.add_theme_color_override("font_color", Color("8fa4b0"))
	row.add_child(_percent_label)

	var close_button := Button.new()
	close_button.text = "Hide"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Hide this mask (Esc)"
	close_button.pressed.connect(func() -> void: hide_requested.emit())
	row.add_child(close_button)


## --- Placement API, all clamped to the parent Surface -----------------------

func set_region_rect(rect: Rect2) -> void:
	_set_size(_fit_size(rect.size))
	position = _clamp_position(rect.position)
	has_been_placed = true
	_reflow_toolbar()
	changed.emit(get_rect())


func center_in_bounds(desired_size: Vector2) -> void:
	var s := _fit_size(desired_size)
	_set_size(s)
	position = ((_bounds_size() - s) * 0.5).max(Vector2.ZERO)
	has_been_placed = true
	_reflow_toolbar()
	changed.emit(get_rect())


func clamp_into_bounds() -> void:
	_set_size(_fit_size(size))
	position = _clamp_position(position)
	_reflow_toolbar()


## --- Drag and resize -------------------------------------------------------

func _on_fill_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			grabbed.emit()
		_fill.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		position = _clamp_position(position + motion.relative)
		_reflow_toolbar()
		changed.emit(get_rect())
		_fill.accept_event()


func _on_handle_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_resizing = button.pressed
		if button.pressed:
			grabbed.emit()
		_handle.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _resizing:
		var room := (_bounds_size() - position).max(MIN_SIZE)
		var next := size + motion.relative
		next.x = clampf(next.x, MIN_SIZE.x, room.x)
		next.y = clampf(next.y, MIN_SIZE.y, room.y)
		_set_size(next)
		_reflow_toolbar()
		changed.emit(get_rect())
		_handle.accept_event()


## --- Helpers -------------------------------------------------------------

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


func _reflow_toolbar() -> void:
	if not is_instance_valid(_toolbar):
		return
	var width := maxf(size.x, TOOLBAR_MIN_WIDTH)
	var height := maxf(_toolbar.get_combined_minimum_size().y, TOOLBAR_MIN_HEIGHT)
	_toolbar.size = Vector2(width, height)
	var above := -(height + TOOLBAR_GAP)
	if position.y + above < 0.0:
		_toolbar.position.y = size.y + TOOLBAR_GAP
	else:
		_toolbar.position.y = above
	var overflow := (position.x + width) - _bounds_size().x
	_toolbar.position.x = -maxf(0.0, overflow)


func _apply_opacity() -> void:
	if is_instance_valid(_fill):
		_fill.color = Color(base_color.r, base_color.g, base_color.b, opacity)
	if is_instance_valid(_opacity_slider):
		_opacity_slider.set_value_no_signal(opacity)
	if is_instance_valid(_percent_label):
		_percent_label.text = "%d%%" % roundi(opacity * 100.0)


func _on_opacity_slider_changed(value: float) -> void:
	opacity = value
