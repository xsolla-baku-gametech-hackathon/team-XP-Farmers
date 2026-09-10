extends Control
## Explicit offline preview; real connection uses local environment credentials.
const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Client = preload("res://addons/streamer_mode/chat/kick_relay_client.gd")
var overlay: StreamerChatOverlay
var client: KickRelayClient
var status: Label


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("204538")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var controller := Controller.new()
	add_child(controller)
	controller.set_enabled(true)
	client = Client.new()
	add_child(client)
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Overlay.new()
	layer.add_child(overlay)
	overlay.bind_controller(controller)
	overlay.bind_client(client)
	var controls := VBoxContainer.new()
	controls.position = Vector2(24, 24)
	add_child(controls)
	var title := Label.new()
	title.text = "CHAT TEST SCENE • Offline preview\nHold Option/Alt and drag the chat to move it."
	controls.add_child(title)
	status = Label.new()
	status.text = client.detail
	controls.add_child(status)
	client.status_changed.connect(func(_state: String, message: String): status.text = message)
	var preview := Button.new()
	preview.text = "Add OFFLINE test message"
	preview.pressed.connect(func():
		client.disconnect_chat()
		title.text = "CHAT TEST SCENE • OFFLINE sample messages\nHold Option/Alt and drag the chat to move it."
		overlay.append_message("", "OFFLINE TEST: Salam! Oyun çox gözəldir. [%s]" % Time.get_ticks_msec())
	)
	controls.add_child(preview)
	var connect_button := Button.new()
	connect_button.text = "Connect my Kick (local environment credentials)"
	connect_button.pressed.connect(func():
		overlay.clear_messages()
		title.text = "CHAT TEST SCENE • Live Kick mode\nHold Option/Alt and drag the chat to move it."
		client.connect_session(OS.get_environment("KICK_RELAY_URL"), OS.get_environment("KICK_SESSION_KEY"))
	)
	controls.add_child(connect_button)
	var toggle := CheckButton.new()
	toggle.text = "Streamer Mode"
	toggle.button_pressed = true
	toggle.toggled.connect(controller.set_enabled)
	controls.add_child(toggle)
	var reset := Button.new()
	reset.text = "Reset chat to bottom right"
	reset.pressed.connect(overlay.reset_position)
	controls.add_child(reset)
	var stop := Button.new()
	stop.text = "Disconnect"
	stop.pressed.connect(client.disconnect_chat)
	controls.add_child(stop)
