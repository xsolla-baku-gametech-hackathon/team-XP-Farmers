class_name PrivacyControlPanel
extends PanelContainer
## Dev / streamer-facing panel for a PrivacyEngine. Drop it anywhere in the
## host UI and call setup(engine). It reads and drives only the engine's public
## API. It excludes itself from scanning and masking, and being a PanelContainer
## it only blocks input inside its own rect - the game and the masks stay usable.

## Emitted when the streamer closes the panel from its own X button, so the
## host can un-toggle whatever button opened it.
signal close_requested

const _MUTED := Color("8fa4b0")
const _INK := Color("e6edf0")

var _engine: PrivacyEngine
var _close_button: Button
var _region_rows: Dictionary = {}   # StringName -> HBoxContainer

var _regions_box: VBoxContainer
var _regions_empty: Label
var _scan_toggle: CheckButton
var _interval_slider: HSlider
var _interval_value: Label
var _param_sliders: Dictionary = {}   # key -> { slider, value_label }
var _packs_box: VBoxContainer
var _pack_boxes: Dictionary = {}      # pack -> CheckBox
var _allow_input: LineEdit
var _allow_box: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(288, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())

	# Scrolls so every section stays reachable when the host gives the panel
	# less height than its content needs.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page.add_child(header)
	var title := _heading("PRIVACY CONTROL")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "X"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "Close this panel"
	_close_button.custom_minimum_size = Vector2(30.0, 26.0)
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	_scan_toggle = CheckButton.new()
	_scan_toggle.text = "Automatic scanning"
	_scan_toggle.focus_mode = Control.FOCUS_NONE
	_scan_toggle.toggled.connect(_on_scan_toggled)
	page.add_child(_scan_toggle)

	var interval_row := _slider_row("Scan interval", 0.05, 2.0, 0.05)
	_interval_slider = interval_row[1]
	_interval_value = interval_row[2]
	_interval_slider.value_changed.connect(_on_interval_changed)
	page.add_child(interval_row[0])

	page.add_child(_heading("PATTERN PACKS"))
	_packs_box = VBoxContainer.new()
	_packs_box.add_theme_constant_override("separation", 2)
	page.add_child(_packs_box)

	page.add_child(_heading("BLUR"))
	for spec in [
		["pixel_size", "Pixel size", 2.0, 48.0, 1.0],
		["blur_spread", "Blur spread", 0.0, 4.0, 0.1],
		["tint_amount", "Tint", 0.0, 1.0, 0.05],
	]:
		var row := _slider_row(spec[1], spec[2], spec[3], spec[4])
		row[1].value_changed.connect(_on_param_changed.bind(spec[0]))
		_param_sliders[spec[0]] = {"slider": row[1], "value_label": row[2]}
		page.add_child(row[0])

	page.add_child(_heading("ACTIVE MASKS"))
	_regions_box = VBoxContainer.new()
	_regions_box.add_theme_constant_override("separation", 4)
	page.add_child(_regions_box)
	_regions_empty = _text("Nothing masked", 12, _MUTED)
	_regions_box.add_child(_regions_empty)

	page.add_child(_heading("ALLOW LIST"))
	var allow_entry := HBoxContainer.new()
	allow_entry.add_theme_constant_override("separation", 6)
	page.add_child(allow_entry)
	_allow_input = LineEdit.new()
	_allow_input.placeholder_text = "Exact text to never mask"
	_allow_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_allow_input.text_submitted.connect(func(_t): _on_allow_add())
	allow_entry.add_child(_allow_input)
	var add_button := Button.new()
	add_button.text = "Add"
	add_button.focus_mode = Control.FOCUS_NONE
	add_button.pressed.connect(_on_allow_add)
	allow_entry.add_child(add_button)
	_allow_box = VBoxContainer.new()
	_allow_box.add_theme_constant_override("separation", 4)
	page.add_child(_allow_box)


func setup(engine: PrivacyEngine) -> void:
	if _engine == engine:
		return
	_disconnect_engine()
	_engine = engine
	if not is_instance_valid(_engine):
		return
	_engine.exclude_subtree(self)
	_engine.region_masked.connect(_on_region_masked)
	_engine.region_cleared.connect(_on_region_cleared)
	_pull_state()


## Hide the panel and tell the host, so its toggle button can follow.
func close() -> void:
	hide()
	close_requested.emit()


## Show the panel and re-sync its controls with the engine.
func open() -> void:
	if is_instance_valid(_engine):
		_pull_state()
	show()


func _exit_tree() -> void:
	_disconnect_engine()


