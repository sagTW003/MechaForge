class_name SimulatorApi
extends RefCounted
## SimulatorApi — Herramientas que OpenClaw puede usar sobre el simulador.
##
## Lectura (se ejecutan al momento):
##   get_scene_state, get_telemetry, analyze_design, list_parts, get_proposal_status,
##   get_circuit_state, measure_voltage (circuito vivo y multímetro)
## Control de la simulación (reversible, se ejecuta al momento):
##   run_simulation, stop_simulation
## Laboratorio matemático (se ejecutan al momento; no tocan el proyecto, solo la
## visualización, y cada acción se anuncia en la barra de estado del laboratorio):
##   lab_list_modules, lab_open, lab_close, lab_get_state, lab_set_param,
##   lab_control, lab_sample, lab_perturb, lab_capture, lab_plot
## Cambios en la escena (requieren confirmación del usuario — vista previa fantasma):
##   add_part, connect_parts, connect_wire, set_property, remove_part,
##   write_controller_script, configure_headset (ajustes del visor VR),
##   write_note (notas del proyecto; get_notes las lee)
## Visor VR (lectura): analyze_headset, check_headset, capture_headset_view
##
## "host" es el controlador principal (ui/Main.gd); aquí solo se valida y traduce.

const TOOLS := [
	{"name": "get_scene_state", "description": "Piezas (uid, tipo, material, posición, rotación, masa), uniones, cables y estado de la simulación.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "list_parts", "description": "Catálogo de piezas disponibles (def_id, nombre, categoría, dimensiones) y materiales.",
		"input_schema": {"type": "object", "properties": {"categoria": {"type": "string"}}}},
	{"name": "get_telemetry", "description": "Telemetría en vivo (posición, velocidad, velocidad angular, masa) de una pieza o de todas, más consumo eléctrico y medidas de control.",
		"input_schema": {"type": "object", "properties": {"uid": {"type": "string"}}}},
	{"name": "analyze_design", "description": "Análisis: masa total, centro de masa, estabilidad/vuelco, esfuerzo estimado por pieza, consumo y autonomía.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "add_part", "description": "Propone añadir una pieza (vista previa; el usuario confirma). Posición en metros; el suelo es y=0.",
		"input_schema": {"type": "object", "required": ["def_id", "pos"], "properties": {
			"def_id": {"type": "string"}, "material": {"type": "string"},
			"pos": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
			"rot_deg": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}}}},
	{"name": "connect_parts", "description": "Propone una unión entre dos piezas: fija, bisagra, deslizadera, rotula o engranaje; opcionalmente con motor. Eje en ejes del mundo; anclaje en m (por defecto, el punto medio); límites en grados (bisagra) o mm (deslizadera). Bisagra con motor: tipo_motor dc/paso/servo, control posicion/velocidad con consigna (° o rad/s) y PID [kp, ki, kd], y perfil de consigna (seno o cuadrada: amplitud, frecuencia Hz, desfase °, centro; ideal=true sigue el perfil exacto, banco de pruebas). Deslizadera: bloqueada=true la fija al simular (un ajuste, como la distancia entre lentes).",
		"input_schema": {"type": "object", "required": ["a", "b", "union"], "properties": {
			"a": {"type": "string"}, "b": {"type": "string"},
			"union": {"type": "string", "enum": ["fija", "bisagra", "deslizadera", "rotula", "engranaje"]},
			"eje": {"type": "string", "enum": ["X", "Y", "Z"]}, "motor": {"type": "boolean"},
			"velocidad": {"type": "number"}, "torque": {"type": "number"},
			"z1": {"type": "integer"}, "z2": {"type": "integer"},
			"anclaje": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
			"limites": {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2},
			"tipo_motor": {"type": "string", "enum": ["dc", "paso", "servo"]},
			"control": {"type": "string", "enum": ["ninguno", "posicion", "velocidad"]},
			"consigna": {"type": "number"},
			"pid": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
			"perfil": {"type": "object", "properties": {"tipo": {"type": "string", "enum": ["fija", "seno", "cuadrada"]},
				"amplitud": {"type": "number"}, "frecuencia": {"type": "number"}, "desfase": {"type": "number"},
				"centro": {"type": "number"}, "ideal": {"type": "boolean"}}},
			"bloqueada": {"type": "boolean"}}}},
	{"name": "connect_wire", "description": "Propone un cable entre dos terminales 'uid:terminal' (p. ej. 'p12:5V' y 'p34:VCC'); el tipo (alimentación, tierra o señal) sale de los terminales. Los terminales de cada pieza están en list_parts / get_scene_state.",
		"input_schema": {"type": "object", "required": ["a", "b"], "properties": {
			"a": {"type": "string"}, "b": {"type": "string"},
			"color": {"type": "string", "enum": ["auto", "rojo", "negro", "naranja", "amarillo", "azul", "verde", "blanco"]}}}},
	{"name": "set_property", "description": "Propone cambiar material, dimensiones (mm), posición (m), rotación (grados), anclaje al mundo o ajustes de una pieza en «estado»: ojo_mm (lente: distancia ojo–lente), i2c_dir (IMU: 104 = 0x68 o 105 = 0x69), impresion {relleno 0–1, paredes_mm}, imu {odr_hz, gyro_fs_dps, accel_fs_g, ideal}, colision (multiple, convexa o caja).",
		"input_schema": {"type": "object", "required": ["uid"], "properties": {
			"uid": {"type": "string"}, "material": {"type": "string"},
			"dims_mm": {"type": "object"}, "pos": {"type": "array", "items": {"type": "number"}},
			"rot_deg": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
			"anclada": {"type": "boolean"}, "estado": {"type": "object"}}}},
	{"name": "configure_headset", "description": "Propone los ajustes del visor VR (se guardan con el proyecto): seguimiento real o imu (las cámaras siguen la orientación roll/pitch/yaw del programa), retardo_ms del enlace, perfil del render (diseno, manual, cardboard_v1, cardboard_v2) y perfil_manual {ipd_mm, dist_mm, k1, k2}, ipd_usuario_mm, predistorsion, cromatica y calidad (0 baja, 1 media, 2 alta).",
		"input_schema": {"type": "object", "properties": {
			"seguimiento": {"type": "string", "enum": ["real", "imu"]}, "retardo_ms": {"type": "number"},
			"perfil": {"type": "string", "enum": ["diseno", "manual", "cardboard_v1", "cardboard_v2"]},
			"perfil_manual": {"type": "object"}, "ipd_usuario_mm": {"type": "number"},
			"predistorsion": {"type": "boolean"}, "cromatica": {"type": "boolean"},
			"calidad": {"type": "integer", "minimum": 0, "maximum": 2}}}},
	{"name": "capture_headset_view", "description": "Guarda en PNG lo que muestra la pantalla del visor (vista 'pantalla') o lo que ve un ojo a través de su lente ('ojo_izquierdo', 'ojo_derecho') y devuelve la ruta. El render del visor debe estar activo (panel 👓 Visor abierto o simulando con la pantalla encendida).",
		"input_schema": {"type": "object", "properties": {"vista": {"type": "string", "enum": ["pantalla", "ojo_izquierdo", "ojo_derecho"]}}}},
	{"name": "remove_part", "description": "Propone eliminar una pieza.",
		"input_schema": {"type": "object", "required": ["uid"], "properties": {"uid": {"type": "string"}}}},
	{"name": "write_controller_script", "description": "Propone el programa del microcontrolador (líneas 'variable = expresión'; la última es la consigna). Las variables conservan su valor entre pasos (empiezan en 0); bajo 'inicio:' solo el primer paso, bajo 'bucle:' cada paso. Entradas: t, x, dt y sensores (IMU: imu1_ax/ay/az en g, imu1_gx/gy/gz en °/s).",
		"input_schema": {"type": "object", "required": ["script"], "properties": {"script": {"type": "string"}}}},
	{"name": "run_simulation", "description": "Inicia la simulación física.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "check_headset", "description": "Verificación del visor VR: por ojo, desalineación de la imagen, distorsión residual y aberración cromática residual (minutos de arco) según el perfil del render frente a las lentes reales; convergencia y desnivel entre los ojos (Δ) con la IPD del usuario; masa, centro de masa respecto de la cara y par; holguras de las lentes y contactos o interferencias entre piezas; avisos.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "analyze_headset", "description": "Óptica del visor VR de la escena (pantalla + lentes): distancia lente–pantalla, imagen virtual, aumento, campo de visión, píxeles por grado, distancia entre lentes (IPD) y avisos; en «render», las cámaras de los ojos (posición, campo con la distorsión de la lente, resolución) de la imagen lado a lado; en «seguimiento», la orientación estimada por el programa con la IMU frente a la real (error RMS por eje, deriva de la guiñada, latencia y error de la vista).", "input_schema": {"type": "object", "properties": {}}},
	{"name": "stop_simulation", "description": "Detiene la simulación y restaura el estado inicial.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "get_proposal_status", "description": "Estado de una propuesta: pending, applied o discarded.",
		"input_schema": {"type": "object", "required": ["id"], "properties": {"id": {"type": "integer"}}}},
	{"name": "get_circuit_state", "description": "Circuito vivo: fuentes (tensión, corriente, desconexión por protección), LED (corriente, encendido/quemado), cortocircuito crítico, componentes insertados en la protoboard (pata → agujero) y lectura del multímetro (modo, pantalla, sondas, fusibles).",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "measure_voltage", "description": "Mide (solo lectura, sin mover las sondas) la tensión entre dos terminales 'uid:terminal' del circuito vivo, p. ej. 'p123:anodo' y 'p456:a14_0' (agujero de la protoboard).",
		"input_schema": {"type": "object", "required": ["a", "b"], "properties": {"a": {"type": "string"}, "b": {"type": "string"}}}},
	{"name": "lab_list_modules", "description": "Laboratorio matemático: sus módulos (id, pilar, nombre, descripción).",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "lab_open", "description": "Abre el Laboratorio matemático (la escena de MechaForge se conserva) en un módulo, o cambia de módulo si ya está abierto.",
		"input_schema": {"type": "object", "properties": {"modulo": {"type": "string", "description": "id de lab_list_modules, p. ej. 'schrodinger'"}}}},
	{"name": "lab_close", "description": "Cierra el laboratorio y vuelve a MechaForge.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "lab_get_state", "description": "Estado del laboratorio: módulo, fórmula, lecturas en vivo (ceros, polos, energía, error, flujo…), puntos críticos en coordenadas matemáticas y todos los controles con su valor, rango u opciones.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "lab_set_param", "description": "Cambia un control del módulo (deslizador, número, opción, casilla, expresión) o pulsa un botón, por su nombre o id de lab_get_state.",
		"input_schema": {"type": "object", "required": ["nombre"], "properties": {
			"nombre": {"type": "string"}, "valor": {"description": "número, texto de la opción o su índice, true/false, o la expresión (p. ej. '(z^2-1)/(z^2+1)')"}}}},
	{"name": "lab_control", "description": "Controles generales del laboratorio.",
		"input_schema": {"type": "object", "required": ["accion"], "properties": {
			"accion": {"type": "string", "enum": ["pausar", "reanudar", "reiniciar", "encuadrar", "vista_perspectiva", "vista_superior", "vista_isometrica", "velocidad"]},
			"valor": {"type": "number", "description": "para 'velocidad': 0.25, 0.5, 1, 2, 4 u 8"}}}},
	{"name": "lab_sample", "description": "Lectura (solo lectura) en el punto matemático (x, y) del módulo: el mismo texto que el tooltip flotante.",
		"input_schema": {"type": "object", "required": ["x", "y"], "properties": {"x": {"type": "number"}, "y": {"type": "number"}}}},
	{"name": "lab_perturb", "description": "Equivale a un clic con «✋ Perturbar» en (x, y): pulso de onda, fuente de calor, barrera, punto inicial… según el módulo.",
		"input_schema": {"type": "object", "required": ["x", "y"], "properties": {"x": {"type": "number"}, "y": {"type": "number"}}}},
	{"name": "lab_capture", "description": "Guarda una captura PNG de la ventana del laboratorio y devuelve la ruta del archivo.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "lab_plot", "description": "Dibuja en el módulo «Gráficas» del laboratorio (lo abre si hace falta): hasta 4 funciones y = f(x) con sus raíces, extremos y cortes, o una curva paramétrica, una polar o una superficie, más puntos de datos. Fórmulas en notación normal (2x, sin x, x^2, e^(-x), sqrt(x), ln x, pi).",
		"input_schema": {"type": "object", "properties": {
			"funciones": {"type": "array", "items": {"type": "string"}, "description": "p. ej. [\"x^2 - 2\", \"sin x\"]"},
			"x": {"type": "array", "description": "intervalo [mín, máx] (números o expresiones como \"-2pi\"); dominio de x en superficies"},
			"y": {"type": "array", "description": "intervalo [mín, máx] (opcional: automático)"},
			"parametrica": {"type": "object", "description": "{\"x\": \"cos t\", \"y\": \"sin t\", \"t\": [0, \"2pi\"]}"},
			"polar": {"type": "object", "description": "{\"r\": \"1 + cos θ\", \"t\": [0, \"2pi\"]}"},
			"superficie": {"type": "string", "description": "z = f(x, y), p. ej. \"sin x cos y\""},
			"puntos": {"type": "array", "description": "[[x, y], …]"},
			"titulo": {"type": "string"}, "marcar": {"type": "boolean"}}}},
	{"name": "write_note", "description": "Propone escribir en las notas del proyecto (resumen de un documento, datos de un enunciado, pasos de una solución). El usuario confirma.",
		"input_schema": {"type": "object", "required": ["texto"], "properties": {"titulo": {"type": "string"}, "texto": {"type": "string"}}}},
	{"name": "get_notes", "description": "Lee las notas del proyecto.", "input_schema": {"type": "object", "properties": {}}},
]

