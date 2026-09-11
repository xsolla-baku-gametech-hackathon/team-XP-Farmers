extends CanvasLayer
## Persistent integration; F8 leaves the game's Escape binding intact.
var controller: StreamerModeController
var audio: StreamSafeMusicBus
var chat: StreamerChat
var privacy: PrivacyEngine
var draw: PrivacyDrawTool
var menu: PopupPanel
var panel: StreamerModePanel
var actions: VBoxContainer
var _was_paused := false
var _opened := false
var _drawing_mode := false
var _draw_was_paused := false
var _scene: Node
var _edit_handles: CheckButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	controller = StreamerModeController.new()
	add_child(controller)
	controller.set_feature_enabled(&"chat", false)
	audio = StreamSafeMusicBus.new()
	audio.replacement_bus = &"Music"
	audio.replacement_stream = _loop("res://streamer_integration/quiet_orbit.wav")
	audio.bind(controller)
	add_child(audio)
	chat = StreamerChat.new()
	chat.bind(controller)
	add_child(chat)
	privacy = PrivacyEngine.new()
	add_child(privacy)
	privacy.setup(controller)
	privacy.set_scan_root(get_tree().root)
	privacy.exclude_subtree(self)
	privacy.scan_node_budget = 50
	draw = PrivacyDrawTool.new()
	add_child(draw)
	draw.setup(privacy)
	draw.show_chrome = false
	draw.armed_changed.connect(_draw_armed)
	menu = preload("res://addons/streamer_mode/ui/streamer_settings_menu.gd").new()
	add_child(menu)
	panel = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn").instantiate()
	panel.bind(controller)
	panel.set_feature_available(&"audio", audio.is_configured())
	panel.set_feature_available(&"privacy", true)
	panel.set_feature_available(&"chat", true)
	panel.set_feature_status(&"audio", "Original music replaced; sound effects preserved.")
	panel.set_feature_status(&"privacy", "Scans game text; draw a region for other content.")
	menu.attach_panel(panel)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	menu.content.add_child(actions)
	menu.content.move_child(actions, 2)
	var tracks := OptionButton.new()
	for title in ["Quiet Orbit", "Neon Run", "Silence"]:
		tracks.add_item(title)
	tracks.item_selected.connect(func(index: int):
		var stream: AudioStream = null
		if index < 2:
			stream = _loop("res://streamer_integration/" + ["quiet_orbit.wav", "neon_run.wav"][index])
		audio.set_replacement(stream))
	actions.add_child(tracks)
	_button("Connect Kick / Chat settings", open_chat_settings)
	_button("Draw private area", begin_private_area)
	_edit_handles = CheckButton.new()
	_edit_handles.text = "Edit mask positions / sizes"
	_edit_handles.toggled.connect(func(enabled: bool): draw.show_chrome = enabled)
	actions.add_child(_edit_handles)
	_button("Clear drawn areas", draw.clear_regions)
	var scanner := CheckButton.new()
	scanner.text = "Automatically scan game text"
	scanner.button_pressed = true
	scanner.toggled.connect(privacy.set_scanning)
	actions.add_child(scanner)
	var note := Label.new()
	note.text = "Manual areas clear when the game scene changes.\nChat history is not scanned for private information."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(note)
	chat.settings.reparent(menu.content)
	chat.settings.close_requested.connect(func(): menu.set_open(false))
	chat.status_changed.connect(func(_state: String, detail: String): panel.set_feature_status(&"chat", detail))
	panel.set_feature_status(&"chat", chat.get_status())
	menu.visibility_changed.connect(_menu_visibility)

func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	actions.add_child(button)

func open_chat_settings() -> void:
	if not menu.visible:
		menu.set_open(true)
	panel.hide()
	actions.hide()
	menu.resume_button.hide()
	chat.open_settings()

func _main_page() -> void:
	chat.settings.hide()
	panel.show()
	actions.show()
	menu.resume_button.show()

func begin_private_area() -> void:
	controller.set_feature_enabled(&"privacy", true)
	controller.set_enabled(true)
	_draw_was_paused = _was_paused if _opened else get_tree().paused
	menu.set_open(false)
	_drawing_mode = true
	get_tree().paused = true
	draw.set_armed(true)

func _draw_armed(armed: bool) -> void:
	if not armed and _drawing_mode:
		_drawing_mode = false
		get_tree().paused = _draw_was_paused
		draw.show_chrome = false
		_edit_handles.set_pressed_no_signal(false)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if draw.is_armed():
			draw.set_armed(false)
		else:
			menu.set_open(not menu.visible)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if get_tree().current_scene != _scene:
		_scene = get_tree().current_scene
		draw.clear_regions()

func _menu_visibility() -> void:
	if menu.visible and not _opened:
		_main_page()
		_was_paused = get_tree().paused
		_opened = true
		get_tree().paused = true
	elif not menu.visible and _opened:
		get_tree().paused = _was_paused
		_opened = false
		_main_page()

func _loop(path: String) -> AudioStream:
	var stream := load(path).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	return stream
