extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, "StreamOriginalMusic")
	var controller := StreamerModeController.new()
	root.add_child(controller)
	var bridge := StreamSafeMusicBus.new()
	bridge.replacement_stream = load("res://demo/assets/audio/quiet_orbit.wav")
	bridge.bind(controller)
	root.add_child(bridge)
	controller.set_enabled(true)
	check(AudioServer.is_bus_mute(index), "Original music bus muted")
	check(bridge.music.is_playing(), "Replacement plays")
	check(not AudioServer.is_bus_mute(0), "Master remains audible")
	bridge.set_replacement(null)
	check(AudioServer.is_bus_mute(index) and not bridge.music.is_playing(), "Silence keeps original muted")
	controller.set_enabled(false)
	check(not AudioServer.is_bus_mute(index), "Original mute state restored")
	AudioServer.set_bus_mute(index, true)
	controller.set_enabled(true)
	controller.set_enabled(false)
	check(AudioServer.is_bus_mute(index), "Initially muted host remains muted")
	AudioServer.set_bus_mute(index, false)
	controller.set_enabled(true)
	bridge.free()
	check(not AudioServer.is_bus_mute(index), "Teardown restores original bus")
	var invalid := StreamSafeMusicBus.new()
	invalid.source_bus = &"Master"
	invalid.replacement_stream = load("res://demo/assets/audio/quiet_orbit.wav")
	invalid.bind(controller)
	root.add_child(invalid)
	check(not invalid.is_configured() and not invalid.music.is_playing(), "Reject Master as a music-only source")
	invalid.free()
	controller.free()
	AudioServer.remove_bus(index)
	await process_frame
	await create_timer(0.5).timeout
	print("Music bus checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
