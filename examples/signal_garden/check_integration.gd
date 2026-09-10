extends SceneTree

var failures: int = 0


func _initialize() -> void:
	create_timer(10.0).timeout.connect(func(): push_error("Integration check timed out"); quit(1))
	call_deferred("_run")


func _run() -> void:
	_check(not DirAccess.dir_exists_absolute("res://demo"), "First demo is absent from this project")
	var game = load("res://world/garden.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var music = game.integration.music
	var player = music.get_node("ManagedMusic")
	_check(player.stream == music.normal_stream and music.is_playing(), "Independent game's music starts normally")
	game.panel.mode_button.button_pressed = true
	_check(player.stream == music.replacement_stream and music.is_playing(), "Copied panel switches copied audio component")
	game._press_cell(0)
	_check(game.moves == 1 and game.integration.click_sound.playing, "Independent gameplay and SFX work while protected")
	game.panel.feature_options[&"audio"].button_pressed = false
	_check(player.stream == music.normal_stream, "Opt-out restores this game's own normal stream")
	game.integration.controller.set_feature_enabled(&"audio", true)
	_check(player.stream == music.replacement_stream, "External host settings update playback")
	game._reset()
	for index in [1, 6, 9]:
		game._press_cell(index)
	_check(game.cells.count(true) == 16, "Puzzle can be completed")
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Independent project checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
