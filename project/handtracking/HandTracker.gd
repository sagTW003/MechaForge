class_name HandTracker
extends Node
## HandTracker — Capa 1 del seguimiento de manos: captura, inferencia y filtrado.
##
## Lanza el proceso tools/handtracking/mf_hands.py (cámara + MediaPipe HandLandmarker
## en otro proceso, así la inferencia nunca frena el render). Recibe sus
## landmarks por UDP en 127.0.0.1 con token y pasa por un filtro One Euro cada
## coordenada de los 21 puntos de cada mano.
##
## Cada mano publicada en `hands` es un Dictionary:
##   label  "Left" | "Right" (mano del usuario: la imagen llega en espejo)
##   score  confianza de la lateralidad
##   lm     PackedVector3Array(21): x, y en [0, 1] sobre la imagen; z relativa a la muñeca
##   wlm    PackedVector3Array(21): coordenadas métricas (m) centradas en la mano
##   img    Vector2: tamaño de la imagen en px (reconstrucción 3D)
##   t      instante de captura (s, reloj del sistema)
##
## Continuidad de las manos: con la mano lejos o de canto MediaPipe confunde a veces
## la derecha con la izquierda. Cada mano conserva su etiqueta mientras se la siga
## (por posición entre paquetes); solo cambia si MediaPipe insiste LABEL_VOTES
## paquetes seguidos.
##
## La configuración (Python, cámara, puerto, token y ajustes) está en
## user://mechaforge_hands.json. El token se genera la primera vez y nunca va en el
## código ni en el repositorio.
##
## Cámara: -1 = la primera que funcione; si no, el índice de DirectShow (el orden de
## CameraList) y su nombre. Al arrancar se busca por el nombre, así la elección se
## mantiene aunque se conecte o desconecte otra cámara.

signal hands_updated(hands: Array)
signal status_changed(text: String, level: String)

const CONFIG_PATH := "user://mechaforge_hands.json"
const DEFAULT_PORT := 18791
const STALE_AFTER := 0.5        # s sin paquetes → se da la mano por perdida
const MATCH_RADIUS := 0.25      # distancia máxima en la imagen para seguir a una mano entre paquetes
const LABEL_VOTES := 8          # paquetes seguidos en que MediaPipe discrepa para cambiar la etiqueta

var python: String = "python"
var camera: int = -1
var camera_name: String = ""    # nombre de la cámara elegida ("" con camera = -1)
var port: int = DEFAULT_PORT
var token: String = ""
var width: int = 640
var height: int = 480
var fps: int = 60
var script_override: String = ""
var min_cutoff: float = 1.0
var beta: float = 10.0
var settings: Dictionary = {}   # ajustes del reconocedor y del controlador (se guardan aquí también)

var running: bool = false
var pid: int = -1
var hands: Array = []
var status_text: String = "Apagado"
var status_level: String = "info"
var fps_measured: float = 0.0
var latency_ms: float = 0.0     # captura → recepción en Godot
var inference_ms: float = 0.0
var cam_size := Vector2i(0, 0)
var last_packet: float = 0.0
var selftest_ok: bool = false

var _udp := PacketPeerUDP.new()
var _filters := {}              # label → {"lm": [OneEuroFilter], "wlm": [OneEuroFilter]}
var _tracks := {}               # label → {"c": centro en la imagen, "votes": discrepancias seguidas, "t": último paquete}
var _arrivals: Array = []
var _error_reported: bool = false

func _ready() -> void:
	load_config()

static func now() -> float:
	return Time.get_unix_time_from_system()

# --- Configuración ---------------------------------------------------------------------

func load_config() -> void:
	var cfg := {}
	if FileAccess.file_exists(CONFIG_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if typeof(d) == TYPE_DICTIONARY:
			cfg = d
	python = str(cfg.get("python", python))
	camera = int(cfg.get("camera", camera))
	camera_name = str(cfg.get("camera_name", ""))
	port = int(cfg.get("port", port))
	token = str(cfg.get("token", ""))
	width = int(cfg.get("width", width))
	height = int(cfg.get("height", height))
	fps = int(cfg.get("fps", fps))
	script_override = str(cfg.get("script", ""))
	min_cutoff = float(cfg.get("min_cutoff", min_cutoff))
	beta = float(cfg.get("beta", beta))
	if typeof(cfg.get("ajustes")) == TYPE_DICTIONARY:
		settings = cfg["ajustes"]
	if token.length() < 16:
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		save_config()

func save_config() -> void:
	var cfg := {"python": python, "camera": camera, "camera_name": camera_name, "port": port, "token": token, "width": width,
		"height": height, "fps": fps, "script": script_override, "min_cutoff": min_cutoff, "beta": beta,
		"ajustes": settings,
		"nota": "Seguimiento de manos de MechaForge. Solo 127.0.0.1; el token autentica los paquetes."}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "\t"))
		f.close()

