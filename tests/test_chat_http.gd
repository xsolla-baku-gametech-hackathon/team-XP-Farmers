extends SceneTree
var received := false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var controller = load("res://addons/streamer_mode/core/streamer_mode_controller.gd").new()
	root.add_child(controller)
	controller.set_enabled(true)
	var chat = load("res://addons/streamer_mode/chat/streamer_chat.tscn").instantiate()
	chat.bind(controller)
	root.add_child(chat)
	var client = chat.client
	paused = true
	client.snapshot_received.connect(func(rows: Array):
		if rows.size() == 1 and rows[0].author == "HTTP_User": received = true)
	client.connect_link(OS.get_environment("CHAT_TEST_LINK"))
	await create_timer(4.0).timeout
	client.disconnect_chat()
	paused = false
	chat.queue_free()
	controller.queue_free()
	await process_frame
	print("Godot HTTP integration: ", "PASS" if received else "FAIL")
	quit(0 if received else 1)
