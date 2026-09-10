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
var chat_status: Label


func _ready() -> void:
	controller = Controller.new()
	controller.name = "StreamerMode"
	add_child(controller)
	services = Services.new()
	services.name = "DemoServices"
	add_child(services)
	services.setup(controller)
	theme = _make_theme()
	_build_ui()
	controller.state_changed.connect(_refresh)
	services.audio_status_changed.connect(func(_message: String): _refresh())
	services.chat_status_changed.connect(func(_state: String, _detail: String): _refresh())
	_refresh()
	_place_chat.call_deferred()


func _place_chat() -> void:
	if is_instance_valid(services.chat.chat_window):
		return
	services.chat.overlay.position = arena.global_position + Vector2(16, 16)
	services.chat.overlay._clamp_position()


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
	brand.add_child(_label("Streamer Mode", 32))
	header.add_child(_label("GODOT ADDON     •     DESKTOP DEMO", 12, MUTED))
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
	lobby_text.add_child(_label("XP-4829", 24))
	lobby_row.add_child(_label("Privacy + Copy\nAwaiting integration", 12, MUTED))
	var sidebar := _column(14)
	sidebar.custom_minimum_size.x = 350
	content.add_child(sidebar)
	sidebar.add_child(_label("02   /   STREAM CONTROLS", 12, MUTED))
	settings_panel = SettingsPanel.instantiate()
	settings_panel.bind(controller)
	settings_panel.set_feature_available(Controller.AUDIO, services.has_audio())
	settings_panel.set_feature_available(Controller.CHAT, services.has_chat())
	sidebar.add_child(settings_panel)
	var chat_card := _card()
	chat_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(chat_card)
	var chat := _column(12)
	chat_card.add_child(chat)
	chat.add_child(_label("LIVE CHAT", 11, MUTED))
	chat_status = _label("Not connected", 16)
	chat_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(chat_status)
	var chat_detail := _label("Twitch / Kick / YouTube\nConnect your channel and adjust the overlay.", 13, MUTED)
	chat_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(chat_detail)
	var chat_settings := Button.new()
	chat_settings.text = "Connect channel / Chat settings"
	chat_settings.pressed.connect(services.chat.open_settings)
	chat.add_child(chat_settings)
	page.add_child(_label("TEAM XP FARMERS     /     STREAMER MODE SDK                                       ESC  Toggle mode", 11, MUTED))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if services.chat.settings.visible:
			services.chat.close_settings()
		else:
			controller.set_enabled(not controller.enabled)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	settings_panel.set_feature_status(Controller.AUDIO, services.get_audio_status())
	settings_panel.set_feature_status(Controller.CHAT, services.get_chat_status())
	chat_status.text = services.get_chat_status()


func _process(_delta: float) -> void:
	arena.set_process(not services.chat.settings.visible)


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

