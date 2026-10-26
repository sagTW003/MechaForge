class_name McuIo
extends RefCounted
## McuIo — El programa del microcontrolador habla por I²C con los sensores a nivel
## de registros, como con la librería Wire de Arduino:
##   i2c_ok(dir)                    1 si el dispositivo responde (ACK), 0 si no
##   i2c_leer(dir, reg)             byte del registro (0…255), −1 si no responde
##   i2c16(dir, reg)                entero de 16 bits con signo (reg = byte alto,
##                                  reg + 1 = byte bajo), 0 si no responde
##   i2c_escribir(dir, reg, valor)  1 si responde (ACK), 0 si no
## Solo responden las IMU bien conectadas al bus de la placa (I2CBus) o sin cables.
##
## Registros del MPU-6050 (mapa de registros rev. 4.2): WHO_AM_I 0x75 = 0x68;
## PWR_MGMT_1 0x6B arranca en 0x40 (dormido: los datos se leen a 0 hasta escribir 0;
## el bit 7 reinicia); SMPLRT_DIV 0x19 y CONFIG 0x1A fijan el muestreo; GYRO_CONFIG
## 0x1B y ACCEL_CONFIG 0x1C (bits 4:3) los fondos de escala; datos en 0x3B–0x40
## (acelerómetro), 0x41–0x42 (temperatura: T = raw/340 + 36.53, 25 °C) y 0x43–0x48
## (giroscopio), en complemento a dos con el byte alto primero.
##
## Seguridad: las llamadas se resuelven ANTES de evaluar la expresión (se sustituyen
## por su resultado numérico), así la Expression nunca recibe un objeto propio. Aun
## sin objeto base, una Expression llega a funciones globales como str_to_var, que
## carga un script de la aplicación y permite reescribirlo y ejecutarlo: un proyecto
## compartido con el programa activo ejecutaría código al abrirse. Por eso cada
## expresión pasa antes por is_safe(): solo números, operadores, variables y las
## funciones de SAFE_CALLS.

const FUNCS := ["i2c_escribir", "i2c_leer", "i2c16", "i2c_ok"]
## Funciones matemáticas de @GlobalScope que puede llamar un programa, y las palabras
## de «a if condición else b» (pueden ir seguidas de un paréntesis).
const SAFE_CALLS := ["sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh",
	"tanh", "asinh", "acosh", "atanh", "sqrt", "pow", "exp", "log", "abs", "absf", "sign",
	"signf", "floor", "ceil", "round", "fmod", "fposmod", "clamp", "clampf", "min", "max",
	"minf", "maxf", "lerp", "lerpf", "inverse_lerp", "remap", "smoothstep", "move_toward",
	"deg_to_rad", "rad_to_deg", "snapped", "wrapf", "is_nan", "is_inf", "randf",
	"randf_range", "float", "int", "if", "else", "and", "or", "not"]
const DATA_KEYS := ["ax", "ay", "az", "t", "gx", "gy", "gz"]

var main: Node
var regs: Dictionary = {}          # uid -> {registro: valor}
var _re: RegEx

static var _call_re: RegEx

func reset() -> void:
	regs.clear()

## true si la expresión (ya sin llamadas i2c) solo tiene números, operadores,
## variables y llamadas a SAFE_CALLS. Sin comillas no hay textos que pasar a una
## función, y sin corchetes ni llaves no hay listas ni diccionarios.
static func is_safe(expr: String) -> bool:
	for ch in ["\"", "'", "[", "{", "$", "@"]:
		if expr.contains(ch):
			return false
	if _call_re == null:
		_call_re = RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for m in _call_re.search_all(expr):
		if not m.get_string(1) in SAFE_CALLS:
			return false
	return true

## Sustituye en "expr" cada llamada i2c_…(…) por su resultado. "eval" evalúa los
## argumentos (que pueden contener variables y otras llamadas). "" si algo falla.
func expand(expr: String, vars: Dictionary, eval: Callable) -> String:
	if _re == null:
		_re = RegEx.create_from_string("\\b(i2c_escribir|i2c_leer|i2c16|i2c_ok)\\s*\\(")
	var guard := 0
	while guard < 256:
		guard += 1
		var m := _re.search(expr)
		if m == null:
			return expr
		var open := m.get_end() - 1
		var depth := 0
		var close := -1
		for i in range(open, expr.length()):
			var ch := expr[i]
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
				if depth == 0:
					close = i
					break
		if close < 0:
			return ""
		var args := []
		for a in _split_args(expr.substr(open + 1, close - open - 1)):
			var v: float = eval.call(a, vars)
			if is_nan(v):
				return ""
			args.append(v)
		var r := call_fn(m.get_string(1), args)
		if is_nan(r):
			return ""
		expr = expr.substr(0, m.get_start()) + "(%s)" % str(r) + expr.substr(close + 1)
	return ""

