extends SceneTree
var failures := 0
var opened := false
var received := false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var connection = load("res://addons/streamer_mode/chat/channel_connection.gd").new()
	connection.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(connection)
	connection.relay_url = OS.get_environment("CHAT_TEST_ORIGIN")
	connection.browser_requested.connect(func(url: String): opened = url.contains("/connect#"))
	connection.channel_connected.connect(func(link: String, channel: String):
		received = link.ends_with("/overlay#" + "b".repeat(43)) and channel == "Fixture channel")
	paused = true
	connection.begin("kick")
	await create_timer(3.0).timeout
	if not opened or not received or not connection.connected:
		failures += 1
		push_error("Native pairing must open browser sign-in and deliver the channel while paused")
	await connection.disconnect_channel()
	if connection.connected or not connection._token.is_empty():
		failures += 1
		push_error("Disconnect must clear the pairing capability")
	paused = false
	connection.queue_free()
	await process_frame
	print("Godot pairing HTTP: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
