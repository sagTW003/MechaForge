class_name CircuitRuntime
extends Node
## CircuitRuntime — Simulación eléctrica EN VIVO del circuito (edición y simulación).
##
## En cada paso construye la netlist (NodeNetlist) a partir de la geometría 3D —
## cables, tiras internas de la protoboard, patas insertadas y sondas del
## multímetro— y la resuelve con el solver no lineal en C# (LED = diodo real).
## Con la solución:
##   · calienta cada cable según I²·R (modelo térmico de primer orden) y lo pinta
##     incandescente (shader de color de cuerpo negro) cuando supera ~450 °C;
##   · detecta el CORTOCIRCUITO CRÍTICO (fuente con carga externa < 0.5 Ω y > 1 A):
##     chispas, humo y, por protección térmica, desconecta la fuente;
##   · quema LED y resistencias sobrecargados (quedan abiertos, con humo);
##   · hace oscilar el NE555 (astable) y aplica las salidas digitales del Arduino
##     Nano que escribe el programa del microcontrolador (d2…d13);
##   · ilumina los LED según su corriente y alimenta el multímetro (DMMController).

signal solved
signal short_changed(active: bool)
signal protection_tripped(source_name: String)

const WIRE_R := 0.05          # Ω por cable (jumper + contactos de la protoboard)
const WIRE_C := 0.004         # J/K: capacidad térmica del conductor del cable
const WIRE_K := 0.002         # W/K: pérdidas al ambiente (τ = C/K = 2 s)
const T_AMB := 25.0
const T_GLOW := 450.0         # °C: empieza a verse rojo oscuro (punto de Draper ≈ 525 °C)
const T_SMOKE := 180.0        # °C: el aislamiento de PVC humea
const T_TRIP := 600.0         # °C: la protección térmica desconecta la fuente
const SHORT_TRIP_TIME := 2.5  # s de cortocircuito sostenido antes de desconectar
const SHORT_R := 0.5          # Ω: carga externa menor = cortocircuito
const SHORT_I := 1.0          # A mínimos para considerarlo crítico
const EDIT_PERIOD := 1.0 / 30.0
const NVT := 2.0 * 0.025852   # n·Vt de un LED (n ≈ 2, 25 °C)
const LED_RS := 8.0

var main: Node
var power_on: bool = true               # interruptor general de alimentación
var tripped: Dictionary = {}            # uid de fuente -> motivo
var burned: Dictionary = {}             # uid -> "led" | "resistencia"
var wire_temp: Dictionary = {}          # uid de cable -> °C
var wire_char: Dictionary = {}          # uid de cable -> máx. °C (aislamiento chamuscado)
var overload: Dictionary = {}           # uid -> s en sobrecarga
var short_active: bool = false
var short_time: float = 0.0
var short_info: Dictionary = {}         # {uid, name, current, wires:[uid], pos}
var time_s: float = 0.0
var ic_state: Dictionary = {}           # uid 555 -> {phase, high, powered}
var digital_out: Dictionary = {}        # uid nano -> {"D13": 1, ...}
var dmm: DMMController
var fx: ShortCircuitFX

var nl: NodeNetlist
var res: Dictionary = {}
var sources: Array = []                 # [{uid, name, branch, pos, neg, v}]
var wire_branch: Dictionary = {}        # uid cable -> rama
var led_diode: Dictionary = {}          # uid LED -> diodo
var res_branch: Dictionary = {}         # uid resistencia -> rama
var led_level: Dictionary = {}          # uid LED -> brillo 0..1.5
var _topo_sig: String = ""
var _accum: float = 0.0
var _lights: Dictionary = {}            # uid LED -> OmniLight3D
var _hot_mats: Dictionary = {}          # uid cable -> ShaderMaterial
var _spark_timer: float = 0.0
var enabled: bool = true

func _ready() -> void:
	dmm = DMMController.new()
	fx = ShortCircuitFX.new()
	fx.name = "EfectosCortocircuito"
	add_child(fx)

