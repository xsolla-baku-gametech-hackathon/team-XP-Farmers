class_name StreamerChatSettings
extends PanelContainer
## Connection and appearance only; the host owns the master/feature controls.
signal close_requested
var _chat: StreamerChat
var _connect: Button
var _disconnect: Button
var _provider: OptionButton
var _enable: Button
var _channel: Label
var _status: Label
var _opacity: HSlider

func _ready() -> void:
	custom_minimum_size = Vector2(500, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182630")
	style.set_content_margin_all(20)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "CHAT SETTINGS"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var help := Label.new()
	help.text = "Choose your platform and approve access in your browser."
	box.add_child(help)
	_provider = OptionButton.new()
	for provider in ["Kick", "Twitch", "YouTube"]:
		_provider.add_item(provider)
	box.add_child(_provider)
	_connect = Button.new()
	_connect.text = "Connect channel"
	_connect.pressed.connect(func():
		_chat.connect_channel(["kick", "twitch", "youtube"][_provider.selected]))
	box.add_child(_connect)
	_channel = Label.new()
	_channel.text = "No channel connected"
	box.add_child(_channel)
	_enable = Button.new()
	_enable.text = "Enable chat"
	_enable.disabled = true
	_enable.pressed.connect(func(): _chat.enable_chat())
	box.add_child(_enable)
	_disconnect = Button.new()
	_disconnect.text = "Disconnect channel"
	_disconnect.pressed.connect(func():
		if is_instance_valid(_chat): _chat.disconnect_chat())
	box.add_child(_disconnect)
	_status = Label.new()
	_status.text = "No channel connected"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var opacity_label := Label.new()
	opacity_label.text = "Chat background opacity · 35%"
	box.add_child(opacity_label)
	_opacity = HSlider.new()
	_opacity.min_value = 0
	_opacity.max_value = 1
	_opacity.step = 0.01
	_opacity.value = 0.35
	_opacity.value_changed.connect(func(value: float):
		_chat.overlay.background_opacity = value
		opacity_label.text = "Chat background opacity · %d%%" % roundi(value * 100))
	box.add_child(_opacity)
	var hint := Label.new()
	hint.text = "Hold and drag the chat to move · Scroll to read history\nDrag the top-left or bottom-right corner to resize"
	box.add_child(hint)
	var close_button := Button.new()
	close_button.text = "Back to game"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	hide()


func setup(chat: StreamerChat) -> void:
	if is_instance_valid(_chat) and _chat.status_changed.is_connected(_on_status):
		_chat.status_changed.disconnect(_on_status)
	_chat = chat
	if is_instance_valid(_chat):
		_chat.status_changed.connect(_on_status)
		_status.text = _chat.get_status()
		_opacity.value = _chat.overlay.background_opacity
		refresh_controls()

func open() -> void:
	refresh_controls()
	show()

func close() -> void:
	hide()
	get_viewport().gui_release_focus()
	close_requested.emit()

func _on_status(_state: String, detail: String) -> void:
	_status.text = detail
	refresh_controls()

func refresh_controls() -> void:
	if not is_instance_valid(_chat) or not is_instance_valid(_connect):
		return
	var mode_on := _chat.is_mode_enabled()
	var connected := _chat.connection.connected
	_provider.disabled = not mode_on
	_connect.disabled = not mode_on
	_disconnect.disabled = not mode_on or not connected
	var active := _chat.is_chat_active()
	_enable.disabled = not mode_on or not connected or active
	_enable.text = "Chat enabled" if active else "Enable chat"
	_channel.text = "Channel: " + _chat.connection.channel if connected else "No channel connected"
	if not mode_on:
		_status.text = "Turn on Streamer Mode to connect your channel."
	else:
		_status.text = _chat.get_status()
