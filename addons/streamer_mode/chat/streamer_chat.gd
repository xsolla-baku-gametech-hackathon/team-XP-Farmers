class_name StreamerChat
extends CanvasLayer
## Place under a persistent host root and bind the shared controller.
const Client = preload("res://addons/streamer_mode/chat/chat_client.gd")
const Overlay = preload("res://addons/streamer_mode/chat/chat_overlay.gd")
const Connection = preload("res://addons/streamer_mode/chat/channel_connection.gd")
@export var desktop_overlay := true
var chat_window: Window
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
	if desktop_overlay and OS.has_feature("pc"):
		chat_window = Window.new()
		chat_window.title = "XP Farmers · Live chat"
		chat_window.visible = false
		chat_window.force_native = true
		chat_window.borderless = true
		chat_window.always_on_top = true
		chat_window.unfocusable = true
		chat_window.transparent = true
		chat_window.transparent_bg = true
		var ui_scale := 1.0
		chat_window.content_scale_factor = ui_scale
		chat_window.min_size = Vector2i(Vector2(240, 140) * ui_scale)
		chat_window.size = Vector2i(overlay.panel_size * ui_scale)
		# A popup/transient window would disappear when switching applications.
		chat_window.transient = false
		chat_window.popup_window = false
		overlay.desktop_window = chat_window
		add_child(chat_window)
		chat_window.add_child(overlay)
		chat_window.close_requested.connect(func():
			if is_instance_valid(_controller):
				_controller.set_feature_enabled(StreamerModeController.CHAT, false))
	else:
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
	if is_instance_valid(settings):
		settings.refresh_controls()
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

func is_mode_enabled() -> bool:
	return is_instance_valid(_controller) and _controller.enabled

func is_chat_active() -> bool:
	return is_mode_enabled() and overlay.display_enabled and _controller.is_feature_active(StreamerModeController.CHAT)

func connect_channel(provider: String) -> void:
	if not is_mode_enabled():
		return
	overlay.display_enabled = false
	client.disconnect_chat()
	connection.begin(provider)

func enable_chat() -> void:
	if is_mode_enabled() and connection.connected:
		overlay.display_enabled = true
		_controller.set_feature_enabled(StreamerModeController.CHAT, true)
		settings.refresh_controls()

func disconnect_chat() -> void:
	overlay.display_enabled = false
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
