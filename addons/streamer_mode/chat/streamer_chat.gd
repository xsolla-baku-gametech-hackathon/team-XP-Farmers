class_name StreamerChat
extends CanvasLayer
## Place under a persistent host root and bind the shared controller.
const Client = preload("res://addons/streamer_mode/chat/chat_client.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Settings = preload("res://addons/streamer_mode/chat/chat_settings.gd")
signal status_changed(state: String, detail: String)
var client: StreamerChatClient
var overlay: StreamerChatOverlay
var settings: StreamerChatSettings
var _controller: StreamerModeController
var _status := "No channel connected"

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_controller()
	if is_instance_valid(client):
		_restore_bindings.call_deferred()

func _ready() -> void:
	layer = 20
	client = Client.new()
	add_child(client)
	overlay = Overlay.new()
	add_child(overlay)
	overlay.bind_client(client)
	overlay.bind_controller(_controller)
	client.status_changed.connect(_on_status)
	settings = Settings.new()
	settings.position = Vector2(24, 68)
	add_child(settings)
	settings.setup(self)
	_sync()

func bind(controller: StreamerModeController) -> void:
	_disconnect_controller()
	_controller = controller
	if is_inside_tree():
		_connect_controller()
	if is_instance_valid(overlay):
		overlay.bind_controller(controller)
	_sync()

# Keep the original public API for existing integrations.
func bind_controller(controller: StreamerModeController) -> void:
	bind(controller)

func get_status() -> String:
	return _status

func _on_status(state: String, detail: String) -> void:
	_status = detail
	status_changed.emit(state, detail)

func _sync() -> void:
	if not is_instance_valid(client):
		return
	client.set_active(is_instance_valid(_controller) and _controller.is_inside_tree()
		and _controller.is_feature_active(StreamerModeController.CHAT))

func _connect_controller() -> void:
	if not is_instance_valid(_controller):
		return
	if not _controller.state_changed.is_connected(_sync):
		_controller.state_changed.connect(_sync)
	if not _controller.tree_exiting.is_connected(_controller_exiting):
		_controller.tree_exiting.connect(_controller_exiting)

func _disconnect_controller() -> void:
	if not is_instance_valid(_controller):
		return
	if _controller.state_changed.is_connected(_sync):
		_controller.state_changed.disconnect(_sync)
	if _controller.tree_exiting.is_connected(_controller_exiting):
		_controller.tree_exiting.disconnect(_controller_exiting)

func _controller_exiting() -> void:
	bind(null)

func open_settings() -> void:
	settings.open()

func close_settings() -> void:
	settings.close()

func connect_link(link: String) -> bool:
	return client.connect_link(link)

func disconnect_chat() -> void:
	client.disconnect_chat()

func _exit_tree() -> void:
	_disconnect_controller()

func _restore_bindings() -> void:
	if not is_inside_tree():
		return
	overlay.bind_client(client)
	overlay.bind_controller(_controller)
	_sync()
