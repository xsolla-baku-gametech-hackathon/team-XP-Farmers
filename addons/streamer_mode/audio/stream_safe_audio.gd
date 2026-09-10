class_name StreamSafeAudio
extends Node
## Owns a game's managed music playback. Route music through this component.
## Switching stops the previous track before starting the selected one.
## Effects/dialogue players and buses are never modified.

signal playback_changed

@export var normal_stream: AudioStream
@export var replacement_stream: AudioStream
@export var music_bus: StringName = &"Master"
@export_range(-60.0, 6.0) var volume_db: float = -8.0
@export var autoplay: bool = false

var _controller: StreamerModeController
var _player: AudioStreamPlayer
var _requested_playing: bool = false
var _paused: bool = false
var _initialized: bool = false


func _enter_tree() -> void:
	_connect_controller()
	if _initialized:
		call_deferred("_synchronize")


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "ManagedMusic"
	_player.max_polyphony = 1
	add_child(_player)
	_player.finished.connect(_on_finished)
	_requested_playing = autoplay
	_initialized = true
	_synchronize()


func _exit_tree() -> void:
	_disconnect_controller()
	if is_instance_valid(_player):
		_player.stop()


func bind(controller: StreamerModeController) -> void:
	_disconnect_controller()
	_controller = controller
	if is_inside_tree():
		_connect_controller()
	_synchronize()


func set_tracks(normal: AudioStream, replacement: AudioStream) -> void:
	normal_stream = normal
	replacement_stream = replacement
	_synchronize()


func play() -> void:
	_requested_playing = true
	_synchronize()


func stop() -> void:
	_requested_playing = false
	if is_instance_valid(_player):
		_player.stop()
	playback_changed.emit()


func set_paused(value: bool) -> void:
	_paused = value
	if is_instance_valid(_player):
		_player.stream_paused = _paused
	playback_changed.emit()


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return is_instance_valid(_player) and _player.playing


func is_protection_active() -> bool:
	return is_instance_valid(_controller) and _controller.is_feature_active(StreamerModeController.AUDIO)


func get_selected_stream() -> AudioStream:
	return replacement_stream if is_protection_active() else normal_stream


func get_status() -> String:
	if not _requested_playing:
		return "Music stopped"
	if get_selected_stream() == null:
		return "Music muted: no replacement configured" if is_protection_active() else "No normal track configured"
	if _paused:
		return "Music paused"
	return "Replacement track playing" if is_protection_active() else "Normal track playing"


func _synchronize() -> void:
	if not is_instance_valid(_player) or not is_inside_tree():
		return
	var selected := get_selected_stream()
	if _player.stream != selected:
		# Never crossfade normal music into the protected output.
		_player.stop()
		_player.stream = selected
	_player.bus = music_bus
	_player.volume_db = volume_db
	if selected == null or not _requested_playing:
		_player.stop()
	elif not _player.playing:
		# Set pause before play as well, so a paused switch never emits a burst.
		_player.stream_paused = _paused
		_player.play()
	_player.stream_paused = _paused
	playback_changed.emit()


func _on_finished() -> void:
	_requested_playing = false
	playback_changed.emit()


func _connect_controller() -> void:
	if is_instance_valid(_controller) and not _controller.state_changed.is_connected(_synchronize):
		_controller.state_changed.connect(_synchronize)


func _disconnect_controller() -> void:
	if is_instance_valid(_controller) and _controller.state_changed.is_connected(_synchronize):
		_controller.state_changed.disconnect(_synchronize)
