extends SceneTree
## PrivacyCopyField checks. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_copy_field.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")
const PrivacyCopyField := preload("res://addons/streamer_mode/privacy/privacy_copy_field.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_masked_but_copy_returns_real_value()
	await _test_copy_works_with_streamer_mode_off()
	await _test_copy_button_sits_outside_the_masked_rect()
	await _test_value_change_is_reflected_in_copy()
	print("Privacy copy field checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _build() -> Array:
	var sv := SubViewport.new()
	sv.size = Vector2i(1000, 700)
	root.add_child(sv)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)
	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	engine.setup(controller)
	var field := PrivacyCopyField.new()
	field.position = Vector2(120, 120)
	field.size = Vector2(320, 48)
	host.add_child(field)
	return [sv, controller, engine, field]


func _test_masked_but_copy_returns_real_value() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var field: PrivacyCopyField = b[3]
	field.value = "ABCD-1234"
	field.bind(engine, &"code")
	controller.set_enabled(true)
	await process_frame
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "The value area is masked while Streamer Mode is on")

	var got: Array = []
	field.copied.connect(func(v): got.append(v))
	field.copy()
	_check(got.size() == 1 and got[0] == "ABCD-1234", "copied signal carries the real value while masked")
	_check_clipboard("ABCD-1234", "clipboard holds the real value, not the blurred text")

	b[0].free()


func _test_copy_works_with_streamer_mode_off() -> void:
	var b := _build()
	var engine = b[2]
	var field: PrivacyCopyField = b[3]
	field.value = "ZZ-9090"
	field.bind(engine, &"code")
	# Streamer Mode never enabled.
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 0, "Nothing is masked while Streamer Mode is off")
	var got: Array = []
	field.copied.connect(func(v): got.append(v))
	field.copy()
	_check(got.size() == 1 and got[0] == "ZZ-9090", "copied signal fires with the value when mode is off")
	_check_clipboard("ZZ-9090", "clipboard holds the value when mode is off")
	_check(field.is_toast_showing(), "Copy shows the Copied! toast state")
	b[0].free()


func _test_copy_button_sits_outside_the_masked_rect() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var field: PrivacyCopyField = b[3]
	field.value = "EFGH-5678"
	field.bind(engine, &"code")
	controller.set_enabled(true)
	await process_frame
	await process_frame
	await process_frame
	var mask := _first_mask(engine)
	_check(mask != null, "A mask was spawned")
	var mask_rect := Rect2(mask.position, mask.size)
	var button := _find_button(field)
	_check(button != null, "Copy button exists")
	var button_rect := button.get_global_rect()
	_check(not mask_rect.intersects(button_rect), "The Copy button is not inside the blurred rect")
	_check(mask_rect.intersects(field.get_mask_target().get_global_rect()), "The mask does cover the value")
	b[0].free()


func _test_value_change_is_reflected_in_copy() -> void:
	var b := _build()
	var field: PrivacyCopyField = b[3]
	field.value = "FIRST-111"
	field.value = "SECOND-222"
	var got: Array = []
	field.copied.connect(func(v): got.append(v))
	field.copy()
	_check(got[0] == "SECOND-222", "copy uses the current underlying value after it changes")
	b[0].free()


func _first_mask(engine) -> Control:
	for child in engine.get_node("Surface").get_children():
		if child is PrivacyBlurMask:
			return child
	return null


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var deep := _find_button(child)
		if deep:
			return deep
	return null


func _check_clipboard(expected: String, description: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		print("  skip (no clipboard on this display server): %s" % description)
		return
	_check(DisplayServer.clipboard_get() == expected, description)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
