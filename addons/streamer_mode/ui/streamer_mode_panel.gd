class_name StreamerModePanel
extends PanelContainer
## Optional, standalone settings UI. Bind a game's controller explicitly.
## Availability describes installed components; it never changes game preferences.

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const ORDER: Array[StringName] = [Controller.AUDIO, Controller.PRIVACY, Controller.CHAT]
const CAPTIONS: Dictionary = {
	Controller.AUDIO: "Stream-safe audio",
	Controller.PRIVACY: "Protect sensitive information",
	Controller.CHAT: "In-game chat",
}

@export var accent_color: Color = Color("b4ee93")
var mode_button: Button
var feature_options: Dictionary = {}
var _controller: StreamerModeController
var _available: Dictionary = {}
var _messages: Dictionary = {}
var _details: Dictionary = {}
var _status: Label


func _enter_tree() -> void:
	_connect_controller()
	if is_instance_valid(mode_button):
		call_deferred("_refresh")


func _ready() -> void:
	_build_ui()
	_refresh()


func _exit_tree() -> void:
	_disconnect_controller()


func bind(controller: StreamerModeController) -> void:
	_disconnect_controller()
	_controller = controller
	if is_inside_tree():
		_connect_controller()
	_refresh()


func set_feature_available(feature: StringName, available: bool) -> void:
	if feature not in ORDER:
		push_warning("Unknown Streamer Mode panel feature: %s" % feature)
		return
	_available[feature] = available
	_refresh()


func set_feature_status(feature: StringName, message: String) -> void:
	if feature not in ORDER:
		return
	_messages[feature] = message
	_refresh()


func get_status_text() -> String:
	return _status.text if is_instance_valid(_status) else ""


func _build_ui() -> void:
	custom_minimum_size.x = maxf(custom_minimum_size.x, 320)
	var skin := Theme.new()
	skin.default_font_size = 14
	skin.set_color("font_color", "Label", Color("e6edf0"))
	skin.set_color("font_color", "CheckBox", Color("e6edf0"))
	skin.set_color("font_disabled_color", "CheckBox", Color("8fa4b0"))
	skin.set_constant("h_separation", "CheckBox", 10)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		skin.set_stylebox(state, "CheckBox", _box(Color.TRANSPARENT, 3))
	var focus := _box(Color.TRANSPARENT, 3)
	focus.set_border_width_all(2)
	focus.border_color = accent_color
	skin.set_stylebox("focus", "Button", focus)
	skin.set_stylebox("focus", "CheckBox", focus)
	theme = skin
	var panel_style := _box(Color("14232e"), 18)
	panel_style.border_color = Color("293d49")
	panel_style.set_border_width_all(1)
	add_theme_stylebox_override("panel", panel_style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title := Label.new()
	title.text = "Streamer Mode"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var description := _detail("Same settings for you and your viewers.")
	column.add_child(description)
	mode_button = Button.new()
	mode_button.name = "ModeToggle"
	mode_button.toggle_mode = true
	mode_button.custom_minimum_size.y = 48
	mode_button.toggled.connect(_on_mode_toggled)
	mode_button.add_theme_stylebox_override("normal", _box(accent_color, 10))
	mode_button.add_theme_stylebox_override("hover", _box(accent_color.lightened(0.12), 10))
	mode_button.add_theme_stylebox_override("pressed", _box(Color("7dd8f4"), 10))
	mode_button.add_theme_stylebox_override("hover_pressed", _box(Color("97e5fb"), 10))
	mode_button.add_theme_stylebox_override("disabled", _box(Color("344653"), 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		mode_button.add_theme_color_override(state, Color("12241c"))
	column.add_child(mode_button)
	_status = _detail("")
	column.add_child(_status)
	column.add_child(HSeparator.new())
	for feature in ORDER:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		column.add_child(row)
		var option := CheckBox.new()
		option.name = String(feature).capitalize() + "Option"
		option.text = CAPTIONS[feature]
		option.toggled.connect(_on_feature_toggled.bind(feature))
		row.add_child(option)
		feature_options[feature] = option
		var detail := _detail("")
		row.add_child(detail)
		_details[feature] = detail


func _refresh() -> void:
	if not is_instance_valid(mode_button):
		return
	var connected := is_instance_valid(_controller) and _controller.is_inside_tree()
	var active_count := 0
	var installed_count := 0
	for feature in ORDER:
		var installed := bool(_available.get(feature, false))
		var option: CheckBox = feature_options[feature]
		option.disabled = not connected or not installed
		option.set_pressed_no_signal(connected and installed and _controller.is_feature_selected(feature))
		var detail: Label = _details[feature]
		detail.text = String(_messages.get(feature, "Ready")) if installed else "Not available in this game"
		if installed:
			installed_count += 1
		if connected and installed and _controller.is_feature_active(feature):
			active_count += 1
	mode_button.disabled = not connected or installed_count == 0
	mode_button.set_pressed_no_signal(connected and _controller.enabled)
	mode_button.text = "STREAMER MODE  /  ON" if connected and _controller.enabled else "ENABLE STREAMER MODE"
	if not connected:
		_status.text = "Waiting for game settings"
	elif installed_count == 0:
		_status.text = "No streamer features available"
	elif not _controller.enabled:
		_status.text = "Mode off / normal game settings"
	elif active_count == 0:
		_status.text = "Mode on / no features selected"
	else:
		_status.text = "Mode on / %d feature%s selected" % [active_count, "" if active_count == 1 else "s"]


func _on_mode_toggled(value: bool) -> void:
	if is_instance_valid(_controller) and not mode_button.disabled:
		_controller.set_enabled(value)


func _on_feature_toggled(value: bool, feature: StringName) -> void:
	if is_instance_valid(_controller) and bool(_available.get(feature, false)):
		_controller.set_feature_enabled(feature, value)


func _connect_controller() -> void:
	if not is_instance_valid(_controller):
		return
	if not _controller.state_changed.is_connected(_refresh):
		_controller.state_changed.connect(_refresh)
	if not _controller.tree_exiting.is_connected(_on_controller_exiting):
		_controller.tree_exiting.connect(_on_controller_exiting)


func _disconnect_controller() -> void:
	if not is_instance_valid(_controller):
		return
	if _controller.state_changed.is_connected(_refresh):
		_controller.state_changed.disconnect(_refresh)
	if _controller.tree_exiting.is_connected(_on_controller_exiting):
		_controller.tree_exiting.disconnect(_on_controller_exiting)


func _on_controller_exiting() -> void:
	bind(null)


func _detail(message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("8fa4b0"))
	return label


func _box(color: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
