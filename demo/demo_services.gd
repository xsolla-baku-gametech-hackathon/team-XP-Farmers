extends Node
## Integration owner connects completed feature components here.

signal audio_status_changed(message: String)

const AudioAdapter = preload("res://addons/streamer_mode/audio/stream_safe_audio.gd")
const NORMAL = preload("res://demo/assets/audio/neon_run.wav")
const REPLACEMENT = preload("res://demo/assets/audio/quiet_orbit.wav")
const COLLECT = preload("res://demo/assets/audio/collect.wav")

var music: StreamSafeAudio
var effects: AudioStreamPlayer


func setup(controller: StreamerModeController) -> void:
	music = AudioAdapter.new()
	music.name = "StreamSafeAudio"
	music.music_bus = &"Music"
	music.normal_stream = _loop(NORMAL)
	music.replacement_stream = _loop(REPLACEMENT)
	music.bind(controller)
	add_child(music)
	music.playback_changed.connect(func(): audio_status_changed.emit(get_audio_status()))
	music.play()
	effects = AudioStreamPlayer.new()
	effects.name = "CollectionSound"
	effects.bus = &"SFX"
	effects.volume_db = -8.0
	effects.max_polyphony = 4
	effects.stream = COLLECT
	add_child(effects)


func get_audio_status() -> String:
	if not is_instance_valid(music):
		return "Audio initializing"
	if music.is_paused() or not music.is_playing():
		return music.get_status()
	return "QUIET ORBIT · replacement track" if music.is_protection_active() else "NEON RUN · normal track"


func has_audio() -> bool:
	return true


func play_collection_sound(_total: int) -> void:
	effects.play()


func _loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	return stream
