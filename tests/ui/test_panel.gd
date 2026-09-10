extends SceneTree

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PanelScene = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel = PanelScene.instantiate()
	root.add_child(panel)
	_check(panel.mode_button.disabled, "Unbound panel cannot change settings")
	var first := Controller.new()
	root.add_child(first)
	first.set_enabled(true)
	panel.bind(first)
	_check(panel.mode_button.disabled, "No installed features means master toggle is disabled")
	panel.set_feature_available(Controller.AUDIO, true)
	_check(panel.mode_button.button_pressed, "Late binding reads enabled state")
	_check(panel.feature_options[Controller.PRIVACY].disabled, "Missing component is not advertised as usable")
	panel.feature_options[Controller.AUDIO].button_pressed = false
	_check(not first.is_feature_selected(Controller.AUDIO), "UI preference updates controller")
	_check(panel.get_status_text().contains("no features selected"), "Enabled without selected features is reported honestly")
	var mirror = PanelScene.instantiate()
	mirror.set_feature_available(Controller.AUDIO, true)
	mirror.bind(first)
	root.add_child(mirror)
	first.set_feature_enabled(Controller.AUDIO, true)
	_check(panel.feature_options[Controller.AUDIO].button_pressed and mirror.feature_options[Controller.AUDIO].button_pressed, "Two panels reflect external settings without feedback")
	panel.set_feature_available(Controller.AUDIO, false)
	_check(first.is_feature_selected(Controller.AUDIO), "Availability never silently changes preferences")
	var second := Controller.new()
	root.add_child(second)
	panel.bind(second)
	panel.set_feature_available(Controller.AUDIO, true)
	first.set_enabled(false)
	first.set_enabled(true)
	_check(not panel.mode_button.button_pressed, "Rebinding disconnects old controller")
	root.remove_child(panel)
	second.set_enabled(true)
	root.add_child(panel)
	await process_frame
	_check(panel.mode_button.button_pressed, "Panel re-entry resynchronizes")
	second.queue_free()
	await process_frame
	_check(panel.mode_button.disabled, "Controller removal disables panel safely")
	panel.queue_free()
	mirror.queue_free()
	first.queue_free()
	await process_frame
	print("Panel checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
