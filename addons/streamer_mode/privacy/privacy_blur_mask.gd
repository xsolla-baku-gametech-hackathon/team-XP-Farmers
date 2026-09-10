class_name PrivacyBlurMask
extends Control
## A non-interactive Control that pixelates and blurs whatever is on screen
## behind it. Its rect eases toward a target; its opacity fades in and out.
## When fully faded out it frees itself. PrivacyEngine owns the instances.

const BLUR_SHADER := preload("res://addons/streamer_mode/privacy/privacy_blur.gdshader")

@export var move_speed := 22.0   ## rect easing per second; <= 0 snaps instantly
@export var fade_speed := 10.0   ## opacity easing per second

var _blur: ColorRect
var _material: ShaderMaterial
var _target_rect := Rect2()
var _has_target := false
var _target_opacity := 0.0
var _opacity := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = BLUR_SHADER
	_material.set_shader_parameter("fill_opacity", 0.0)
	_blur = ColorRect.new()
	_blur.name = "Blur"
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur.material = _material
	add_child(_blur)


## Merge shader parameters (pixel_size, blur_spread, tint, tint_amount, feather).
func configure(params: Dictionary) -> void:
	for key in params:
		_material.set_shader_parameter(key, params[key])


func move_to(target: Rect2, instant := false) -> void:
	_target_rect = target
	_has_target = true
	_target_opacity = 1.0
	if instant or move_speed <= 0.0:
		position = target.position
		size = target.size


func dismiss() -> void:
	_target_opacity = 0.0


func is_dismissing() -> bool:
	return _target_opacity == 0.0


func is_finished() -> bool:
	return _target_opacity == 0.0 and _opacity <= 0.001


func _process(delta: float) -> void:
	if _has_target and move_speed > 0.0:
		var t := clampf(move_speed * delta, 0.0, 1.0)
		position = position.lerp(_target_rect.position, t)
		size = size.lerp(_target_rect.size, t)
	var f := clampf(fade_speed * delta, 0.0, 1.0)
	_opacity = lerpf(_opacity, _target_opacity, f)
	_material.set_shader_parameter("fill_opacity", _opacity)
	if is_finished():
		queue_free()