static var TOOL_NAMES: Array = TOOLS.map(func(t): return t["name"])

var host: Node

func _init(h: Node) -> void:
	host = h

## Herramientas de la escena que siguen disponibles con el laboratorio abierto.
const LAB_SAFE := ["list_parts", "get_proposal_status", "get_notes"]

func call_tool(name: String, p: Dictionary) -> Dictionary:
	if host.get("math_lab") != null and not name.begins_with("lab_") and not name in LAB_SAFE and name in TOOL_NAMES:
		return {"error": "El Laboratorio matemático está abierto: usa lab_close para volver a MechaForge antes de '%s'." % name}
	match name:
		"get_scene_state": return host.api_scene_state()
		"list_parts": return _list_parts(str(p.get("categoria", "")))
		"get_telemetry": return host.api_telemetry(str(p.get("uid", "")))
		"analyze_design": return host.api_analyze()
		"analyze_headset": return host.api_headset()
		"check_headset": return host.api_headset_check()
		"capture_headset_view": return host.api_capture_headset(str(p.get("vista", "pantalla")))
		"connect_wire": return _wire(p)
		"configure_headset": return _headset_config(p)
		"run_simulation": return host.api_run(true)
		"stop_simulation": return host.api_run(false)
		"get_proposal_status": return host.api_proposal_status(int(p.get("id", -1)))
		"get_circuit_state": return host.api_circuit_state()
		"measure_voltage": return host.api_measure_voltage(str(p.get("a", "")), str(p.get("b", "")))
		"add_part": return _add_part(p)
		"connect_parts": return _connect(p)
		"set_property": return _set_property(p)
		"remove_part": return _remove(p)
		"write_controller_script": return _script(p)
		"lab_list_modules": return LabApi.modules()
		"lab_open": return host.api_lab_open(str(p.get("modulo", "")))
		"lab_close": return host.api_lab_close()
		"lab_get_state": return host.api_lab_state()
		"lab_set_param":
			var key := str(p.get("nombre", ""))
			var val = p.get("valor", null)
			return host.api_lab(func(lab): return LabApi.set_param(lab, key, val))
		"lab_control":
			var act := str(p.get("accion", ""))
			var v = p.get("valor", null)
			return host.api_lab(func(lab): return LabApi.control(lab, act, v))
		"lab_sample", "lab_perturb":
			if not (typeof(p.get("x")) in [TYPE_INT, TYPE_FLOAT] and typeof(p.get("y")) in [TYPE_INT, TYPE_FLOAT]):
				return {"error": "x e y deben ser números (coordenadas matemáticas del módulo)"}
			var x := float(p["x"])
			var y := float(p["y"])
			if name == "lab_sample":
				return host.api_lab(func(lab): return LabApi.sample(lab, x, y))
			return host.api_lab(func(lab): return LabApi.perturb(lab, x, y))
		"lab_capture": return host.api_lab(func(lab): return LabApi.capture(lab))
		"lab_plot": return host.api_lab_plot(p)
		"write_note":
			var txt := str(p.get("texto", ""))
			if txt.strip_edges() == "":
				return {"error": "texto vacío"}
			return host.api_propose([{"tipo": "nota", "titulo": str(p.get("titulo", "")), "texto": txt}])
		"get_notes": return host.api_notes()
	return {"error": "herramienta desconocida: %s" % name}

