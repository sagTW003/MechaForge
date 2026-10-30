extends LabModule
## D-branas y acoplamiento (Física moderna, Fase 6). Las cinco supercuerdas (I, IIA, IIB y las dos
## heteróticas) con sus D-branas estables: membranas donde terminan las cuerdas abiertas, que
## tienen la masa de su longitud (M = d/2πα′) y dan un grupo gauge U(N) cuando N branas se
## juntan. g_s fija la tensión de las branas (∝ 1/g_s), la gravedad (G ∝ g_s²) y las dualidades.
## La rejilla se hunde con la energía de lo construido (ilustrativo). Unidades de cuerda: α′ = 1.

const TIPOS := ["I", "IIA", "IIB", "HO", "HE"]
const MAX_BRANAS := 4
const LADO := 2.0                     # media anchura dibujada de una brana (en z)
const ALTO := 2.4                     # alto dibujado (en y)
const ALTURA := 1.3                   # centro de las branas
const PUNTOS := 33
const TOL := 0.02                     # dos branas a menos de esto (ℓ_s) están juntas
const REJ := 4.0                      # media anchura de la rejilla
const LINEAS := 25

var tipo := "IIA"
var gs := 0.2
var p := 2
var pos := [-1.2, 1.0, 1.0]           # posición x de cada brana (ℓ_s)
var sel := 0
var tau := 0.0
var branas: Node3D
var cuerdas: Node3D
var rejilla: MeshInstance3D
var _anclas := []                     # por cuerda: [i, j, y_a, z_a, y_b, z_b, fase]
var _p_opt: OptionButton
var _gs_sl: HSlider
var _n_sl: HSlider
var _sel_sl: HSlider
var _pos_sl: HSlider
var _syncing := false

func title() -> String: return "D-branas y acoplamiento"
func formula() -> String: return "T_p = 1/(g_s (2π)^p α′^((p+1)/2))     M = d/(2πα′)     16πG₁₀ = (2π)⁷ g_s² α′⁴"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3(0, 1.0, 0), "dist": 8.5, "yaw": -32.0, "pitch": -20.0}

func setup() -> void:
	branas = Node3D.new()
	add_child(branas)
	cuerdas = Node3D.new()
	add_child(cuerdas)
	rejilla = MeshInstance3D.new()
	rejilla.mesh = ImmediateMesh.new()
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.4, 0.75, 1.0, 0.6)
	rejilla.material_override = rm
	add_child(rejilla)
	_rebuild()

## D-branas que el arenero sabe dibujar: las estables del tipo con 0 ≤ p ≤ 8 (la D(−1) es un
## instante y la D9 llena el espacio: se nombran en la información).
func dp_validas(t: String = tipo) -> Array:
	var d: PackedInt32Array = Fisica.StringType(t)["dp"]
	return Array(d).filter(func(q): return q >= 0 and q <= 8)

# --- Dibujo ------------------------------------------------------------------------------

func _rebuild() -> void:
	for nodo in [branas, cuerdas]:
		for c in nodo.get_children():
			nodo.remove_child(c)
			c.queue_free()
	_anclas.clear()
	var g := RandomNumberGenerator.new()
	g.seed = rng.seed + 7
	var mat_b := glass_mat(Color(0.55, 0.8, 1.0), 0.16)
	var luz_b := glow_mat(Color(0.55, 0.8, 1.0), 1.2)
	for x in pos:
		if p == 0:
			var s := sphere(0.1, luz_b)
			s.position = Vector3(x, ALTURA, 0)
			branas.add_child(s)
		elif p == 1:
			branas.add_child(rod(Vector3(x, ALTURA, -LADO), Vector3(x, ALTURA, LADO), 0.025, luz_b))
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.01, ALTO, 2.0 * LADO)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = mat_b
			mi.position = Vector3(x, ALTURA, 0)
			branas.add_child(mi)
	var sin_masa := glow_mat(Color(0.5, 1.0, 0.55), 1.4)
	var con_masa := glow_mat(Color(1.0, 0.6, 0.3), 1.4)
	for i in pos.size():
		for j in pos.size():
			_anclas.append([i, j, g.randf_range(0.5, ALTO - 0.5), g.randf_range(-1.4, 1.4), g.randf_range(0.5, ALTO - 0.5),
				g.randf_range(-1.4, 1.4), g.randf() * TAU])
			var mi := MeshInstance3D.new()
			mi.material_override = sin_masa if absf(pos[i] - pos[j]) < TOL else con_masa
			cuerdas.add_child(mi)
	_draw_grid()
	_draw_strings()

