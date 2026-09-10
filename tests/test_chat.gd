extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var demo = load("res://demo/chat_integration.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var chat = demo.chat
	check(not chat.overlay.visible, "Master off hides chat")
	demo.controller.set_enabled(true)
	check(chat.overlay.visible, "Master on shows chat")
	for provider in ["kick", "twitch", "youtube"]:
		chat.client.set_active(false)
		chat.client.set_active(true)
		var snapshot := {"provider": provider, "state": "connected", "settings": {"enabled": true}, "messages": [{"id": "old", "author": "old", "text": "history"}]}
		chat.client.accept_snapshot(snapshot)
		check(chat.overlay.messages.is_empty(), "No initial history")
		snapshot.messages.append({"id": "new", "author": "Əli_🎮", "text": "[b]literal[/b]"})
		chat.client.accept_snapshot(snapshot)
		check(chat.overlay.messages == ["Əli_🎮: [b]literal[/b]"], provider + " username and literal text")
		chat.client.accept_snapshot(snapshot)
		check(chat.overlay.messages.size() == 1, "No duplicates")
		snapshot.messages.pop_back()
		chat.client.accept_snapshot(snapshot)
		check(chat.overlay.messages.is_empty(), "Moderated message removed")

	var record := {"id": "hidden", "author": "hidden", "text": "while off"}
	demo.controller.set_enabled(false)
	chat.client.accept_snapshot({"state": "connected", "settings": {"enabled": true}, "messages": [record]})
	check(chat.overlay.messages.is_empty(), "Disabled mode clears incoming messages")
	demo.controller.set_enabled(true)
	chat.client.accept_snapshot({"state": "connected", "settings": {"enabled": true}, "messages": [record]})
	check(chat.overlay.messages.is_empty(), "Re-enabling excludes off-period history")
	chat.client.accept_snapshot({"state": "connected", "settings": null, "messages": null})
	check(chat.overlay.messages.is_empty(), "Malformed snapshot fails closed")
	chat.overlay.background_opacity = 0.73
	check(is_equal_approx(chat.overlay._background.color.a, 0.73), "Background opacity")
	check(chat.overlay._label.modulate.a == 1.0, "Text stays opaque")
	chat.open_settings()
	chat.close_settings()
	check(demo.controller.enabled and chat.overlay.visible, "Closing settings preserves mode")
	demo.controller.set_feature_enabled(&"chat", false)
	check(not chat.overlay.visible and not chat.client._active, "Chat opt-out disables rendering")
	demo.controller.set_feature_enabled(&"chat", true)
	check(chat.overlay.visible, "Chat opt-in")
	check(not chat.connect_link("http://example.com/overlay#" + "a".repeat(43)), "Reject nonlocal HTTP")
	check(not chat.connect_link("https://user:pass@example.com/overlay#" + "a".repeat(43)), "Reject credentials in URL")
	check(chat.connect_link("http://localhost:8789/overlay#" + "a".repeat(43)), "Accept development link")
	check(chat.client._key == "a".repeat(43), "Extract bearer key correctly")
	chat.client.disconnect_chat()
	check(chat.client._key.is_empty(), "Disconnect drops capability")
	demo.queue_free()
	await process_frame
	print("Godot chat checks: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