func _disconnect_engine() -> void:
	if not is_instance_valid(_engine):
		return
	if _engine.region_masked.is_connected(_on_region_masked):
		_engine.region_masked.disconnect(_on_region_masked)
	if _engine.region_cleared.is_connected(_on_region_cleared):
		_engine.region_cleared.disconnect(_on_region_cleared)


## Mirror the engine's current settings onto the controls.
func _pull_state() -> void:
	var stats := _engine.get_scan_stats()
	_scan_toggle.set_pressed_no_signal(stats.get("scanning", false))
	_rebuild_packs()
	_interval_slider.set_value_no_signal(_engine.scan_interval)
	_interval_value.text = "%.2fs" % _engine.scan_interval
	for key in _param_sliders:
		var s = _param_sliders[key]
		var v: float = float(_engine.mask_params.get(key, s["slider"].value))
		s["slider"].set_value_no_signal(v)
		s["value_label"].text = _fmt(v)
	_rebuild_allow_list()


func _rebuild_packs() -> void:
	for child in _packs_box.get_children():
		child.queue_free()
	_pack_boxes.clear()
	for pack in _engine.get_packs():
		var box := CheckBox.new()
		box.text = String(pack)
		box.focus_mode = Control.FOCUS_NONE
		box.add_theme_font_size_override("font_size", 12)
		box.set_pressed_no_signal(_engine.is_pack_enabled(pack))
		box.toggled.connect(_on_pack_toggled.bind(pack))
		_packs_box.add_child(box)
		_pack_boxes[pack] = box


func _on_pack_toggled(pressed: bool, pack: StringName) -> void:
	if is_instance_valid(_engine):
		_engine.set_pack_enabled(pack, pressed)


func _on_scan_toggled(pressed: bool) -> void:
	if is_instance_valid(_engine):
		_engine.set_scanning(pressed)


func _on_interval_changed(v: float) -> void:
	_interval_value.text = "%.2fs" % v
	if is_instance_valid(_engine):
		_engine.scan_interval = v


func _on_param_changed(v: float, key: String) -> void:
	_param_sliders[key]["value_label"].text = _fmt(v)
	if is_instance_valid(_engine):
		_engine.set_mask_param(key, v)


func _on_allow_add() -> void:
	var text := _allow_input.text.strip_edges()
	if text.is_empty() or not is_instance_valid(_engine):
		return
	_engine.allow_text(text)
	_allow_input.clear()
	_rebuild_allow_list()


func _on_allow_remove(text: String) -> void:
	if is_instance_valid(_engine):
		_engine.remove_allowed_text(text)
	_rebuild_allow_list()


func _rebuild_allow_list() -> void:
	for child in _allow_box.get_children():
		child.queue_free()
	var entries := _engine.get_allowed_texts()
	if entries.is_empty():
		_allow_box.add_child(_text("Empty", 12, _MUTED))
		return
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := _text(entry, 12, _INK)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove := Button.new()
		remove.text = "x"
		remove.focus_mode = Control.FOCUS_NONE
		remove.pressed.connect(_on_allow_remove.bind(entry))
		row.add_child(remove)
		_allow_box.add_child(row)


func _on_region_masked(id: StringName, _rect: Rect2) -> void:
	if _region_rows.has(id):
		return
	_regions_empty.hide()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var tag := _text(_kind_tag(id), 11, _MUTED)
	tag.custom_minimum_size.x = 48
	row.add_child(tag)
	row.add_child(_text(_short_id(id), 12, _INK))
	_regions_box.add_child(row)
	_region_rows[id] = row


func _on_region_cleared(id: StringName) -> void:
	if _region_rows.has(id):
		_region_rows[id].queue_free()
		_region_rows.erase(id)
	if _region_rows.is_empty():
		_regions_empty.show()


## --- small builders ------------------------------------------------------

func _slider_row(title: String, min_v: float, max_v: float, step: float) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var name_label := _text(title, 12, _MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := _text("", 12, _MUTED)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(value_label)
	box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	box.add_child(slider)
	return [box, slider, value_label]


func _heading(text: String) -> Label:
	return _text(text, 11, Color("b4ee93"))


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _fmt(v: float) -> String:
	return "%.0f" % v if v >= 10.0 else "%.2f" % v


func _short_id(id: StringName) -> String:
	var s := String(id)
	return s.get_slice(":", 1) if s.contains(":") else s


func _kind_tag(id: StringName) -> String:
	var s := String(id)
	if s.begins_with("scan:"):
		return "scan"
	if s.begins_with("group:"):
		return "group"
	return "region"


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111d26")
	style.border_color = Color("293d49")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	return style