## Ruta de mf_hands.py: junto al ejecutable (paquetes) o en tools/ (proyecto).
func find_script() -> String:
	var res := ProjectSettings.globalize_path("res://")
	var cands := [script_override,
		OS.get_executable_path().get_base_dir().path_join("handtracking/mf_hands.py"),
		res.path_join("../tools/handtracking/mf_hands.py").simplify_path(),
		res.path_join("../handtracking/mf_hands.py").simplify_path()]
	for c in cands:
		if str(c) != "" and FileAccess.file_exists(c):
			return c
	return ""

# --- Cámaras ---------------------------------------------------------------------------

## Nombres de las cámaras (índice = el que usa mf_hands.py). No abre ninguna.
static func list_cameras() -> Array:
	var scr = load("res://handtracking/CameraList.cs")
	if scr == null:
		return []
	var cl = scr.new()
	if cl == null or not cl.has_method("Names"):
		return []
	return Array(cl.Names())

## Índice actual de la cámara elegida: la busca por su nombre (puede haber cambiado
## de posición). -1 = automática o no está conectada. Sin lista (otro sistema o
## fallo al enumerar) se usa el índice guardado.
static func resolve_camera(index: int, name: String, names: Array) -> int:
	if index < 0 or name == "" or names.is_empty():
		return index
	if index < names.size() and str(names[index]) == name:
		return index            # dos cámaras con el mismo nombre: se respeta la elegida
	return names.find(name)

## Argumentos de mf_hands.py con la cámara ya localizada entre las conectadas (names).
func build_args(script: String, names: Array, selftest: bool) -> Array:
	var cam := resolve_camera(camera, camera_name, names)
	var args := [script, "--port", str(port), "--token", token, "--camera", str(cam),
		"--width", str(width), "--height", str(height), "--fps", str(fps), "--parent-pid", str(OS.get_process_id())]
	if cam >= 0 and camera_name != "":
		args.append_array(["--camera-name", camera_name])
	if selftest:
		args.append("--selftest")
	return args

# --- Ciclo de vida del proceso ---------------------------------------------------------

## Arranca el seguimiento (selftest: sin cámara, para comprobar Python, modelo y UDP).
func start(selftest: bool = false) -> bool:
	if running:
		return true
	load_config()
	_error_reported = false
	selftest_ok = false
	if _udp.bind(port, "127.0.0.1") != OK:
		_set_status("No se pudo escuchar en 127.0.0.1:%d (¿otra copia de MechaForge usa el seguimiento?)." % port, "error")
		return false
	var script := find_script()
	if script == "":
		_udp.close()
		_set_status("No encuentro tools/handtracking/mf_hands.py.", "error")
		return false
	var names := list_cameras()
	var missing := camera >= 0 and resolve_camera(camera, camera_name, names) < 0
	pid = OS.create_process(python, build_args(script, names, selftest), false)
	if pid <= 0:
		_udp.close()
		_set_status("No se pudo ejecutar «%s». Instala Python 3 con mediapipe y opencv-python (tools/handtracking/requirements.txt) o indica la ruta de Python en %s." % [python, CONFIG_PATH], "error")
		return false
	running = true
	last_packet = now()
	_reset_filters()
	if missing and not selftest:
		_set_status("La cámara «%s» no está conectada: uso la primera que funcione." % camera_name, "warn")
	else:
		_set_status("Iniciando cámara y MediaPipe…", "info")
	return true

func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	_udp.close()
	if running:
		running = false
		_set_status("Apagado", "info")
	if not hands.is_empty():
		hands = []
		hands_updated.emit(hands)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		stop()

func _process(_delta: float) -> void:
	if not running:
		return
	while _udp.get_available_packet_count() > 0:
		var d = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			feed(d)
	var t := now()
	if not hands.is_empty() and t - last_packet > STALE_AFTER:
		hands = []
		hands_updated.emit(hands)
	if pid > 0 and not OS.is_process_running(pid):
		pid = -1
		running = false
		_udp.close()
		if not _error_reported:
			_set_status("El proceso de seguimiento terminó sin avisar. Comprueba que «%s» tiene mediapipe y opencv-python." % python, "error")

func _set_status(text: String, level: String) -> void:
	status_text = text
	status_level = level
	if level == "error":
		_error_reported = true
	status_changed.emit(text, level)

# --- Paquetes y filtrado ---------------------------------------------------------------

func _reset_filters() -> void:
	_filters.clear()
	_tracks.clear()