func _process(delta: float) -> void:
	if not enabled or main == null:
		return
	if main.simulator.is_running():
		return
	_accum += delta
	if _accum >= EDIT_PERIOD:
		step(_accum)
		_accum = 0.0

func _physics_process(delta: float) -> void:
	if not enabled or main == null:
		return
	if main.simulator.is_running() and not main.simulator.paused:
		step(delta)

#region TOPOLOGÍA Y ELEMENTOS ----------------------------------------------------

func _topology_signature() -> String:
	var s := PackedStringArray()
	for part in main._electronic_parts():
		s.append(part.uid)
		if part.is_inserted():
			s.append(part.inserted_in + str(part.pin_map))
	return "|".join(s)

func _ensure_topology() -> void:
	var sig := _topology_signature()
	if nl != null and sig == _topo_sig:
		return
	_topo_sig = sig
	nl = NodeNetlist.new()
	var boards := {}
	for part in main._electronic_parts():
		if part.is_breadboard():
			boards[part.uid] = part
	for part in main._electronic_parts():
		var groups := {}
		for t in part.def.get("terminales", []):
			var k: String = main._key(part.uid, str(t["id"]))
			nl.add_point(k)
			var g := str(t.get("grupo", ""))
			if g != "" and part.is_breadboard():
				if groups.has(g):
					nl.link(groups[g], k)
				else:
					groups[g] = k
		# Pines internos unidos del Arduino Nano (dos GND y dos RESET) y de la ESP32.
		var etipo := str(part.def.get("electrico", {}).get("tipo", ""))
		if etipo == "nano":
			nl.link(main._key(part.uid, "GND"), main._key(part.uid, "GND2"))
			nl.link(main._key(part.uid, "RST"), main._key(part.uid, "RST2"))
		elif etipo == "esp32":
			nl.link(main._key(part.uid, "GND"), main._key(part.uid, "GND2"))
	# Patas insertadas: pata y agujero son el mismo nodo.
	for part in main._electronic_parts():
		if part.is_inserted() and boards.has(part.inserted_in):
			for pin in part.pin_map:
				nl.link(main._key(part.uid, str(pin)), main._key(part.inserted_in, str(part.pin_map[pin])))
	nl.freeze()

## Fuerza reconstruir la topología (tras insertar/retirar piezas o cargar).
func invalidate() -> void:
	_topo_sig = ""

func _led_params(el: Dictionary) -> Dictionary:
	var dd: Dictionary = el.get("diodo", {})
	var vf := float(dd.get("vf_v", 1.9))
	var vj := vf - 0.02 * LED_RS
	return {"is": 0.02 / exp(vj / NVT), "imax": float(dd.get("imax_a", 0.03)), "color": str(dd.get("color", "rojo"))}

