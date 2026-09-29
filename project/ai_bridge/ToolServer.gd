class_name ToolServer
extends Node
## ToolServer — API local de herramientas para OpenClaw (JSON-RPC 2.0 sobre HTTP).
##
## Escucha SOLO en 127.0.0.1 (por defecto puerto 18790) y exige un token:
##   Authorization: Bearer <token>     (o cabecera X-MechaForge-Token)
## El token y el puerto se guardan en user://mechaforge_api.json (se generan la
## primera vez; nunca van en el código ni en el repositorio).
##
##   GET  /tools  -> lista de herramientas con su esquema JSON
##   GET  /health -> {"ok": true}
##   POST /rpc    -> {"jsonrpc":"2.0","id":1,"method":"get_scene_state","params":{}}
##
## Las herramientas las implementa SimulatorApi. Las que MODIFICAN la escena no se
## aplican directamente: se muestran como vista previa "fantasma" en el panel de
## IA y requieren la confirmación del usuario (Aplicar/Descartar).

signal request_handled(method: String, ok: bool)

const CONFIG_PATH := "user://mechaforge_api.json"
const DEFAULT_PORT := 18790
const MAX_BODY := 1 << 20

var api: SimulatorApi
var port: int = DEFAULT_PORT
var token: String = ""
var enabled: bool = true
var _server := TCPServer.new()
var _clients: Array = []          # [{peer, buf, t}]

func _ready() -> void:
	_load_or_create_config()
	if enabled:
		start()

func _load_or_create_config() -> void:
	var cfg := {}
	if FileAccess.file_exists(CONFIG_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if typeof(d) == TYPE_DICTIONARY:
			cfg = d
	port = int(cfg.get("port", DEFAULT_PORT))
	token = str(cfg.get("token", ""))
	enabled = bool(cfg.get("enabled", true))
	if token.length() < 16:
		var crypto := Crypto.new()
		token = crypto.generate_random_bytes(16).hex_encode()
		cfg = {"port": port, "token": token, "enabled": enabled,
			"nota": "API local de MechaForge para OpenClaw. Solo 127.0.0.1."}
		var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(cfg, "\t"))
			f.close()

func start() -> bool:
	if _server.is_listening():
		return true
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("ToolServer: no se pudo escuchar en 127.0.0.1:%d (%d)" % [port, err])
		return false
	return true

func stop() -> void:
	_server.stop()
	for c in _clients:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_clients.clear()

func is_listening() -> bool:
	return _server.is_listening()

## No se detiene al salir del árbol: MechaForge lo mueve a la raíz mientras el
## Laboratorio matemático ocupa la ventana. Se cierra solo al liberarse.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_clients.append({"peer": peer, "buf": PackedByteArray(), "t": Time.get_ticks_msec()})
	var keep := []
	for c in _clients:
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var avail := peer.get_available_bytes()
		if avail > 0:
			var got := peer.get_data(avail)
			if got[0] == OK:
				# Los PackedByteArray se copian al modificarlos: hay que reasignar.
				var buf: PackedByteArray = c["buf"]
				buf.append_array(got[1])
				c["buf"] = buf
		var req := _parse_request(c["buf"])
		if req.is_empty():
			if Time.get_ticks_msec() - int(c["t"]) < 5000 and (c["buf"] as PackedByteArray).size() < MAX_BODY:
				keep.append(c)
			else:
				_respond(peer, 408, {"error": "timeout"})
			continue
		_handle(peer, req)
	_clients = keep

## Devuelve {} si la petición aún no está completa.
func _parse_request(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var sep := text.find("\r\n\r\n")
	if sep < 0:
		return {}
	var head := text.substr(0, sep).split("\r\n")
	if head.is_empty():
		return {}
	var first := head[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, head.size()):
		var k := head[i].find(":")
		if k > 0:
			headers[head[i].substr(0, k).strip_edges().to_lower()] = head[i].substr(k + 1).strip_edges()
	var body_start := sep + 4
	var clen := int(headers.get("content-length", "0"))
	# Longitud en BYTES: se compara con el búfer, no con el texto.
	var head_bytes := text.substr(0, body_start).to_utf8_buffer().size()
	if buf.size() - head_bytes < clen:
		return {}
	var body := buf.slice(head_bytes, head_bytes + clen).get_string_from_utf8()
	return {"method": first[0], "path": first[1], "headers": headers, "body": body}

func _authorized(headers: Dictionary) -> bool:
	var auth := str(headers.get("authorization", ""))
	if auth.begins_with("Bearer ") and auth.substr(7).strip_edges() == token:
		return true
	return str(headers.get("x-mechaforge-token", "")) == token

func _handle(peer: StreamPeerTCP, req: Dictionary) -> void:
	var path := str(req["path"]).split("?")[0]
	if req["method"] == "GET" and path == "/health":
		_respond(peer, 200, {"ok": true, "app": "MechaForge", "version": Config.APP_VERSION})
		return
	if not _authorized(req["headers"]):
		_respond(peer, 401, {"error": "token inválido o ausente (ver user://mechaforge_api.json)"})
		return
	if req["method"] == "GET" and path == "/tools":
		_respond(peer, 200, {"tools": SimulatorApi.TOOLS})
		return
	if req["method"] != "POST" or path != "/rpc":
		_respond(peer, 404, {"error": "usa POST /rpc o GET /tools"})
		return
	var msg = JSON.parse_string(str(req["body"]))
	if typeof(msg) != TYPE_DICTIONARY:
		_respond(peer, 200, _rpc_error(null, -32700, "JSON inválido"))
		return
	var id = msg.get("id", null)
	var method := str(msg.get("method", ""))
	var params = msg.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		params = {}
	var result: Dictionary = api.call_tool(method, params) if api else {"error": "API no disponible"}
	var ok := not result.has("error")
	request_handled.emit(method, ok)
	if ok:
		_respond(peer, 200, {"jsonrpc": "2.0", "id": id, "result": result})
	else:
		_respond(peer, 200, _rpc_error(id, -32000 if method in SimulatorApi.TOOL_NAMES else -32601, str(result["error"])))

func _rpc_error(id, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}

func _respond(peer: StreamPeerTCP, code: int, data: Dictionary) -> void:
	var body := JSON.stringify(data).to_utf8_buffer()
	var status: String = {200: "OK", 401: "Unauthorized", 404: "Not Found", 408: "Request Timeout"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, status, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
