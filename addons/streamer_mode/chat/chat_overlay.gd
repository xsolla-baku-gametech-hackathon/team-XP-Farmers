class_name StreamerChatOverlay
extends Control
## Chat with usernames and an adjustable black background.
## Scroll to read history, drag the body to move, drag either corner to resize.

@export_range(1, 100) var max_messages: int = 30
@export var panel_size := Vector2(360, 220)
@export_range(0.0, 1.0, 0.01) var background_opacity: float = 0.35:
	set(value):
		background_opacity = clampf(value, 0.0, 1.0)
		if is_instance_valid(_background):
			_background.color = Color(0, 0, 0, background_opacity)
var display_enabled := false:
	set(value):
		display_enabled = value
		_sync()
var desktop_window: Window
var messages: Array[String] = []
var _background: ColorRect
var _controller: StreamerModeController
var _client: Node
var _label: RichTextLabel
var _desktop_start_mouse := Vector2i.ZERO
var _desktop_start_position := Vector2i.ZERO
var _desktop_start_size := Vector2i.ZERO
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_handle: Label
var _top_left_handle: Label
var _resize_from_top_left := false
var _resize_position := Vector2.ZERO
var _resize_handle: Label
var _resizing := false
var _resize_start := Vector2.ZERO
var _resize_size := Vector2.ZERO
var _render_queued := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = panel_size
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.color = Color(0, 0, 0, background_opacity)
	add_child(_background)
	_label = RichTextLabel.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 12
	_label.offset_top = 34
	_label.offset_right = -12
	_label.offset_bottom = -24
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.bbcode_enabled = false
	_label.scroll_active = true
	_label.focus_mode = Control.FOCUS_NONE
	_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.gui_input.connect(_on_drag_input)
	add_child(_label)
	var bar := _label.get_v_scroll_bar()
	bar.custom_minimum_size.x = 12
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.15, 0.2, 0.23, 0.7)
	bar.add_theme_stylebox_override("scroll", track)
	for state in ["slider", "slider_highlight", "slider_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("b4ee93")
		thumb.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(state, thumb)
	_drag_handle = Label.new()
	_drag_handle.text = "Live chat · Drag to move"
	_drag_handle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_drag_handle.offset_left = 28
	_drag_handle.offset_top = 2
	_drag_handle.offset_right = -8
	_drag_handle.offset_bottom = 30
	_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_drag_handle.add_theme_font_size_override("font_size", 13)
	_drag_handle.add_theme_color_override("font_color", Color("b4ee93"))
	_drag_handle.gui_input.connect(_on_drag_input)
	add_child(_drag_handle)
	_top_left_handle = Label.new()
	_top_left_handle.text = "◤"
	_top_left_handle.size = Vector2(24, 24)
	_top_left_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_top_left_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_top_left_handle.tooltip_text = "Drag to resize chat"
	_top_left_handle.add_theme_color_override("font_color", Color("b4ee93"))
	_top_left_handle.gui_input.connect(_on_resize_input.bind(true))
	add_child(_top_left_handle)
	_resize_handle = Label.new()
	_resize_handle.text = "◢"
	_resize_handle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_resize_handle.offset_left = -24
	_resize_handle.offset_top = -24
	_resize_handle.offset_right = -2
	_resize_handle.offset_bottom = -2
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.tooltip_text = "Drag to resize chat"
	_resize_handle.add_theme_color_override("font_color", Color("b4ee93"))
	_resize_handle.gui_input.connect(_on_resize_input)
	add_child(_resize_handle)
	get_viewport().size_changed.connect(_clamp_position)
	reset_position()
	_sync()
	_render()


func bind_controller(controller: StreamerModeController) -> void:
	if is_instance_valid(_controller) and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	_controller = controller
	if is_instance_valid(_controller):
		_controller.state_changed.connect(_sync)
	_sync()


func bind_client(client: Node) -> void:
	if is_instance_valid(_client) and _client.snapshot_received.is_connected(replace_messages):
		_client.snapshot_received.disconnect(replace_messages)
	_client = client
	clear_messages()
	if is_instance_valid(_client):
		_client.snapshot_received.connect(replace_messages)


func replace_messages(rows: Array) -> void:
	var next: Array[String] = []
	for row in rows.slice(-maxi(1, max_messages)):
		next.append(_message_line(str(row.get("author", "Unknown user")), str(row.get("text", ""))))
	if next == messages:
		return
	messages = next
	_render()


func _message_line(author: String, message: String) -> String:
	# Chat content is plain text, never BBCode.
	var username := author.replace("\n", " ").replace("\r", " ").strip_edges().left(100)
	if username.is_empty(): username = "Unknown user"
	return username + ": " + message.left(2000)


func append_message(author: String, message: String) -> void:
	messages.append(_message_line(author, message))
	while messages.size() > maxi(1, max_messages):
		messages.pop_front()
	_render()


func clear_messages() -> void:
	messages.clear()
	_render()


func _render() -> void:
	if not is_instance_valid(_label) or _render_queued: return
	_render_queued = true
	_flush_render.call_deferred()


func _flush_render() -> void:
	_render_queued = false
	if not is_instance_valid(_label): return
	var text := "\n".join(messages)
	if _label.text == text: return
	var bar := _label.get_v_scroll_bar()
	var old_value := bar.value
	var at_bottom := bar.value >= bar.max_value - bar.page - 2.0
	_label.text = text
	_restore_scroll.call_deferred(at_bottom, old_value)


func _restore_scroll(follow: bool, old_value: float) -> void:
	if not is_instance_valid(_label): return
	var bar := _label.get_v_scroll_bar()
	bar.value = bar.max_value if follow else old_value


func set_panel_size(value: Vector2) -> void:
	if is_instance_valid(desktop_window):
		var ui_scale := desktop_window.content_scale_factor
		panel_size = value.max(Vector2(240, 140)).min(Vector2(_screen_rect().size - Vector2i(40, 40)) / ui_scale)
		desktop_window.size = Vector2i(panel_size * ui_scale)
	else:
		panel_size = value.max(Vector2(240, 140)).min(get_viewport_rect().size)
	_clamp_position()


func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_resizing = false
		_dragging = true
		if is_instance_valid(desktop_window):
			_begin_desktop_pointer()
		else:
			_drag_offset = get_global_mouse_position() - global_position
		_drag_handle.accept_event()


func _scroll_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventPanGesture):
		return false
	if not _label.get_global_rect().has_point(event.position):
		return false
	var amount := 0.0
	if event is InputEventPanGesture:
		amount = event.delta.y * 32.0
	elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		amount = (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * event.factor * 48.0
	else:
		return false
	var bar := _label.get_v_scroll_bar()
	bar.value = clampf(bar.value + amount, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	get_viewport().set_input_as_handled()
	return true


func _on_resize_input(event: InputEvent, from_top_left := false) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_resize_from_top_left = from_top_left
		if is_instance_valid(desktop_window):
			_resizing = true
			_dragging = false
			_begin_desktop_pointer()
			_resize_handle.accept_event()
			return
		_resize_position = position
		_resizing = true
		_dragging = false
		_resize_start = get_global_mouse_position()
		_resize_size = size
		_resize_handle.accept_event()


func _begin_desktop_pointer() -> void:
	_desktop_start_mouse = DisplayServer.mouse_get_position()
	_desktop_start_position = desktop_window.position
	_desktop_start_size = desktop_window.size


func _process(_delta: float) -> void:
	if is_instance_valid(desktop_window) and (_dragging or _resizing):
		_update_desktop_pointer(DisplayServer.mouse_get_position(),
			(DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) != 0)


func _update_desktop_pointer(pointer: Vector2i, held: bool) -> void:
	if not held or not desktop_window.visible:
		_dragging = false
		_resizing = false
		return
	var delta := pointer - _desktop_start_mouse
	if _dragging:
		desktop_window.position = _desktop_start_position + delta
	elif _resizing:
		var requested := _desktop_start_size - delta if _resize_from_top_left else _desktop_start_size + delta
		var limit := _screen_rect().size - Vector2i(40, 40)
		desktop_window.size = requested.clamp(desktop_window.min_size, limit)
		if _resize_from_top_left:
			desktop_window.position = _desktop_start_position + _desktop_start_size - desktop_window.size
		_clamp_position()


func _screen_rect() -> Rect2i:
	var area := DisplayServer.screen_get_usable_rect(desktop_window.current_screen)
	if area.size.x <= 0 or area.size.y <= 0:
		area = Rect2i(Vector2i.ZERO, Vector2i(1280, 800))
	return area


func reset_position() -> void:
	if is_instance_valid(desktop_window):
		var area := _screen_rect()
		desktop_window.max_size = area.size - Vector2i(40, 40)
		desktop_window.position = area.end - desktop_window.size - Vector2i(20, 20)
		_clamp_position()
		return
	position = get_viewport_rect().size - size - Vector2(20, 20)
	_clamp_position()


func _clamp_position() -> void:
	if is_instance_valid(desktop_window):
		position = Vector2.ZERO
		size = desktop_window.get_visible_rect().size
		panel_size = size
		return
	size = panel_size.max(Vector2(240, 140)).min(get_viewport_rect().size)
	position = position.clamp(Vector2.ZERO, (get_viewport_rect().size - size).max(Vector2.ZERO))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_dragging = false
		_resizing = false
		return
	if is_instance_valid(desktop_window) and (_dragging or _resizing):
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			get_viewport().set_input_as_handled()
			return
	if _scroll_input(event):
		return
	if _resizing:
		if event is InputEventMouseMotion:
			var delta := get_global_mouse_position() - _resize_start
			if _resize_from_top_left:
				var opposite := _resize_position + _resize_size
				position = (_resize_position + delta).clamp(Vector2.ZERO, opposite - Vector2(240, 140))
				set_panel_size(opposite - position)
			else:
				set_panel_size((_resize_size + delta).min(get_viewport_rect().size - position))
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_resizing = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _dragging:
			_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			return
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_position()
		get_viewport().set_input_as_handled()


func _sync() -> void:
	visible = display_enabled and is_instance_valid(_controller) and _controller.is_feature_active(StreamerModeController.CHAT)
	if is_instance_valid(desktop_window):
		desktop_window.visible = visible
	if not visible:
		_dragging = false
		_resizing = false
	if not is_instance_valid(_controller):
		clear_messages()


func _exit_tree() -> void:
	bind_client(null)
	bind_controller(null)