## Punto de anclaje en la brana i: en una D0, su centro; en una D1, a lo largo de su línea.
func _ancla(i: int, y: float, z: float) -> Vector3:
	if p == 0:
		return Vector3(pos[i], ALTURA, 0)
	if p == 1:
		return Vector3(pos[i], ALTURA, z)
	return Vector3(pos[i], ALTURA - ALTO / 2 + y, z)

func _draw_strings() -> void:
	for idx in _anclas.size():
		var an: Array = _anclas[idx]
		var i: int = an[0]
		var j: int = an[1]
		var a := _ancla(i, an[2], an[3])
		var b := _ancla(j, an[4], an[5])
		var lazo := Vector3.ZERO
		if i == j:
			# Los dos extremos en la misma brana: un arco que sale de ella.
			b = a + Vector3(0, 0, 0.5) if p != 0 else a
			lazo = Vector3(0.45 if idx % 2 == 0 else -0.45, 0.35 if p == 0 else 0.0, 0.0)
		# Extremos fijos en las branas: modos sin nσ (Dirichlet), la forma de la fase 5.
		var sh: PackedFloat64Array = Fisica.StringShape("DD", 1.0, PackedInt32Array([1, 0, 0, 0]), PackedFloat64Array([an[6], 0, 0, 0]),
			PackedInt32Array([0, 1, 0, 0]), PackedFloat64Array([0, an[6], 0, 0]), tau * 2.0, PUNTOS)
		var pts := PackedVector3Array()
		for q in PUNTOS:
			var s := float(q) / (PUNTOS - 1)
			var c := a.lerp(b, s) + lazo * sin(PI * s)
			if i == j and p == 0:
				c = a + Vector3(lazo.x * sin(TAU * s), lazo.y * (1.0 - cos(TAU * s)), 0)
			pts.append(c + Vector3(0, sh[2 * q] * 0.03, sh[2 * q + 1] * 0.03))
		(cuerdas.get_child(idx) as MeshInstance3D).mesh = CableRenderer.tube_mesh(pts, 0.016, 5)

## Fuentes de la rejilla: [x, radial, intensidad]. Por brana ∝ G·T_p ∝ g_s²/g_s = g_s; por cuerda
## estirada ∝ G·M ∝ g_s²·M (las dos orientaciones). La forma 1/√(r² + ε²) es ilustrativa.
func _fuentes() -> Array:
	var f := []
	for x in pos:
		f.append([x, p == 0, 0.6 * gs])
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			var d := absf(pos[i] - pos[j])
			if d >= TOL:
				f.append([0.5 * (pos[i] + pos[j]), true, 2.0 * 0.6 * gs * gs * sqrt(Fisica.StretchedMass2(d, 1.0, 0))])
	return f

func profundidad(x: float, z: float, f: Array = []) -> float:
	if f.is_empty():
		f = _fuentes()
	var h := 0.0
	for fu in f:
		var r2: float = pow(x - fu[0], 2) + (z * z if fu[1] else 0.0)
		h += fu[2] / sqrt(r2 + 0.09)
	return minf(h, 2.0)

func _draw_grid() -> void:
	var f := _fuentes()
	var im: ImmediateMesh = rejilla.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var paso := 2.0 * REJ / (LINEAS - 1)
	var fino := paso / 2.0
	for a in LINEAS:
		var u := -REJ + a * paso
		for b in int(2.0 * REJ / fino):
			var v0 := -REJ + b * fino
			var v1 := v0 + fino
			for par in [[Vector2(u, v0), Vector2(u, v1)], [Vector2(v0, u), Vector2(v1, u)]]:
				for q in par:
					im.surface_add_vertex(Vector3(q.x, 0.02 - (profundidad(q.x, q.y, f) if not f.is_empty() else 0.0), q.y))
	im.surface_end()

func step(dt: float) -> void:
	tau += dt
	_draw_strings()

func reset() -> void:
	tau = 0.0
	_draw_strings()

# --- Interfaz ----------------------------------------------------------------------------

