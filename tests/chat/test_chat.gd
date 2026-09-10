extends SceneTree
const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Client = preload("res://addons/streamer_mode/chat/kick_relay_client.gd")
var failures := 0
var received := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var overlay := Overlay.new()
	root.add_child(overlay)
	overlay.bind_controller(controller)
	_check(not overlay.visible, "Hidden while mode is off")
	controller.set_enabled(true)
	_check(overlay.visible, "Shared mode enables chat")
	controller.set_feature_enabled(Controller.CHAT, false)
	_check(not overlay.visible, "Chat preference hides overlay")
	var other := Controller.new()
	root.add_child(other)
	other.set_enabled(true)
	overlay.bind_controller(other)
	_check(not controller.state_changed.is_connected(overlay._sync), "Rebinding disconnects old controller")
	_check(overlay.visible, "Late binding synchronizes immediately")
	overlay.max_messages = 3
	for index in range(10):
		overlay.append_message("name", str(index))
	_check(overlay.messages == ["7", "8", "9"], "History stays bounded")
	overlay.append_message("name", "[b]literal[/b]")
	_check(not overlay._label.bbcode_enabled and "[b]literal[/b]" in overlay._label.text, "User text cannot inject BBCode")
	overlay.position = Vector2(10000, -100)
	overlay._clamp_position()
	_check(overlay.position.y == 0 and overlay.position.x + overlay.size.x <= overlay.get_viewport_rect().size.x, "Dragged chat remains on screen")
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Ordinary mouse input passes through")
	var client := Client.new()
	root.add_child(client)
	overlay.bind_client(client)
	client.message_received.connect(func(_author: String, _message: String): received += 1)
	var packet := {"state": "connected", "detail": "Receiving Kick chat", "cursor": 1, "messages": [{"sequence": 1, "text": "Salam"}]}
	client._accept_reply(packet)
	client._accept_reply(packet)
	_check(received == 1 and overlay.messages == ["Salam"], "Kick relay cursor prevents duplicate messages")
	client._accept_reply({"state": "error", "detail": "Expired"})
	_check(client.state == "error" and client._key.is_empty(), "Relay errors stop polling and clear session key")
	overlay.bind_client(null)
	_check(not client.message_received.is_connected(overlay.append_message), "Client unbind disconnects signals")
	overlay.queue_free()
	client.queue_free()
	controller.queue_free()
	other.queue_free()
	await process_frame
	print("Chat checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
