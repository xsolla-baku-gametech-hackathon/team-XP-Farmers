extends SceneTree
## PrivacyControlPanel checks. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_control_panel.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")
const PrivacyControlPanel := preload("res://addons/streamer_mode/privacy/privacy_control_panel.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_close_button_closes_and_reports()
	await _test_open_resyncs_and_shows()
	await _test_panel_is_never_a_masking_target()
	await _test_pack_boxes_mirror_the_engine()
	print("Privacy control panel checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _build() -> Array:
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 700)
	root.add_child(sv)
	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	engine.setup(controller)
	var panel := PrivacyControlPanel.new()
	sv.add_child(panel)
	panel.setup(engine)
	return [sv, controller, engine, panel]


func _test_close_button_closes_and_reports() -> void:
	var b := _build()
	var panel = b[3]
	await process_frame

	var close_button := _find_button(panel, "Close")
	_check(close_button != null, "The panel has an X button")
	_check(close_button != null and close_button.text == "X", "The button is labelled X")

	var closed := []
	panel.close_requested.connect(func(): closed.append(true))
	panel.show()
	_check(panel.visible, "Panel starts visible for this check")

	close_button.pressed.emit()
	await process_frame
	_check(not panel.visible, "Pressing X hides the panel")
	_check(closed.size() == 1, "Pressing X emits close_requested so the host toggle can follow")
	b[0].free()


func _test_open_resyncs_and_shows() -> void:
	var b := _build()
	var engine = b[2]
	var panel = b[3]
	await process_frame
	panel.close()
	_check(not panel.visible, "close() hides the panel")

	# Change engine state while the panel is closed.
	engine.set_pack_enabled(PrivacyEngine.PACK_CONTACT, true)
	panel.open()
	await process_frame
	_check(panel.visible, "open() shows the panel again")
	var box := _find_check_box(panel, "contact")
	_check(box != null and box.button_pressed, "open() re-syncs the controls with the engine")
	b[0].free()


func _test_panel_is_never_a_masking_target() -> void:
	var b := _build()
	var controller = b[1]
	var engine = b[2]
	var panel = b[3]
	# A code-shaped string inside the panel must not be scanned.
	var bait := Label.new()
	bait.name = "bait"
	bait.text = "Room: GAME-2231"
	panel.add_child(bait)
	engine.set_scan_root(b[0])
	controller.set_enabled(true)
	engine.refresh()
	for i in 6:
		await process_frame
	_check(engine.active_region_count() == 0, "Text inside the panel is excluded from scanning")
	b[0].free()


func _test_pack_boxes_mirror_the_engine() -> void:
	var b := _build()
	var engine = b[2]
	var panel = b[3]
	await process_frame
	_check(_find_check_box(panel, "lobby_codes") != null, "A checkbox exists per pattern pack")
	var contact := _find_check_box(panel, "contact")
	_check(contact != null and not contact.button_pressed, "Opt-in packs start unchecked")
	if contact:
		contact.toggled.emit(true)
		_check(engine.is_pack_enabled(PrivacyEngine.PACK_CONTACT), "Ticking a pack box enables it on the engine")
	b[0].free()


## --- helpers -------------------------------------------------------------

func _find_button(node: Node, wanted_name: String) -> Button:
	if node is Button and node.name == wanted_name:
		return node
	for child in node.get_children():
		var found := _find_button(child, wanted_name)
		if found:
			return found
	return null


func _find_check_box(node: Node, label: String) -> CheckBox:
	if node is CheckBox and (node as CheckBox).text == label:
		return node
	for child in node.get_children():
		var found := _find_check_box(child, label)
		if found:
			return found
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
