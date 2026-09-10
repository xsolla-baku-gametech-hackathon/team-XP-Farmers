class_name StreamerModeController
extends Node
## Shared runtime state. Add one controller to a game's persistent root.
## Components subscribe to state_changed and read is_feature_active().
## This controller never claims that a component has been integrated.

signal mode_changed(enabled: bool)
signal feature_changed(feature: StringName, selected: bool)
signal state_changed

const PRIVACY: StringName = &"privacy"
const AUDIO: StringName = &"audio"
const CHAT: StringName = &"chat"
const FEATURES: Array[StringName] = [PRIVACY, AUDIO, CHAT]

var enabled: bool = false:
	set(value):
		if enabled == value:
			return
		enabled = value
		mode_changed.emit(enabled)
		state_changed.emit()

var _selected: Dictionary = {PRIVACY: true, AUDIO: true, CHAT: true}


func set_enabled(value: bool) -> void:
	enabled = value


func set_feature_enabled(feature: StringName, selected: bool) -> void:
	if not _selected.has(feature):
		push_warning("Unknown Streamer Mode feature: %s" % feature)
		return
	if _selected[feature] == selected:
		return
	_selected[feature] = selected
	feature_changed.emit(feature, selected)
	state_changed.emit()


func is_feature_selected(feature: StringName) -> bool:
	return bool(_selected.get(feature, false))


func is_feature_active(feature: StringName) -> bool:
	return enabled and is_feature_selected(feature)

