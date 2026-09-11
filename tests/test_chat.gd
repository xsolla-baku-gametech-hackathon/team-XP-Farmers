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
	check(is_instance_valid(chat.chat_window), "Desktop host creates a separate chat window")
	check(chat.overlay.get_parent() == chat.chat_window, "Chat renders in its own viewport")
	check(chat.chat_window.force_native and chat.chat_window.always_on_top, "Chat floats outside the embedded game")
	check(not chat.chat_window.popup_window and not chat.chat_window.transient, "App switching does not dismiss chat as a popup")
	check(chat.chat_window.transparent and chat.chat_window.transparent_bg, "Native window preserves background transparency")
	check(not chat.chat_window.visible, "Master off hides native window")
	check(not chat.overlay.visible, "Master off hides chat")
	check(chat.settings._connect.disabled and chat.settings._provider.disabled, "Mode off locks channel controls")
	chat.connect_channel("kick")
	check(not chat.connection.connected, "Mode off cannot begin channel connection")
	chat.enable_chat()
	check(not chat.overlay.display_enabled, "Enable cannot bypass mode and connection")
	demo.controller.set_enabled(true)
	check(not chat.settings._connect.disabled, "Mode on unlocks channel connection")
	check(not chat.chat_window.visible, "Mode on alone does not open empty chat")
	check(chat.chat_window.size == Vector2i(360, 220), "Initial desktop panel remains compact")
	chat.connection.connected = true
	chat.connection.channel = "Fixture"
	chat.settings.refresh_controls()
	check(not chat.settings._enable.disabled, "Connected channel unlocks Enable chat")
	check(not chat.chat_window.visible, "Connected channel waits for explicit chat enable")
	chat.enable_chat()
	check(chat.overlay.visible and chat.chat_window.visible, "Enable chat opens native panel")
	demo.controller.set_enabled(false)
	check(chat.settings._connect.disabled and not chat.chat_window.visible, "Mode off locks controls and hides chat")
	demo.controller.set_enabled(true)
	check(chat.chat_window.visible, "Mode toggle restores explicitly enabled chat")
	var native_press := InputEventMouseButton.new()
	native_press.button_index = MOUSE_BUTTON_LEFT
	native_press.pressed = true
	chat.overlay._label.gui_input.emit(native_press)
	var original_position: Vector2i = chat.chat_window.position
	var pointer_start: Vector2i = chat.overlay._desktop_start_mouse
	chat.overlay._update_desktop_pointer(pointer_start + Vector2i(1, 1), true)
	check(chat.chat_window.position == original_position, "Click jitter does not move the panel")
	chat.overlay._update_desktop_pointer(pointer_start + Vector2i(-80, -40), true)
	check(chat.chat_window.position == original_position + Vector2i(-80, -40), "Body drag moves one-to-one with cursor")
	for tick in range(10):
		chat.overlay._update_desktop_pointer(pointer_start + Vector2i(-80, -40), true)
	check(chat.chat_window.position == original_position + Vector2i(-80, -40), "Stationary cursor never accumulates movement")
	check(not chat.overlay._top_left_handle is Label and not chat.overlay._resize_handle is Label and not chat.overlay._drag_handle is Label, "Handles contain no visible text or corner glyphs")
	chat.overlay._update_desktop_pointer(pointer_start, false)
	check(not chat.overlay._dragging, "Release outside window ends desktop drag")
	chat.overlay._top_left_handle.gui_input.emit(native_press)
	var fixed_corner: Vector2i = chat.chat_window.position + chat.chat_window.size
	var original_size: Vector2i = chat.chat_window.size
	pointer_start = chat.overlay._desktop_start_mouse
	chat.overlay._update_desktop_pointer(pointer_start - Vector2i(60, 40), true)
	check(chat.chat_window.size == original_size + Vector2i(60, 40), "Top-left drag resizes actual native window")
	check(chat.chat_window.position + chat.chat_window.size == fixed_corner, "Top-left resize keeps opposite corner fixed")
	chat.overlay._update_desktop_pointer(pointer_start + Vector2i(9999, 9999), true)
	check(chat.chat_window.size == chat.chat_window.min_size, "Desktop resize stops at minimum size")
	chat.overlay._update_desktop_pointer(pointer_start, false)
	check(not chat.overlay._resizing, "Release ends desktop resizing")
	chat.chat_window.content_scale_factor = 2.0
	chat.overlay.set_panel_size(Vector2(320, 180))
	check(chat.chat_window.size == Vector2i(640, 360), "HiDPI window uses physical pixels")
	check(chat.overlay.size == Vector2(320, 180), "HiDPI content fits without clipping")
	chat.chat_window.content_scale_factor = 1.0
	chat.overlay.set_panel_size(Vector2(400, 260))
	for provider in ["kick", "twitch", "youtube"]:
		chat.client.disconnect_chat()
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

	var record := {"id": "kept", "author": "Viewer", "text": "Keep this message"}
	var snapshot := {"state": "connected", "settings": {"enabled": true}, "messages": [record]}
	chat.client.accept_snapshot(snapshot)
	check(chat.overlay.messages == ["Viewer: Keep this message"], "New message appears")
	for feature_only in [true, false]:
		if feature_only:
			demo.controller.set_feature_enabled(&"chat", false)
		else:
			demo.controller.set_enabled(false)
		check(not chat.overlay.visible, "Mode toggle hides overlay")
		check(chat.overlay.messages == ["Viewer: Keep this message"], "Hiding preserves history immediately")
		chat.client.accept_snapshot(snapshot)
		check(chat.overlay.messages == ["Viewer: Keep this message"], "Hidden polling preserves existing messages")
		if feature_only:
			demo.controller.set_feature_enabled(&"chat", true)
		else:
			demo.controller.set_enabled(true)
		check(chat.overlay.visible and chat.overlay.messages == ["Viewer: Keep this message"], "Re-enabling restores messages before next poll")
	demo.controller.set_feature_enabled(&"chat", false)
	snapshot.messages.append({"id": "hidden", "author": "New viewer", "text": "While hidden"})
	chat.client.accept_snapshot(snapshot)
	check(not chat.overlay.visible and chat.overlay.messages.size() == 2, "Messages continue updating while hidden")
	snapshot.messages.remove_at(0)
	chat.client.accept_snapshot(snapshot)
	demo.controller.set_feature_enabled(&"chat", true)
	check(chat.overlay.messages == ["New viewer: While hidden"], "Moderation still removes messages while hidden")
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
	# Real RichTextLabel layout: scrolling up survives repeated and new snapshots.
	var history: Array = []
	for n in range(25):
		history.append({"author": "Viewer", "text": "Message %d" % n})
	chat.overlay.set_panel_size(Vector2(320, 180))
	chat.overlay.replace_messages(history)
	await process_frame
	await process_frame
	var bar: VScrollBar = chat.overlay._label.get_v_scroll_bar()
	check(bar.max_value > bar.page, "Long chat exposes scrollable history")
	bar.value = 100
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = chat.overlay._label.get_global_rect().get_center()
	check(chat.overlay._scroll_input(wheel), "Wheel over messages is handled")
	check(bar.value < 100, "Mouse wheel moves history upward")
	var before_pan := bar.value
	var pan := InputEventPanGesture.new()
	pan.position = wheel.position
	pan.delta = Vector2(0, 1)
	check(chat.overlay._scroll_input(pan), "Trackpad gesture is handled")
	check(bar.value > before_pan, "Trackpad moves history downward")
	wheel.position = Vector2(-10, -10)
	check(not chat.overlay._scroll_input(wheel), "Scrolling outside chat is not intercepted")
	check(not chat.overlay._dragging, "Scrolling never starts panel dragging")
	bar.value = 50
	var reading_position := bar.value
	chat.overlay.replace_messages(history)
	await process_frame
	check(is_equal_approx(bar.value, reading_position), "Identical snapshots preserve scroll position")
	history.append({"author": "Viewer", "text": "New while reading"})
	chat.overlay.replace_messages(history)
	await process_frame
	await process_frame
	check(is_equal_approx(bar.value, reading_position), "New messages do not pull reader to bottom")
	bar.value = bar.max_value
	history.append({"author": "Viewer", "text": "Follow this"})
	chat.overlay.replace_messages(history)
	await process_frame
	await process_frame
	check(bar.value >= bar.max_value - bar.page - 2, "Readers at bottom follow new messages")
	chat.overlay.set_panel_size(Vector2(520, 340))
	check(chat.overlay.size == Vector2(520, 340), "Panel can grow")
	chat.overlay.set_panel_size(Vector2(280, 160))
	check(chat.overlay.size == Vector2(280, 160), "Panel can shrink")
	chat.overlay.set_panel_size(Vector2(1, 1))
	check(chat.overlay.size == Vector2(240, 140), "Resize respects usable minimum")
	chat.overlay.set_panel_size(Vector2(10000, 10000))
	check(chat.overlay.size.x <= chat.overlay.get_viewport_rect().size.x and chat.overlay.size.y <= chat.overlay.get_viewport_rect().size.y, "Panel remains inside viewport")
	chat.overlay.set_panel_size(Vector2(400, 260))
	check(not chat.connect_link("http://example.com/overlay#" + "a".repeat(43)), "Reject nonlocal HTTP")
	check(not chat.connect_link("https://user:pass@example.com/overlay#" + "a".repeat(43)), "Reject credentials in URL")
	check(chat.connect_link("http://localhost:8789/overlay#" + "a".repeat(43)), "Accept development link")
	check(chat.client._key == "a".repeat(43), "Extract bearer key correctly")
	chat.client.disconnect_chat()
	check(chat.client._key.is_empty(), "Disconnect drops capability")
	# Shared settings panel uses the same controller; unavailable features stay off.
	check(demo.settings_panel.feature_options[&"chat"].text == "In-game chat", "Platform-neutral chat caption")
	check(not demo.settings_panel.feature_options[&"chat"].disabled, "Chat available in common panel")
	check(demo.settings_panel.feature_options[&"audio"].disabled, "Audio not falsely advertised")
	check(demo.settings_panel.feature_options[&"privacy"].disabled, "Privacy not falsely advertised")
	demo.settings_panel.feature_options[&"chat"].button_pressed = false
	check(not chat.overlay.visible, "Common panel controls chat")
	check(not chat.chat_window.visible, "Common panel hides the desktop window")
	demo.settings_panel.feature_options[&"chat"].button_pressed = true
	paused = true
	await process_frame
	check(chat.client.can_process(), "Chat keeps polling while gameplay is paused")
	check(chat.settings.can_process(), "Chat settings remain usable while paused")
	paused = false
	# Removing and re-adding the component restores bindings without duplicate children.
	demo.remove_child(chat)
	demo.add_child(chat)
	await process_frame
	check(chat.overlay.visible, "Re-entry restores overlay controller")
	chat.client.accept_snapshot({"state": "connected", "settings": {"enabled": true}, "messages": []})
	chat.client.accept_snapshot({"state": "connected", "settings": {"enabled": true}, "messages": [{"id": "reentry", "author": "Test", "text": "Re-entry fixture"}]})
	check(chat.overlay.messages == ["Test: Re-entry fixture"], "Re-entry restores client subscription")
	check(chat.overlay.get_parent() == chat.chat_window, "Re-entry retains the same desktop window")
	check(chat.get_child_count() == 4, "Re-entry does not create duplicate components")
	demo.controller.queue_free()
	await process_frame
	check(not chat.overlay.visible and not chat.client._active, "Controller removal disables chat")
	check(not chat.chat_window.visible, "Controller removal hides native window")
	demo.queue_free()
	await process_frame
	var embedded = load("res://addons/streamer_mode/chat/streamer_chat.gd").new()
	embedded.desktop_overlay = false
	root.add_child(embedded)
	await process_frame
	check(not is_instance_valid(embedded.chat_window), "Host can retain in-game-only mode")
	check(embedded.overlay.get_parent() == embedded, "In-game fallback keeps the original canvas hierarchy")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	embedded.overlay._label.gui_input.emit(press)
	check(embedded.overlay._dragging, "Plain press on chat body begins moving without Alt or Option")
	embedded.overlay._top_left_handle.gui_input.emit(press)
	check(embedded.overlay._resizing and embedded.overlay._resize_from_top_left and not embedded.overlay._dragging, "Top-left corner resizes instead of moving")
	embedded.overlay._resize_handle.gui_input.emit(press)
	check(embedded.overlay._resizing and not embedded.overlay._resize_from_top_left, "Bottom-right resizing remains available")
	embedded.queue_free()
	await process_frame
	print("Godot chat checks: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
