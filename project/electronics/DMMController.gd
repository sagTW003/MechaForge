class_name DMMController
extends RefCounted
## DMMController — Estado y lógica de medida del multímetro digital.
##
## Modos del selector giratorio: OFF, V⎓ (tensión continua), V~ (tensión alterna,
## valor eficaz de la componente alterna), A⎓ (corriente), Ω y continuidad (🔊).
## Las puntas (roja = VΩmA / 10 A, negra = COM) tocan terminales del circuito;
## la lectura se calcula con la solución del circuito vivo (CircuitRuntime):
##   · V: diferencia de potencial V(roja) − V(negra) con 10 MΩ de entrada (en
##     paralelo, sin alterar el circuito).
##   · A: el amperímetro es un derivador EN SERIE: borne VΩmA (1 Ω, fusible de
##     400 mA) o borne 10 A (0.01 Ω, fusible de 10 A). Si se conecta en paralelo
##     con la fuente (casi un cortocircuito) la corriente supera el fusible y lo
##     FUNDE: chispas en las puntas y la pantalla muestra «FUSE» hasta reemplazarlo.
##   · Ω: resistencia equivalente entre las puntas SOLO con el circuito
##     desenergizado (si hay una fuente conectada muestra «Err»).
##   · Continuidad: si R < 50 Ω pita (tono sintético) y enciende el LED.
## El estado (modo, fusible y posición de las sondas) se guarda en la pieza.

signal fuse_blown

enum Mode { OFF, V_DC, V_AC, A_DC, OHM, CONT }
const MODE_IDS := ["OFF", "V_DC", "V_AC", "A_DC", "OHM", "CONT"]
const MODE_NAMES := ["OFF", "V⎓", "V~", "A⎓", "Ω", "🔊"]
const MODE_LONG := ["Apagado", "Tensión continua", "Tensión alterna (RMS)", "Corriente continua", "Resistencia", "Continuidad"]
const CONT_THRESHOLD := 50.0
const R_IN := 10.0e6
const R_SHUNT_MA := 1.0         # borne VΩmA (rango mA)
const FUSE_MA := 0.4
const R_SHUNT_10A := 0.01       # borne 10 A
const FUSE_10A := 10.0
const V_TEST := 1.0
const R_TEST := 10000.0
const AC_WINDOW := 1.0

var part: PartInstance
var main: Node
var mode: int = Mode.V_DC
var fuse_ok: bool = true            # fusible del borne en uso (mA o 10 A)
var fuse_ma_ok: bool = true
var fuse_10a_ok: bool = true
var jack_10a: bool = false          # sonda roja en el borne 10 A
var display: String = "0.000"
var unit: String = "V"
var value: float = 0.0
var beeping: bool = false
var status: String = ""
var _shunt_branch: int = -1
var _over: float = 0.0
var _ac: Array = []            # [[t, v], …]
var _t: float = 0.0

## Asocia el controlador a la pieza multímetro (y carga su estado guardado).
func bind(p: PartInstance, m: Node) -> void:
	part = p
	main = m
	_ac.clear()
	_over = 0.0
	if part == null:
		return
	var st := part.estado
	mode = maxi(0, MODE_IDS.find(str(st.get("modo", "V_DC"))))
	fuse_ma_ok = bool(st.get("fusible", true))
	fuse_10a_ok = bool(st.get("fusible_10a", true))
	jack_10a = bool(st.get("borne_10a", false))
	_sync_fuse()
	if not st.has("roja"):
		st["roja"] = {"clave": "", "pos": null}
	if not st.has("negra"):
		st["negra"] = {"clave": "", "pos": null}

func set_mode(m: int) -> void:
	mode = clampi(m, 0, MODE_IDS.size() - 1)
	_ac.clear()
	if part:
		part.estado["modo"] = MODE_IDS[mode]

func _sync_fuse() -> void:
	fuse_ok = fuse_10a_ok if jack_10a else fuse_ma_ok

func fuse_rating() -> float:
	return FUSE_10A if jack_10a else FUSE_MA

func set_jack_10a(on: bool) -> void:
	jack_10a = on
	_over = 0.0
	_sync_fuse()
	if part:
		part.estado["borne_10a"] = on

