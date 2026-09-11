extends Control

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Arena = preload("res://demo/arena.gd")
const SettingsPanel = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn")
const Services = preload("res://demo/demo_services.gd")
const INK := Color("e6edf0")
const MUTED := Color("8fa4b0")
const LIME := Color("b4ee93")

var controller: StreamerModeController
var services: Node
var arena: Control
var settings_panel: StreamerModePanel
var score_label: Label
var settings_menu: PopupPanel
var privacy_engine: PrivacyEngine
var copy_field: PrivacyCopyField
var chat_button: Button


func _ready() -> void:
	controller = Controller.new()
	controller.name = "StreamerMode"
	add_child(controller)
	services = Services.new()
	services.name = "DemoServices"
	add_child(services)
	services.setup(controller)
	privacy_engine = PrivacyEngine.new()
	add_child(privacy_engine)
	privacy_engine.target_margin = 2.0
	privacy_engine.setup(controller)
	privacy_engine.set_mask_param("tint_amount", 1.0)
	theme = _make_theme()
	_build_ui()
	controller.state_changed.connect(_refresh)
	services.audio_status_changed.connect(func(_message: String): _refresh())
	services.chat_status_changed.connect(func(_message: String): _refresh())
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	add_child(margin)
	var page := _column(22)
	margin.add_child(page)
	var header := _row(16)
	page.add_child(header)
	var brand := _column(3)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	brand.add_child(_label("XP FARMERS   /   GAME TECH LAB", 12, LIME))
	brand.add_child(_label("Shard Run", 32))
	var settings_button := Button.new()
	settings_button.text = "Settings / Esc"
	settings_button.pressed.connect(func(): set_menu_open(true))
	header.add_child(settings_button)
	var content := _row(26)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(content)
	var game := _column(14)
	game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(game)
	var game_header := _row(12)
	game.add_child(game_header)
	var title := _label("01   /   THE PLAYGROUND", 12, MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_header.add_child(title)
	score_label = _label("00  SHARDS", 14, LIME)
	game_header.add_child(score_label)
	arena = Arena.new()
	game.add_child(arena)
	arena.collected.connect(func(total: int): score_label.text = "%02d  SHARDS" % total)
	arena.collected.connect(services.play_collection_sound)
	var game_footer := _row(12)
	game.add_child(game_footer)
	var controls := _label("W A S D  /  ARROWS   Move & collect shards", 13, MUTED)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_footer.add_child(controls)
	var reset := Button.new()
	reset.text = "Reset run"
	reset.pressed.connect(_reset_run)
	game_footer.add_child(reset)
	var lobby := _card()
	game.add_child(lobby)
	var lobby_row := _row(20)
	lobby.add_child(lobby_row)
	var lobby_text := _column(6)
	lobby_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_row.add_child(lobby_text)
	lobby_text.add_child(_label("DEMO LOBBY   /   SAMPLE DATA", 11, MUTED))
	copy_field = PrivacyCopyField.new()
	copy_field.caption = "JOIN CODE"
	copy_field.value = "XP-4829"
	lobby_text.add_child(copy_field)
	copy_field.bind(privacy_engine, &"lobby")
	settings_menu = preload("res://addons/streamer_mode/ui/streamer_settings_menu.gd").new()
	add_child(settings_menu)
	settings_panel = SettingsPanel.instantiate()
	settings_panel.bind(controller)
	settings_panel.set_feature_available(Controller.AUDIO, services.has_audio())
	settings_panel.set_feature_available(Controller.PRIVACY, true)
	settings_panel.set_feature_available(Controller.CHAT, services.has_chat())
	settings_panel.set_feature_status(Controller.PRIVACY, "Private game UI concealed; Copy stays available.")
	settings_menu.attach_panel(settings_panel)
	chat_button = Button.new()
	chat_button.text = "Connect channel / Chat settings"
	chat_button.pressed.connect(open_chat_settings)
	settings_menu.content.add_child(chat_button)
	settings_menu.content.move_child(chat_button, 2)
	services.chat.settings.reparent(settings_menu.content)
	services.chat.settings.close_requested.connect(func(): set_menu_open(false))
	settings_menu.visibility_changed.connect(_menu_visibility)
	privacy_engine.exclude_subtree(services.chat)
	privacy_engine.exclude_subtree(settings_menu)
	privacy_engine.set_scan_root(game)
	page.add_child(_label("WASD / ARROWS  Move     |     ESC  Settings", 11, MUTED))

func set_menu_open(open: bool) -> void:
	if open:
		_show_main_settings()
	settings_menu.set_open(open)
	arena.set_process(not open)



func _show_main_settings() -> void:
	services.chat.settings.hide()
	settings_panel.show()
	chat_button.show()
	settings_menu.resume_button.show()

func _menu_visibility() -> void:
	arena.set_process(not settings_menu.visible)
	if not settings_menu.visible:
		_show_main_settings()

func open_chat_settings() -> void:
	if not settings_menu.visible:
		set_menu_open(true)
	settings_panel.hide()
	chat_button.hide()
	settings_menu.resume_button.hide()
	services.chat.open_settings()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_menu_open(not settings_menu.visible)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	settings_panel.set_feature_status(Controller.AUDIO, services.get_audio_status())
	settings_panel.set_feature_status(Controller.CHAT, services.get_chat_status())


func _reset_run() -> void:
	arena.score = 0
	arena.player = Vector2(0.5, 0.55)
	score_label.text = "00  SHARDS"
	get_viewport().gui_release_focus()


func _label(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _column(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


func _row(separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _style(Color("14232e"))
	style.border_color = Color("293d49")
	style.set_border_width_all(1)
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.content_margin_left = 20
	style.content_margin_right = 20
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	result.set_constant("h_separation", "CheckBox", 10)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_color", "CheckBox", INK)
	result.set_color("font_disabled_color", "CheckBox", MUTED)
	result.set_stylebox("normal", "Button", _style(Color("213643")))
	result.set_stylebox("hover", "Button", _style(Color("304a58")))
	result.set_stylebox("pressed", "Button", _style(Color("39586b")))
	var focus := _style(Color(0, 0, 0, 0))
	focus.set_border_width_all(2)
	focus.border_color = LIME
	result.set_stylebox("focus", "Button", focus)
	return result

