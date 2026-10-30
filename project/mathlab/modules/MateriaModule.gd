extends LabModule
## Construcción de materia (Física moderna, Fase 4): con quarks, protones, neutrones,
## electrones y átomos se forman hadrones, núcleos, átomos o iones y moléculas. Cada
## combinación se valida (color, ligadura, carga del ion, valencias) y, si no vale, se dice
## por qué. Los hadrones muestran la cuerda de la fuerza fuerte (potencial de Cornell) y el
## espectro del cuarkonio; los núcleos inestables se desintegran (α, β, γ) con sus datos de
## NUBASE2020 o la predicción de la fórmula semiempírica. Física en C# (Fisica, Materia.cs).

const QUARKS := ["u", "d", "s", "c", "b", "t"]
const COLORES := [Color(1.0, 0.3, 0.3), Color(0.3, 1.0, 0.4), Color(0.35, 0.5, 1.0)]
const M_CONST_GEV := 0.33             # masa típica de un quark ligero constituyente (ilustrativa)
const HBARC := 0.1973269804           # GeV·fm
const PSI_SPLIT_MEV := 3686.097 - 3096.900   # ψ(2S) − J/ψ del PDG 2026

var items: Array = []                 # ids de la tabla («u», «d~», «p», «n», «e-») o átomos «Z:8»
var resultado: Dictionary = {}
var sep_fm := 0.4                     # separación de los quarks
var alpha_s := 0.30
var sigma := 0.18                     # GeV² (Deur, Brodsky y de Teramond, 2016)
var m_c := 1.5                        # GeV, masa del quark c para el cuarkonio
var t := 0.0
var _emitidos: Array = []             # [{nodo, vel}] de una desintegración
var view_root: Node3D
var _items_label: Label
var _z_spin: SpinBox
var _last_decay := ""

func title() -> String: return "Construcción de materia"
func formula() -> String: return "V(r) = −(4/3)αₛ/r + σr     B(Z, N) fórmula semiempírica"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3(0, 0.3, 0), "dist": 6.5, "yaw": -25.0, "pitch": -20.0}

func setup() -> void:
	view_root = Node3D.new()
	add_child(view_root)
	items = ["u", "u", "d"]
	_update()

# --- Combinación --------------------------------------------------------------------------

static func _is_atom(it: String) -> bool:
	return it.begins_with("Z:")

func _info(id: String) -> Dictionary:
	return Fisica.ParticleInfo(id)

## Clasifica el recipiente y forma lo que se pueda; en error, el motivo.
func _combine() -> Dictionary:
	if items.is_empty():
		return {"tipo": "vacio"}
	var quarks: Array = []
	var p := 0
	var nn := 0
	var e := 0
	var atomos: Array = []
	var otros: Array = []
	for it in items:
		if _is_atom(it):
			atomos.append(int(str(it).substr(2)))
		elif str(it).trim_suffix("~") in QUARKS:
			quarks.append(it)
		elif it == "p":
			p += 1
		elif it == "n":
			nn += 1
		elif it == "e-":
			e += 1
		else:
			otros.append(it)
	if not quarks.is_empty():
		if quarks.size() != items.size():
			return {"tipo": "error", "motivo": "mezcla quarks con otras partículas: primero forma un hadrón (p o n) y luego combínalo"}
		var h: Dictionary = Fisica.HadronFromQuarks(PackedStringArray(quarks))
		if str(h["id"]) == "":
			return {"tipo": "error", "motivo": h["motivo"], "quarks": quarks}
		return {"tipo": "hadron", "id": h["id"], "quarks": quarks, "alternativas": h["alternativas"], "clase": h["tipo"]}
	if not otros.is_empty():
		var nombres := ", ".join(otros.map(func(x): return _info(x)["simbolo"]))
		return {"tipo": "error", "motivo": "%s no forma estados ligados en este modelo (solo hadrones de quarks; núcleos y átomos de p, n y e⁻; moléculas de átomos)" % nombres}
	if not atomos.is_empty():
		if p + nn + e > 0:
			return {"tipo": "error", "motivo": "mezcla átomos con nucleones o electrones sueltos: combínalos por separado"}
		if atomos.size() == 1:
			return _atom(atomos[0], _neutrons_for(atomos[0]), atomos[0])
		var mol: Dictionary = Fisica.MoleculeBonds(PackedInt32Array(atomos), 7)
		if not bool(mol["ok"]):
			return {"tipo": "error", "motivo": mol["motivo"], "atomos": atomos}
		return {"tipo": "molecula", "atomos": atomos, "enlaces": mol["enlaces"], "pos": mol["posiciones"]}
	if p == 0 and nn == 0:
		return {"tipo": "error", "motivo": "electrones sueltos: sin núcleo no hay átomo"}
	var nuc: Dictionary = Fisica.NucleusInfo(p, nn)
	if not bool(nuc["ligado"]):
		return {"tipo": "error", "motivo": "%s: %s" % [nuc["nombre"], nuc["nota"]]}
	if e == 0:
		return {"tipo": "nucleo", "z": p, "n": nn, "nuc": nuc}
	if e > p + 1:
		return {"tipo": "error", "motivo": "%d electrones para Z = %d: un átomo admite como mucho uno de más (los aniones con más carga no están ligados)" % [e, p]}
	return _atom(p, nn, e)

