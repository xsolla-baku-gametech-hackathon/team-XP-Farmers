extends SceneTree
## Scanner accuracy against a labelled corpus, plus sub-rect precision.
## Run headless:
##   godot --headless --path . --script res://tests/privacy/test_privacy_scan_accuracy.gd

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const PrivacyEngine := preload("res://addons/streamer_mode/privacy/privacy_engine.gd")
const Corpus := preload("res://tests/privacy/fixtures/scan_corpus.gd")

const ROW_H := 26.0
const ROW_W := 700.0
const TARGET := 0.95

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_accuracy_all_packs()
	await _test_opt_in_packs_are_off_by_default()
	await _test_substring_precision()
	await _test_automation_is_on_after_setup()
	print("Privacy scan accuracy checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)


## Build one Label per corpus entry and return [viewport, controller, engine, labels].
func _build(all_packs: bool) -> Array:
	var entries: Array = Corpus.ENTRIES
	var sv := SubViewport.new()
	sv.size = Vector2i(int(ROW_W) + 80, int(ROW_H * entries.size()) + 80)
	root.add_child(sv)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)

	var labels: Array[Label] = []
	for i in entries.size():
		var l := Label.new()
		l.name = "corpus_%d" % i          # never contains a scan keyword
		l.text = entries[i]["text"]
		l.position = Vector2(20.0, 20.0 + ROW_H * i)
		l.size = Vector2(ROW_W, ROW_H - 4.0)
		l.custom_minimum_size = l.size
		host.add_child(l)
		labels.append(l)

	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	engine.setup(controller)
	if all_packs:
		for pack in engine.get_packs():
			engine.set_pack_enabled(pack, true)
	engine.set_scan_root(host)
	controller.set_enabled(true)
	return [sv, controller, engine, labels]


## Map instance_id -> true for every node that produced a scan region.
func _collect(engine, _labels: Array[Label]) -> Dictionary:
	var hits := {}
	engine.region_masked.connect(func(id: StringName, _rect: Rect2):
		var parts := String(id).split(":")
		if parts.size() >= 2 and parts[0] == "scan":
			hits[int(parts[1])] = true)
	engine.refresh()
	for i in 8:
		await process_frame
	return hits


func _test_accuracy_all_packs() -> void:
	var b := _build(true)
	var engine = b[2]
	var labels: Array[Label] = b[3]
	var hits: Dictionary = await _collect(engine, labels)

	var entries: Array = Corpus.ENTRIES
	var tp := 0
	var fp := 0
	var fn := 0
	var tn := 0
	var missed: Array = []
	var spurious: Array = []
	for i in entries.size():
		var expected: bool = entries[i]["should_match"]
		var got: bool = hits.has(labels[i].get_instance_id())
		if expected and got:
			tp += 1
		elif expected and not got:
			fn += 1
			missed.append(entries[i]["text"])
		elif not expected and got:
			fp += 1
			spurious.append(entries[i]["text"])
		else:
			tn += 1

	var precision := float(tp) / maxf(1.0, float(tp + fp))
	var recall := float(tp) / maxf(1.0, float(tp + fn))
	print("")
	print("  corpus size      : %d  (%d positive, %d negative)" % [entries.size(), tp + fn, tn + fp])
	print("  true positives   : %d" % tp)
	print("  false positives  : %d" % fp)
	print("  false negatives  : %d" % fn)
	print("  true negatives   : %d" % tn)
	print("  precision        : %.4f" % precision)
	print("  recall           : %.4f" % recall)
	if not missed.is_empty():
		print("  MISSED (false negatives):")
		for t in missed:
			print("    - %s" % t)
	if not spurious.is_empty():
		print("  SPURIOUS (false positives):")
		for t in spurious:
			print("    - %s" % t)
	print("")

	_check(precision >= TARGET, "Precision >= %.2f (got %.4f)" % [TARGET, precision])
	_check(recall >= TARGET, "Recall >= %.2f (got %.4f)" % [TARGET, recall])
	b[0].free()


