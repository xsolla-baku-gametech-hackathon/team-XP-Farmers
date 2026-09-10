extends Node
## This is the host game's integration glue. The addon itself is copied unchanged.

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Music = preload("res://addons/streamer_mode/audio/stream_safe_audio.gd")
const Sounds = preload("res://world/sounds.gd")

var controller: StreamerModeController
var music: StreamSafeAudio
var click_sound: AudioStreamPlayer
var panel: StreamerModePanel


func _ready() -> void:
	controller = Controller.new()
	add_child(controller)
	music = Music.new()
	music.set_tracks(Sounds.melody(false), Sounds.melody(true))
	music.bind(controller)
	add_child(music)
	panel = get_parent().get_node("SettingsPanel")
	panel.bind(controller)
	panel.set_feature_available(Controller.AUDIO, true)
	music.playback_changed.connect(_update_status)
	music.play()
	click_sound = AudioStreamPlayer.new()
	click_sound.stream = Sounds.chime()
	add_child(click_sound)


func play_click() -> void:
	click_sound.play()


func _update_status() -> void:
	panel.set_feature_status(Controller.AUDIO, music.get_status())