func _list_parts(cat: String) -> Dictionary:
	var parts := []
	for id in PartLibrary.all_ids():
		var d := PartLibrary.get_def(id)
		if cat != "" and d.get("categoria", "") != cat:
			continue
		var item := {"def_id": id, "nombre": d.get("nombre", id), "categoria": d.get("categoria", ""),
			"dimensiones_mm": d.get("dimensiones_mm", {}), "material": d.get("material", "")}
		if d.has("terminales"):
			item["terminales"] = (d["terminales"] as Array).map(func(t): return "%s (%s)" % [t.get("id", ""), t.get("tipo", "signal")])
		if d.has("descripcion"):
			item["descripcion"] = d["descripcion"]
		parts.append(item)
	return {"piezas": parts, "materiales": MaterialLibrary.ids()}

static func _vec3(v, fallback = Vector3.ZERO) -> Variant:
	if typeof(v) != TYPE_ARRAY or v.size() < 3:
		return fallback
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

func _add_part(p: Dictionary) -> Dictionary:
	var def_id := str(p.get("def_id", ""))
	if not PartLibrary.has_part(def_id):
		return {"error": "def_id inexistente: %s (usa list_parts)" % def_id}
	var mat := str(p.get("material", PartLibrary.get_def(def_id).get("material", "aluminio")))
	if not MaterialLibrary.has_material(mat):
		return {"error": "material inexistente: %s" % mat}
	var pos = _vec3(p.get("pos"), null)
	if pos == null:
		return {"error": "pos debe ser [x, y, z] en metros"}
	var rot: Vector3 = _vec3(p.get("rot_deg"), Vector3.ZERO)
	return host.api_propose([{"tipo": "add_part", "def_id": def_id, "material": mat,
		"pos": [pos.x, pos.y, pos.z], "rot_deg": [rot.x, rot.y, rot.z]}])

