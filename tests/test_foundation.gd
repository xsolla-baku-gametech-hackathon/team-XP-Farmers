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
	demo.settings_panel.mode_button.button_pressed = true
	_check(demo.controller.enabled, "UI toggle is wired to controller")
	_check(demo.services.has_chat(), "Main demo installs chat through DemoServices")
	_check(demo.services.chat.overlay.visible, "Main demo master switch activates chat")
	_check(demo.settings_panel.feature_options[Controller.AUDIO].disabled, "Audio remains unavailable")
	_check(demo.settings_panel.feature_options[Controller.PRIVACY].disabled, "Privacy remains unavailable")
	demo.services.chat.client.status_changed.emit("connecting", "Connecting fixture")
	_check(demo.chat_status.text == "Connecting fixture", "Relay status reaches shared demo UI")
	demo.services.chat.open_settings()
	await process_frame
	_check(not demo.arena.is_processing(), "Opening chat settings pauses arena input")
	demo.services.chat.close_settings()
	await process_frame
	_check(demo.arena.is_processing(), "Closing settings restores gameplay")
	_check(demo.controller.enabled, "Closing settings keeps streamer mode enabled")
	demo._reset_run()
	_check(demo.arena.score == 0, "Demo resets gameplay")
	demo.queue_free()
	await process_frame
	print("Foundation checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

