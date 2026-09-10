extends PopupPanel
## Optional settings host; services must live outside the menu.
var content: VBoxContainer
var resume_button: Button

func _ready() -> void:
	exclusive = true
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var title := Label.new()
	title.text = "Settings / Streamer Mode"
	content.add_child(title)
	resume_button = Button.new()
	resume_button.text = "Resume game"
	resume_button.pressed.connect(hide)
	content.add_child(resume_button)

func attach_panel(panel: Control) -> void:
	if panel.get_parent():
		panel.reparent(content)
	else:
		content.add_child(panel)
	content.move_child(panel, 1)

func set_open(open: bool) -> void:
	if open:
		popup_centered(Vector2i(440, 520))
		_recenter.call_deferred()
		resume_button.grab_focus()
	else:
		hide()

func _recenter() -> void:
	await get_tree().process_frame
	if visible:
		position = (get_parent().get_viewport().get_visible_rect().size - Vector2(size)) / 2
