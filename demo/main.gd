extends Control

const Controller = preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const Arena = preload("res://demo/arena.gd")
const Services = preload("res://demo/demo_services.gd")
const PrivacyEngine = preload("res://addons/streamer_mode/privacy/privacy_engine.gd")
const PrivacyCopyField = preload("res://addons/streamer_mode/privacy/privacy_copy_field.gd")
const PrivacyControlPanel = preload("res://addons/streamer_mode/privacy/privacy_control_panel.gd")
const PrivacyDrawTool = preload("res://addons/streamer_mode/privacy/privacy_draw_tool.gd")
const INK := Color("e6edf0")
const MUTED := Color("8fa4b0")
const LIME := Color("b4ee93")

var controller: StreamerModeController
var services: Node
var arena: Control
var mode_button: Button
var audio_option: CheckBox
var privacy_option: CheckBox
var status_label: Label
var audio_label: Label
var privacy_label: Label
var score_label: Label
var lobby_card: PanelContainer
var lobby_status: Label
var privacy_engine: PrivacyEngine
var join_code_field: PrivacyCopyField
var control_panel: PrivacyControlPanel
var panel_toggle: Button
var privacy_draw: PrivacyDrawTool
var draw_button: Button
var handles_button: Button


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
	privacy_engine = PrivacyEngine.new()
	privacy_engine.name = "PrivacyEngine"
	add_child(privacy_engine)
	privacy_engine.setup(controller)
	# Strategy B, explicit: the join code is masked but stays copyable.
	join_code_field.bind(privacy_engine, &"join_code")
	# Strategy B, by group: the "SESSION" line is tagged privacy_sensitive and
	# auto-registered (the scanner's conservative patterns miss that string).
	privacy_engine.refresh_group()
	# Dev panel: create and exclude it before scanning starts so it is never
	# itself a scan target or a mask target.
	control_panel = PrivacyControlPanel.new()
	control_panel.name = "PrivacyControlPanel"
	control_panel.anchor_left = 1.0
	control_panel.anchor_right = 1.0
	control_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	control_panel.offset_left = -318
	control_panel.offset_right = -30
	control_panel.offset_top = 96
	control_panel.hide()
	add_child(control_panel)
	control_panel.setup(privacy_engine)
	# Automatic scanning is already running: PrivacyEngine.setup() starts it.
	# It only needs to be told which subtree to watch.
	privacy_engine.set_scan_root(self)
	# Supplement, not the primary path: for anything the scanner cannot reach.
	privacy_draw = PrivacyDrawTool.new()
	privacy_draw.name = "PrivacyDrawTool"
	add_child(privacy_draw)
	privacy_draw.setup(privacy_engine)
	privacy_draw.armed_changed.connect(func(on: bool): draw_button.set_pressed_no_signal(on))
	privacy_draw.regions_changed.connect(func(_n: int): _refresh())
	controller.state_changed.connect(_refresh)
	services.audio_status_changed.connect(func(_message: String): _refresh())
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
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
	# Demo composition: leave room for the sensitive lines below the arena.
	arena.custom_minimum_size = Vector2(420, 250)
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
	lobby_card = _card()
	game.add_child(lobby_card)
	var lobby_row := _row(20)
	lobby_card.add_child(lobby_row)
	var lobby_text := _column(6)
	lobby_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_row.add_child(lobby_text)
	lobby_text.add_child(_label("DEMO LOBBY   /   SAMPLE DATA", 11, MUTED))
	join_code_field = PrivacyCopyField.new()
	join_code_field.caption = "JOIN CODE"
	join_code_field.value = "XP-4829"
	lobby_text.add_child(join_code_field)
	lobby_status = _label("Privacy + Copy\nVisible on stream", 12, MUTED)
	lobby_row.add_child(lobby_status)
	# Mixed line: only the code blurs, the player name and "Room:" stay readable.
	game.add_child(_label("Player: xXx_Shadow_xXx     |     Room: GAME-2231", 14, INK))
	var meta_row := _row(28)
	game.add_child(meta_row)
	meta_row.add_child(_label("MATCH SERVER   203.0.113.42:7777", 11, MUTED))
	var session_line := _label("SESSION   KX7Q-22F1", 11, MUTED)
	session_line.add_to_group("privacy_sensitive")
	meta_row.add_child(session_line)
	var sidebar := _column(14)
	sidebar.custom_minimum_size.x = 350
	content.add_child(sidebar)
	sidebar.add_child(_label("02   /   STREAM CONTROLS", 12, MUTED))
	var settings_card := _card()
	sidebar.add_child(settings_card)
	var settings := _column(10)
	settings_card.add_child(settings)
	settings.add_child(_label("One switch. Your settings.", 22))
	settings.add_child(_label("Changes apply to player and viewers.", 13, MUTED))
	var mode_row := _row(8)
	settings.add_child(mode_row)
	mode_button = Button.new()
	mode_button.custom_minimum_size.y = 52
	mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_button.toggle_mode = true
	mode_button.add_theme_stylebox_override("normal", _style(Color("b4ee93")))
	mode_button.add_theme_stylebox_override("hover", _style(Color("c8f6b0")))
	mode_button.add_theme_stylebox_override("pressed", _style(Color("7dd8f4")))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		mode_button.add_theme_color_override(state, Color("12241c"))
	mode_button.toggled.connect(controller.set_enabled)
	mode_row.add_child(mode_button)
	panel_toggle = Button.new()
	panel_toggle.text = "PANEL"
	panel_toggle.toggle_mode = true
	panel_toggle.focus_mode = Control.FOCUS_NONE
	panel_toggle.custom_minimum_size = Vector2(64, 52)
	panel_toggle.tooltip_text = "Show the privacy control panel"
	panel_toggle.toggled.connect(func(on: bool): control_panel.visible = on)
	mode_row.add_child(panel_toggle)
	status_label = _label("", 12, MUTED)
	settings.add_child(status_label)
	settings.add_child(HSeparator.new())
	audio_option = CheckBox.new()
	audio_option.text = "Stream-safe audio"
	audio_option.disabled = not services.has_audio()
	audio_option.button_pressed = true
	audio_option.toggled.connect(func(selected: bool): controller.set_feature_enabled(Controller.AUDIO, selected))
	settings.add_child(audio_option)
	audio_label = _label("", 12, MUTED)
	audio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(audio_label)
	privacy_option = CheckBox.new()
	privacy_option.text = "Protect sensitive information"
	privacy_option.button_pressed = controller.is_feature_selected(Controller.PRIVACY)
	privacy_option.toggled.connect(func(selected: bool): controller.set_feature_enabled(Controller.PRIVACY, selected))
	settings.add_child(privacy_option)
	privacy_label = _label("", 12, MUTED)
	privacy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(privacy_label)
	var draw_row := _row(8)
	settings.add_child(draw_row)
	draw_button = Button.new()
	draw_button.text = "+ Blur region"
	draw_button.toggle_mode = true
	draw_button.focus_mode = Control.FOCUS_NONE
	draw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_button.tooltip_text = "Then drag a box over anything you want hidden"
	draw_button.toggled.connect(func(on: bool): privacy_draw.set_armed(on))
	draw_row.add_child(draw_button)
	handles_button = Button.new()
	handles_button.text = "Handles"
	handles_button.toggle_mode = true
	handles_button.button_pressed = true
	handles_button.focus_mode = Control.FOCUS_NONE
	handles_button.tooltip_text = "Show or hide the region frames"
	handles_button.toggled.connect(func(on: bool): privacy_draw.show_chrome = on)
	draw_row.add_child(handles_button)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.tooltip_text = "Remove every region you drew"
	clear_button.pressed.connect(func(): privacy_draw.clear_regions())
	draw_row.add_child(clear_button)
	var chat_option := CheckBox.new()
	chat_option.text = "In-game Twitch chat"
	chat_option.disabled = true
	settings.add_child(chat_option)
	settings.add_child(_label("Chat: awaiting integration", 12, MUTED))
	var chat_card := _card()
	chat_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(chat_card)
	var chat := _column(12)
	chat_card.add_child(chat)
	chat.add_child(_label("LIVE CHAT", 11, MUTED))
	chat.add_child(_label("Not connected", 20))
	var chat_detail := _label("The Twitch panel will live here.", 13, MUTED)
	chat_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(chat_detail)
	page.add_child(_label("TEAM XP FARMERS     /     STREAMER MODE SDK                                       ESC  Toggle mode", 11, MUTED))