## Neutrones del isótopo más común de los elementos ligeros (para los átomos de la paleta).
static func _neutrons_for(z: int) -> int:
	var tabla := {1: 0, 2: 2, 3: 4, 4: 5, 5: 6, 6: 6, 7: 7, 8: 8, 9: 10, 10: 10, 11: 12, 12: 12, 13: 14, 14: 14, 15: 16, 16: 16, 17: 18, 18: 22, 19: 20, 20: 20}
	return tabla.get(z, int(round(z * (1.0 + 0.0064 * z))))

func _atom(z: int, n_neu: int, e: int) -> Dictionary:
	return {"tipo": "atomo", "z": z, "n": n_neu, "e": e, "config": Fisica.AtomConfiguration(z, e), "nuc": Fisica.NucleusInfo(z, n_neu)}

func _update() -> void:
	resultado = _combine()
	if _items_label:
		_items_label.text = "Recipiente: " + (" ".join(items.map(func(x): return _label_of(x))) if not items.is_empty() else "(vacío)")
	_draw()

func _label_of(it: String) -> String:
	return Fisica.ElementSymbol(int(it.substr(2))) if _is_atom(it) else str(_info(it)["simbolo"])

# --- Dibujo -------------------------------------------------------------------------------

func _draw() -> void:
	for c in view_root.get_children():
		c.queue_free()
	_emitidos.clear()
	match str(resultado.get("tipo", "")):
		"hadron":
			_draw_hadron()
		"nucleo":
			_draw_nucleus(int(resultado["z"]), int(resultado["n"]), 1.0)
		"atomo":
			_draw_atom()
		"molecula":
			_draw_molecule()
		"error":
			view_root.add_child(label3d("✖ " + str(resultado["motivo"]).left(70), Vector3(0, 1.2, 0), Color(1.0, 0.5, 0.5), 0.004))

func _ball(at: Vector3, r: float, col: Color) -> MeshInstance3D:
	var s := sphere(r, glow_mat(col, 1.2))
	s.position = at
	view_root.add_child(s)
	return s

