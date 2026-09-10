extends Control

var cells: Array[bool] = []
var buttons: Array[Button] = []
var moves: int = 0
var progress_label: Label
var panel: StreamerModePanel
var settings_menu: PopupPanel
@onready var integration: Node = $Integration


func _ready() -> void:
	panel = $SettingsPanel
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 22)
	margin.add_child(page)
	page.add_child(_label("A LITTLE PUZZLE ABOUT CONNECTIONS", 12, Color("57745f")))
	page.add_child(_label("Signal Garden", 38, Color("1e3d32")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	var game := VBoxContainer.new()
	game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.add_theme_constant_override("separation", 18)
	row.add_child(game)
	var instructions := _label("Light every tile. Each click flips a tile and its neighbours.", 16, Color("456150"))
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.add_child(instructions)
	progress_label = _label("", 14, Color("456150"))
	game.add_child(progress_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	game.add_child(grid)
	for index in range(16):
		var button := Button.new()
		button.custom_minimum_size = Vector2(80, 80)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_press_cell.bind(index))
		grid.add_child(button)
		buttons.append(button)
	var reset := Button.new()
	reset.text = "Start again"
	reset.custom_minimum_size.y = 42
	reset.pressed.connect(_reset)
	game.add_child(reset)
	var settings_button := Button.new()
	settings_button.text = "Settings / Esc"
	settings_button.pressed.connect(func(): set_menu_open(true))
	page.add_child(settings_button)
	settings_menu = preload("res://addons/streamer_mode/ui/streamer_settings_menu.gd").new()
	add_child(settings_menu)
	settings_menu.attach_panel(panel)
	var private_field := PrivacyCopyField.new()
	private_field.caption = "GARDEN INVITE"
	private_field.value = "GARDEN-7362"
	game.add_child(private_field)
	private_field.bind(integration.privacy_engine, &"garden_invite")
	integration.privacy_engine.set_scan_root(game)
	page.add_child(_label("CLICK TO PLAY     /     ESC FOR SETTINGS", 12, Color("57745f")))
	_reset()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _press_cell(index: int) -> void:
	if settings_menu.visible:
		return
	_flip(index)
	moves += 1
	integration.play_click()
	_refresh_board()


func _flip(index: int) -> void:
	var x := index % 4
	var y := index / 4
	for delta in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var target: Vector2i = Vector2i(x, y) + delta
		if target.x >= 0 and target.x < 4 and target.y >= 0 and target.y < 4:
			var position: int = target.y * 4 + target.x
			cells[position] = not cells[position]


func _reset() -> void:
	cells.assign([true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true])
	for index in [1, 6, 9]:
		_flip(index)
	moves = 0
	_refresh_board()


func _refresh_board() -> void:
	var lit := cells.count(true)
	progress_label.text = "Garden complete!   /   %d moves" % moves if lit == 16 else "%02d / 16 tiles lit   /   %d moves" % [lit, moves]
	for index in range(16):
		var style := StyleBoxFlat.new()
		style.bg_color = Color("bcd875") if cells[index] else Color("d5dfd0")
		style.set_corner_radius_all(18)
		style.set_border_width_all(2)
		style.border_color = Color("8cac52") if cells[index] else Color("bdccba")
		buttons[index].add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = style.bg_color.lightened(0.1)
		buttons[index].add_theme_stylebox_override("hover", hover)
		buttons[index].add_theme_stylebox_override("pressed", style)
		buttons[index].add_theme_color_override("font_color", Color("284733"))
		buttons[index].add_theme_color_override("font_hover_color", Color("284733"))
		buttons[index].text = "+" if cells[index] else "·"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_menu_open(not settings_menu.visible)
		get_viewport().set_input_as_handled()


func set_menu_open(open: bool) -> void:
	settings_menu.set_open(open)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _capture() -> void:
	await get_tree().create_timer(0.5).timeout
	integration.controller.set_enabled(true)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	get_viewport().get_texture().get_image().save_png("res://.artifacts/signal-garden.png")
	integration.music.stop()
	integration.click_sound.stop()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
