class_name OpenClawBridge
extends Node
## OpenClawBridge — Puente desacoplado con OpenClaw (Fase 4).
##
## Se conecta al gateway local de OpenClaw (endpoint compatible con OpenAI,
## descubierto en el Paso 0) para el chat y el diagnóstico. La dirección, el
## puerto y el token viven en un archivo de configuración (user://), nunca en el
## código. Si no hay configuración, el puente queda inactivo y la app funciona
## igual sin IA.

signal status_changed(connected: bool, text: String)
signal reply(text: String)
signal failed(text: String)

var host: String = "127.0.0.1"
var port: int = 18789
var token: String = ""
var model: String = "openclaw/cerebro"
var path: String = "/v1/chat/completions"
var configured: bool = false
var busy: bool = false

var _chat: HTTPRequest
var _health: HTTPRequest

func _ready() -> void:
	_chat = HTTPRequest.new(); add_child(_chat)
	_chat.request_completed.connect(_on_chat_done)
	_health = HTTPRequest.new(); add_child(_health)
	_health.request_completed.connect(_on_health_done)
	_load_config()

func _config_path() -> String:
	return "user://openclaw_config.json"

func _load_config() -> void:
	var cfg: Dictionary = {}
	if FileAccess.file_exists(_config_path()):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_config_path()))
		if typeof(parsed) == TYPE_DICTIONARY:
			cfg = parsed
	else:
		cfg = _autodetect()
		if not cfg.is_empty():
			var f := FileAccess.open(_config_path(), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(cfg, "\t")); f.close()
	if cfg.has("token"):
		host = cfg.get("host", host)
		port = int(cfg.get("port", port))
		token = str(cfg.get("token", ""))
		model = cfg.get("model", model)
		path = cfg.get("path", path)
		configured = token != ""

## Lee la configuración local de OpenClaw (solo lectura) para autoconfigurar el
## puente la primera vez. No modifica la configuración de OpenClaw.
func _autodetect() -> Dictionary:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	var p := home.path_join(".openclaw/openclaw.json")
	if not FileAccess.file_exists(p):
		return {}
	var oc = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(oc) != TYPE_DICTIONARY:
		return {}
	var gw: Dictionary = oc.get("gateway", {})
	var auth: Dictionary = gw.get("auth", {})
	if str(auth.get("token", "")) == "":
		return {}
	return {
		"host": "127.0.0.1", "port": gw.get("port", 18789),
		"token": auth.get("token", ""), "model": "openclaw/cerebro",
		"path": "/v1/chat/completions",
	}

func base_url() -> String:
	return "http://%s:%d" % [host, port]

## Lista de agentes de OpenClaw (para elegir a cuál dirigir el chat).
func agents() -> Array:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	var p := home.path_join(".openclaw/openclaw.json")
	if FileAccess.file_exists(p):
		var oc = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(oc) == TYPE_DICTIONARY:
			var lst: Array = oc.get("agents", {}).get("list", [])
			var out := []
			for a in lst:
				if typeof(a) == TYPE_DICTIONARY and a.has("id"):
					out.append(str(a["id"]))
			if not out.is_empty():
				return out
	return ["default", "cerebro", "main"]

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % token,
		"Content-Type: application/json",
	])

func check_health() -> void:
	if not configured:
		status_changed.emit(false, "OpenClaw sin configurar")
		return
	_health.cancel_request()
	var err := _health.request(base_url() + "/health", _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		status_changed.emit(false, "No se pudo consultar el estado")

func _on_health_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		status_changed.emit(true, "Conectado a OpenClaw (%s)" % model)
	else:
		status_changed.emit(false, "Sin conexión con OpenClaw")

func send_chat(messages: Array) -> void:
	if not configured:
		failed.emit("OpenClaw no está configurado.")
		return
	if busy:
		failed.emit("Espera la respuesta anterior…")
		return
	busy = true
	var body := JSON.stringify({
		"model": model, "messages": messages, "max_tokens": 1000, "stream": false,
	})
	var err := _chat.request(base_url() + path, _headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		busy = false
		failed.emit("No se pudo enviar el mensaje (error %d)." % err)

func _on_chat_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Fallo de red (%d). ¿Está encendido el gateway de OpenClaw?" % result)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("choices"):
		failed.emit("Respuesta inesperada de OpenClaw (código %d)." % code)
		return
	var choices: Array = data["choices"]
	if choices.is_empty():
		failed.emit("OpenClaw no devolvió respuesta.")
		return
	reply.emit(str(choices[0]["message"]["content"]))
