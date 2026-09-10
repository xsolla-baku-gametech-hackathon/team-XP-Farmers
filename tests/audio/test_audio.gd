extends SceneTree

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Adapter = preload("res://addons/streamer_mode/audio/stream_safe_audio.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var normal := _tone(220.0)
	var safe := _tone(440.0)
	var audio := Adapter.new()
	audio.set_tracks(normal, safe)
	audio.bind(controller)
	root.add_child(audio)
	audio.play()
	_check(audio.is_playing() and audio.get_selected_stream() == normal, "Normal mode plays normal music")
	var player := audio.get_node("ManagedMusic") as AudioStreamPlayer
	var effects := AudioStreamPlayer.new()
	effects.stream = normal
	effects.bus = &"SFX"
	root.add_child(effects)
	effects.play()
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var sfx_volume := AudioServer.get_bus_volume_db(sfx_bus)
	controller.set_enabled(true)
	_check(player.stream == safe and audio.is_playing(), "Toggle replaces the actual player stream")
	_check(effects.playing and effects.stream == normal, "Independent effects keep playing")
	_check(AudioServer.get_bus_volume_db(sfx_bus) == sfx_volume and not AudioServer.is_bus_mute(sfx_bus), "SFX bus is untouched")
	controller.set_feature_enabled(Controller.AUDIO, false)
	_check(player.stream == normal, "Audio opt-out restores normal music")
	controller.set_feature_enabled(Controller.AUDIO, true)
	audio.set_paused(true)
	controller.set_enabled(false)
	controller.set_enabled(true)
	_check(player.stream_paused and player.stream == safe, "Switching while paused stays paused")
	audio.set_paused(false)
	_check(not player.stream_paused and audio.is_playing(), "Playback resumes after pause")
	audio.stop()
	controller.set_enabled(false)
	controller.set_enabled(true)
	_check(not audio.is_playing(), "Mode changes cannot restart deliberately stopped playback")
	audio.play()
	audio.set_tracks(normal, null)
	_check(player.stream == null and not audio.is_playing(), "Missing replacement stops normal music")
	_check(audio.get_status().contains("muted"), "Missing replacement has an explicit status")
	controller.set_enabled(false)
	_check(player.stream == normal and audio.is_playing(), "Normal mode restores music after missing replacement")
	controller.set_enabled(true)
	audio.set_tracks(normal, safe)
	_check(player.stream == safe and audio.is_playing(), "Providing a replacement recovers protected playback")
	var second_controller := Controller.new()
	root.add_child(second_controller)
	audio.bind(second_controller)
	controller.set_enabled(false)
	controller.set_enabled(true)
	_check(player.stream == normal, "Old controller is disconnected after rebinding")
	second_controller.set_enabled(true)
	_check(player.stream == safe, "New controller controls playback")
	root.remove_child(audio)
	second_controller.set_enabled(false)
	root.add_child(audio)
	await process_frame
	_check(player.stream == normal and audio.is_playing(), "Scene re-entry synchronizes current mode")
	var before := player.get_playback_position()
	second_controller.set_enabled(false)
	_check(player.get_playback_position() >= before, "Duplicate mode does not restart playback")
	audio.queue_free()
	effects.queue_free()
	controller.queue_free()
	second_controller.queue_free()
	await process_frame
	# A late-bound, autoplaying component must never start normal music first.
	var enabled_controller := Controller.new()
	enabled_controller.set_enabled(true)
	root.add_child(enabled_controller)
	var late := Adapter.new()
	late.autoplay = true
	late.set_tracks(normal, safe)
	late.bind(enabled_controller)
	root.add_child(late)
	_check(late.get_node("ManagedMusic").stream == safe, "Enabled-before-start selects replacement immediately")
	late.queue_free()
	enabled_controller.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Audio checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _tone(frequency: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(22050 * 2)
	for index in range(22050):
		data.encode_s16(index * 2, int(sin(TAU * frequency * index / 22050.0) * 4000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050
	return stream


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
