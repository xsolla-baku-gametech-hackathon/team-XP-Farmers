class_name StreamSafeMusicBus
extends Node
## Host routes only original music to a dedicated bus. Replacement bypasses it.
## Source bus must not contain effects/dialogue or the replacement output.
@export var source_bus: StringName = &"StreamOriginalMusic"
@export var replacement_bus: StringName = &"Master"
@export var replacement_stream: AudioStream
var music: StreamSafeAudio
var _controller: StreamerModeController
var _owns_mute := false
var _previous_mute := false

func _ready() -> void:
	music = StreamSafeAudio.new()
	music.music_bus = replacement_bus
	music.replacement_stream = replacement_stream
	add_child(music)
	music.bind(_controller if is_configured() else null)
	music.play()
	_sync()

func bind(controller: StreamerModeController) -> void:
	if is_instance_valid(_controller) and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	_restore()
	_controller = controller
	if is_instance_valid(controller):
		controller.state_changed.connect(_sync)
	if is_instance_valid(music):
		music.bind(controller if is_configured() else null)
	_sync()

func set_replacement(stream: AudioStream) -> void:
	replacement_stream = stream
	if is_instance_valid(music):
		music.set_tracks(null, stream)

func is_configured() -> bool:
	return source_bus != &"Master" and source_bus != replacement_bus and AudioServer.get_bus_index(source_bus) > 0 and AudioServer.get_bus_index(replacement_bus) >= 0

func _sync() -> void:
	if not is_configured():
		if is_instance_valid(music):
			music.stop()
		return
	var active := is_instance_valid(_controller) and _controller.is_feature_active(StreamerModeController.AUDIO)
	if active:
		var index := AudioServer.get_bus_index(source_bus)
		if not _owns_mute:
			_previous_mute = AudioServer.is_bus_mute(index)
			_owns_mute = true
		AudioServer.set_bus_mute(index, true)
	else:
		_restore()

func _restore() -> void:
	if _owns_mute:
		var index := AudioServer.get_bus_index(source_bus)
		if index >= 0:
			AudioServer.set_bus_mute(index, _previous_mute)
		_owns_mute = false

func _exit_tree() -> void:
	_restore()
	if is_instance_valid(_controller) and _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