func _connect(p: Dictionary) -> Dictionary:
	for k in ["a", "b"]:
		if host._find_part(str(p.get(k, ""))) == null:
			return {"error": "pieza '%s' no encontrada" % str(p.get(k, ""))}
	var union := str(p.get("union", "fija")).to_lower()
	if not union in ["fija", "bisagra", "deslizadera", "rotula", "engranaje"]:
		return {"error": "union no válida: %s" % union}
	var a := p.duplicate()
	a["tipo"] = "connect"
	return host.api_propose([a])

const ESTADO_KEYS := ["ojo_mm", "i2c_dir", "impresion", "imu", "colision"]

func _set_property(p: Dictionary) -> Dictionary:
	if host._find_part(str(p.get("uid", ""))) == null:
		return {"error": "pieza no encontrada"}
	if p.has("material") and not MaterialLibrary.has_material(str(p["material"])):
		return {"error": "material inexistente"}
	if p.has("estado"):
		if typeof(p["estado"]) != TYPE_DICTIONARY:
			return {"error": "estado debe ser un objeto"}
		for k in p["estado"]:
			if not str(k) in ESTADO_KEYS:
				return {"error": "estado.%s no se puede cambiar (válidos: %s)" % [k, ", ".join(ESTADO_KEYS)]}
	var a := p.duplicate()
	a["tipo"] = "set_property"
	return host.api_propose([a])

