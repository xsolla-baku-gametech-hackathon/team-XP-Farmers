extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(25).timeout.connect(func(): push_error("External check timed out"); quit(1))
	call_deferred("_run")
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func _run() -> void:
	var host := root.get_node("StreamerIntegration")
	var platformer := ResourceLoader.exists("res://level_1.tscn")
	var scene_path := "res://level_1.tscn" if platformer else "res://scenes/game/game.tscn"
	var scene = load(scene_path).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var source = scene.get_node("Music")
	check(source.playing and source.bus == &"StreamOriginalMusic", "Existing game music is playing on dedicated source bus")
	var index := AudioServer.get_bus_index("StreamOriginalMusic")
	check(not AudioServer.is_bus_mute(index), "Normal mode preserves music")
	host.menu.set_open(true)
	check(paused and not host.controller.enabled, "Opening settings pauses without changing protection")
	host.controller.set_enabled(true)
	check(AudioServer.is_bus_mute(index), "Original game music muted")
	check(host.audio.music.is_playing(), "Our replacement is playing")
	host.menu.set_open(false)
	check(not paused and host.controller.enabled, "Closing settings resumes with protection")
	var effect = scene.find_child("JumpSfx", true, false) if platformer else scene.find_child("ShotSound", true, false)
	check(effect != null and effect.bus != &"StreamOriginalMusic", "Gameplay SFX stay on a separate route")
	if effect:
		effect.play()
		check(effect.playing and not AudioServer.is_bus_mute(AudioServer.get_bus_index(effect.bus)), "Gameplay SFX continue while protected")
	host.audio.set_replacement(null)
	check(AudioServer.is_bus_mute(index) and not host.audio.music.is_playing(), "Silence selection mutes only original music")
	host.audio.set_replacement(host._loop("res://streamer_integration/neon_run.wav"))
	check(host.audio.music.is_playing(), "Second bundled track plays")
	scene.free()
	current_scene = null
	var next = load("res://level_2.tscn" if platformer else "res://scenes/menu/menu.tscn").instantiate()
	root.add_child(next)
	current_scene = next
	await process_frame
	await process_frame
	check(AudioServer.is_bus_mute(index) and host.audio.music.is_playing(), "Protection survives real game scene change")
	host.controller.set_enabled(false)
	check(not AudioServer.is_bus_mute(index) and not host.audio.music.is_playing(), "Disabling restores original game music")
	next.free()
	current_scene = null
	host.free()
	await process_frame
	await create_timer(0.5).timeout
	print("External game checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
