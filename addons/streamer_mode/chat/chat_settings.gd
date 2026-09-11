class_name StreamerChatSettings
extends PanelContainer
## Connection and appearance only; the host owns the master/feature controls.
signal close_requested
var _chat: StreamerChat
var _provider: OptionButton
var _enable: Button
var _channel: Label
var _status: Label
var _opacity: HSlider
var _relay_address: LineEdit

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
	var address_label := Label.new()
	address_label.text = "Chat service URL"
	box.add_child(address_label)
	_relay_address = LineEdit.new()
	_relay_address.placeholder_text = "https://your-chat-service.example"
	box.add_child(_relay_address)
	var address_hint := Label.new()
	address_hint.text = "HTTPS or localhost; not your Kick stream URL.\nKept for this game session. Sign in through your browser."
	address_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(address_hint)
	_provider = OptionButton.new()
	for provider in ["Kick", "Twitch", "YouTube"]:
		_provider.add_item(provider)
	box.add_child(_provider)
	var connect_button := Button.new()
	connect_button.text = "Connect channel"
	connect_button.pressed.connect(_connect_selected)
	box.add_child(connect_button)
	_channel = Label.new()
	_channel.text = "No channel connected"
	box.add_child(_channel)
	_enable = Button.new()
	_enable.text = "Enable chat"
	_enable.disabled = true
	_enable.pressed.connect(func(): _chat.enable_chat())
	box.add_child(_enable)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect channel"
	disconnect_button.pressed.connect(func():
		if is_instance_valid(_chat): _chat.disconnect_chat())
	box.add_child(disconnect_button)
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
	var move_key := "Option" if OS.has_feature("macos") else "Alt"
	hint.text = "Scroll to read history · %s + drag to move\nDrag the bottom-right corner to resize" % move_key
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
		_relay_address.text = _chat.connection.relay_url
		_opacity.value = _chat.overlay.background_opacity

func open() -> void:
	show()

func close() -> void:
	hide()
	get_viewport().gui_release_focus()
	close_requested.emit()

func _on_status(_state: String, detail: String) -> void:
	_status.text = detail
	if is_instance_valid(_chat):
		_enable.disabled = not _chat.connection.connected
		_channel.text = "Channel: " + _chat.connection.channel if _chat.connection.connected else "No channel connected"

func set_relay_address(address: String) -> bool:
	var origin := address.strip_edges().trim_suffix("/")
	var pattern := RegEx.new()
	pattern.compile("^(https://[A-Za-z0-9.-]+(:[0-9]+)?|http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?)$")
	if pattern.search(origin) == null:
		_status.text = "Enter an HTTPS chat service URL or local HTTP address, not an RTMP stream URL."
		return false
	if not is_instance_valid(_chat):
		return false
	_chat.connection.relay_url = origin
	_relay_address.text = origin
	return true

func _connect_selected() -> void:
	if set_relay_address(_relay_address.text):
		_chat.connect_channel(["kick", "twitch", "youtube"][_provider.selected])
