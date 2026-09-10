class_name StreamerKickChat
extends CanvasLayer
## Drop-in Godot component. Bind the shared controller and call open_settings().
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Client = preload("res://addons/streamer_mode/chat/kick_relay_client.gd")

@export var relay_url: String = ""
@export_range(0.0, 1.0, 0.01) var initial_background_opacity: float = 0.35
var overlay: StreamerChatOverlay
var client: KickRelayClient
var opacity_slider: HSlider
var _controller: StreamerModeController
var _settings: PanelContainer
var _address: LineEdit
var _status: Label
var _opacity_value: Label

func _ready() -> void:
	layer = 20
	client = Client.new()
	add_child(client)
	overlay = Overlay.new()
	overlay.background_opacity = initial_background_opacity
	add_child(overlay)
	overlay.bind_client(client)
	overlay.bind_controller(_controller)
	_build_settings()
	client.status_changed.connect(_on_status)

func bind_controller(controller: StreamerModeController) -> void:
	_controller = controller
	if is_instance_valid(overlay):
		overlay.bind_controller(controller)

func open_settings() -> void:
	_settings.show()
	_address.grab_focus()

func close_settings() -> void:
	_settings.hide()
	get_viewport().gui_release_focus()

func connect_account(address: String = relay_url) -> void:
	relay_url = address.strip_edges()
	_address.text = relay_url
	overlay.clear_messages()
	client.connect_account(relay_url)

func disconnect_chat() -> void:
	client.disconnect_chat()
	overlay.clear_messages()

func set_background_opacity(value: float) -> void:
	overlay.background_opacity = value
	opacity_slider.set_value_no_signal(overlay.background_opacity)
	_opacity_value.text = "%d%%" % roundi(overlay.background_opacity * 100.0)

func _on_status(_state: String, detail: String) -> void:
	_status.text = detail

func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.name = "KickChatSettings"
	_settings.position = Vector2(24, 24)
	_settings.custom_minimum_size.x = 460
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17212b")
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_settings.add_theme_stylebox_override("panel", style)
	add_child(_settings)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_settings.add_child(column)
	var heading := Label.new()
	heading.text = "Kick Chat"
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	_address = LineEdit.new()
	_address.placeholder_text = "Kick server address (https://…)"
	_address.text = relay_url
	column.add_child(_address)
	var account_buttons := HBoxContainer.new()
	column.add_child(account_buttons)
	var connect_button := Button.new()
	connect_button.text = "Connect my Kick account"
	connect_button.pressed.connect(func(): connect_account(_address.text))
	account_buttons.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect"
	disconnect_button.pressed.connect(disconnect_chat)
	account_buttons.add_child(disconnect_button)
	_status = Label.new()
	_status.text = "Not connected"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var opacity_row := HBoxContainer.new()
	column.add_child(opacity_row)
	var opacity_title := Label.new()
	opacity_title.text = "Black background opacity"
	opacity_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_row.add_child(opacity_title)
	_opacity_value = Label.new()
	opacity_row.add_child(_opacity_value)
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0.0
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.01
	opacity_slider.custom_minimum_size.y = 28
	opacity_slider.value_changed.connect(set_background_opacity)
	column.add_child(opacity_slider)
	set_background_opacity(initial_background_opacity)
	var help := Label.new()
	help.text = "0%: transparent • 100%: black\nHold Option/Alt and drag the chat to move it."
	column.add_child(help)
	var reset := Button.new()
	reset.text = "Reset chat to bottom right"
	reset.pressed.connect(overlay.reset_position)
	column.add_child(reset)
	var close := Button.new()
	close.text = "Back to game"
	close.pressed.connect(close_settings)
	column.add_child(close)
	_settings.hide()
