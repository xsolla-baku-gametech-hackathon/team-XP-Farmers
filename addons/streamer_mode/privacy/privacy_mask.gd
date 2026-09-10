class_name PrivacyMaskComponent
extends CanvasLayer
## Reusable in-game privacy mask.
##
## Add one instance under the game's UI root and call setup(controller). While
## Streamer Mode and the Privacy feature are both active it shows a translucent,
## draggable, resizable rectangle over private UI. It renders inside the game's
## own viewport on a high CanvasLayer, never as an OS-level always-on-top
## window, so it behaves identically under the Compatibility and Forward+
## renderers and needs no per-pixel-transparency or window settings.
##
## Contract (matches docs/TEAM_WORKFLOW.md "Shared API"):
##   var mask := PrivacyMaskComponent.new()
##   ui_root.add_child(mask)
##   mask.setup(controller)          # syncs immediately, even if mode is on
##   mask.cover_node(private_card)   # optional: initial coverage target

const Controller := preload("res://addons/streamer_mode/core/streamer_mode_controller.gd")
const MaskRegionScript := preload("res://addons/streamer_mode/privacy/mask_region.gd")

const OVERLAY_LAYER := 128
const DEFAULT_SIZE := Vector2(360.0, 140.0)
const PENDING_MARGIN := 12.0

## While a mask is on screen this key hides it and clears the Privacy
## selection, and the event is consumed so it does not also reach a
## game-wide handler. With no mask on screen the key is left untouched.
@export var emergency_keycode := KEY_ESCAPE
@export_range(0.05, 1.0, 0.01) var default_opacity := 0.8

var _controller: StreamerModeController
var _surface: Control
var _region: MaskRegionScript
var _pending_rect := Rect2()
var _pending_node: Control = null
var _has_pending := false


func _ready() -> void:
	layer = OVERLAY_LAYER
	visible = false

	_surface = Control.new()
	_surface.name = "Surface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.resized.connect(_on_bounds_changed)
	add_child(_surface)

	_region = MaskRegionScript.new()
	_region.name = "MaskRegion"
	_region.opacity = default_opacity
	_region.hide()
	_region.hide_requested.connect(_on_region_hide_requested)
	_region.grabbed.connect(_on_region_grabbed)
	_surface.add_child(_region)

	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_bounds_changed):
		vp.size_changed.connect(_on_bounds_changed)


func _exit_tree() -> void:
	if _controller and _controller.state_changed.is_connected(_refresh):
		_controller.state_changed.disconnect(_refresh)
	_untrack_target()


## Bind (or rebind) the shared controller. Safe to call repeatedly.
func setup(controller: StreamerModeController) -> void:
	if _controller == controller:
		return
	if _controller and _controller.state_changed.is_connected(_refresh):
		_controller.state_changed.disconnect(_refresh)
	_controller = controller
	if _controller:
		_controller.state_changed.connect(_refresh)
	_refresh()


## Open the mask over this rectangle (viewport pixels) the next time it becomes
## visible. One-shot: cleared once applied.
func cover_rect(global_rect: Rect2) -> void:
	_untrack_target()
	_pending_rect = global_rect
	_has_pending = true
	_place_region.call_deferred()


## Track a UI node: the mask snaps to that node's on-screen rectangle and keeps
## following it through layout and window resizes, until the streamer grabs the
## mask (drag or resize), after which it moves freely.
func cover_node(node: Control) -> void:
	_untrack_target()
	_pending_node = node
	_pending_rect = Rect2()
	_has_pending = true
	if is_instance_valid(node) and not node.item_rect_changed.is_connected(_on_target_rect_changed):
		node.item_rect_changed.connect(_on_target_rect_changed)
	_place_region.call_deferred()


## Emergency teardown: hide the mask and clear the Privacy selection so the
## sidebar checkbox reflects reality. Streamer Mode itself stays on.
func panic_hide() -> void:
	if is_instance_valid(_region):
		_region.hide()
	visible = false
	if _controller:
		_controller.set_feature_enabled(Controller.PRIVACY, false)


func is_mask_visible() -> bool:
	return visible and is_instance_valid(_region) and _region.visible


func get_mask_rect() -> Rect2:
	return _region.get_rect() if is_instance_valid(_region) else Rect2()


## --- Internals ----------------------------------------------------------

func _refresh() -> void:
	var active := _controller != null and _controller.is_feature_active(Controller.PRIVACY)
	visible = active
	if not is_instance_valid(_region):
		return
	_region.visible = active
	if active:
		_place_region.call_deferred()


func _on_bounds_changed() -> void:
	if is_instance_valid(_surface):
		_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place_region()


func _place_region() -> void:
	if not is_mask_visible():
		return
	if _surface.size.x < 1.0 or _surface.size.y < 1.0:
		return  # layout not resolved yet; _surface.resized will call back
	if _has_pending:
		var rect := _resolve_pending()
		if rect.size != Vector2.ZERO:
			_region.set_region_rect(rect)
			if _pending_node == null:
				_has_pending = false
			return
	if _region.has_been_placed:
		_region.clamp_into_bounds()
	else:
		_region.center_in_bounds(DEFAULT_SIZE)


func _resolve_pending() -> Rect2:
	if is_instance_valid(_pending_node):
		return _pending_node.get_global_rect().grow(PENDING_MARGIN)
	return _pending_rect


func _on_target_rect_changed() -> void:
	if _has_pending and is_mask_visible():
		_place_region()


func _untrack_target() -> void:
	if is_instance_valid(_pending_node) and _pending_node.item_rect_changed.is_connected(_on_target_rect_changed):
		_pending_node.item_rect_changed.disconnect(_on_target_rect_changed)
	_pending_node = null


func _on_region_grabbed() -> void:
	# The streamer took manual control; stop following the target UI.
	_untrack_target()
	_has_pending = false


func _on_region_hide_requested() -> void:
	panic_hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_mask_visible():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == emergency_keycode:
		panic_hide()
		get_viewport().set_input_as_handled()