func build_ui(pnl: VBoxContainer) -> void:
	LabUI.option(pnl, "Tipo:", ["Tipo I", "Tipo IIA", "Tipo IIB", "Heterótica SO(32)", "Heterótica E8 × E8"], TIPOS.find(tipo), _on_tipo)
	_gs_sl = LabUI.slider(pnl, "Acoplamiento g_s", 0.05, 2.0, 0.05, gs, _on_gs, "%.2f")
	LabUI.section(pnl, "D-branas")
	_p_opt = LabUI.option(pnl, "Branas:", ["—"], 0, _on_p)
	_n_sl = LabUI.slider(pnl, "Número de branas", 1, MAX_BRANAS, 1, maxi(pos.size(), 1), _on_n, "%d")
	_sel_sl = LabUI.slider(pnl, "Brana elegida", 1, MAX_BRANAS, 1, sel + 1, _on_sel, "%d")
	_pos_sl = LabUI.slider(pnl, "Posición x (ℓ_s)", -3.0, 3.0, 0.05, 0.0, _on_pos, "%.2f")
	var r := LabUI.row(pnl)
	LabUI.button(r, "Juntar todas", _juntar)
	LabUI.button(r, "Separar", _separar)
	LabUI.note(pnl, "Las cuerdas abiertas terminan en las branas (extremos Dirichlet en las 9 − p direcciones transversales). Verdes: sin masa (branas juntas: bosones gauge); naranjas: estiradas, con la masa de su longitud. Con g_s ≥ 1 el cálculo perturbativo deja de valer: entonces manda la teoría dual.")
	_sync()

func _sync() -> void:
	if _p_opt == null:
		return
	_syncing = true
	var dv := dp_validas()
	_p_opt.clear()
	for q in dv:
		_p_opt.add_item("D%d" % q)
	if dv.is_empty():
		_p_opt.add_item("— (sin D-branas)")
	_p_opt.select(maxi(dv.find(p), 0))
	_p_opt.disabled = dv.is_empty()
	for s in [_n_sl, _sel_sl, _pos_sl]:
		(s as HSlider).editable = not dv.is_empty()
	_gs_sl.value = gs
	_n_sl.value = maxi(pos.size(), 1)
	_sel_sl.max_value = maxi(pos.size(), 1)
	_sel_sl.value = sel + 1
	_pos_sl.value = pos[sel] if sel < pos.size() else 0.0
	_syncing = false

func _on_tipo(i: int) -> void:
	remember()
	tipo = TIPOS[i]
	var dv := dp_validas()
	if dv.is_empty():
		pos = []
	else:
		if not p in dv:
			p = dv[mini(1, dv.size() - 1)]
		if pos.is_empty():
			pos = [-1.0, 1.0]
	sel = 0
	_sync()
	_rebuild()

func _on_gs(v: float) -> void:
	if _syncing:
		return
	remember()
	gs = v
	_draw_grid()

func _on_p(i: int) -> void:
	if _syncing:
		return
	remember()
	p = dp_validas()[i]
	_rebuild()

func _on_n(v: float) -> void:
	if _syncing or dp_validas().is_empty():
		return
	remember()
	var nn := int(v)
	while pos.size() < nn:
		pos.append(clampf(float(pos.back()) + 1.0 if not pos.is_empty() else 0.0, -3.0, 3.0))
	pos.resize(nn)
	sel = mini(sel, nn - 1)
	_sync()
	_rebuild()

func _on_sel(v: float) -> void:
	if _syncing:
		return
	sel = clampi(int(v) - 1, 0, maxi(pos.size() - 1, 0))
	_sync()

func _on_pos(v: float) -> void:
	if _syncing or sel >= pos.size():
		return
	remember()
	pos[sel] = v
	_rebuild()

func _juntar() -> void:
	if pos.is_empty():
		return
	remember()
	var x: float = pos[sel]
	for i in pos.size():
		pos[i] = x
	_sync()
	_rebuild()

func _separar() -> void:
	remember()
	for i in pos.size():
		pos[i] = (i - (pos.size() - 1) / 2.0) * 1.5
	_sync()
	_rebuild()