## Reemplaza los dos fusibles (400 mA y 10 A).
func replace_fuse() -> void:
	fuse_ma_ok = true
	fuse_10a_ok = true
	_over = 0.0
	_sync_fuse()
	if part:
		part.estado["fusible"] = true
		part.estado["fusible_10a"] = true

## Clave del terminal que toca una sonda ("" = suelta).
func probe_key(which: String) -> String:
	if part == null:
		return ""
	return str(part.estado.get(which, {}).get("clave", ""))

func set_probe(which: String, key: String, free_pos = null) -> void:
	if part == null:
		return
	var d := {"clave": key, "pos": null}
	if free_pos is Vector3:
		d["pos"] = [free_pos.x, free_pos.y, free_pos.z]
	part.estado[which] = d
	_ac.clear()

## Punta de la sonda en el mundo (terminal, posición libre o reposo junto al DMM).
func probe_tip(which: String) -> Vector3:
	if part == null or main == null:
		return Vector3.ZERO
	var k := probe_key(which)
	if k != "":
		var p = main._terminal_live_by_key(k)
		if p != null:
			return p
	var fp = part.estado.get(which, {}).get("pos", null)
	if fp is Array and (fp as Array).size() == 3:
		return Vector3(fp[0], fp[1], fp[2])
	var xf: Transform3D = main._part_live_xform(part)
	var side := 1.0 if which == "roja" else -1.0
	var dm := PartLibrary.dims_m(part.def)
	return xf * Vector3(side * (dm.x * 0.5 + 0.018), -dm.y * 0.5 + 0.0045, -dm.z * 0.3)

## Elementos del propio multímetro en la netlist (según el modo).
func add_elements(n: NodeNetlist) -> void:
	_shunt_branch = -1
	var r := probe_key("roja")
	var b := probe_key("negra")
	if r == "" or b == "" or r == b:
		return
	match mode:
		Mode.V_DC, Mode.V_AC:
			n.add_branch(r, b, R_IN, 0.0, {"kind": "dmm"})
		Mode.A_DC:
			if fuse_ok:
				_shunt_branch = n.add_branch(r, b, R_SHUNT_10A if jack_10a else R_SHUNT_MA, 0.0, {"kind": "dmm_shunt"})

## Comprueba el fusible (modo A). Devuelve true si se acaba de fundir.
func check_fuse(rt: CircuitRuntime, dt: float) -> bool:
	if mode != Mode.A_DC or not fuse_ok or _shunt_branch < 0:
		_over = 0.0
		return false
	var i := absf(rt.branch_current(_shunt_branch))
	var rating := fuse_rating()
	# Fusible rápido: instantáneo por encima de 3× su valor, o tras 50 ms por encima de 1.5×.
	if i > 1.5 * rating:
		_over += dt
	else:
		_over = 0.0
	if i > 3.0 * rating or _over > 0.05:
		if jack_10a:
			fuse_10a_ok = false
			part.estado["fusible_10a"] = false
		else:
			fuse_ma_ok = false
			part.estado["fusible"] = false
		_sync_fuse()
		_shunt_branch = -1
		_over = 0.0
		fuse_blown.emit()
		return true
	return false

