extends SceneTree
## PrivacyEngine checks. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_engine.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_feature_gating()
	await _test_registered_node_is_masked_and_follows()
	await _test_hidden_node_releases_but_registration_persists()
	await _test_scanner_matches_code_and_ip_only()
	await _test_scanner_respects_allow_list()
	await _test_scanner_dedupes_against_registered_region()
	await _test_scanner_clears_when_text_stops_matching()
	print("Privacy engine checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


func _make(host: Node) -> Array:
	var controller := Controller.new()
	host.add_child(controller)
	var engine := PrivacyEngine.new()
	host.add_child(engine)
	engine.setup(controller)
	return [controller, engine]


func _viewport() -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(1000, 700)
	sv.handle_input_locally = true
	root.add_child(sv)
	return sv


func _label(parent: Node, txt: String, pos: Vector2, sz := Vector2(180, 40)) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = sz
	l.custom_minimum_size = sz
	parent.add_child(l)
	return l


func _test_feature_gating() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var target := _label(sv, "watch me", Vector2(100, 100))
	engine.register_node(&"t", target)
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 0, "Nothing is masked while Streamer Mode is off")

	controller.set_enabled(true)
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Enabling mode masks the registered region")

	controller.set_enabled(false)
	await process_frame
	_check(engine.active_region_count() == 0, "Disabling mode clears the masks")

	sv.free()


func _test_registered_node_is_masked_and_follows() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var target := _label(sv, "secret card", Vector2(120, 140), Vector2(220, 90))
	engine.register_node(&"card", target)
	controller.set_enabled(true)
	await process_frame
	await process_frame

	var mask := _first_mask(engine)
	_check(mask != null, "A blur mask was spawned for the registered node")
	var expected := target.get_global_rect().grow(engine.target_margin)
	_check(_rect_near(Rect2(mask.position, mask.size), expected), "Mask snaps onto the node's global rect plus margin")

	target.position = Vector2(500, 360)
	target.size = Vector2(300, 120)
	# move_speed eases; let it converge.
	for i in 40:
		await process_frame
	expected = target.get_global_rect().grow(engine.target_margin)
	_check(_rect_near(Rect2(mask.position, mask.size), expected, 2.0), "Mask follows the node when it moves and resizes")

	sv.free()


func _test_hidden_node_releases_but_registration_persists() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var target := _label(sv, "peekaboo", Vector2(100, 100))
	engine.register_node(&"t", target)
	controller.set_enabled(true)
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Masked while visible")

	target.visible = false
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 0, "Mask released when the node is hidden")

	target.visible = true
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Mask returns when the node is shown again")

	sv.free()


func _test_scanner_matches_code_and_ip_only() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)
	_label(host, "GAME-2231", Vector2(40, 40))
	_label(host, "hello world", Vector2(40, 120))
	_label(host, "relay 10.0.0.5:9999", Vector2(40, 200))
	var field := LineEdit.new()
	field.text = "nothing special"
	field.position = Vector2(40, 280)
	field.size = Vector2(200, 30)
	host.add_child(field)

	engine.set_scan_root(host)
	engine.set_scanning(true)
	controller.set_enabled(true)
	await process_frame
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 2, "Scanner masks the code and the IP, not the plain text")

	sv.free()


func _test_scanner_respects_allow_list() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)
	_label(host, "SCORE-0000", Vector2(40, 40))

	engine.allow_text("SCORE-0000")
	engine.set_scan_root(host)
	engine.set_scanning(true)
	controller.set_enabled(true)
	await process_frame
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 0, "Allow-listed text is never masked")

	sv.free()


func _test_scanner_dedupes_against_registered_region() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var panel := Control.new()
	panel.position = Vector2(60, 60)
	panel.size = Vector2(400, 200)
	sv.add_child(panel)
	_label(panel, "ROOM-9931", Vector2(20, 20))

	engine.register_node(&"panel", panel)
	engine.set_scan_root(sv)
	engine.set_scanning(true)
	controller.set_enabled(true)
	await process_frame
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Scan match inside a registered region does not add a second mask")

	sv.free()


func _test_scanner_clears_when_text_stops_matching() -> void:
	var sv := _viewport()
	var pair := _make(sv)
	var controller: Node = pair[0]
	var engine = pair[1]
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)
	var code := _label(host, "LOBBY-8080", Vector2(40, 40))

	engine.set_scan_root(host)
	engine.set_scanning(true)
	controller.set_enabled(true)
	await process_frame
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Scanner masks the lobby code")

	code.text = "in match"
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 0, "Mask clears once the text no longer matches")

	sv.free()


## --- helpers --------------------------------------------------------------

func _first_mask(engine) -> Control:
	var surface: Node = engine.get_node("Surface")
	for child in surface.get_children():
		if child is PrivacyBlurMask:
			return child
	return null


func _rect_near(a: Rect2, b: Rect2, eps := 1.0) -> bool:
	return absf(a.position.x - b.position.x) <= eps \
		and absf(a.position.y - b.position.y) <= eps \
		and absf(a.size.x - b.size.x) <= eps \
		and absf(a.size.y - b.size.y) <= eps


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
