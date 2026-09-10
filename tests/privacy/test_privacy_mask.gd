extends SceneTree
## Privacy mask component checks. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_mask.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyMask := preload("res://addons/streamer_mode/privacy/privacy_mask.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_visibility_follows_state()
	await _test_placement_and_drag_stay_on_screen()
	await _test_resize_stays_on_screen()
	await _test_opacity_controls_fill_alpha()
	await _test_escape_is_a_safe_panic_hide()
	await _test_real_mouse_events_reach_the_mask()
	await _test_viewport_resize_reclamps()
	print("Privacy mask checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _test_visibility_follows_state() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var mask := PrivacyMask.new()
	root.add_child(mask)
	mask.setup(controller)
	await process_frame
	_check(not mask.is_mask_visible(), "Mask hidden while Streamer Mode is off")

	controller.set_enabled(true)
	await process_frame
	await process_frame
	_check(mask.is_mask_visible(), "Mask shows when mode + privacy are both active")

	controller.set_feature_enabled(Controller.PRIVACY, false)
	await process_frame
	_check(not mask.is_mask_visible(), "Mask hides when privacy is opted out")

	controller.set_feature_enabled(Controller.PRIVACY, true)
	controller.set_enabled(false)
	await process_frame
	_check(not mask.is_mask_visible(), "Mask hides when the whole mode is switched off")

	mask.free()
	controller.free()


func _test_placement_and_drag_stay_on_screen() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var mask := PrivacyMask.new()
	root.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var surface: Control = mask.get_node("Surface")
	var region: PrivacyMaskRegion = mask.get_node("Surface/MaskRegion")
	var bounds := surface.size
	_check(bounds.x > 0.0 and bounds.y > 0.0, "Surface adopts the live viewport size, no hardcoded bounds")
	_check(_inside(region.get_rect(), bounds), "Default placement sits fully on screen")

	# Ask it to cover a rectangle that is mostly off the bottom-right corner.
	mask.cover_rect(Rect2(bounds.x - 40.0, bounds.y - 20.0, 500.0, 400.0))
	await process_frame
	await process_frame
	_check(_inside(region.get_rect(), bounds), "cover_rect() past the corner is clamped back on screen")

	# Drag hard toward negative infinity.
	_drag(region, Vector2(-9000.0, -9000.0))
	_check(region.position.x >= -0.5 and region.position.y >= -0.5, "Dragging toward -inf stops at the top-left corner")

	# Drag hard toward positive infinity.
	_drag(region, Vector2(9000.0, 9000.0))
	_check(_inside(region.get_rect(), bounds), "Dragging toward +inf stops at the bottom-right corner")

	mask.free()
	controller.free()


func _test_resize_stays_on_screen() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var mask := PrivacyMask.new()
	root.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var surface: Control = mask.get_node("Surface")
	var region: PrivacyMaskRegion = mask.get_node("Surface/MaskRegion")
	var bounds := surface.size
	region.set_region_rect(Rect2(bounds.x - 160.0, bounds.y - 120.0, 120.0, 90.0))

	# Grow the bottom-right handle far past the viewport edge.
	_resize(region, Vector2(9000.0, 9000.0))
	_check(_inside(region.get_rect(), bounds), "Resizing past the edge is clamped inside the viewport")

	# Shrink below the minimum.
	_resize(region, Vector2(-9000.0, -9000.0))
	_check(region.size.x >= PrivacyMaskRegion.MIN_SIZE.x - 0.5 and region.size.y >= PrivacyMaskRegion.MIN_SIZE.y - 0.5, "Resizing below the minimum is clamped up")

	mask.free()
	controller.free()


func _test_opacity_controls_fill_alpha() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var mask := PrivacyMask.new()
	root.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var region: PrivacyMaskRegion = mask.get_node("Surface/MaskRegion")
	var fill: ColorRect = region.get_node("Fill")

	region._on_opacity_slider_changed(0.2)
	_check(absf(fill.color.a - 0.2) < 0.01, "Opacity slider drives the fill alpha down")
	region._on_opacity_slider_changed(1.0)
	_check(absf(fill.color.a - 1.0) < 0.01, "Opacity slider drives the fill alpha up")
	region._on_opacity_slider_changed(0.0)
	_check(fill.color.a >= PrivacyMaskRegion.MIN_OPACITY - 0.001, "Opacity is floored so the mask never fully disappears")

	mask.free()
	controller.free()


func _test_escape_is_a_safe_panic_hide() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var mask := PrivacyMask.new()
	root.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame
	_check(mask.is_mask_visible(), "Mask is visible before Escape")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	mask._unhandled_key_input(esc)
	await process_frame
	_check(not mask.is_mask_visible(), "Escape hides the mask")
	_check(not controller.is_feature_selected(Controller.PRIVACY), "Escape clears the Privacy selection so the checkbox agrees")
	_check(controller.enabled, "Escape leaves Streamer Mode itself on")

	mask.free()
	controller.free()


func _test_real_mouse_events_reach_the_mask() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(900, 600)
	sub.handle_input_locally = true
	sub.gui_embed_subwindows = true
	root.add_child(sub)
	var controller := Controller.new()
	sub.add_child(controller)
	var mask := PrivacyMask.new()
	sub.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var region: PrivacyMaskRegion = mask.get_node("Surface/MaskRegion")
	region.set_region_rect(Rect2(120.0, 100.0, 220.0, 140.0))
	await process_frame
	var start := region.position
	var fill: Control = region.get_node("Fill")
	var grab := fill.global_position + fill.size * 0.5

	_push_button(sub, grab, true)
	_push_motion(sub, grab + Vector2(70.0, 50.0), Vector2(70.0, 50.0))
	await process_frame
	_push_button(sub, grab + Vector2(70.0, 50.0), false)
	await process_frame
	_check(region.position.is_equal_approx(start + Vector2(70.0, 50.0)), "Real mouse events routed through the viewport drag the mask")

	mask.free()
	controller.free()
	sub.free()


func _test_viewport_resize_reclamps() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(1000, 700)
	sub.handle_input_locally = true
	root.add_child(sub)
	var controller := Controller.new()
	sub.add_child(controller)
	var mask := PrivacyMask.new()
	sub.add_child(mask)
	mask.setup(controller)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var region: PrivacyMaskRegion = mask.get_node("Surface/MaskRegion")
	region.set_region_rect(Rect2(700.0, 500.0, 260.0, 170.0))
	await process_frame

	sub.size = Vector2i(480, 360)
	await process_frame
	await process_frame
	_check(_inside(region.get_rect(), mask.get_node("Surface").size), "Shrinking the viewport pulls the mask back into view")

	mask.free()
	controller.free()
	sub.free()


## --- helpers --------------------------------------------------------------

func _inside(rect: Rect2, bounds: Vector2) -> bool:
	return rect.position.x >= -0.5 \
		and rect.position.y >= -0.5 \
		and rect.position.x + rect.size.x <= bounds.x + 0.5 \
		and rect.position.y + rect.size.y <= bounds.y + 0.5


func _drag(region: PrivacyMaskRegion, delta: Vector2) -> void:
	region._on_fill_gui_input(_button(true))
	region._on_fill_gui_input(_motion(delta))
	region._on_fill_gui_input(_button(false))


func _resize(region: PrivacyMaskRegion, delta: Vector2) -> void:
	region._on_handle_gui_input(_button(true))
	region._on_handle_gui_input(_motion(delta))
	region._on_handle_gui_input(_button(false))


func _button(pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = relative
	return e


func _push_button(vp: SubViewport, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	vp.push_input(e, true)


func _push_motion(vp: SubViewport, at: Vector2, relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = relative
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e, true)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
