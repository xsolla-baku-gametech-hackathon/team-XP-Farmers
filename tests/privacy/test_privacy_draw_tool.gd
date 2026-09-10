extends SceneTree
## PrivacyDrawTool checks. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_draw_tool.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")
const PrivacyDrawTool := preload("res://addons/streamer_mode/privacy/privacy_draw_tool.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_drag_creates_a_blurred_region()
	await _test_tiny_drag_creates_nothing()
	await _test_region_can_be_moved_and_the_blur_follows()
	await _test_region_can_be_resized_and_stays_on_screen()
	await _test_delete_and_clear()
	await _test_arming_gates_the_catcher_and_escape_cancels()
	await _test_hiding_handles_stops_blocking_the_game()
	await _test_real_mouse_events_draw_a_region()
	print("Privacy draw tool checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _build() -> Array:
	var sv := SubViewport.new()
	sv.size = Vector2i(1000, 700)
	sv.handle_input_locally = true
	root.add_child(sv)
	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	engine.setup(controller)
	var tool_node := PrivacyDrawTool.new()
	sv.add_child(tool_node)
	tool_node.setup(engine)
	return [sv, controller, engine, tool_node]


## Drive the catcher the way the mouse would.
func _draw_box(tool_node, from: Vector2, to: Vector2) -> void:
	tool_node.set_armed(true)
	tool_node._on_catcher_gui_input(_button(true, from))
	tool_node._on_catcher_gui_input(_motion(to))
	tool_node._on_catcher_gui_input(_button(false, to))


func _test_drag_creates_a_blurred_region() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var tool_node = b[3]
	controller.set_enabled(true)
	await process_frame

	_draw_box(tool_node, Vector2(120, 140), Vector2(420, 300))
	_check(tool_node.get_region_count() == 1, "Dragging a box creates one region")
	var drawn: Rect2 = tool_node.get_region_rects()[0]
	_check(_rect_near(drawn, Rect2(120, 140, 300, 160)), "The region matches the dragged rectangle")
	_check(not tool_node.is_armed(), "The tool disarms itself after one region")

	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "PrivacyEngine blurs the drawn region")
	var mask := _first_mask(engine)
	_check(mask != null and _rect_near(Rect2(mask.position, mask.size), drawn, 1.5),
		"The blur lands exactly on what was drawn")
	b[0].free()


func _test_tiny_drag_creates_nothing() -> void:
	var b := _build()
	var tool_node = b[3]
	_draw_box(tool_node, Vector2(200, 200), Vector2(206, 204))
	_check(tool_node.get_region_count() == 0, "A stray click or tiny drag creates no region")
	b[0].free()


func _test_region_can_be_moved_and_the_blur_follows() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var tool_node = b[3]
	controller.set_enabled(true)
	_draw_box(tool_node, Vector2(100, 100), Vector2(340, 260))
	await process_frame
	await process_frame

	var region := _first_region(tool_node)
	# Snap instead of ease so the assertion does not depend on frame timing.
	var mask := _first_mask(engine)
	mask.move_speed = 0.0

	var before: Vector2 = region.position
	region._gui_input(_button(true, Vector2.ZERO))
	region._gui_input(_motion_rel(Vector2(150, 90)))
	region._gui_input(_button(false, Vector2.ZERO))
	_check(region.position.is_equal_approx(before + Vector2(150, 90)), "Dragging the frame moves the region")

	await process_frame
	await process_frame
	_check(_rect_near(Rect2(mask.position, mask.size), Rect2(region.position, region.size), 1.5),
		"The blur follows the region as it moves")

	# Shove it hard past the corner: it must stay on screen.
	region._gui_input(_button(true, Vector2.ZERO))
	region._gui_input(_motion_rel(Vector2(9000, 9000)))
	region._gui_input(_button(false, Vector2.ZERO))
	var bounds: Vector2 = tool_node.get_node("Surface").size
	_check(region.position.x + region.size.x <= bounds.x + 0.5
		and region.position.y + region.size.y <= bounds.y + 0.5, "A region cannot be dragged off screen")
	b[0].free()


func _test_region_can_be_resized_and_stays_on_screen() -> void:
	var b := _build()
	var controller = b[1]
	var tool_node = b[3]
	controller.set_enabled(true)
	_draw_box(tool_node, Vector2(80, 80), Vector2(300, 220))
	await process_frame
	var region := _first_region(tool_node)
	var handle: Control = region.get_node("Resize")

	region._on_handle_gui_input(_button(true, Vector2.ZERO))
	region._on_handle_gui_input(_motion_rel(Vector2(120, 60)))
	region._on_handle_gui_input(_button(false, Vector2.ZERO))
	_check(region.size.is_equal_approx(Vector2(340, 200)), "The corner handle resizes the region")

	region._on_handle_gui_input(_button(true, Vector2.ZERO))
	region._on_handle_gui_input(_motion_rel(Vector2(9000, 9000)))
	region._on_handle_gui_input(_button(false, Vector2.ZERO))
	var bounds: Vector2 = tool_node.get_node("Surface").size
	_check(region.position.x + region.size.x <= bounds.x + 0.5, "Resizing past the edge is clamped")

	region._on_handle_gui_input(_button(true, Vector2.ZERO))
	region._on_handle_gui_input(_motion_rel(Vector2(-9000, -9000)))
	region._on_handle_gui_input(_button(false, Vector2.ZERO))
	_check(region.size.x >= PrivacyDrawRegion.MIN_SIZE.x - 0.5
		and region.size.y >= PrivacyDrawRegion.MIN_SIZE.y - 0.5, "Resizing below the minimum is clamped up")
	_check(handle != null, "The resize handle exists")
	b[0].free()


func _test_delete_and_clear() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var tool_node = b[3]
	controller.set_enabled(true)
	_draw_box(tool_node, Vector2(60, 60), Vector2(220, 180))
	_draw_box(tool_node, Vector2(400, 300), Vector2(600, 460))
	await process_frame
	await process_frame
	_check(tool_node.get_region_count() == 2, "Two regions drawn")
	_check(engine.active_region_count() == 2, "Both are blurred")

	var region := _first_region(tool_node)
	region.remove_requested.emit()
	await process_frame
	await process_frame
	_check(tool_node.get_region_count() == 1, "The x button removes one region")
	_check(engine.active_region_count() == 1, "Its blur is gone too")

	tool_node.clear_regions()
	await process_frame
	await process_frame
	_check(tool_node.get_region_count() == 0, "Clear removes the rest")
	_check(engine.active_region_count() == 0, "No blur is left behind")
	b[0].free()


func _test_arming_gates_the_catcher_and_escape_cancels() -> void:
	var b := _build()
	var tool_node = b[3]
	var catcher: Control = tool_node.get_node("Surface/DrawCatcher")
	_check(catcher.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Disarmed, the catcher ignores the mouse")

	var seen: Array = []
	tool_node.armed_changed.connect(func(on): seen.append(on))
	tool_node.set_armed(true)
	_check(catcher.mouse_filter == Control.MOUSE_FILTER_STOP, "Armed, the catcher takes the mouse")
	_check(seen == [true], "armed_changed fired")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	tool_node._unhandled_key_input(esc)
	_check(not tool_node.is_armed(), "Escape cancels arming")
	_check(catcher.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The catcher lets the mouse through again")
	_check(tool_node.get_region_count() == 0, "Cancelling draws nothing")
	b[0].free()


func _test_hiding_handles_stops_blocking_the_game() -> void:
	var b := _build()
	var controller = b[1]
	var tool_node = b[3]
	controller.set_enabled(true)
	_draw_box(tool_node, Vector2(100, 100), Vector2(300, 240))
	await process_frame
	var region := _first_region(tool_node)
	_check(region.mouse_filter == Control.MOUSE_FILTER_STOP, "With handles on, the frame is grabbable")

	tool_node.show_chrome = false
	await process_frame
	_check(region.mouse_filter == Control.MOUSE_FILTER_IGNORE, "With handles off, clicks pass through to the game")
	_check(tool_node.get_region_count() == 1, "Hiding handles keeps the region and its blur")

	tool_node.show_chrome = true
	await process_frame
	_check(region.mouse_filter == Control.MOUSE_FILTER_STOP, "Handles come back")
	b[0].free()


func _test_real_mouse_events_draw_a_region() -> void:
	var b := _build()
	var sv: SubViewport = b[0]
	var controller = b[1]
	var tool_node = b[3]
	controller.set_enabled(true)
	tool_node.set_armed(true)
	await process_frame

	_push_button(sv, Vector2(200, 180), true)
	_push_motion(sv, Vector2(500, 380))
	_push_button(sv, Vector2(500, 380), false)
	await process_frame
	_check(tool_node.get_region_count() == 1, "Real mouse events routed through the viewport draw a region")
	if tool_node.get_region_count() == 1:
		_check(_rect_near(tool_node.get_region_rects()[0], Rect2(200, 180, 300, 200), 2.0),
			"The region from real events matches the dragged rectangle")
	b[0].free()


## --- helpers --------------------------------------------------------------

func _first_region(tool_node) -> PrivacyDrawRegion:
	for child in tool_node.get_node("Surface").get_children():
		if child is PrivacyDrawRegion:
			return child
	return null


func _first_mask(engine) -> Control:
	for child in engine.get_node("Surface").get_children():
		if child is PrivacyBlurMask and not child.is_dismissing():
			return child
	return null


func _button(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	return e


func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	return e


func _motion_rel(rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	return e


func _push_button(vp: SubViewport, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	vp.push_input(e, true)


func _push_motion(vp: SubViewport, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e, true)


func _rect_near(a: Rect2, b: Rect2, eps := 1.0) -> bool:
	return absf(a.position.x - b.position.x) <= eps \
		and absf(a.position.y - b.position.y) <= eps \
		and absf(a.size.x - b.size.x) <= eps \
		and absf(a.size.y - b.size.y) <= eps


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