## Añade los elementos del circuito a la netlist. "with_sources": incluir fuentes
## (el óhmetro mide con el circuito desenergizado). "with_meter": incluir el
## propio multímetro (10 MΩ del voltímetro o derivador del amperímetro).
func _add_elements(n: NodeNetlist, with_sources: bool, with_meter: bool) -> String:
	var ground := ""
	if with_sources:
		sources = []
	wire_branch = {}; led_diode = {}; res_branch = {}
	var k := func(p: PartInstance, t: String) -> String: return main._key(p.uid, t)
	for part in main._electronic_parts():
		var el: Dictionary = part.def.get("electrico", {})
		var tipo := str(el.get("tipo", ""))
		match tipo:
			"bateria":
				if with_sources and power_on and not tripped.has(part.uid):
					var pos := ""
					var neg := ""
					for t in part.def["terminales"]:
						if t.get("tipo") == "power": pos = k.call(part, str(t["id"]))
						elif t.get("tipo") == "gnd": neg = k.call(part, str(t["id"]))
					if pos != "" and neg != "":
						var v := float(el.get("voltaje", 0.0))
						var bi := n.add_branch(neg, pos, float(el.get("r_interna_ohm", 0.05)), -v, {"kind": "src", "uid": part.uid})
						sources.append({"uid": part.uid, "name": part.def.get("nombre", "Batería"), "branch": bi, "pos": pos, "neg": neg, "v": v, "part": part})
						if ground == "":
							ground = neg
			"nano":
				if with_sources and power_on and not tripped.has(part.uid):
					var gnd: String = k.call(part, "GND")
					var b5 := n.add_branch(gnd, k.call(part, "5V"), 0.15, -5.0, {"kind": "src", "uid": part.uid})
					sources.append({"uid": part.uid, "name": "Arduino Nano (5V)", "branch": b5, "pos": k.call(part, "5V"), "neg": gnd, "v": 5.0, "part": part})
					var b3 := n.add_branch(gnd, k.call(part, "3V3"), 1.0, -3.3, {"kind": "src", "uid": part.uid})
					sources.append({"uid": part.uid, "name": "Arduino Nano (3V3)", "branch": b3, "pos": k.call(part, "3V3"), "neg": gnd, "v": 3.3, "part": part})
					for pin in digital_out.get(part.uid, {}):
						var level := int(digital_out[part.uid][pin])
						if level > 0:
							n.add_branch(k.call(part, "5V"), k.call(part, pin), 25.0, 0.0, {"kind": "io", "uid": part.uid})
						else:
							n.add_branch(k.call(part, pin), gnd, 25.0, 0.0, {"kind": "io", "uid": part.uid})
					if ground == "":
						ground = gnd
			"esp32":
				# Alimentada por USB: 5V del puerto y 3V3 del regulador AMS1117.
				if with_sources and power_on and not tripped.has(part.uid):
					var g32: String = k.call(part, "GND")
					var e5 := n.add_branch(g32, k.call(part, "5V"), 0.15, -5.0, {"kind": "src", "uid": part.uid})
					sources.append({"uid": part.uid, "name": "ESP32 (5V)", "branch": e5, "pos": k.call(part, "5V"), "neg": g32, "v": 5.0, "part": part})
					var e3 := n.add_branch(g32, k.call(part, "3V3"), 0.5, -3.3, {"kind": "src", "uid": part.uid})
					sources.append({"uid": part.uid, "name": "ESP32 (3V3)", "branch": e3, "pos": k.call(part, "3V3"), "neg": g32, "v": 3.3, "part": part})
					if ground == "":
						ground = g32
			"ic555":
				var vcc: String = k.call(part, "VCC")
				var g5: String = k.call(part, "GND")
				n.add_branch(vcc, g5, 1700.0, 0.0, {"kind": "ic", "uid": part.uid})
				var st: Dictionary = ic_state.get(part.uid, {})
				if with_sources and bool(st.get("powered", false)):
					if bool(st.get("high", false)):
						n.add_branch(vcc, k.call(part, "OUT"), 15.0, 1.7, {"kind": "ic", "uid": part.uid})
					else:
						n.add_branch(k.call(part, "OUT"), g5, 15.0, 0.1, {"kind": "ic", "uid": part.uid})
			"carga":
				if burned.has(part.uid):
					continue
				var terms: Array = part.def.get("terminales", [])
				if terms.size() < 2:
					continue
				if el.has("diodo"):
					var lp := _led_params(el)
					led_diode[part.uid] = n.add_diode(k.call(part, "anodo"), k.call(part, "catodo"), lp["is"], NVT, LED_RS, {"kind": "led", "uid": part.uid})
				elif part.def.get("apariencia", "") == "potenciometro" and terms.size() >= 3:
					var rt := 10000.0
					var w := clampf(float(part.estado.get("posicion", 0.5)), 0.001, 0.999)
					n.add_branch(k.call(part, "A"), k.call(part, "W"), rt * w, 0.0, {"kind": "load", "uid": part.uid})
					n.add_branch(k.call(part, "W"), k.call(part, "B"), rt * (1.0 - w), 0.0, {"kind": "load", "uid": part.uid})
				else:
					var bi := n.add_branch(k.call(part, str(terms[0]["id"])), k.call(part, str(terms[1]["id"])), float(el.get("resistencia_ohm", 1.0)), 0.0, {"kind": "load", "uid": part.uid})
					if part.def.get("apariencia", "") == "resistencia":
						res_branch[part.uid] = bi
	for w in main.wires:
		wire_branch[str(w["uid"])] = n.add_branch(str(w["a_key"]), str(w["b_key"]), WIRE_R, 0.0, {"kind": "wire", "uid": str(w["uid"])})
	if with_meter and dmm and dmm.part:
		dmm.add_elements(n)
	return ground