## Etiqueta de cada mano del paquete: la de su pista si se la venía siguiendo (la
## más cercana dentro de MATCH_RADIUS); si no, la de MediaPipe.
func _assign_labels(raw: Array, t: float) -> Array:
	for k in _tracks.keys():
		if t - float(_tracks[k]["t"]) > STALE_AFTER:
			_tracks.erase(k)
	var n := raw.size()
	var labels := []
	labels.resize(n)
	var pairs := []
	for i in range(n):
		for k in _tracks:
			var dist: float = (raw[i]["c"] as Vector2).distance_to(_tracks[k]["c"])
			if dist < MATCH_RADIUS:
				pairs.append([dist, i, k])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var taken := {}
	var votes := {}
	for pr in pairs:
		var i: int = pr[1]
		var k: String = pr[2]
		if labels[i] != null or taken.has(k):
			continue
		labels[i] = k
		taken[k] = true
		var mp: String = raw[i]["mp"]
		votes[i] = int(_tracks[k]["votes"]) + 1 if mp != k else 0
	# MediaPipe insiste en la otra etiqueta: se le hace caso (p. ej. se cambió de mano).
	for i in votes:
		var mp: String = raw[i]["mp"]
		if int(votes[i]) >= LABEL_VOTES and not labels.has(mp):
			labels[i] = mp
			votes[i] = 0
	for i in range(n):
		if labels[i] == null:
			var mp: String = raw[i]["mp"]
			labels[i] = mp if not labels.has(mp) else ("Left" if mp == "Right" else "Right")
			votes[i] = 0
	# Dos manos con la misma etiqueta (MediaPipe las dio iguales): la segunda es la otra.
	if n >= 2 and labels[0] == labels[1]:
		labels[1] = "Left" if labels[0] == "Right" else "Right"
	for i in range(n):
		_tracks[labels[i]] = {"c": raw[i]["c"], "votes": int(votes.get(i, 0)), "t": t}
	return labels

func set_filter_params(p_min_cutoff: float, p_beta: float) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	for k in _filters:
		for space in ["lm", "wlm"]:
			for f in _filters[k][space]:
				(f as OneEuroFilter).min_cutoff = min_cutoff
				(f as OneEuroFilter).beta = beta

func _filters_for(label: String) -> Dictionary:
	if not _filters.has(label):
		var lm := []
		var wlm := []
		for i in range(21):
			lm.append(OneEuroFilter.new(min_cutoff, beta))
			wlm.append(OneEuroFilter.new(min_cutoff, beta))
		_filters[label] = {"lm": lm, "wlm": wlm}
	return _filters[label]

## Procesa un paquete del proceso de seguimiento (también lo usan las pruebas).
## Devuelve false si el token no coincide.
func feed(d: Dictionary) -> bool:
	if str(d.get("token", "")) != token:
		return false
	last_packet = now()
	match str(d.get("type", "")):
		"status":
			if d.get("selftest_done", false):
				selftest_ok = true
			if d.has("width"):
				cam_size = Vector2i(int(d["width"]), int(d["height"]))
			_set_status(str(d.get("msg", "")), str(d.get("level", "info")))
		"hands":
			_on_hands(d)
	return true

func _on_hands(d: Dictionary) -> void:
	var t: float = float(d.get("t_cap", now()))
	latency_ms = maxf(0.0, (now() - t) * 1000.0)
	inference_ms = float(d.get("inf_ms", 0.0))
	_arrivals.append(now())
	while _arrivals.size() > 1 and float(_arrivals[_arrivals.size() - 1]) - float(_arrivals[0]) > 1.0:
		_arrivals.pop_front()
	if _arrivals.size() > 1:
		fps_measured = float(_arrivals.size() - 1) / maxf(1e-3, float(_arrivals[_arrivals.size() - 1]) - float(_arrivals[0]))
	if status_level != "ok" and status_level != "error":
		_set_status("Seguimiento activo.", "ok")
	var out := []
	var used := {}
	var img := Vector2(float(d.get("w", 640)), float(d.get("h", 480)))
	var valid := []
	var raw := []
	for h in d.get("hands", []):
		var raw_lm: Array = h.get("lm", [])
		if raw_lm.size() < 21:
			continue
		var c := Vector2.ZERO
		for i in [0, 5, 17]:
			c += Vector2(float(raw_lm[i][0]), float(raw_lm[i][1])) / 3.0
		valid.append(h)
		raw.append({"mp": "Left" if str(h.get("label", "Right")) == "Left" else "Right", "c": c})
	var labels := _assign_labels(raw, t)
	for j in range(valid.size()):
		var h: Dictionary = valid[j]
		var raw_lm: Array = h.get("lm", [])
		var label: String = labels[j]
		used[label] = true
		var raw_w: Array = h.get("wlm", [])
		var flt := _filters_for(label)
		var lm := PackedVector3Array()
		var wlm := PackedVector3Array()
		for i in range(21):
			var p: Array = raw_lm[i]
			lm.append((flt["lm"][i] as OneEuroFilter).filter(Vector3(p[0], p[1], p[2]), t))
			if raw_w.size() >= 21:
				var q: Array = raw_w[i]
				wlm.append((flt["wlm"][i] as OneEuroFilter).filter(Vector3(q[0], q[1], q[2]), t))
		out.append({"label": label, "score": float(h.get("score", 0.0)), "lm": lm, "wlm": wlm, "img": img, "t": t})
	# Filtros de manos que ya no se siguen: se reinician para no arrastrar su historia
	# (los de una mano que falta un par de paquetes se conservan).
	for k in _filters.keys():
		if not used.has(k) and not _tracks.has(k):
			_filters.erase(k)
	hands = out
	hands_updated.emit(hands)