## Argumentos separados por comas de primer nivel.
static func _split_args(s: String) -> Array:
	var out := []
	var depth := 0
	var cur := ""
	for ch in s:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out

func call_fn(fname: String, args: Array) -> float:
	var need := {"i2c_ok": 1, "i2c_leer": 2, "i2c16": 2, "i2c_escribir": 3}
	if args.size() != int(need.get(fname, -1)):
		return NAN
	var dev := device(int(args[0]))
	match fname:
		"i2c_ok":
			return 1.0 if dev else 0.0
		"i2c_leer":
			return float(read_reg(dev, int(args[1]) & 0xFF)) if dev else -1.0
		"i2c16":
			if dev == null:
				return 0.0
			var reg := int(args[1]) & 0xFF
			var v := (read_reg(dev, reg) << 8) | read_reg(dev, (reg + 1) & 0xFF)
			return float(v - 65536 if v >= 32768 else v)
		"i2c_escribir":
			if dev == null:
				return 0.0
			write_reg(dev, int(args[1]) & 0xFF, int(args[2]) & 0xFF)
			return 1.0
	return NAN

## IMU que responde en la dirección "addr" desde la placa del programa.
func device(addr: int) -> PartInstance:
	var bus: Dictionary = main.mcu_sensors.bus
	if bus.is_empty():
		bus = I2CBus.statuses(main)
	var board: PartInstance = main._find_mcu_part()
	for c in main.parts_root.get_children():
		if not (c is PartInstance):
			continue
		var p := c as PartInstance
		if not (p.def.has("imu") and p.def.has("terminales")) or I2CBus.address(p) != addr:
			continue
		var st: Dictionary = bus.get(p.uid, {})
		if st.is_empty() or not st.get("cableada", false):
			return p
		if st.get("ok", false) and (board == null or str(st.get("placa", "")) == board.uid):
			return p
	return null

func _regs(dev: PartInstance) -> Dictionary:
	if not regs.has(dev.uid):
		regs[dev.uid] = {0x6B: 0x40, 0x75: 0x68, 0x19: 0, 0x1A: 0, 0x1B: 0, 0x1C: 0}
	return regs[dev.uid]

func read_reg(dev: PartInstance, reg: int) -> int:
	var r := _regs(dev)
	if reg >= 0x3B and reg <= 0x48:
		if int(r[0x6B]) & 0x40 or not main.simulator.is_running():
			return 0
		var idx := reg - 0x3B
		var key: String = DATA_KEYS[idx / 2]
		var raw: int = int(roundf((25.0 - 36.53) * 340.0)) if key == "t" else int(main.mcu_sensors.raw_counts(dev, key))
		var u: int = raw & 0xFFFF
		return (u >> 8) & 0xFF if idx % 2 == 0 else u & 0xFF
	return int(r.get(reg, 0))

func write_reg(dev: PartInstance, reg: int, val: int) -> void:
	if reg == 0x75:
		return                       # WHO_AM_I es de solo lectura
	if reg == 0x6B and val & 0x80:
		regs.erase(dev.uid)          # DEVICE_RESET: vuelve a los valores de fábrica
		main.mcu_sensors.runtime.erase(dev.uid)
		return
	var r := _regs(dev)
	r[reg] = val
	var rt: Dictionary = main.mcu_sensors.runtime.get(dev.uid, {})
	match reg:
		0x1B:
			rt["gyro_fs_dps"] = 250.0 * pow(2.0, (val >> 3) & 3)
		0x1C:
			rt["accel_fs_g"] = 2.0 * pow(2.0, (val >> 3) & 3)
		0x19, 0x1A:
			var dlpf := int(r.get(0x1A, 0)) & 7
			var base := 8000.0 if dlpf == 0 or dlpf == 7 else 1000.0
			rt["odr_hz"] = base / (1 + int(r.get(0x19, 0)))
	main.mcu_sensors.runtime[dev.uid] = rt