#endregion

#region PASO DE SIMULACIÓN ------------------------------------------------------

func step(dt: float) -> void:
	time_s += dt
	_sync_dmm()
	_ensure_topology()
	_solve_now()
	# El fusible del amperímetro actúa antes que la protección de la fuente.
	if dmm.part and dmm.check_fuse(self, dt):
		fx.sparks_at(dmm.probe_tip("roja"), 50)
		fx.sparks_at(dmm.probe_tip("negra"), 50)
		fx.flash_at(dmm.probe_tip("roja"))
		fx.puff_at(_part_pos(dmm.part) + Vector3(0, 0.03, 0))
		Config.notify("💥 ¡Fusible de %s del multímetro fundido! Mediste corriente en PARALELO con la fuente (el amperímetro es casi un cortocircuito). Reemplázalo desde el panel del multímetro." % ("10 A" if dmm.jack_10a else "400 mA"), 9.0)
		_solve_now()
	_update_ics(dt)
	_update_thermal(dt)
	_detect_short(dt)
	_update_parts_overload(dt)
	_update_leds()
	dmm.update(self, dt)
	_update_fx(dt)
	solved.emit()

func _solve_now() -> void:
	nl.begin()
	var ground := _add_elements(nl, true, true)
	nl.finalize(ground)
	res = nl.solve()

## Resolver ya (p. ej. «Analizar circuito» o en pruebas) sin avanzar el tiempo.
func solve_once() -> Dictionary:
	_sync_dmm()
	_ensure_topology()
	_solve_now()
	return res

func voltage(key: String) -> float:
	if nl == null or key == "":
		return NAN
	return nl.voltage(res, key)

func branch_current(i: int) -> float:
	var ib: PackedFloat64Array = res.get("ib", PackedFloat64Array())
	return ib[i] if i >= 0 and i < ib.size() else 0.0

func source_current(s: Dictionary) -> float:
	return branch_current(int(s["branch"]))

func led_current(uid: String) -> float:
	var i := int(led_diode.get(uid, -1))
	var idv: PackedFloat64Array = res.get("id", PackedFloat64Array())
	return idv[i] if i >= 0 and i < idv.size() else 0.0

func wire_current(uid: String) -> float:
	return branch_current(int(wire_branch.get(uid, -1)))

## Corriente total entregada por las fuentes y potencia (para el panel).
func totals() -> Dictionary:
	var i := 0.0
	var p := 0.0
	for s in sources:
		var si := source_current(s)
		i += maxf(0.0, si)
		p += maxf(0.0, si) * (voltage(s["pos"]) - voltage(s["neg"]))
	return {"current": i, "power": p, "sources": sources.size()}

func _update_ics(dt: float) -> void:
	for part in main._electronic_parts():
		if str(part.def.get("electrico", {}).get("tipo", "")) != "ic555":
			continue
		var st: Dictionary = ic_state.get(part.uid, {"phase": 0.0, "high": false, "powered": false})
		var vcc := voltage(main._key(part.uid, "VCC")) - voltage(main._key(part.uid, "GND"))
		var reset_v := voltage(main._key(part.uid, "RESET")) - voltage(main._key(part.uid, "GND"))
		var powered := not is_nan(vcc) and vcc >= 4.5
		# RESET a nivel bajo detiene el oscilador (flotante = activo, como en la práctica).
		if not is_nan(reset_v) and nl.index_of(main._key(part.uid, "RESET")) >= 0 and reset_v < 0.7:
			powered = false
		st["powered"] = powered
		if powered:
			var el: Dictionary = part.def.get("electrico", {})
			var f := maxf(0.01, float(part.estado.get("frecuencia_hz", el.get("frecuencia_hz", 1.0))))
			st["phase"] = fmod(float(st["phase"]) + dt * f, 1.0)
			st["high"] = float(st["phase"]) < float(el.get("ciclo", 0.5))
		else:
			st["phase"] = 0.0
			st["high"] = false
		ic_state[part.uid] = st

