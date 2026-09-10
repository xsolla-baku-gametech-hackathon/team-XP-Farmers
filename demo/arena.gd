extends Control
## Self-contained demo gameplay. The addon must never depend on this script.

signal collected(total: int)

var player := Vector2(0.5, 0.55)
var score: int = 0
var _time: float = 0.0
var _targets: Array[Vector2] = [Vector2(0.22, 0.32), Vector2(0.76, 0.3), Vector2(0.7, 0.72)]
var _trail: Array[Vector2] = []
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	custom_minimum_size = Vector2(420, 390)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_random.randomize()


func _process(delta: float) -> void:
	_time += delta
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1
	if direction != Vector2.ZERO:
		_trail.push_front(player * size)
		if _trail.size() > 12:
			_trail.pop_back()
		player += direction.normalized() * 245.0 * delta / size
	player = player.clamp(Vector2(0.045, 0.07), Vector2(0.955, 0.93))
	for index in range(_targets.size()):
		if (player * size).distance_to(_targets[index] * size) < 28.0:
			score += 1
			_targets[index] = Vector2(_random.randf_range(0.1, 0.9), _random.randf_range(0.15, 0.85))
			collected.emit(score)
	queue_redraw()


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for x in range(24, int(size.x), 36):
		for y in range(24, int(size.y), 36):
			draw_circle(Vector2(x, y), 1.0, Color("243440"))
	var center := size * Vector2(0.5, 0.52)
	draw_arc(center, minf(size.x, size.y) * 0.34, 0, TAU, 100, Color("203842"), 1.5, true)
	draw_arc(center, minf(size.x, size.y) * 0.35, -0.5, 0.9, 32, Color("385448"), 2.0, true)
	for i in range(_targets.size()):
		var point := _targets[i] * size
		var pulse := 16.0 + sin(_time * 2.8 + i) * 3.0
		draw_circle(point, pulse + 8, Color(0.65, 0.93, 0.57, 0.055))
		draw_arc(point, pulse, 0, TAU, 32, Color("557b54"), 1.0, true)
		var diamond := PackedVector2Array([point + Vector2(0, -9), point + Vector2(7, 0), point + Vector2(0, 9), point + Vector2(-7, 0)])
		draw_colored_polygon(diamond, Color("b4ee93"))
	for i in range(_trail.size()):
		draw_circle(_trail[i], 7.0 * (1.0 - float(i) / 12), Color(0.39, 0.77, 0.91, 0.06))
	var position_px := player * size
	draw_circle(position_px, 24, Color(0.39, 0.77, 0.91, 0.08))
	draw_circle(position_px, 15, Color("27495a"))
	draw_arc(position_px, 15, 0, TAU, 36, Color("7dd8f4"), 2.0, true)
	draw_circle(position_px, 6, Color("d0f5ff"))


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0e1b25")
	style.set_corner_radius_all(18)
	style.border_color = Color("263b47")
	style.set_border_width_all(1)
	return style