func update(rt: CircuitRuntime, dt: float) -> void:
	_t += dt
	beeping = false
	status = ""
	if part == null:
		return
	if mode == Mode.OFF:
		display = ""
		unit = ""
		return
	var r := probe_key("roja")
	var b := probe_key("negra")
	var both := r != "" and b != ""
	match mode:
		Mode.V_DC:
			var v := 0.0
			if both:
				var vr := rt.voltage(r)
				var vb := rt.voltage(b)
				v = 0.0 if (is_nan(vr) or is_nan(vb)) else vr - vb
			value = v
			_fmt_volts(v)
		Mode.V_AC:
			var v2 := 0.0
			if both:
				var vr2 := rt.voltage(r)
				var vb2 := rt.voltage(b)
				v2 = 0.0 if (is_nan(vr2) or is_nan(vb2)) else vr2 - vb2
			_ac.append([_t, v2])
			while not _ac.is_empty() and _t - float(_ac[0][0]) > AC_WINDOW:
				_ac.pop_front()
			var mean := 0.0
			for s in _ac: mean += float(s[1])
			mean /= maxf(1.0, _ac.size())
			var acc := 0.0
			for s in _ac: acc += pow(float(s[1]) - mean, 2.0)
			value = sqrt(acc / maxf(1.0, _ac.size()))
			_fmt_volts(value)
		Mode.A_DC:
			if not fuse_ok:
				display = "FUSE"
				unit = "A"
				value = 0.0
				status = "Fusible de %s fundido: reemplázalo." % ("10 A" if jack_10a else "400 mA")
				return
			var i := rt.branch_current(_shunt_branch) if (both and _shunt_branch >= 0) else 0.0
			value = i
			if absf(i) < 0.6:
				display = _num(i * 1000.0, 2 if absf(i * 1000.0) < 100.0 else 1)
				unit = "mA"
			else:
				display = _num(i, 3 if absf(i) < 6.0 else 2)
				unit = "A"
		Mode.OHM, Mode.CONT:
			unit = "Ω"
			if not both:
				display = "OL"
				value = INF
				return
			if rt.energized([r, b]):
				display = "Err"
				value = NAN
				status = "Circuito energizado: apaga la alimentación para medir resistencia."
				return
			var ohm := rt.measure_resistance(r, b)
			value = ohm
			if mode == Mode.CONT:
				beeping = ohm < CONT_THRESHOLD
				if ohm > 600.0:
					display = "OL"
				else:
					display = _num(ohm, 1)
				return
			if ohm > 40.0e6 or is_inf(ohm):
				display = "OL"
			elif ohm < 1000.0:
				display = _num(ohm, 1)
			elif ohm < 1.0e6:
				display = _num(ohm / 1000.0, 3 if ohm < 1.0e4 else 2)
				unit = "kΩ"
			else:
				display = _num(ohm / 1.0e6, 2)
				unit = "MΩ"

func _fmt_volts(v: float) -> void:
	var a := absf(v)
	if a < 0.6:
		display = _num(v * 1000.0, 1)
		unit = "mV"
	elif a < 6.0:
		display = _num(v, 3)
		unit = "V"
	elif a < 60.0:
		display = _num(v, 2)
		unit = "V"
	else:
		display = _num(v, 1)
		unit = "V"

func _num(x: float, dec: int) -> String:
	var s := ("%." + str(dec) + "f") % x
	if s.begins_with("-0.") and absf(x) < pow(10.0, -dec) * 0.5:
		s = s.substr(1)
	return s

## Texto completo para la interfaz: "1.953 V" / "OL Ω" / "FUSE".
func reading_text() -> String:
	if mode == Mode.OFF:
		return "— apagado —"
	return ("%s %s" % [display, unit]).strip_edges()

# --- Pantalla LCD de 7 segmentos ---
## Bits: a=1 (arriba), b=2, c=4, d=8 (abajo), e=16, f=32, g=64 (centro).
const SEG := {
	"0": 63, "1": 6, "2": 91, "3": 79, "4": 102, "5": 109, "6": 125, "7": 7, "8": 127, "9": 111,
	"O": 63, "L": 56, "E": 121, "r": 80, "F": 113, "U": 62, "S": 109, "o": 92, "n": 84,
	"P": 115, "A": 119, "H": 118, "d": 94, "t": 120, "C": 57, "-": 64, " ": 0,
}

## Codifica el texto de la pantalla en 4 dígitos: {seg: [4 ints], dp: bits, minus}.
static func lcd_encode(text: String) -> Dictionary:
	var cells := []
	var dps := []
	var minus := false
	var t := text.strip_edges()
	if t.begins_with("-"):
		minus = true
		t = t.substr(1)
	for ch in t:
		if ch == ".":
			if not dps.is_empty():
				dps[dps.size() - 1] = true
			continue
		cells.append(int(SEG.get(ch, 0)))
		dps.append(false)
	while cells.size() > 4:
		cells.pop_front(); dps.pop_front()
	while cells.size() < 4:
		cells.push_front(0); dps.push_front(false)
	var dp := 0
	for i in range(4):
		if dps[i]:
			dp |= 1 << i
	return {"seg": cells, "dp": dp, "minus": minus}