#endregion

#region CALOR, CORTOCIRCUITO Y SOBRECARGA ---------------------------------------

func _update_thermal(dt: float) -> void:
	for w in main.wires:
		var uid := str(w["uid"])
		var i := wire_current(uid)
		var t := float(wire_temp.get(uid, T_AMB))
		t += dt * (i * i * WIRE_R - WIRE_K * (t - T_AMB)) / WIRE_C
		t = clampf(t, T_AMB, 1150.0)
		wire_temp[uid] = t
		if t > float(wire_char.get(uid, T_AMB)):
			wire_char[uid] = t
		_apply_wire_heat(uid, t)

func _detect_short(dt: float) -> void:
	var worst := {}
	var worst_i := 0.0
	for s in sources:
		var i := source_current(s)
		var vt := voltage(s["pos"]) - voltage(s["neg"])
		if i > SHORT_I and (vt / i) < SHORT_R and i > worst_i:
			worst_i = i
			worst = s
	var was := short_active
	short_active = not worst.is_empty()
	if short_active:
		short_time += dt
		var path := []
		var hottest := ""
		var hot_t := 0.0
		for w in main.wires:
			var uid := str(w["uid"])
			if absf(wire_current(uid)) > 0.3 * worst_i:
				path.append(uid)
				if float(wire_temp.get(uid, 0.0)) >= hot_t:
					hot_t = float(wire_temp.get(uid, 0.0))
					hottest = uid
		short_info = {"uid": worst["uid"], "name": worst["name"], "current": worst_i, "wires": path, "hottest": hottest,
			"pos": _key_pos(worst["pos"])}
		if not was:
			# Chispazo al cerrar el cortocircuito.
			for uid in path:
				var ends := _wire_ends(uid)
				for p in ends:
					fx.sparks_at(p, 70)
			fx.flash_at(short_info["pos"] if short_info["pos"] != null else Vector3.ZERO)
			Config.notify("⚠ CORTOCIRCUITO CRÍTICO en %s: %.1f A sin carga. La protección térmica la desconectará." % [worst["name"], worst_i], 8.0)
		var hot := float(wire_temp.get(hottest, T_AMB)) if hottest != "" else T_AMB
		if short_time >= SHORT_TRIP_TIME or hot >= T_TRIP:
			_trip(worst, "Protección térmica: cortocircuito de %.1f A" % worst_i)
	else:
		short_time = 0.0
	if was != short_active:
		short_changed.emit(short_active)

func _trip(s: Dictionary, why: String) -> void:
	tripped[s["uid"]] = why
	short_active = false
	short_time = 0.0
	protection_tripped.emit(str(s["name"]))
	Config.notify("🔌 %s DESCONECTADA por protección térmica. Corrige el cableado y pulsa «Rearmar» en el panel Circuito eléctrico." % s["name"], 10.0)

## Rearma las fuentes desconectadas y repone componentes quemados.
func rearm() -> void:
	tripped.clear()
	burned.clear()
	overload.clear()
	wire_char.clear()
	for uid in wire_temp.keys():
		wire_temp[uid] = T_AMB
		_apply_wire_heat(uid, T_AMB)
	short_active = false
	short_time = 0.0
	fx.clear_all()
	for part in main._electronic_parts():
		_mark_burned_visual(part, false)