## Quarks con su color (o anticolor) unidos por la cuerda; si la energía de la cuerda pasa
## de 2·m_q constituyente, se rompe en dos hadrones (hadronización, ilustrativa).
func _draw_hadron() -> void:
	var q: Array = resultado["quarks"]
	var k := 1.6                         # mundo por fm
	var pts: Array = []
	if q.size() == 2:
		pts = [Vector3(-sep_fm * k / 2, 0.6, 0), Vector3(sep_fm * k / 2, 0.6, 0)]
	else:
		# Triángulo de lado «separación».
		var rr := sep_fm * k / sqrt(3.0)
		for i in 3:
			var a := TAU * i / 3.0 + PI / 2
			pts.append(Vector3(cos(a) * rr, 0.6 + sin(a) * rr, 0))
	var rota := _string_broken()
	for i in q.size():
		var anti := str(q[i]).ends_with("~")
		var col: Color = COLORES[i % 3]
		if anti:
			col = Color(1, 1, 1) - col + Color(0, 0, 0, 1)
		_ball(pts[i], 0.12, col)
		view_root.add_child(label3d(_info(q[i])["simbolo"], pts[i] + Vector3(0, 0.22, 0), col.lightened(0.3), 0.004))
	var tube := glow_mat(Color(1.0, 0.85, 0.4), 2.5)
	if q.size() == 2:
		if rota:
			var mid: Vector3 = (pts[0] + pts[1]) / 2
			view_root.add_child(rod(pts[0], mid - Vector3(0.18, 0, 0), 0.03, tube))
			view_root.add_child(rod(mid + Vector3(0.18, 0, 0), pts[1], 0.03, tube))
			_ball(mid - Vector3(0.12, 0, 0), 0.09, Color(0.6, 0.9, 1.0))
			_ball(mid + Vector3(0.12, 0, 0), 0.09, Color(1.0, 0.6, 0.9))
		else:
			view_root.add_child(rod(pts[0], pts[1], 0.035, tube))
	else:
		var c: Vector3 = (pts[0] + pts[1] + pts[2]) / 3
		for p in pts:
			view_root.add_child(rod(p, c, 0.03, tube))

## Energía de la cuerda V(r) − V(r₀) del par a la separación actual (GeV).
func string_energy(r_fm: float) -> float:
	var r := r_fm / HBARC
	var r0 := 0.2 / HBARC
	return (-4.0 / 3.0 * alpha_s / r + sigma * r) - (-4.0 / 3.0 * alpha_s / r0 + sigma * r0)

func _string_broken() -> bool:
	return (resultado["quarks"] as Array).size() == 2 and string_energy(sep_fm) > 2.0 * M_CONST_GEV

func _nucleon_positions(a: int, radio: float) -> Array:
	var out: Array = []
	for i in a:
		var r := radio * pow((i + 0.5) / a, 1.0 / 3.0)
		var cz := 1.0 - 2.0 * (i + 0.5) / a
		var phi := i * 2.399963229728653
		var sz := sqrt(maxf(0.0, 1.0 - cz * cz))
		out.append(Vector3(r * sz * cos(phi), r * cz, r * sz * sin(phi)))
	return out

func _draw_nucleus(z: int, n_neu: int, escala: float) -> void:
	var a := z + n_neu
	var radio := 0.35 * pow(a, 1.0 / 3.0) * escala
	var pos := _nucleon_positions(a, radio)
	var rn := 0.33 * escala
	# Z protones repartidos al azar (siempre igual para el mismo núcleo).
	var orden := range(a)
	var mezcla := RandomNumberGenerator.new()
	mezcla.seed = a * 1000 + z
	for i in range(a - 1, 0, -1):
		var j := mezcla.randi_range(0, i)
		var tmp: int = orden[i]
		orden[i] = orden[j]
		orden[j] = tmp
	for i in a:
		var proton: bool = orden[i] < z
		_ball(Vector3(0, 0.6, 0) + pos[i], rn, Color(1.0, 0.35, 0.3) if proton else Color(0.7, 0.7, 0.75))

