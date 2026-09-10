extends Node
## Integration owner connects completed feature components here.
## Feature owners work in addons/streamer_mode/<feature> and tests/<feature>.

signal audio_status_changed(message: String)
signal chat_status_changed(state: String, detail: String)

const Chat = preload("res://addons/streamer_mode/chat/streamer_chat.tscn")
var chat: StreamerChat


func setup(controller: StreamerModeController) -> void:
	if not is_instance_valid(chat):
		chat = Chat.instantiate()
		chat.name = "StreamerChat"
		chat.bind(controller)
		add_child(chat)
		chat.status_changed.connect(func(state: String, detail: String):
			chat_status_changed.emit(state, detail))
	else:
		chat.bind(controller)


func has_chat() -> bool:
	return is_instance_valid(chat)


func get_chat_status() -> String:
	return chat.get_status() if has_chat() else "Chat component pending"


func get_audio_status() -> String:
	return "Audio component pending"


func has_audio() -> bool:
	return false


func play_collection_sound(_total: int) -> void:
	pass

