class_name PrivacyCopyField
extends Control
## A labelled value with a Copy button. On stream the value is masked by
## PrivacyEngine, but Copy always puts the real, unblurred string on the
## clipboard - so a streamer can share a join code without showing it.
##
## Only the value's sub-rect (get_mask_target()) is registered with the engine,
## so the Copy button and caption are never inside the blurred area.

signal copied(value: String)

const _TOAST_SECONDS := 1.4

@export var caption := "JOIN CODE":
	set(v):
		caption = v
		if is_instance_valid(_caption_label):
			_caption_label.text = v

@export var value := "":
	set(v):
		value = v
		if is_instance_valid(_value_label):
			_value_label.text = v

@export var copy_button_text := "Copy"

var _caption_label: Label
var _value_label: Label
var _mask_target: Control
var _copy_button: Button
var _toast_timer: Timer
var _engine: PrivacyEngine
var _region_id: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 44

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 2)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	_caption_label = Label.new()
	_caption_label.text = caption
	_caption_label.add_theme_font_size_override("font_size", 11)
	_caption_label.add_theme_color_override("font_color", Color("8fa4b0"))
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_caption_label)

	# Only this wrapper is handed to PrivacyEngine.
	_mask_target = Control.new()
	_mask_target.name = "MaskTarget"
	_mask_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_target.custom_minimum_size = Vector2(140, 26)
	_mask_target.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text_col.add_child(_mask_target)

	_value_label = Label.new()
	_value_label.text = value
	_value_label.add_theme_font_size_override("font_size", 20)
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_target.add_child(_value_label)

	_copy_button = Button.new()
	_copy_button.text = copy_button_text
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_copy_button.pressed.connect(copy)
	row.add_child(_copy_button)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = _TOAST_SECONDS
	_toast_timer.timeout.connect(_end_toast)
	add_child(_toast_timer)


## Register this field's value area with the engine so it is masked while the
## Privacy feature is active.
func bind(engine: PrivacyEngine, id: StringName) -> void:
	unbind()
	_engine = engine
	_region_id = id
	if is_instance_valid(_engine):
		_engine.register_node(id, _mask_target)
		_engine.active_changed.connect(_set_concealed)
		_set_concealed(_engine.is_active())


func unbind() -> void:
	if is_instance_valid(_engine) and _engine.active_changed.is_connected(_set_concealed):
		_engine.active_changed.disconnect(_set_concealed)
	_set_concealed(false)
	if is_instance_valid(_engine) and _region_id != &"":
		_engine.unregister(_region_id)
	_engine = null
	_region_id = &""


## Put the real underlying value on the clipboard. Works whether or not the
## value is currently masked, and never reads the rendered/blurred text.
func copy() -> void:
	DisplayServer.clipboard_set(value)
	copied.emit(value)
	if is_instance_valid(_copy_button):
		_copy_button.text = "Copied!"
		_toast_timer.start()


func is_toast_showing() -> bool:
	return is_instance_valid(_toast_timer) and not _toast_timer.is_stopped()


## The sub-rect that PrivacyEngine masks (the value only, not the button).
func get_mask_target() -> Control:
	return _mask_target


func _end_toast() -> void:
	if is_instance_valid(_copy_button):
		_copy_button.text = copy_button_text

## Suppress the source text synchronously: a moving/fading mask must never
## expose the underlying code. The stored value remains available to Copy.
func _set_concealed(concealed: bool) -> void:
	if is_instance_valid(_value_label):
		_value_label.visible = not concealed
