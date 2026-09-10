extends Control
const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Chat = preload("res://addons/streamer_mode/chat/streamer_chat.gd")
const Arena = preload("res://demo/arena.gd")
var controller: StreamerModeController
var chat: StreamerChat
var arena: Control

func _ready() -> void:
	controller = Controller.new()
	add_child(controller)
	arena = Arena.new()
	add_child(arena)
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chat = Chat.new()
	chat.bind_controller(controller)
	add_child(chat)
	var settings_button := Button.new()
	settings_button.position = Vector2(24, 20)
	settings_button.text = "Settings · Esc"
	settings_button.pressed.connect(_toggle_settings)
	add_child(settings_button)
	var hint := Label.new()
	hint.position = Vector2(220, 25)
	hint.text = "XP Farmers · Godot chat integration   |   WASD / arrows to move   |   No channel connected by default"
	add_child(hint)
	chat.open_settings()

func _toggle_settings() -> void:
	if chat.settings.visible:
		chat.close_settings()
	else:
		chat.open_settings()

func _process(_delta: float) -> void:
	arena.set_process(not chat.settings.visible)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_settings()
		get_viewport().set_input_as_handled()