func _unhandled_key_input(event: InputEvent) -> void:
	# The privacy mask consumes Escape first while it is on screen (its own
	# panic-hide). This global toggle only runs when no mask is showing.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		controller.set_enabled(not controller.enabled)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	mode_button.set_pressed_no_signal(controller.enabled)
	mode_button.text = "STREAMER MODE  •  ON" if controller.enabled else "ENABLE STREAMER MODE"
	status_label.text = "Mode enabled • integrated features active" if controller.enabled else "Mode off • normal game settings"
	audio_label.text = services.get_audio_status()
	audio_option.set_pressed_no_signal(controller.is_feature_selected(Controller.AUDIO))
	privacy_option.set_pressed_no_signal(controller.is_feature_selected(Controller.PRIVACY))
	var privacy_active := controller.is_feature_active(Controller.PRIVACY)
	var drawn := privacy_draw.get_region_count() if is_instance_valid(privacy_draw) else 0
	if privacy_active:
		var scanning: bool = privacy_engine.is_scanning()
		privacy_label.text = "%s • %d hand-drawn region%s" % [
			"Scanning automatically" if scanning else "Automatic scanning off",
			drawn, "" if drawn == 1 else "s"]
	else:
		privacy_label.text = "Private UI shown normally"
	if is_instance_valid(lobby_status):
		lobby_status.text = "Privacy + Copy\nMasked on stream" if privacy_active else "Privacy + Copy\nVisible on stream"


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
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.content_margin_left = 18
	style.content_margin_right = 18
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

