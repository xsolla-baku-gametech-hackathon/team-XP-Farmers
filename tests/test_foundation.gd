extends SceneTree

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
var failures: int = 0
var notifications: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	controller.state_changed.connect(func(): notifications += 1)
	_check(not controller.is_feature_active(Controller.AUDIO), "Mode starts off")
	controller.set_enabled(true)
	_check(controller.is_feature_active(Controller.AUDIO), "Enabling mode activates selected features")
	controller.set_feature_enabled(Controller.AUDIO, false)
	_check(not controller.is_feature_active(Controller.AUDIO), "Feature opt-out works while enabled")
	_check(controller.is_feature_active(Controller.PRIVACY), "Audio opt-out does not change privacy")
	controller.set_enabled(false)
	controller.set_enabled(true)
	_check(not controller.is_feature_active(Controller.AUDIO), "Preferences survive mode toggles")
	var before := notifications
	controller.set_enabled(true)
	_check(notifications == before, "Repeated state does not restart components")
	_check(not controller.is_feature_active(&"unknown"), "Unknown features are inactive")
	controller.queue_free()
	var demo = load("res://demo/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	_check(not demo.settings_menu.visible, "Settings start hidden")
	demo.set_menu_open(true)
	_check(demo.settings_menu.size.y <= 600, "Settings remain bounded within the game window")
	_check(not demo.controller.enabled and not demo.arena.is_processing(), "Settings pause gameplay without enabling mode")
	demo.settings_panel.mode_button.button_pressed = true
	demo.settings_menu.resume_button.pressed.emit()
	_check(not demo.settings_menu.visible, "Resume button dismisses settings")
	_check(demo.controller.enabled and demo.arena.is_processing(), "Closing settings retains mode and resumes gameplay")
	_check(demo.services.music.is_protection_active(), "Audio remains protected with menu closed")
	_check(demo.controller.enabled, "UI toggle is wired to controller")
	demo._reset_run()
	_check(demo.arena.score == 0, "Demo resets gameplay")
	_check(not demo.settings_panel.feature_options[Controller.PRIVACY].disabled, "Privacy toggle is enabled after integration")
	_check(demo.privacy_engine != null, "Privacy engine is wired into the demo")
	demo.controller.set_enabled(true)
	await process_frame
	await process_frame
	await process_frame
	_check(demo.privacy_engine.active_region_count() >= 1, "Enabling mode masks the registered private region")
	demo.controller.set_feature_enabled(Controller.PRIVACY, false)
	await process_frame
	_check(demo.privacy_engine.active_region_count() == 0, "Opting out of privacy clears the masks")
	demo.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Foundation checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

