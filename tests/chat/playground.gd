extends Control
## Feature scene inside the shared Godot project; not a separate desktop app.
const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const ChatScene = preload("res://addons/streamer_mode/chat/kick_chat.tscn")
var chat: StreamerKickChat

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("204538")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var controller := Controller.new()
	add_child(controller)
	controller.set_enabled(true)
	chat = ChatScene.instantiate()
	chat.relay_url = OS.get_environment("KICK_RELAY_URL")
	chat.bind_controller(controller)
	add_child(chat)
	var controls := VBoxContainer.new()
	controls.position = Vector2(24, 24)
	controls.add_theme_constant_override("separation", 12)
	add_child(controls)
	var title := Label.new()
	title.text = "KICK CHAT • GODOT FEATURE TEST\nConnect in settings, or add a labeled OFFLINE sample."
	controls.add_child(title)
	var settings := Button.new()
	settings.text = "Kick chat settings / background opacity"
	settings.pressed.connect(chat.open_settings)
	controls.add_child(settings)
	var preview := Button.new()
	preview.text = "Add OFFLINE test messages"
	preview.pressed.connect(func():
		chat.disconnect_chat()
		chat.overlay.append_message("Zarifa", "OFFLINE TEST: Salam! Oyun çox gözəldir.")
		chat.overlay.append_message("Player2", "OFFLINE TEST: [b]Bu yazı olduğu kimi görünür.[/b]")
	)
	controls.add_child(preview)
	var toggle := CheckButton.new()
	toggle.text = "Streamer Mode"
	toggle.button_pressed = true
	toggle.toggled.connect(controller.set_enabled)
	controls.add_child(toggle)
	var stop := Button.new()
	stop.text = "Stop test"
	stop.pressed.connect(func(): get_tree().quit())
	controls.add_child(stop)
