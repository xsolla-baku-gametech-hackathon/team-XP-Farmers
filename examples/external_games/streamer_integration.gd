extends CanvasLayer
## Host glue. F8 avoids taking over the original game's Escape/pause action.
var controller: StreamerModeController
var audio: StreamSafeMusicBus
var menu: PopupPanel
var panel: StreamerModePanel
var _was_paused := false
var _opened := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	controller = StreamerModeController.new()
	add_child(controller)
	audio = StreamSafeMusicBus.new()
	audio.replacement_bus = &"Music"
	audio.replacement_stream = _loop("res://streamer_integration/quiet_orbit.wav")
	audio.bind(controller)
	add_child(audio)
	menu = preload("res://addons/streamer_mode/ui/streamer_settings_menu.gd").new()
	add_child(menu)
	panel = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn").instantiate()
	panel.bind(controller)
	panel.set_feature_available(&"audio", audio.is_configured())
	panel.set_feature_status(&"audio", "Original music replaced; sound effects preserved.")
	menu.attach_panel(panel)
	var tracks := OptionButton.new()
	tracks.add_item("Quiet Orbit")
	tracks.add_item("Neon Run")
	tracks.add_item("Silence")
	tracks.item_selected.connect(func(index: int):
		var stream: AudioStream = null
		if index < 2:
			stream = _loop("res://streamer_integration/" + ["quiet_orbit.wav", "neon_run.wav"][index])
		audio.set_replacement(stream))
	menu.content.add_child(tracks)
	menu.content.move_child(tracks, 2)
	menu.visibility_changed.connect(_menu_visibility)
	# No fake private data: these single-player hosts have no lobby codes.
	panel.set_feature_status(&"privacy", "No private fields registered in this host.")
	panel.set_feature_status(&"chat", "Chat integration reviewed separately.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		menu.set_open(not menu.visible)
		get_viewport().set_input_as_handled()

func _menu_visibility() -> void:
	if menu.visible and not _opened:
		_was_paused = get_tree().paused
		_opened = true
		get_tree().paused = true
	elif not menu.visible and _opened:
		get_tree().paused = _was_paused
		_opened = false

func _loop(path: String) -> AudioStream:
	var stream := load(path).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	return stream