func info() -> String:
	var t: Dictionary = Fisica.StringType(tipo)
	var dp: Array = Array(t["dp"] as PackedInt32Array)
	var s := "%s (D = 10): %d supercargas · %s · %s · %s" % [t["nombre"], t["supercargas"], "orientada" if t["orientada"] else "no orientada",
		"quiral" if t["quiral"] else "no quiral",
		"cuerdas abiertas y cerradas" if t["abiertas"] else ("cuerdas cerradas (y abiertas en las D-branas)" if not dp.is_empty() else "solo cuerdas cerradas")]
	s += "\nSin masa: %s · grupo gauge: %s · D-branas estables: %s" % [t["sin_masa"], t["gauge"],
		", ".join(dp.map(func(q): return "D%d" % q)) if not dp.is_empty() else "ninguna"]
	s += "\ng_s = %.2f · G₁₀ = 8π⁶g_s²α′⁴ = %s" % [gs, LabUI.sci(Fisica.Newton10(gs, 1.0), 3)]
	if dp.is_empty():
		s += "\nSin D-branas: el grupo gauge sale de 16 dimensiones internas de la cuerda en una red par autodual: %s + 16 = 496 bosones gauge." % (
			"E8 × E8, 2 × %d raíces" % Fisica.LatticeRoots(8) if tipo == "HE" else "Spin(32)/Z₂, %d raíces" % Fisica.LatticeRoots(16))
	else:
		s += "\nD%d: T_%d = 1/(g_s(2π)^%d α′^%s) = %s · extremos libres (N) en %d direcciones (tiempo y volumen), fijos (D) en %d" % [
			p, p, p, str((p + 1) / 2.0), LabUI.sci(Fisica.BraneTension(p, gs, 1.0), 3), p + 1, 9 - p]
		var gg: Dictionary = Fisica.BraneGauge(tipo, p, PackedFloat64Array(pos), TOL)
		s += "\n%d D%d en x = %s → grupo gauge %s (%d bosones gauge sin masa)" % [pos.size(), p,
			", ".join(pos.map(func(x): return "%.2f" % x)), gg["grupo"], gg["vectores"]]
		var est := []
		for i in pos.size():
			for j in range(i + 1, pos.size()):
				var d := absf(pos[i] - pos[j])
				if d >= TOL:
					est.append([sqrt(Fisica.StretchedMass2(d, 1.0, 0)), "(%d, %d): d = %.2f, M = %.3f" % [i + 1, j + 1, d, sqrt(Fisica.StretchedMass2(d, 1.0, 0))]])
		est.sort_custom(func(a, b): return a[0] < b[0])
		if not est.is_empty():
			s += "\nCuerdas estiradas (M = d/2πα′, en M_s): " + ", ".join(est.map(func(e): return e[1]))
		if tipo == "I":
			s += "\nTipo I: la proyección Ω da O(k) en las D1 y Sp(k) en las D5; las 16 D9 (y sus imágenes) dan el SO(32) del vacío."
		if p == 3:
			var pila := 0
			for x in pos:
				pila = maxi(pila, pos.filter(func(y): return absf(y - x) < TOL).size())
			s += "\nCerca de %d D3 juntas el espacio es AdS₅ × S⁵ de radio L = (4πg_sN)^¼ ℓ_s = %.3f ℓ_s." % [pila, Fisica.AdsRadius(gs, pila, 1.0)]
	match tipo:
		"IIA":
			s += "\nDualidad: R₁₁ = g_s√α′ = %.2f ℓ_s. Con g_s ≳ 1 la 11.ª dimensión se hace grande: teoría M en D = 11 (las D0, de masa 1/(g_s√α′) = 1/R₁₁, son sus modos de Kaluza-Klein)." % Fisica.MTheoryRadius(gs, 1.0)
		"IIB":
			s += "\nDualidad S: g_s → 1/g_s = %.2f intercambia la cuerda F1 y la D1 (T_D1 = T_F1/g_s = %.4f)." % [1.0 / gs, Fisica.BraneTension(1, gs, 1.0)]
		"I":
			s += "\nDualidad S: la tipo I con g_s es la heterótica SO(32) con g = 1/g_s = %.2f." % (1.0 / gs)
		"HO":
			s += "\nDualidad S: la heterótica SO(32) con g_s es la tipo I con g = 1/g_s = %.2f." % (1.0 / gs)
		"HE":
			s += "\nA acoplamiento fuerte: teoría M en un intervalo de longitud ∝ g_s (Hořava-Witten)."
	if gs >= 1.0:
		s += "\n[color=#ffb060]⚠ g_s ≥ 1: fuera del régimen perturbativo; estas fórmulas (a primer orden en g_s) ya no bastan: mira la teoría dual.[/color]"
	return s

func metricas() -> Dictionary:
	return {"entidades": pos.size() + _anclas.size()}

func estado() -> Dictionary:
	return {"tipo": tipo, "gs": gs, "p": p, "pos": pos.duplicate()}

