class_name StreamerChat
extends CanvasLayer
## Drop into a game and bind its existing StreamerModeController.
const Client = preload("res://addons/streamer_mode/chat/chat_client.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
signal status_changed(state: String, detail: String)
var client: StreamerChatClient
var overlay: StreamerChatOverlay
var settings: PanelContainer
var _controller: StreamerModeController
var _link: LineEdit
var _status: Label
var _mode: CheckButton
var _chat: CheckButton

func _ready() -> void:
	layer = 20
	client = Client.new()
	add_child(client)
	overlay = Overlay.new()
	add_child(overlay)
	overlay.bind_client(client)
	overlay.bind_controller(_controller)
	_build_settings()
	client.status_changed.connect(func(state: String, detail: String):
		_status.text = detail
		status_changed.emit(state, detail))
	_sync()

func bind_controller(controller: StreamerModeController) -> void:
	if is_instance_valid(_controller) and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	_controller = controller
	if is_instance_valid(controller):
		controller.state_changed.connect(_sync)
	if is_instance_valid(overlay):
		overlay.bind_controller(controller)
	_sync()

func _sync() -> void:
	if not is_instance_valid(client):
		return
	var bound := is_instance_valid(_controller)
	client.set_active(bound and _controller.is_feature_active(StreamerModeController.CHAT))
	_mode.disabled = not bound
	_chat.disabled = not bound
	_mode.set_pressed_no_signal(bound and _controller.enabled)
	_chat.set_pressed_no_signal(bound and _controller.is_feature_selected(StreamerModeController.CHAT))

func open_settings() -> void:
	settings.show()

func close_settings() -> void:
	settings.hide()
	get_viewport().gui_release_focus()

func connect_link(link: String) -> bool:
	return client.connect_link(link)

func _build_settings() -> void:
	settings = PanelContainer.new()
	settings.position = Vector2(24, 68)
	settings.custom_minimum_size = Vector2(500, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182630")
	style.set_content_margin_all(20)
	style.set_corner_radius_all(12)
	settings.add_theme_stylebox_override("panel", style)
	add_child(settings)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	settings.add_child(box)
	var title := Label.new()
	title.text = "Settings → Streamer Mode"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_mode = CheckButton.new()
	_mode.text = "Streamer Mode"
	_mode.toggled.connect(func(value: bool):
		if is_instance_valid(_controller): _controller.set_enabled(value))
	box.add_child(_mode)
	_chat = CheckButton.new()
	_chat.text = "In-game chat · Twitch / Kick / YouTube"
	_chat.toggled.connect(func(value: bool):
		if is_instance_valid(_controller): _controller.set_feature_enabled(StreamerModeController.CHAT, value))
	box.add_child(_chat)
	var help := Label.new()
	help.text = "Connect your channel in the relay's browser page.\nPaste its private chat link here. The link is kept in memory only."
	box.add_child(help)
	_link = LineEdit.new()
	_link.placeholder_text = "https://your-relay/overlay#…"
	_link.secret = true
	box.add_child(_link)
	var connect_button := Button.new()
	connect_button.text = "Connect chat"
	connect_button.pressed.connect(func():
		connect_link(_link.text)
		_link.clear())
	box.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect chat"
	disconnect_button.pressed.connect(client.disconnect_chat)
	box.add_child(disconnect_button)
	_status = Label.new()
	_status.text = "No channel connected"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var opacity_label := Label.new()
	opacity_label.text = "Chat background opacity · 35%"
	box.add_child(opacity_label)
	var opacity := HSlider.new()
	opacity.min_value = 0
	opacity.max_value = 1
	opacity.step = 0.01
	opacity.value = 0.35
	opacity.value_changed.connect(func(value: float):
		overlay.background_opacity = value
		opacity_label.text = "Chat background opacity · %d%%" % roundi(value * 100))
	box.add_child(opacity)
	var hint := Label.new()
	hint.text = "Alt + drag to move chat. Text remains fully visible."
	box.add_child(hint)
	var close_button := Button.new()
	close_button.text = "Back to game"
	close_button.pressed.connect(close_settings)
	box.add_child(close_button)
	settings.hide()