func _draw_atom() -> void:
	_draw_nucleus(int(resultado["z"]), int(resultado["n"]), 0.25)
	# Capas por n (dibujo ilustrativo: el radio crece como n²·0,25, no está a escala).
	var por_capa := {}
	for orb in str(resultado["config"]).split(" "):
		if orb == "":
			continue
		var capa := int(orb.substr(0, 1))
		var cuenta := _sup_to_int(orb.substr(2))
		por_capa[capa] = int(por_capa.get(capa, 0)) + cuenta
	for capa in por_capa:
		var r: float = 0.45 + 0.28 * capa * capa
		var shell := sphere(r, glass_mat(Color(0.5, 0.75, 1.0), 0.05))
		shell.position = Vector3(0, 0.6, 0)
		view_root.add_child(shell)
		var k: int = por_capa[capa]
		for i in k:
			var cz := 1.0 - 2.0 * (i + 0.5) / k
			var phi: float = i * 2.399963229728653 + capa
			var sz := sqrt(maxf(0.0, 1.0 - cz * cz))
			var el := _ball(Vector3(0, 0.6, 0) + Vector3(r * sz * cos(phi), r * cz, r * sz * sin(phi)), 0.05, Color(0.4, 0.75, 1.0))
			el.set_meta("orbita", [capa, phi, cz, r])

static func _sup_to_int(s: String) -> int:
	const SUP := "⁰¹²³⁴⁵⁶⁷⁸⁹"
	var v := 0
	for ch in s:
		var d := SUP.find(ch)
		if d >= 0:
			v = v * 10 + d
	return v

const CPK := {1: Color(0.95, 0.95, 0.95), 6: Color(0.35, 0.35, 0.38), 7: Color(0.3, 0.45, 1.0), 8: Color(1.0, 0.25, 0.2),
	9: Color(0.4, 0.95, 0.4), 15: Color(1.0, 0.55, 0.1), 16: Color(1.0, 0.9, 0.25), 17: Color(0.3, 0.9, 0.3)}

func _draw_molecule() -> void:
	var zs: Array = resultado["atomos"]
	var pos: PackedFloat64Array = resultado["pos"]
	var s := 1.1
	var c := Vector3.ZERO
	for i in zs.size():
		c += Vector3(pos[3 * i], pos[3 * i + 1], pos[3 * i + 2])
	c /= zs.size()
	var w: Array = []
	for i in zs.size():
		w.append((Vector3(pos[3 * i], pos[3 * i + 1], pos[3 * i + 2]) - c) * s + Vector3(0, 0.6, 0))
	for i in zs.size():
		var z: int = zs[i]
		_ball(w[i], 0.16 if z == 1 else 0.24, CPK.get(z, Color(1.0, 0.6, 0.9)))
		view_root.add_child(label3d(Fisica.ElementSymbol(z), w[i] + Vector3(0, 0.32, 0), Color(0.9, 0.95, 1.0), 0.004))
	var bm := glass_mat(Color(0.85, 0.85, 0.9), 0.9)
	for en in resultado["enlaces"]:
		var a: Vector3 = w[en[0]]
		var b: Vector3 = w[en[1]]
		var perp := (b - a).cross(Vector3.UP).normalized() * 0.06
		if perp.length() < 0.01:
			perp = Vector3(0.06, 0, 0)
		var o: int = en[2]
		for k in o:
			var off := perp * (k - (o - 1) / 2.0)
			view_root.add_child(rod(a + off, b + off, 0.025, bm))

func step(dt: float) -> void:
	t += dt
	for c in view_root.get_children():
		if c.has_meta("orbita"):
			var m: Array = c.get_meta("orbita")
			var phi: float = m[1] + t * 0.8 / m[0]
			var sz := sqrt(maxf(0.0, 1.0 - m[2] * m[2]))
			c.position = Vector3(0, 0.6, 0) + Vector3(m[3] * sz * cos(phi), m[3] * m[2], m[3] * sz * sin(phi))
	for em in _emitidos:
		(em["nodo"] as Node3D).position += em["vel"] * dt

# --- Acciones -----------------------------------------------------------------------------

func add_item(it: String) -> void:
	remember()
	items.append(it)
	_update()

