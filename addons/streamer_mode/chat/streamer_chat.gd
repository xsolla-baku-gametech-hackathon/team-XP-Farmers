class_name StreamerChat
extends CanvasLayer
## Place under a persistent host root and bind the shared controller.
const Client = preload("res://addons/streamer_mode/chat/chat_client.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Connection = preload("res://addons/streamer_mode/chat/channel_connection.gd")
@export var relay_url := "http://localhost:8788"
var connection: StreamerChannelConnection
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
	connection = Connection.new()
	connection.relay_url = ProjectSettings.get_setting("streamer_mode/chat/relay_url", relay_url)
	add_child(connection)
	connection.status_changed.connect(_on_status)
	connection.browser_requested.connect(func(url: String):
		if OS.shell_open(url) != OK:
			_on_status("error", "Could not open your browser. Try connecting again."))
	connection.channel_connected.connect(func(link: String, channel: String):
		if connect_link(link):
			_on_status("connected", "Connected to " + channel + ". Enable chat to display messages."))
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

func connect_channel(provider: String) -> void:
	client.disconnect_chat()
	connection.begin(provider)

func enable_chat() -> void:
	if is_instance_valid(_controller):
		_controller.set_feature_enabled(StreamerModeController.CHAT, true)
		_controller.set_enabled(true)

func disconnect_chat() -> void:
	client.disconnect_chat()
	connection.disconnect_channel()

func _exit_tree() -> void:
	_disconnect_controller()

func _restore_bindings() -> void:
	if not is_inside_tree():
		return
	overlay.bind_client(client)
	overlay.bind_controller(_controller)
	_sync()