func _test_opt_in_packs_are_off_by_default() -> void:
	var b := _build(false)
	var engine = b[2]
	var labels: Array[Label] = b[3]

	for pack in Corpus.OPT_IN_PACKS:
		_check(not engine.is_pack_enabled(StringName(pack)), "Pack '%s' is off by default" % pack)
	_check(engine.is_pack_enabled(PrivacyEngine.PACK_LOBBY_CODES), "Pack 'lobby_codes' is on by default")
	_check(engine.is_pack_enabled(PrivacyEngine.PACK_NETWORK), "Pack 'network' is on by default")

	var hits: Dictionary = await _collect(engine, labels)
	var entries: Array = Corpus.ENTRIES
	var opt_in_leaks := 0
	var overlaps: Array = []
	var default_hits := 0
	var default_total := 0
	for i in entries.size():
		if not entries[i]["should_match"]:
			continue
		var got: bool = hits.has(labels[i].get_instance_id())
		if Corpus.OPT_IN_PACKS.has(entries[i]["pack"]):
			if not got:
				continue
			# Some opt-in strings contain a code-shaped run that a default pack
			# legitimately catches. Those are declared in the corpus.
			if entries[i].get("default_overlap", false):
				overlaps.append(entries[i]["text"])
			else:
				opt_in_leaks += 1
				printerr("  LEAK: %s" % entries[i]["text"])
		else:
			default_total += 1
			if got:
				default_hits += 1
	for t in overlaps:
		print("  note: default packs also catch part of an opt-in string: %s" % t)
	_check(opt_in_leaks == 0, "No contact/identifiers entry matches while those packs are off (%d leaked)" % opt_in_leaks)
	_check(default_hits == default_total, "Every lobby_codes/network positive still matches (%d/%d)" % [default_hits, default_total])

	engine.set_pack_enabled(PrivacyEngine.PACK_CONTACT, true)
	_check(engine.is_pack_enabled(PrivacyEngine.PACK_CONTACT), "set_pack_enabled turns a pack on")
	b[0].free()


func _test_substring_precision() -> void:
	var cases := [
		{"text": "Player: xXx_Shadow_xXx  |  Room: GAME-2231", "secret": "GAME-2231"},
		{"text": "MATCH SERVER   203.0.113.42:7777", "secret": "203.0.113.42:7777"},
		{"text": "Squad: Alpha  -  Invite: pk39Zt", "secret": "pk39Zt"},
	]
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 400)
	root.add_child(sv)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)

	var labels: Array[Label] = []
	for i in cases.size():
		var l := Label.new()
		l.name = "precise_%d" % i
		l.text = cases[i]["text"]
		l.position = Vector2(40.0, 40.0 + 60.0 * i)
		l.size = Vector2(760.0, 30.0)
		l.custom_minimum_size = l.size
		host.add_child(l)
		labels.append(l)

	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	engine.setup(controller)
	engine.set_scan_root(host)
	controller.set_enabled(true)

	var rects := {}
	engine.region_masked.connect(func(id: StringName, rect: Rect2):
		var parts := String(id).split(":")
		if parts.size() >= 2 and parts[0] == "scan":
			rects[int(parts[1])] = rect)
	engine.refresh()
	for i in 8:
		await process_frame

	var margin: float = engine.substring_margin
	for i in cases.size():
		var l := labels[i]
		var secret: String = cases[i]["secret"]
		var idx: int = l.text.find(secret)
		var font := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var prefix_w: float = font.get_string_size(l.text.substr(0, idx), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var secret_w: float = font.get_string_size(secret, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var full_w: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

		var got: bool = rects.has(l.get_instance_id())
		_check(got, "Mixed line %d produced a mask" % i)
		if not got:
			continue
		var rect: Rect2 = rects[l.get_instance_id()]
		var expect_w := secret_w + margin * 2.0
		var expect_x := l.global_position.x + prefix_w - margin
		_check(absf(rect.size.x - expect_w) <= 6.0,
			"Mask width matches the substring, not the label (%.1f vs %.1f, label text is %.1f wide)" % [rect.size.x, expect_w, full_w])
		_check(absf(rect.position.x - expect_x) <= 6.0,
			"Mask starts at the substring offset, not x=0 (%.1f vs %.1f)" % [rect.position.x, expect_x])
		_check(rect.position.x > l.global_position.x + 4.0,
			"Mask is inset from the label's left edge")
		_check(rect.size.x < full_w * 0.9,
			"Mask is narrower than the whole line (%.1f < %.1f)" % [rect.size.x, full_w * 0.9])

	sv.free()


func _test_automation_is_on_after_setup() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(600, 300)
	root.add_child(sv)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.add_child(host)
	var l := Label.new()
	l.name = "auto_probe"
	l.text = "Room: GAME-2231"
	l.position = Vector2(30, 30)
	l.size = Vector2(300, 24)
	l.custom_minimum_size = l.size
	host.add_child(l)

	var controller := Controller.new()
	sv.add_child(controller)
	var engine := PrivacyEngine.new()
	sv.add_child(engine)
	# Only setup() and a scan root - no set_scanning() call anywhere.
	engine.setup(controller)
	_check(engine.is_scanning(), "setup() starts the scanner; automation is the default")
	engine.set_scan_root(host)
	controller.set_enabled(true)
	for i in 8:
		await process_frame
	_check(engine.active_region_count() >= 1, "The code is masked without any extra opt-in step")

	var off := PrivacyEngine.new()
	off.auto_scan_on_setup = false
	sv.add_child(off)
	off.setup(controller)
	_check(not off.is_scanning(), "auto_scan_on_setup = false still allows a manual-only host")
	sv.free()


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: %s" % description)
	else:
		print("  ok: %s" % description)