func _update_parts_overload(dt: float) -> void:
	for uid in led_diode:
		var part: PartInstance = main._find_part(uid)
		if part == null:
			continue
		var lp := _led_params(part.def.get("electrico", {}))
		var i := led_current(uid)
		if i > 3.0 * float(lp["imax"]):
			overload[uid] = float(overload.get(uid, 0.0)) + dt
			if overload[uid] > 0.25:
				_burn(part, "led", "LED quemado: %.0f mA (máx. %.0f mA). Pon una resistencia en serie." % [i * 1000.0, float(lp["imax"]) * 1000.0])
		else:
			overload[uid] = 0.0
	for uid in res_branch:
		var part: PartInstance = main._find_part(uid)
		if part == null:
			continue
		var el: Dictionary = part.def.get("electrico", {})
		var i := branch_current(res_branch[uid])
		var p := i * i * float(el.get("resistencia_ohm", 1.0))
		var rating := float(el.get("potencia_w", 0.25))
		if p > 3.0 * rating:
			overload[uid] = float(overload.get(uid, 0.0)) + dt
			fx.smoke_on("r:" + uid, _part_pos(part) + Vector3(0, 0.004, 0), clampf(p / (10.0 * rating), 0.3, 1.0))
			if overload[uid] > 1.5:
				_burn(part, "resistencia", "Resistencia quemada: disipaba %.2f W (máx. %.2f W)." % [p, rating])
		else:
			overload[uid] = 0.0
			fx.smoke_off("r:" + uid)

func _burn(part: PartInstance, what: String, msg: String) -> void:
	if burned.has(part.uid):
		return
	burned[part.uid] = what
	overload.erase(part.uid)
	fx.puff_at(_part_pos(part) + Vector3(0, 0.006, 0))
	fx.sparks_at(_part_pos(part), 20)
	fx.smoke_off("r:" + part.uid)
	_mark_burned_visual(part, true)
	Config.notify("💨 " + msg, 8.0)