func build_ui(pnl: VBoxContainer) -> void:
	LabUI.section(pnl, "Paleta")
	var r1 := LabUI.row(pnl)
	for q in QUARKS:
		var qq: String = q
		LabUI.button(r1, _info(q)["simbolo"], func(): add_item(qq))
	var r2 := LabUI.row(pnl)
	for q in QUARKS:
		var qq: String = q + "~"
		LabUI.button(r2, _info(qq)["simbolo"], func(): add_item(qq))
	var r3 := LabUI.row(pnl)
	for id in ["p", "n", "e-"]:
		var ii: String = id
		LabUI.button(r3, _info(id)["simbolo"], func(): add_item(ii))
	_z_spin = LabUI.spin(pnl, "Átomo (Z)", 1, Fisica.ElementCount(), 1, 8, func(_v): pass)
	LabUI.button(pnl, "Añadir el átomo", func(): add_item("Z:%d" % int(_z_spin.value)))
	LabUI.text_field(pnl, "Añadir por nombre o símbolo:", "", "u, ū, p, e⁻, O, oxígeno…", _on_buscar)
	LabUI.section(pnl, "Recipiente")
	_items_label = LabUI.note(pnl, "")
	var r4 := LabUI.row(pnl)
	LabUI.button(r4, "Quitar el último", _quitar)
	LabUI.button(r4, "Vaciar", _vaciar)
	LabUI.button(pnl, "☢ Desintegrar (núcleo inestable)", desintegrar)
	LabUI.section(pnl, "Fuerza fuerte (Cornell)")
	LabUI.slider(pnl, "Separación de los quarks (fm)", 0.2, 2.0, 0.02, sep_fm, _on_sep, "%.2f")
	LabUI.slider(pnl, "αₛ", 0.19, 0.40, 0.01, alpha_s, _on_alpha, "%.2f")
	LabUI.slider(pnl, "σ (GeV²)", 0.10, 0.25, 0.005, sigma, _on_sigma, "%.3f")
	LabUI.slider(pnl, "m_c del cuarkonio (GeV)", 1.2, 1.9, 0.01, m_c, func(v): m_c = v, "%.2f")
	_update()
	LabUI.note(pnl, "Prueba: u u d (protón), u d̄ (pion), p p n n (helio-4), p p n n e⁻ e⁻ (átomo de helio), seis átomos de H y uno de O… o algo imposible (u u, H H H) para ver qué ley o regla lo impide.")

func _quitar() -> void:
	if not items.is_empty():
		remember()
		items.pop_back()
		_update()

func _vaciar() -> void:
	remember()
	items.clear()
	_update()

func _on_sep(v: float) -> void:
	sep_fm = v
	_draw()

func _on_alpha(v: float) -> void:
	alpha_s = v
	_draw()

func _on_sigma(v: float) -> void:
	sigma = v
	_draw()

func _on_buscar(texto: String) -> void:
	var q := texto.strip_edges()
	if q == "":
		return
	for id in Fisica.ParticleIds():
		var inf: Dictionary = _info(id)
		if (q == id or q == str(inf["simbolo"])) and (str(id).trim_suffix("~") in QUARKS or id in ["p", "n", "e-"]):
			add_item(id)
			return
	for z in range(1, Fisica.ElementCount() + 1):
		if q == Fisica.ElementSymbol(z) or q.to_lower() == Fisica.ElementName(z):
			add_item("Z:%d" % z)
			return