## Terminal «uid:terminal» de una pieza de la escena (vacío si no existe).
func _terminal(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	var part: PartInstance = host._find_part(parts[0])
	if part == null:
		return {}
	for t in part.def.get("terminales", []):
		if str(t.get("id", "")) == parts[1]:
			return t
	return {}

func _wire(p: Dictionary) -> Dictionary:
	var a := str(p.get("a", ""))
	var b := str(p.get("b", ""))
	for k in [a, b]:
		if _terminal(k).is_empty():
			return {"error": "terminal '%s' no encontrado (formato 'uid:terminal')" % k}
	if a == b:
		return {"error": "los dos extremos son el mismo terminal"}
	return host.api_propose([{"tipo": "cable", "a": a, "b": b, "color": str(p.get("color", "auto"))}])

func _headset_config(p: Dictionary) -> Dictionary:
	var keys := ["seguimiento", "retardo_ms", "perfil", "perfil_manual", "ipd_usuario_mm", "predistorsion", "cromatica", "calidad"]
	var a := {"tipo": "visor"}
	for k in p:
		if not str(k) in keys:
			return {"error": "ajuste desconocido: %s (válidos: %s)" % [k, ", ".join(keys)]}
		a[k] = p[k]
	if a.size() == 1:
		return {"error": "no hay ajustes"}
	if a.has("perfil") and not str(a["perfil"]) in ["diseno", "manual", "cardboard_v1", "cardboard_v2"]:
		return {"error": "perfil no válido"}
	return host.api_propose([a])

func _remove(p: Dictionary) -> Dictionary:
	if host._find_part(str(p.get("uid", ""))) == null:
		return {"error": "pieza no encontrada"}
	return host.api_propose([{"tipo": "remove", "uid": str(p["uid"])}])

func _script(p: Dictionary) -> Dictionary:
	var s := str(p.get("script", ""))
	if s.strip_edges() == "":
		return {"error": "script vacío"}
	if is_nan(host._mcu_run(s.split("\n"), 0.0, 0.0, 1.0 / 120.0)):
		if McuProgram.rejected != "":
			return {"error": "el script no es válido: no se permite «%s». Se permite: %s" % [McuProgram.rejected, ", ".join(McuIo.SAFE_CALLS)]}
		return {"error": "el script no es válido (usa 'variable = expresión')"}
	return host.api_propose([{"tipo": "script", "script": s}])
