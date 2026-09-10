class_name StreamerChatSettings
extends PanelContainer
## Connection and appearance only; the host owns the master/feature controls.
signal close_requested
var _chat: StreamerChat
var _link: LineEdit
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
	help.text = "Connect Twitch, Kick or YouTube in the relay browser page.\nPaste its private chat link here. Enable chat in Streamer Mode."
	box.add_child(help)
	_link = LineEdit.new()
	_link.placeholder_text = "https://your-relay/overlay#…"
	_link.secret = true
	box.add_child(_link)
	var connect_button := Button.new()
	connect_button.text = "Connect chat"
	connect_button.pressed.connect(func():
		_chat.connect_link(_link.text)
		_link.clear())
	box.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect chat"
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
	hint.text = "Alt + drag to move chat. Text remains fully visible."
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

func open() -> void:
	show()

func close() -> void:
	hide()
	_link.clear()
	get_viewport().gui_release_focus()
	close_requested.emit()

func _on_status(_state: String, detail: String) -> void:
	_status.text = detail