## Desintegración del núcleo: modo al azar según las fracciones; el recipiente pasa a la hija.
func desintegrar() -> void:
	if str(resultado.get("tipo", "")) != "nucleo":
		return
	var modos: Array = resultado["nuc"]["modos"]
	if modos.is_empty():
		return
	remember()
	var u := rng.randf()
	var m: Dictionary = modos[0]
	var acc := 0.0
	for x in modos:
		acc += float(x["fraccion"])
		if u < acc:
			m = x
			break
	var proceso := {"β⁻": [["n"], ["p", "e-", "nu_e~"]], "β⁺": [["p"], ["n", "e+", "nu_e"]], "CE": [["p", "e-"], ["n", "nu_e"]]}
	var viol := PackedStringArray()
	if proceso.has(m["tipo"]):
		viol = Fisica.Conservation(PackedStringArray(proceso[m["tipo"]][0]), PackedStringArray(proceso[m["tipo"]][1]), false)
	_last_decay = "%s → %s por %s%s · %s" % [resultado["nuc"]["nombre"], m["nombre"], m["tipo"], (" (" + str(m["nota"]) + ")") if str(m["nota"]) != "" else "",
		"conserva carga, B y Lₑ ✓" if viol.is_empty() else ", ".join(viol)]
	items.clear()
	for i in int(m["z"]):
		items.append("p")
	for i in int(m["n"]):
		items.append("n")
	_update()
	var col := {"α": Color(1.0, 0.85, 0.3), "β⁻": Color(0.4, 0.7, 1.0), "β⁺": Color(1.0, 0.5, 0.5), "CE": Color(0.6, 0.6, 1.0), "n": Color(0.7, 0.7, 0.75), "p": Color(1.0, 0.35, 0.3)}
	var b := _ball(Vector3(0, 0.6, 0), 0.12, col.get(m["tipo"], Color.WHITE))
	_emitidos.append({"nodo": b, "vel": Vector3(1.2, 0.6, 0.4)})

func info() -> String:
	var tipo := str(resultado.get("tipo", ""))
	var s := ""
	match tipo:
		"vacio":
			s = "Añade piezas de la paleta."
		"error":
			s = "[color=#ff7070]✖ No forma un estado ligado: %s[/color]" % resultado["motivo"]
		"hadron":
			s = _hadron_info()
		"nucleo":
			s = _nucleus_info(resultado["nuc"])
		"atomo":
			var z: int = resultado["z"]
			var e: int = resultado["e"]
			var carga := z - e
			s = "%s (%s, Z = %d) · %s · %s\nConfiguración: %s%s" % [Fisica.ElementName(z).capitalize(), Fisica.ElementSymbol(z), z,
				"neutro" if carga == 0 else "ion %s%s" % [Fisica.ElementSymbol(z), ("%d+" % carga) if carga > 0 else "%d−" % -carga],
				resultado["nuc"]["nombre"], resultado["config"], " (excepción a la regla de Madelung)" if Fisica.IsMadelungException(z) and carga == 0 else ""]
			if e == 1:
				s += "\nIon hidrogenoide: Eₙ = −13,6057·Z²/n² eV → E₁ = %.3f eV" % (-13.605693122990 * z * z)
			if carga < 0:
				s += "\nUn anión solo está ligado si la afinidad electrónica es positiva (H⁻ sí, He⁻ no): no se modela."
		"molecula":
			s = _molecule_info()
	if _last_decay != "":
		s += "\nÚltima desintegración: " + _last_decay
	return s

func _hadron_info() -> String:
	var f: Dictionary = _info(resultado["id"])
	var q: Array = resultado["quarks"]
	var carga := 0
	for x in q:
		carga += int(_info(x)["carga3"])
	var s := "%s %s (%s): m = %s MeV, q = %s, espín %s, B = %s · quarks %s · sin color ✓" % [f["simbolo"], f["nombre"], resultado["clase"],
		str(snappedf(float(f["masa_MeV"]), 0.001)), f["carga"], f["espin"], f["B"], " ".join(q.map(func(x): return _info(x)["simbolo"]))]
	var alt: PackedStringArray = resultado["alternativas"]
	if not alt.is_empty():
		s += "\nCon los mismos quarks también: " + ", ".join(Array(alt).map(func(x): return "%s (espín %s, %s MeV)" % [_info(x)["simbolo"], _info(x)["espin"], str(snappedf(float(_info(x)["masa_MeV"]), 0.01))]))
	s += "\nCuerda (Cornell) a %.2f fm: V − V(0,2 fm) = %.3f GeV%s" % [sep_fm, string_energy(sep_fm),
		" → se rompe: crea un par qq̄ y salen dos hadrones (ilustrativo)" if _string_broken() else ""]
	var l0: PackedFloat64Array = Fisica.QuarkoniumLevels(m_c, alpha_s, sigma, 0, 2)
	var l1: PackedFloat64Array = Fisica.QuarkoniumLevels(m_c, alpha_s, sigma, 1, 1)
	s += "\nCharmonio con estos parámetros: 2S − 1S = %.0f MeV (PDG: ψ(2S) − J/ψ = %.0f MeV) · 1P − 1S = %.0f MeV" % [
		(l0[1] - l0[0]) * 1000.0, PSI_SPLIT_MEV, (l1[0] - l0[0]) * 1000.0]
	return s