## Aspecto quemado: cuerpo ennegrecido y LED apagado.
func _mark_burned_visual(part: PartInstance, on: bool) -> void:
	for root in _visual_roots(part):
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("burn_tint"):
				var m3 := mi as MeshInstance3D
				# Los materiales texturados están compartidos (caché): se duplica antes de teñir.
				if on and not m3.has_meta("orig_mat") and m3.material_override is StandardMaterial3D:
					m3.set_meta("orig_mat", m3.material_override)
					var dup := (m3.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = Color(0.08, 0.07, 0.06, dup.albedo_color.a)
					dup.albedo_texture = null
					dup.emission_energy_multiplier = 0.0
					m3.material_override = dup
				elif not on and m3.has_meta("orig_mat"):
					m3.material_override = m3.get_meta("orig_mat")
					m3.remove_meta("orig_mat")

#endregion

#region LED, FX Y VISUALES ------------------------------------------------------

const LED_COLORS := {"rojo": Color(1.0, 0.12, 0.08), "verde": Color(0.2, 1.0, 0.25), "amarillo": Color(1.0, 0.8, 0.1),
	"azul": Color(0.2, 0.4, 1.0), "blanco": Color(1, 1, 1)}

func _update_leds() -> void:
	var seen := {}
	for uid in led_diode:
		var part: PartInstance = main._find_part(uid)
		if part == null:
			continue
		var i := led_current(uid)
		var level := clampf(i / 0.02, 0.0, 1.5)
		led_level[uid] = level
		seen[uid] = true
		_set_led_visual(part, level)
	for part in main._electronic_parts():
		# LED quemados o fuera del circuito: apagados.
		if part.def.get("apariencia", "") == "led" and not seen.has(part.uid):
			led_level[part.uid] = 0.0
			_set_led_visual(part, 0.0)
		elif part.def.has("pantalla"):
			_set_screen_lit(part, screen_powered(part))
		elif str(part.def.get("electrico", {}).get("tipo", "")) == "nano":
			var on := power_on and not tripped.has(part.uid)
			var d13 := int(digital_out.get(part.uid, {}).get("D13", 0)) > 0
			for root in _visual_roots(part):
				for mi in root.find_children("*", "MeshInstance3D", true, false):
					if mi.has_meta("nano_led"):
						var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
						var lit: bool = on if str(mi.get_meta("nano_led")) == "PWR" else (on and d13)
						if m: m.emission_energy_multiplier = 4.0 if lit else 0.05

## Pantalla del visor: encendida si entre 5V y GND llegan al menos 4.3 V.
func screen_powered(part: PartInstance) -> bool:
	if burned.has(part.uid):
		return false
	var v := voltage(main._key(part.uid, "5V")) - voltage(main._key(part.uid, "GND"))
	return not is_nan(v) and v >= 4.3

func _set_screen_lit(part: PartInstance, lit: bool) -> void:
	for root in _visual_roots(part):
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("pantalla_luz"):
				var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
				if m:
					m.emission_energy_multiplier = 1.0 if lit else 0.0

func _set_led_visual(part: PartInstance, level: float) -> void:
	var col: Color = LED_COLORS.get(_led_params(part.def.get("electrico", {}))["color"], Color(1, 0.1, 0.1))
	for root in _visual_roots(part):
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("led_glow"):
				var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
				if m:
					m.emission = col
					m.emission_energy_multiplier = 0.05 + level * 2.2
	# Luz real del LED sobre la protoboard cuando brilla.
	var light: OmniLight3D = _lights.get(part.uid)
	if level > 0.03:
		if light == null or not is_instance_valid(light):
			light = OmniLight3D.new()
			light.omni_range = 0.05
			light.shadow_enabled = false
			light.light_specular = 0.2
			add_child(light)
			_lights[part.uid] = light
		light.light_color = col
		light.light_energy = level * 0.08
		light.global_position = _part_pos(part) + Vector3(0, 0.004, 0)
	elif light and is_instance_valid(light):
		light.queue_free()
		_lights.erase(part.uid)

func _update_fx(dt: float) -> void:
	# Humo de cables recalentados (aislamiento de PVC).
	for w in main.wires:
		var uid := str(w["uid"])
		var t := float(wire_temp.get(uid, T_AMB))
		if t > T_SMOKE:
			var mid = _wire_mid(uid)
			if mid != null:
				fx.smoke_on("w:" + uid, mid, clampf((t - T_SMOKE) / 500.0, 0.25, 1.0))
		elif t < T_SMOKE - 60.0:
			fx.smoke_off("w:" + uid)
	# Chisporroteo mientras dura el cortocircuito.
	if short_active:
		_spark_timer -= dt
		if _spark_timer <= 0.0:
			_spark_timer = randf_range(0.06, 0.22)
			var hottest := str(short_info.get("hottest", ""))
			if hottest != "":
				var ends := _wire_ends(hottest)
				if not ends.is_empty():
					fx.sparks_at(ends[randi() % ends.size()], 25)

## Color/brillo de incandescencia del cable (shader de cuerpo negro).
func _apply_wire_heat(uid: String, t: float) -> void:
	var node: Node3D = main._wire_nodes.get(uid) if "_wire_nodes" in main else null
	if node == null or not is_instance_valid(node) or node.get_child_count() == 0:
		return
	var tube := node.get_child(0) as MeshInstance3D
	var charred := float(wire_char.get(uid, T_AMB))
	if t < 120.0 and charred < 150.0:
		if tube.has_meta("hot"):
			tube.material_override = tube.get_meta("cool_mat")
			tube.remove_meta("hot")
		return
	var sm: ShaderMaterial = _hot_mats.get(uid)
	if sm == null:
		sm = ShaderMaterial.new()
		sm.shader = load("res://rendering/hot_wire.gdshader")
		_hot_mats[uid] = sm
	if not tube.has_meta("hot"):
		tube.set_meta("cool_mat", tube.material_override)
		var base := Color(0.1, 0.35, 0.85)
		if tube.material_override is StandardMaterial3D:
			base = (tube.material_override as StandardMaterial3D).albedo_color
		sm.set_shader_parameter("base_color", base)
		tube.material_override = sm
		tube.set_meta("hot", true)
	sm.set_shader_parameter("temperature", t)
	sm.set_shader_parameter("char_amount", clampf((charred - 150.0) / 500.0, 0.0, 1.0))

#endregion

#region POSICIONES EN VIVO ------------------------------------------------------

func _visual_roots(part: PartInstance) -> Array:
	var out: Array = [part]
	if main.simulator.is_running():
		var b: Node = main.simulator.get_body(part.uid)
		if b:
			var clone: Node = b.get_node_or_null("Visual_%s" % part.uid)
			out.append(clone if clone else b)
	return out

func _part_pos(part: PartInstance) -> Vector3:
	return main._part_live_xform(part).origin

func _key_pos(key: String):
	return main._terminal_live_by_key(key)

func _wire_ends(uid: String) -> Array:
	for w in main.wires:
		if str(w["uid"]) == uid:
			var out := []
			for k in [w["a_key"], w["b_key"]]:
				var p = _key_pos(str(k))
				if p != null:
					out.append(p)
			return out
	return []

func _wire_mid(uid: String):
	var pts = main._wire_pts.get(uid) if "_wire_pts" in main else null
	if pts is PackedVector3Array and (pts as PackedVector3Array).size() > 2:
		return (pts as PackedVector3Array)[(pts as PackedVector3Array).size() / 2]
	var ends := _wire_ends(uid)
	if ends.size() == 2:
		return (ends[0] + ends[1]) * 0.5 + Vector3(0, 0.01, 0)
	return null

#endregion

#region MULTÍMETRO: CONSULTAS ---------------------------------------------------

func _sync_dmm() -> void:
	var found: PartInstance = null
	for c in main.parts_root.get_children():
		if c is PartInstance and (c as PartInstance).def.get("apariencia", "") == "multimetro":
			found = c
			break
	if found != dmm.part:
		dmm.bind(found, main)

## ¿Hay una fuente activa conectada (por cualquier elemento) a alguno de los nodos?
func energized(keys: Array) -> bool:
	if nl == null or sources.is_empty():
		return false
	# Componentes conexos del grafo de elementos (incluidas las fuentes).
	var parent := {}
	var f := func(x: String) -> String:
		var r := x
		while parent.has(r) and parent[r] != r:
			r = parent[r]
		return r
	var join := func(a: String, b: String) -> void:
		var ra: String = f.call(a)
		var rb: String = f.call(b)
		if not parent.has(ra): parent[ra] = ra
		if not parent.has(rb): parent[rb] = rb
		if ra != rb: parent[ra] = rb
	for e in nl.branches:
		if str(e["meta"].get("kind", "")) in ["dmm", "dmm_shunt"]:
			continue
		join.call(nl.find(e["a"]), nl.find(e["b"]))
	for d in nl.diodes:
		join.call(nl.find(d["a"]), nl.find(d["k"]))
	for s in sources:
		var rs: String = f.call(nl.find(s["pos"]))
		for kk in keys:
			if str(kk) != "" and f.call(nl.find(str(kk))) == rs:
				return true
	return false

## Resistencia entre dos claves con el circuito DESENERGIZADO (sin fuentes): el
## óhmetro inyecta 1 V a través de 10 kΩ y mide V/I. INF si está abierto.
func measure_resistance(red: String, black: String) -> float:
	if nl == null or red == "" or black == "":
		return INF
	if nl.same_node(red, black):
		return 0.0
	var n2 := NodeNetlist.new()
	n2._parent = nl._parent
	n2._root_cache = nl._root_cache
	n2.begin()
	var saved_sources := sources
	var saved_maps := [wire_branch, led_diode, res_branch]
	_add_elements(n2, false, false)
	sources = saved_sources
	wire_branch = saved_maps[0]; led_diode = saved_maps[1]; res_branch = saved_maps[2]
	var bi := n2.add_branch(black, red, DMMController.R_TEST, -DMMController.V_TEST, {"kind": "dmm_test"})
	n2.finalize(black)
	var r2 := n2.solve()
	var ib: PackedFloat64Array = r2.get("ib", PackedFloat64Array())
	if bi >= ib.size():
		return INF
	var i := ib[bi]
	var vx := n2.voltage(r2, red) - n2.voltage(r2, black)
	if i <= 1.0e-12:
		return INF
	return maxf(0.0, vx / i)

#endregion