func cargar(d: Dictionary) -> String:
	var t := str(d.get("tipo", ""))
	if not t in TIPOS:
		return "tipo de cuerda desconocido"
	var g := float(d.get("gs", 0.0))
	if g < 0.05 or g > 2.0:
		return "g_s fuera de rango (0,05 a 2)"
	var ps = d.get("pos", [])
	if typeof(ps) != TYPE_ARRAY or (ps as Array).size() > MAX_BRANAS:
		return "posiciones: una lista de hasta %d" % MAX_BRANAS
	for x in ps:
		if absf(float(x)) > 3.0:
			return "posición fuera de rango (−3 a 3 ℓ_s)"
	var dv := dp_validas(t)
	var pp := int(d.get("p", -99))
	if not dv.is_empty():
		if not pp in dv:
			return "una D%d no es estable en la %s" % [pp, Fisica.StringType(t)["nombre"]]
		if (ps as Array).is_empty():
			return "faltan las branas"
	tipo = t
	gs = g
	pos = []
	if not dv.is_empty():
		p = pp
		for x in ps:
			pos.append(float(x))
	sel = 0
	_sync()
	_rebuild()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Tipos de supercuerda", "nivel": "exacto",
			"modelo": "Espectro sin masa, supercargas, orientación, quiralidad y D-branas estables (BPS) de las cinco supercuerdas en D = 10",
			"ecuaciones": "IIA: Dp con p par; IIB: p impar; tipo I: D1, D5, D9; heteróticas: ninguna", "unidades": "adimensional (recuentos)",
			"referencias": "Polchinski, String Theory II, cap. 10–13; Johnson, D-Branes (2003)"},
		{"subsistema": "Tensiones y masas", "nivel": "exacto",
			"modelo": "A primer orden en g_s: tensión de una Dp, de la cuerda fundamental, y masa de una cuerda abierta estirada entre dos branas (estado más bajo tras la GSO)",
			"ecuaciones": "T_p = 1/(g_s(2π)^p α′^((p+1)/2)), T_F1 = 1/(2πα′), M² = (d/2πα′)² + N/α′",
			"unidades": "α′ = 1: longitudes en ℓ_s, masas en M_s", "referencias": "Polchinski II, cap. 13"},
		{"subsistema": "Grupo gauge en las branas", "nivel": "exacto",
			"modelo": "N branas juntas: U(N) en la tipo II; en la tipo I, O(k) en D1 y Sp(k) en D5 por la proyección Ω (nivel perturbativo)",
			"ecuaciones": "U(N): N² bosones gauge; O(k): k(k − 1)/2; Sp(k): k(2k + 1)", "unidades": "adimensional (recuentos)",
			"referencias": "Witten, Nucl. Phys. B 460, 335 (1996) y 460, 541 (1996); Polchinski y Witten, Nucl. Phys. B 460, 525 (1996)"},
		{"subsistema": "Grupo gauge heterótico", "nivel": "exacto",
			"modelo": "Las 16 dimensiones internas viven en una red par autodual: E8 ⊕ E8 o D16⁺; los bosones gauge son sus raíces (norma 2, contadas en el programa) más 16",
			"ecuaciones": "2 × 240 + 16 = 480 + 16 = 496", "unidades": "adimensional (recuentos)",
			"referencias": "Gross, Harvey, Martinec y Rohm, Nucl. Phys. B 256, 253 (1985); Polchinski II, cap. 11"},
		{"subsistema": "g_s y dualidades", "nivel": "aproximado",
			"modelo": "Relaciones a primer orden en g_s; las dualidades S (IIB consigo misma, tipo I ↔ heterótica SO(32)) y la teoría M son conjeturas con muchas comprobaciones (estados BPS). Con g_s ≥ 1 el cálculo perturbativo no vale",
			"ecuaciones": "16πG₁₀ = (2π)⁷g_s²α′⁴; R₁₁ = g_s√α′; L⁴ = 4πg_sNα′² (N D3)", "unidades": "ℓ_s",
			"referencias": "Witten, Nucl. Phys. B 443, 85 (1995); Hořava y Witten, Nucl. Phys. B 460, 506 (1996); Maldacena, Adv. Theor. Math. Phys. 2, 231 (1998)"},
		{"subsistema": "Branas y cuerdas dibujadas", "nivel": "ilustrativo",
			"modelo": "Membranas translúcidas con 2 de sus p dimensiones; las cuerdas vibran con el modo sin σ de extremos fijos (amplitud visual)",
			"ecuaciones": "", "unidades": "sin escala", "referencias": ""},
		{"subsistema": "Curvatura del espacio-tiempo", "nivel": "ilustrativo",
			"modelo": "Rejilla hundida con 1/√(r² + ε²): proporcional a g_s por brana (G·T_p) y a g_s²·M por cuerda estirada. Las escalas con g_s son las reales; la forma no es la solución de supergravedad",
			"ecuaciones": "h ∝ G·E, G ∝ g_s², T_p ∝ 1/g_s", "unidades": "sin escala", "referencias": ""},
	]