func _nucleus_info(nuc: Dictionary) -> String:
	var s := "%s: B = %.2f MeV (%.3f MeV por nucleón) · R ≈ %.2f fm · %s" % [nuc["nombre"], nuc["B"], nuc["B_A"], nuc["radio_fm"],
		"estable" if bool(nuc["estable"]) else "inestable"]
	if not bool(nuc["estable"]):
		s += ", vida media %s" % nuc["medio"] if str(nuc["medio"]) != "sin dato" else " (vida media sin dato)"
		for m in nuc["modos"]:
			s += "\n  %s → %s (%.2f %%) %s" % [m["tipo"], m["nombre"], float(m["fraccion"]) * 100.0, m["nota"]]
	s += "\nFuente: %s" % nuc["nota"]
	return s

func _molecule_info() -> String:
	var zs: Array = resultado["atomos"]
	var cuenta := {}
	for z in zs:
		cuenta[z] = int(cuenta.get(z, 0)) + 1
	var orden: Array = cuenta.keys()
	orden.sort_custom(func(a, b):
		var ka := 0 if a == 6 else (1 if a == 1 else 2)
		var kb := 0 if b == 6 else (1 if b == 1 else 2)
		return ka < kb if ka != kb else Fisica.ElementSymbol(a) < Fisica.ElementSymbol(b))
	var formula := ""
	for z in orden:
		formula += Fisica.ElementSymbol(z) + ("" if cuenta[z] == 1 else _sub(cuenta[z]))
	var en: Array = []
	for e in resultado["enlaces"]:
		en.append("%s%s%s" % [Fisica.ElementSymbol(zs[e[0]]), ["", "–", "=", "≡"][e[2]], Fisica.ElementSymbol(zs[e[1]])])
	return "Molécula %s · valencias saturadas ✓ · enlaces: %s\nGeometría ilustrativa (muelles), no a escala." % [formula, ", ".join(en)]

static func _sub(x: int) -> String:
	const SUB := "₀₁₂₃₄₅₆₇₈₉"
	var o := ""
	for ch in str(x):
		o += SUB[int(ch)]
	return o

func metricas() -> Dictionary:
	return {"entidades": items.size()}

func estado() -> Dictionary:
	return {"items": items.duplicate(), "sep": sep_fm, "alpha_s": alpha_s, "sigma": sigma, "m_c": m_c}

