extends SceneTree
## PrivacyEngine robustness under churn. Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_engine_churn.gd
##
## Covers scene-swap re-binding, multiple scan roots / SubViewports, round-robin
## scan batching + a stress pass, and "privacy_sensitive" group auto-registration.

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")

var failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 12345
	call_deferred("_run")


func _run() -> void:
	await _test_scene_swap_rebinds_the_scanner()
	await _test_multiple_scan_roots_and_to_screen_mapping()
	await _test_scan_batches_and_stays_correct_under_mutation()
	await _test_group_auto_registration()
	print("Privacy engine churn checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


# --- 1. scene swap ------------------------------------------------------

func _test_scene_swap_rebinds_the_scanner() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var engine := PrivacyEngine.new()
	root.add_child(engine)                 # persistent - survives the scene swap
	engine.setup(controller)
	controller.set_enabled(true)

	var scene_a := _scene_with_label("CODE-111")
	root.add_child(scene_a)
	current_scene = scene_a
	engine.set_scan_root(scene_a)
	engine.set_scanning(true)
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "Scanner masks the code in scene A")

	var scene_b := _scene_with_label("ROOM-222")
	root.add_child(scene_b)
	current_scene = scene_b
	await process_frame                    # _process picks up tree_changed
	await process_frame
	scene_a.free()
	await process_frame
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "After the swap the scanner masks scene B's code")
	var stats: Dictionary = engine.get_scan_stats()
	_check(int(stats["indexed"]) == 1, "Scanner re-indexed onto scene B (1 text node), not stale on A")

	engine.free()
	controller.free()
	scene_b.free()


# --- 2. multiple roots + SubViewport mapping --------------------------

func _test_multiple_scan_roots_and_to_screen_mapping() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var engine := PrivacyEngine.new()
	root.add_child(engine)
	engine.setup(controller)
	controller.set_enabled(true)

	var sv1 := SubViewport.new()
	sv1.size = Vector2i(400, 300)
	root.add_child(sv1)
	var root1 := _fill_control(sv1)
	_add_label(root1, "AAA-100", Vector2(10, 10))

	var sv2 := SubViewport.new()
	sv2.size = Vector2i(400, 300)
	root.add_child(sv2)
	var root2 := _fill_control(sv2)
	var l2 := _add_label(root2, "BBB-200", Vector2(20, 20))

	var offset := Vector2(600, 40)
	var to_screen := func(r: Rect2) -> Rect2: return Rect2(r.position + offset, r.size)
	engine.set_scan_roots([root1, {"node": root2, "to_screen": to_screen}])
	engine.set_scanning(true)
	engine.refresh()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 2, "Both SubViewport roots are scanned")

	var mask := _mask_over(engine, l2.get_global_rect().position + offset)
	_check(mask != null, "The mapped root's mask is placed at the to_screen-mapped position")

	engine.free()
	controller.free()
	sv1.free()
	sv2.free()


# --- 3. batching + stress -------------------------------------------

func _test_scan_batches_and_stays_correct_under_mutation() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var engine := PrivacyEngine.new()
	root.add_child(engine)
	engine.setup(controller)
	controller.set_enabled(true)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var labels: Array[Label] = []
	var matching := 0
	for i in 300:
		var is_secret := i % 2 == 0
		var l := _add_label(host, ("SECRET-%03d" % i) if is_secret else ("plain line %d" % i),
			Vector2(4 + (i % 20) * 40, 4 + (i / 20) * 18), Vector2(120, 14))
		labels.append(l)
		if is_secret:
			matching += 1

	engine.scan_node_budget = 50          # 300 nodes -> 6 batches per sweep
	engine.scan_interval = 0.0            # one batch every frame
	engine.set_scan_root(host)
	engine.set_scanning(true)

	for i in 24:                          # a few full sweeps
		await process_frame
	var stats: Dictionary = engine.get_scan_stats()
	_check(int(stats["indexed"]) == 300, "All 300 text nodes indexed")
	_check(engine.active_region_count() == matching, "Batched scan masks exactly the matching labels (%d)" % matching)

	# 50 mutation cycles: flip ~10 random labels each time, expect counts to track.
	var ok_cycles := 0
	for cycle in 50:
		for _n in 10:
			var idx := _rng.randi_range(0, labels.size() - 1)
			var l := labels[idx]
			var was_secret := l.text.begins_with("SECRET-")
			if was_secret:
				l.text = "plain line %d" % idx
				matching -= 1
			else:
				l.text = "SECRET-%03d" % idx
				matching += 1
		engine.refresh()                 # forced full sweep = deterministic
		await process_frame
		await process_frame
		if engine.active_region_count() == matching:
			ok_cycles += 1
	_check(ok_cycles == 50, "Counts stayed correct across 50 mutation cycles (%d/50)" % ok_cycles)

	# Worst case (forced full pass over 300 nodes) fits in a frame.
	var t0 := Time.get_ticks_usec()
	engine.refresh()
	var us := Time.get_ticks_usec() - t0
	print("BENCHMARK: 300-node forced scan: %d us; target < 16000 us" % us)
	if "--strict-performance" in OS.get_cmdline_user_args():
		_check(us < 16000, "A full 300-node scan pass takes < 16 ms (%d us)" % us)

	engine.free()
	controller.free()
	host.free()


# --- 4. group auto-registration ------------------------------------

func _test_group_auto_registration() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var tagged := _add_label(host, "just some words", Vector2(40, 40))
	tagged.add_to_group("privacy_sensitive")

	var engine := PrivacyEngine.new()
	host.add_child(engine)
	engine.setup(controller)
	controller.set_enabled(true)
	engine.refresh_group()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 1, "A group-tagged Control is masked even though its text matches no pattern")

	var late := Label.new()
	late.text = "another private box"
	late.position = Vector2(40, 90)
	late.size = Vector2(200, 24)
	late.add_to_group("privacy_sensitive")   # tagged before entering the tree
	host.add_child(late)
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 2, "A group-tagged Control added at runtime is auto-registered")

	# Re-tagging an already-mounted node needs an explicit refresh_group().
	var retag := _add_label(host, "third private", Vector2(40, 140))
	retag.add_to_group("privacy_sensitive")
	engine.refresh_group()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 3, "refresh_group() picks up a node tagged after mounting")

	late.free()
	await process_frame
	await process_frame
	_check(engine.active_region_count() == 2, "Freeing a group node clears its mask")

	engine.free()
	controller.free()
	host.free()


# --- helpers ------------------------------------------------------

func _scene_with_label(text: String) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_label(c, text, Vector2(50, 50))
	return c


func _fill_control(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	return c


func _add_label(parent: Node, text: String, pos: Vector2, sz := Vector2(200, 24)) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.custom_minimum_size = sz
	parent.add_child(l)
	return l


func _mask_over(engine, point: Vector2) -> Control:
	for child in engine.get_node("Surface").get_children():
		if child is PrivacyBlurMask and Rect2(child.position, child.size).has_point(point):
			return child
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
