class_name KickRelayClient
extends Node
## In-game Kick OAuth and polling client. Provider secrets stay on the relay.
signal message_received(author: String, message: String)
signal status_changed(state: String, detail: String)
var state := "disconnected"
var detail := "Not connected"
var _url := ""
var _key := ""
var _cursor := 0
var _generation := 0
var _busy := false
var _next_poll := 0.0
var _request: HTTPRequest

func connect_account(relay_url: String) -> void:
	disconnect_chat()
	if not _valid_origin(relay_url):
		_set_status("error", "Enter your team's HTTPS relay address.")
		return
	_url = relay_url.trim_suffix("/")
	_set_status("connecting", "Opening Kick sign-in…")
	var current := _generation
	var request := HTTPRequest.new()
	_request = request
	request.timeout = 15.0
	request.max_redirects = 0
	add_child(request)
	if request.request(_url + "/sessions", [], HTTPClient.METHOD_POST) != OK:
		request.queue_free()
		_set_status("error", "Cannot reach Kick relay.")
		return
	var response: Array = await request.request_completed
	request.queue_free()
	if current != _generation:
		return
	_request = null
	var payload = JSON.parse_string(response[3].get_string_from_utf8())
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 201 or not payload is Dictionary:
		_set_status("error", "Kick sign-in could not start. Check the relay address and configuration.")
		return
	var login := str(payload.get("authorize_url", ""))
	var session_key := str(payload.get("session_key", ""))
	if not login.begins_with("https://id.kick.com/oauth/authorize?") or session_key.is_empty() or "\n" in session_key or "\r" in session_key:
		_set_status("error", "Invalid Kick sign-in response.")
		return
	_key = session_key
	if OS.shell_open(login) != OK:
		disconnect_chat()
		_set_status("error", "Could not open the browser. Try connecting again.")
		return
	_set_status("connecting", "Finish signing in to Kick in your browser, then return to the game.")

func _valid_origin(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^https://[^/?#@\\s]+/?$")
	return regex.search(value) != null

func connect_session(relay_url: String, session_key: String) -> void:
	disconnect_chat()
	if not _valid_origin(relay_url) or session_key.is_empty() or "\n" in session_key or "\r" in session_key:
		_set_status("error", "A valid HTTPS relay origin and session key are required.")
		return
	_url = relay_url.trim_suffix("/")
	_key = session_key
	_set_status("connecting", "Connecting to Kick relay…")

func disconnect_chat() -> void:
	# Remove the old relay session as well as stopping local polling.
	if not _key.is_empty() and is_inside_tree():
		var cleanup := HTTPRequest.new()
		cleanup.timeout = 5.0
		cleanup.max_redirects = 0
		add_child(cleanup)
		cleanup.request_completed.connect(func(_result, _code, _headers, _body): cleanup.queue_free())
		if cleanup.request(_url + "/session", PackedStringArray(["Authorization: Bearer " + _key]), HTTPClient.METHOD_DELETE) != OK:
			cleanup.queue_free()
	_generation += 1
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_key = ""
	_cursor = 0
	_busy = false
	_next_poll = 0.0
	_set_status("disconnected", "Not connected")

func _process(_delta: float) -> void:
	if not _key.is_empty() and not _busy and Time.get_ticks_msec() / 1000.0 >= _next_poll:
		_poll()

func _poll() -> void:
	_busy = true
	var current := _generation
	var request := HTTPRequest.new()
	_request = request
	request.timeout = 15.0
	request.max_redirects = 0
	add_child(request)
	if request.request(_url + "/session?after=" + str(_cursor), PackedStringArray(["Authorization: Bearer " + _key])) != OK:
		request.queue_free()
		_busy = false
		_next_poll = Time.get_ticks_msec() / 1000.0 + 3.0
		_set_status("connecting", "Relay unavailable; retrying…")
		return
	var response: Array = await request.request_completed
	request.queue_free()
	if current != _generation:
		return
	_request = null
	_busy = false
	_next_poll = Time.get_ticks_msec() / 1000.0 + 1.0
	if response[1] == 401:
		disconnect_chat()
		_set_status("error", "Session expired. Connect your Kick account again.")
		return
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		_set_status("connecting", "Relay unavailable; retrying…")
		return
	var payload = JSON.parse_string(response[3].get_string_from_utf8())
	if payload is Dictionary:
		_accept_reply(payload)

func _accept_reply(payload: Dictionary) -> void:
	_set_status(str(payload.get("state", "error")), str(payload.get("detail", "Invalid relay response")))
	for message in payload.get("messages", []):
		if message is Dictionary and int(message.get("sequence", 0)) > _cursor:
			message_received.emit(str(message.get("author", "Unknown user")), str(message.get("text", "")))
			_cursor = int(message.get("sequence", _cursor))
	_cursor = maxi(_cursor, int(payload.get("cursor", _cursor)))
	if state == "error":
		_key = ""

func _set_status(value: String, message: String) -> void:
	state = value
	detail = message
	status_changed.emit(state, detail)

func _exit_tree() -> void:
	disconnect_chat()