func cargar(d: Dictionary) -> String:
	if typeof(d.get("items")) != TYPE_ARRAY:
		return "falta «items»"
	for it in d["items"]:
		var s := str(it)
		if not (_is_atom(s) or s in Fisica.ParticleIds()):
			return "pieza desconocida «%s»" % s
	items = Array(d["items"]).duplicate()
	sep_fm = float(d.get("sep", sep_fm))
	alpha_s = float(d.get("alpha_s", alpha_s))
	sigma = float(d.get("sigma", sigma))
	m_c = float(d.get("m_c", m_c))
	_last_decay = ""
	_update()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Hadrones", "nivel": "exacto",
			"modelo": "Sin color: qqq, q̄q̄q̄ o qq̄ (los exóticos no se modelan). Carga, B y espín de la tabla del PDG; con los mismos quarks se elige el de menor masa. Los mesones neutros uū y dd̄ se mezclan (π⁰, ρ⁰, ω) y el ss̄ se muestra como η",
			"ecuaciones": "q = Σ qᵢ;  B = (n_q − n_q̄)/3", "unidades": "MeV, e", "referencias": "PDG 2026"},
		{"subsistema": "Potencial de Cornell y cuarkonio", "nivel": "aproximado",
			"modelo": "Modelo efectivo de la fuerza fuerte: Coulomb de un gluon más confinamiento lineal; espectro del cuarkonio por la ecuación radial no relativista (diferencias finitas, autovalores por secuencias de Sturm), sin espín",
			"ecuaciones": "V(r) = −(4/3)αₛ/r + σr;  −u″/2μ + [V + l(l+1)/2μr²]u = Eu",
			"unidades": "GeV, fm (ħc = 0,1973269804 GeV·fm); σ ≃ 0,18 GeV², αₛ entre 0,19 y 0,4",
			"referencias": "Eichten et al., Phys. Rev. D 17, 3090 (1978); Deur, Brodsky y de Teramond, Prog. Part. Nucl. Phys. 90, 1 (2016)"},
		{"subsistema": "Ruptura de la cuerda (hadronización)", "nivel": "ilustrativo",
			"modelo": "Cuando la energía de la cuerda pasa de 2·m_q constituyente (≈ 0,33 GeV por quark ligero, valor típico de los modelos de quarks) se dibuja un par qq̄ nuevo y dos hadrones; no es un cálculo de hadronización",
			"ecuaciones": "σr ≳ 2m_q", "unidades": "GeV, fm", "referencias": ""},
		{"subsistema": "Núcleos con datos", "nivel": "exacto",
			"modelo": "Vida media, modos y fracciones medidos de 17 núclidos radiactivos y 33 estables",
			"ecuaciones": "N(t) = N₀·2^{−t/T½}", "unidades": "s, años (1 año = 365,2422 días)",
			"referencias": "NUBASE2020: Kondev et al., Chin. Phys. C 45, 030001 (2021)"},
		{"subsistema": "Núcleos sin datos", "nivel": "aproximado",
			"modelo": "Fórmula semiempírica de masas: ligadura, energías de separación y valores Q de β⁻, β⁺/CE y α (α solo con A > 140). Poco fiable con A < 20; no da vidas medias",
			"ecuaciones": "B = a_V A − a_S A^{2/3} − a_C Z(Z−1)/A^{1/3} − a_A(N−Z)²/A ± a_P/√A",
			"unidades": "MeV (a_V 15,75; a_S 17,8; a_C 0,711; a_A 23,7; a_P 11,18)", "referencias": "Rohlf, Modern Physics from α to Z⁰ (1994)"},
		{"subsistema": "Configuraciones electrónicas", "nivel": "exacto",
			"modelo": "Regla de Madelung con las 20 excepciones medidas hasta Z = 103 (Cr, Cu, Nb, Mo, Ru, Rh, Pd, Ag, Pt, Au, La, Ce, Gd, Ac, Th, Pa, U, Np, Cm, Lr); más allá, predicción. Los cationes pierden primero los electrones de mayor n (regla habitual, con excepciones en algunos iones)",
			"ecuaciones": "orden de llenado n + l creciente", "unidades": "electrones por orbital", "referencias": "NIST, Ground Levels and Ionization Energies"},
		{"subsistema": "Moléculas y dibujos", "nivel": "ilustrativo",
			"modelo": "Valencias covalentes habituales saturadas con enlaces de orden 1 a 3 en una molécula conexa; geometría por muelles (no VSEPR ni longitudes reales). Núcleos y capas electrónicas dibujados sin escala",
			"ecuaciones": "Σⱼ bᵢⱼ = vᵢ", "unidades": "sin escala", "referencias": ""},
	]
