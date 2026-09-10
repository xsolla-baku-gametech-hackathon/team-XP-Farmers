extends Control
## Interactive audio verification without loading the main demo scene.

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Services = preload("res://demo/demo_services.gd")

var controller: StreamerModeController
var services: Node
var status: Label
var replacement: AudioStream


func _ready() -> void:
	controller = Controller.new()
	add_child(controller)
	services = Services.new()
	add_child(services)
	services.setup(controller)
	replacement = services.music.replacement_stream
	var panel := VBoxContainer.new()
	panel.position = Vector2(48, 48)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)
	var title := Label.new()
	title.text = "Audio integration lab"
	title.add_theme_font_size_override("font_size", 30)
	panel.add_child(title)
	var explanation := Label.new()
	explanation.text = "Listen while toggling mode, pausing, stopping and removing the replacement.\nEffects should remain audible independently."
	panel.add_child(explanation)
	status = Label.new()
	panel.add_child(status)
	_toggle(panel, "Streamer Mode", func(value: bool): controller.set_enabled(value))
	_toggle(panel, "Opt out of audio replacement", func(value: bool): controller.set_feature_enabled(Controller.AUDIO, not value))
	_toggle(panel, "Pause music", func(value: bool): services.music.set_paused(value))
	_toggle(panel, "No replacement configured", func(value: bool): services.music.set_tracks(services.music.normal_stream, null if value else replacement))
	_button(panel, "Play music", services.music.play)
	_button(panel, "Stop music", services.music.stop)
	_button(panel, "Play independent sound effect", func(): services.play_collection_sound(0))
	services.audio_status_changed.connect(func(_message: String): _refresh())
	_refresh()


func _refresh() -> void:
	status.text = services.music.get_status()


func _button(parent: Control, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	parent.add_child(button)


func _toggle(parent: Control, caption: String, action: Callable) -> void:
	var button := CheckBox.new()
	button.text = caption
	button.toggled.connect(action)
	parent.add_child(button)
