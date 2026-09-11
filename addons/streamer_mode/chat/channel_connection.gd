class_name StreamerChannelConnection
extends Node
## Short-lived browser pairing; provider secrets never enter Godot.
signal status_changed(state: String, detail: String)
signal channel_connected(link: String, channel: String)
signal browser_requested(url: String)
var relay_url := "http://localhost:8788"
var channel := ""
var connected := false
var _token := ""
var _origin := ""
var _generation := 0
var _polling := false
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 2.0
	_timer.timeout.connect(_poll)
	add_child(_timer)

func begin(provider: String) -> void:
	var generation := _generation + 1
	await disconnect_channel()
	if generation != _generation: return
	var origin := relay_url.trim_suffix("/")
	var pattern := RegEx.new()
	pattern.compile("^(https://[A-Za-z0-9.-]+(:[0-9]+)?|http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?)$")
	if pattern.search(origin) == null:
		status_changed.emit("error", "The game developer must configure a valid chat service address.")
		return
	_origin = origin
	status_changed.emit("connecting", "Opening channel sign-in…")
	var result: Dictionary = await _call(origin, "/api/device", HTTPClient.METHOD_POST, "", {"provider": provider})
	if generation != _generation:
		if result.has("token"):
			await _call(origin, "/api/device", HTTPClient.METHOD_DELETE, str(result.token))
		return
	if not result.get("token") is String or not result.get("browserURL") is String:
		status_changed.emit("error", str(result.get("error", "Chat service unavailable. Try again.")))
		return
	_token = result.token
	var browser_url: String = result.browserURL
	# The relay selects the public origin; permit HTTPS or local development only.
	var browser_origin := browser_url.get_slice("/connect#", 0)
	if pattern.search(browser_origin) == null or not browser_url.begins_with(browser_origin + "/connect#"):
		await disconnect_channel()
		status_changed.emit("error", "The chat service returned an invalid sign-in address.")
		return
	status_changed.emit("connecting", "Approve your channel in the browser, then return to the game.")
	browser_requested.emit(browser_url)
	_timer.start()

func disconnect_channel() -> void:
	_generation += 1
	if is_instance_valid(_timer): _timer.stop()
	var previous := _token
	_token = ""
	channel = ""
	connected = false
	status_changed.emit("disconnected", "No channel connected")
	if not previous.is_empty():
		await _call(_origin, "/api/device", HTTPClient.METHOD_DELETE, previous)

func _poll() -> void:
	if _token.is_empty() or _polling: return
	_polling = true
	var generation := _generation
	var result: Dictionary = await _call(_origin, "/api/device", HTTPClient.METHOD_GET, _token)
	_polling = false
	if generation != _generation: return
	if result.has("overlayURL"):
		_timer.stop()
		channel = str(result.get("channel", "Your channel"))
		connected = true
		channel_connected.emit(str(result.overlayURL), channel)
	elif result.get("state") == "error" or result.get("code") == 401:
		_timer.stop()
		status_changed.emit("error", str(result.get("error", result.get("detail", "Sign-in failed. Try again."))))
	elif result.has("error"):
		status_changed.emit("connecting", "Waiting for the chat service. Retrying…")

func _call(origin: String, path: String, method: int, token: String = "", values: Dictionary = {}) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 10
	request.max_redirects = 0
	request.body_size_limit = 65536
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Chat-Studio: 1"])
	if not token.is_empty(): headers.append("Authorization: Bearer " + token)
	var error := request.request(origin + path, headers, method, JSON.stringify(values) if method == HTTPClient.METHOD_POST else "")
	if error != OK:
		request.queue_free()
		return {"error": "Cannot reach chat service."}
	var reply: Array = await request.request_completed
	request.queue_free()
	var data = JSON.parse_string(reply[3].get_string_from_utf8())
	if reply[0] != HTTPRequest.RESULT_SUCCESS or not data is Dictionary:
		return {"error": "Cannot reach chat service."}
	data["code"] = reply[1]
	return data
