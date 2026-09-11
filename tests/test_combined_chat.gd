extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(15).timeout.connect(func(): push_error("Combined check timed out"); quit(1))
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var demo = load("res://demo/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var chat = demo.services.chat
	check(not demo.settings_menu.visible and not chat.settings.visible, "Both settings views start hidden")
	demo.open_chat_settings()
	check(demo.settings_menu.visible and chat.settings.visible and not demo.arena.is_processing(), "Chat settings are inside the game modal")
	check(not demo.controller.enabled, "Opening connection settings does not enable features")
	chat.enable_chat()
	check(demo.controller.is_feature_active(&"audio") and demo.controller.is_feature_active(&"privacy"), "Explicit enable uses existing master and selected features")
	check(demo.services.music.is_protection_active() and not demo.copy_field._value_label.visible, "Audio and private code remain protected")
	chat.client.accept_snapshot({"state":"connected", "settings":{"enabled":true}, "messages":[]})
	chat.client.accept_snapshot({"state":"connected", "settings":{"enabled":true}, "messages":[{"id":"1", "author":"Fixture", "text":"Test message"}]})
	check(chat.overlay.messages.size() == 1, "Native chat renders a fixture message")
	chat.settings.close()
	check(not demo.settings_menu.visible and demo.arena.is_processing(), "Back to game closes modal and resumes gameplay")
	check(demo.controller.enabled and chat.overlay.visible, "Closing chat settings preserves master and chat")
	demo.controller.set_feature_enabled(&"chat", false)
	check(not chat.overlay.visible and chat.overlay.messages.size() == 1, "Chat opt-out hides but preserves teammate history behavior")
	check(demo.services.music.is_protection_active() and not demo.copy_field._value_label.visible, "Chat opt-out leaves audio/privacy active")
	demo.controller.set_feature_enabled(&"chat", true)
	check(chat.overlay.visible, "Chat can be re-enabled")
	demo.set_menu_open(true)
	check(demo.settings_panel.visible and not chat.settings.visible, "Reopening settings returns to main feature controls")
	demo.set_menu_open(false)
	demo.controller.set_enabled(false)
	check(not chat.overlay.visible and demo.copy_field._value_label.visible, "Master off restores private text and hides chat")
	demo.free()
	await process_frame
	await create_timer(0.5).timeout
	print("Combined chat checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
