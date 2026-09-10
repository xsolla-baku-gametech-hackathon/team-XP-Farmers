class_name StreamerChatOverlay
extends Control
## Transparent message-only overlay. Put under a CanvasLayer, outside containers.
## Hold Alt and drag the message area to move it; ordinary input passes through.

@export_range(1, 100) var max_messages: int = 30
@export var panel_size := Vector2(400, 260)
var messages: Array[String] = []
var _controller: StreamerModeController
var _client: Node
var _label: RichTextLabel
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = panel_size
	_label = RichTextLabel.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if is_instance_valid(_client) and _client.message_received.is_connected(append_message):
		_client.message_received.disconnect(append_message)
	_client = client
	clear_messages()
	if is_instance_valid(_client):
		_client.message_received.connect(append_message)


func append_message(_author: String, message: String) -> void:
	# Plain text deliberately prevents chat content from becoming BBCode.
	messages.append(message.left(2000))
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
	# Keep the newest lines visible without a scrollbar or background.
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


func _exit_tree() -> void:
	bind_client(null)
	bind_controller(null)
