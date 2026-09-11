class_name StreamerChatClient
extends Node
## Read-only relay client. OAuth credentials remain on the server.
signal snapshot_received(messages: Array)
signal status_changed(state: String, detail: String)
var _endpoint := ""
var _key := ""
var _active := false
var _baseline := true
var _excluded: Dictionary = {}
var _request: HTTPRequest
var _timer: Timer

func _enter_tree() -> void:
	if is_instance_valid(_timer) and not _endpoint.is_empty():
		_timer.start()

func _exit_tree() -> void:
	_request.cancel_request()
	_timer.stop()
	_baseline = true
	_excluded.clear()

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 10
	_request.max_redirects = 0
	_request.body_size_limit = 1048576
	add_child(_request)
	_request.request_completed.connect(_completed)
	_timer = Timer.new()
	_timer.wait_time = 1.5
	add_child(_timer)
	_timer.timeout.connect(_poll)

func connect_link(link: String) -> bool:
	disconnect_chat()
	var pattern := RegEx.new()
	pattern.compile("^(https://[A-Za-z0-9.-]+(:[0-9]+)?|http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?)/overlay#([A-Za-z0-9_-]{43})$")
	var matched := pattern.search(link.strip_edges())
	if matched == null:
		status_changed.emit("error", "Paste a private chat link from your relay (HTTPS, or localhost for development).")
		return false
	_endpoint = matched.get_string(1) + "/api/overlay"
	_key = matched.get_string(5)
	status_changed.emit("connecting", "Connecting to chat relay…")
	_timer.start()
	_poll()
	return true

func disconnect_chat() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
	if is_instance_valid(_timer):
		_timer.stop()
	_endpoint = ""
	_key = ""
	_baseline = true
	_excluded.clear()
	snapshot_received.emit([])
	status_changed.emit("disconnected", "No channel connected")

func set_active(value: bool) -> void:
	# Mode controls visibility, not the connected channel's message history.
	_active = value

func _poll() -> void:
	if _endpoint.is_empty() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var result := _request.request(_endpoint, PackedStringArray(["Authorization: Bearer " + _key]))
	if result != OK:
		snapshot_received.emit([])
		status_changed.emit("error", "Cannot reach chat relay. Retrying…")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 401 or code == 403:
		disconnect_chat()
		status_changed.emit("error", "Chat link expired or was replaced. Reconnect with a new link.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary:
		snapshot_received.emit([])
		status_changed.emit("error", "Chat relay unavailable. Retrying…")
		return
	accept_snapshot(data)

func accept_snapshot(data: Dictionary) -> void:
	var state := str(data.get("state", "error"))
	status_changed.emit(state, str(data.get("provider", "")) + " · " + str(data.get("detail", "")))
	var rows = data.get("messages", [])
	if not rows is Array:
		rows = []
	var present: Dictionary = {}
	var accepted: Array = []
	var delivery = data.get("settings", {})
	var enabled := state == "connected" and delivery is Dictionary and bool(delivery.get("enabled", false))
	for row in rows.slice(-100):
		if not row is Dictionary or not row.get("id") is String:
			continue
		var id: String = row.id
		present[id] = true
		if _baseline or not enabled:
			_excluded[id] = true
		if enabled and not _excluded.has(id):
			accepted.append(row)
	# Snapshot replacement also removes deleted/moderated messages.
	for id in _excluded.keys():
		if not present.has(id):
			_excluded.erase(id)
	_baseline = not enabled
	snapshot_received.emit(accepted)
