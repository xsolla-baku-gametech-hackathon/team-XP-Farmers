class_name StreamerChatOverlay
extends Control
## In-game chat with usernames and an adjustable black background.
## Hold Alt and drag the message area to move it; ordinary input passes through.

@export_range(1, 100) var max_messages: int = 30
@export var panel_size := Vector2(400, 260)
@export_range(0.0, 1.0, 0.01) var background_opacity: float = 0.35:
	set(value):
		background_opacity = clampf(value, 0.0, 1.0)
		if is_instance_valid(_background):
			_background.color = Color(0, 0, 0, background_opacity)
var messages: Array[String] = []
var _background: ColorRect
var _controller: StreamerModeController
var _client: Node
var _label: RichTextLabel
var _dragging := false
var _drag_offset := Vector2.ZERO


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
	_label.offset_top = 12
	_label.offset_right = -12
	_label.offset_bottom = -12
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.bbcode_enabled = false
	_label.scroll_active = false
	_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
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
	clear_messages()
	for row in rows:
		append_message(str(row.get("author", "Unknown user")), str(row.get("text", "")))


func append_message(author: String, message: String) -> void:
	# Plain text deliberately prevents chat content from becoming BBCode.
	var username := author.replace("\n", " ").replace("\r", " ").strip_edges().left(100)
	if username.is_empty():
		username = "Unknown user"
	messages.append(username + ": " + message.left(2000))
	while messages.size() > maxi(1, max_messages):
		messages.pop_front()
	_render()


func clear_messages() -> void:
	messages.clear()
	_render()


func _render() -> void:
	if not is_instance_valid(_label):
		return
	_label.text = "\n".join(messages)
	# Keep the newest lines visible without a scrollbar.
	_scroll_latest.call_deferred()


func _scroll_latest() -> void:
	if is_instance_valid(_label):
		_label.scroll_to_line(maxi(0, _label.get_line_count() - 1))


func reset_position() -> void:
	position = get_viewport_rect().size - size - Vector2(20, 20)
	_clamp_position()


func _clamp_position() -> void:
	size = panel_size.min(get_viewport_rect().size)
	position = position.clamp(Vector2.ZERO, (get_viewport_rect().size - size).max(Vector2.ZERO))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_dragging = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.alt_pressed and get_global_rect().has_point(get_global_mouse_position()):
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			get_viewport().set_input_as_handled()
		elif not event.pressed and _dragging:
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
	visible = is_instance_valid(_controller) and _controller.is_feature_active(StreamerModeController.CHAT)
	if not visible:
		_dragging = false
		clear_messages()


func _exit_tree() -> void:
	bind_client(null)
	bind_controller(null)
