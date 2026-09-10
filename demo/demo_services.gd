extends Node
## Integration owner connects completed feature components here.
## Feature owners work in addons/streamer_mode/<feature> and tests/<feature>.

signal audio_status_changed(message: String)


func setup(_controller: StreamerModeController) -> void:
	pass


func get_audio_status() -> String:
	return "Audio component pending"


func has_audio() -> bool:
	return false


func play_collection_sound(_total: int) -> void:
	pass

