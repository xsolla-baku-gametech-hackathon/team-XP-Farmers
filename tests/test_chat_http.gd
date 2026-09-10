extends SceneTree
var received := false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var client = load("res://addons/streamer_mode/chat/chat_client.gd").new()
	root.add_child(client)
	client.set_active(true)
	client.snapshot_received.connect(func(rows: Array):
		if rows.size() == 1 and rows[0].author == "HTTP_User": received = true)
	client.connect_link(OS.get_environment("CHAT_TEST_LINK"))
	await create_timer(4.0).timeout
	client.disconnect_chat()
	client.queue_free()
	await process_frame
	print("Godot HTTP integration: ", "PASS" if received else "FAIL")
	quit(0 if received else 1)
