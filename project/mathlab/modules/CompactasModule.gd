extends LabModule
## Dimensiones compactas (Física moderna, Fase 6). La cuerda cerrada en un toro T^k de radio R:
## el momento de Kaluza-Klein n, el enrollamiento w y los osciladores N, Ñ dan su masa,
## M² = (n/R)² + (wR/α′)² + (2/α′)(N + Ñ − 2a) con N − Ñ = n·w; la dualidad T (R → α′/R,
## n ↔ w) y la simetría aumentada en R = √α′. «Calabi-Yau»: la sección real de la quíntica
## (ilustrativa) con sus números exactos. Unidades de cuerda: α′ = 1 (R en ℓ_s, M en M_s).

const CY_SHADER := preload("res://mathlab/fisica/shaders/calabi_yau.gdshader")
const PUNTOS := 120
const LARGO := 6.0                    # dirección grande dibujada (k = 1)
const MAYOR := 2.0                    # radio mayor del toro dibujado (k ≥ 2)
const ALTURA := 1.2
const PRESETS := ["Personalizado", "Taquión (N = Ñ = 0)", "Gravitón (N = Ñ = 1)", "Kaluza-Klein: n = 1", "Enrollada: w = 1",
	"Autodual: R = √α′, n = w = 1"]

var teoria := "bosonica"              # «bosonica» (D = 26) o «super» (tipo II, D = 10)
var k := 2                            # dimensiones compactas (todas de radio R)
var radio := 1.6                      # R en ℓ_s = √α′
var n := 1                            # momento en la primera dimensión compacta
var w := 1                            # enrollamiento en ella
var osc_n := 1                        # N (modos hacia la derecha)
var osc_nt := 0                       # Ñ (hacia la izquierda)
var vista := 0                        # 0 toro, 1 Calabi-Yau
var tau := 0.0
var fases := [0.0, 0.0]
var tubo: MeshInstance3D
var line: MeshInstance3D
var cy: MeshInstance3D
var cy_mat: ShaderMaterial
var _sl := {}
var _teoria_opt: OptionButton
var _vista_opt: OptionButton
var _syncing := false

func title() -> String: return "Dimensiones compactas"
func formula() -> String: return "M² = (n/R)² + (wR/α′)² + (2/α′)(N + Ñ − 2a),  N − Ñ = n·w"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3(0, ALTURA, 0), "dist": 8.0, "yaw": -30.0, "pitch": -22.0}

func setup() -> void:
	tubo = MeshInstance3D.new()
	tubo.material_override = glass_mat(Color(0.45, 0.75, 1.0), 0.2)
	add_child(tubo)
	line = MeshInstance3D.new()
	line.material_override = glow_mat(Color(1.0, 0.8, 0.35), 1.6)
	add_child(line)
	cy_mat = ShaderMaterial.new()
	cy_mat.shader = CY_SHADER
	cy = MeshInstance3D.new()
	cy.mesh = _cy_mesh()
	cy.material_override = cy_mat
	cy.scale = Vector3.ONE * 1.4
	cy.position = Vector3(0, ALTURA, 0)
	add_child(cy)
	fases = [rng.randf() * TAU, rng.randf() * TAU]
	_refresh()

# --- Física del estado -------------------------------------------------------------------

func dim_total() -> int:
	return 26 if teoria == "bosonica" else 10

func emparejado() -> bool:
	return Fisica.CompactLevelMatched(PackedInt32Array([n]), PackedInt32Array([w]), osc_n, osc_nt)

func masa2() -> float:
	return Fisica.CompactMass2(teoria == "super", 1.0, PackedFloat64Array([radio]), PackedInt32Array([n]), PackedInt32Array([w]), osc_n, osc_nt)

## Estados sin masa con carga (n, w) ≠ (0, 0) en el radio actual: los de la simetría aumentada.
func sin_masa_extra() -> int:
	var sp: PackedFloat64Array = Fisica.CompactCircleSpectrum(teoria == "super", 1.0, radio, 1000)
	var c := 0
	for i in range(0, sp.size(), 5):
		if absf(sp[i + 4]) < 1e-6 and (sp[i] != 0.0 or sp[i + 1] != 0.0):
			c += 1
	return c

func dualidad_t() -> void:
	remember()
	radio = clampf(1.0 / radio, 0.2, 5.0)
	var t := n
	n = w
	w = t
	_sync()
	_refresh()

# --- Dibujo ------------------------------------------------------------------------------

## Radio dibujado del círculo compacto (crece con R; la forma real de un toro plano no cabe en 3D).
func _r_vis() -> float:
	return clampf(0.3 * radio, 0.08, 1.2)

func _refresh() -> void:
	tubo.visible = vista == 0
	line.visible = vista == 0
	cy.visible = vista == 1
	var r := _r_vis()
	if k == 1:
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = LARGO
		cm.radial_segments = 48
		tubo.mesh = cm
		tubo.rotation = Vector3(0, 0, PI / 2)
		tubo.position = Vector3(0, ALTURA, 0)
	else:
		var tm := TorusMesh.new()
		tm.inner_radius = MAYOR - r
		tm.outer_radius = MAYOR + r
		tm.rings = 64
		tm.ring_segments = 32
		tubo.mesh = tm
		tubo.rotation = Vector3.ZERO
		tubo.position = Vector3(0, ALTURA, 0)
	_draw_string()

## Punto del tubo: u a lo largo de la dirección grande (recta si k = 1, el círculo mayor si k ≥ 2)
## y θ alrededor del círculo compacto, a distancia rad del eje.
func _surface(u: float, th: float, rad: float) -> Vector3:
	if k == 1:
		return Vector3(u, ALTURA + rad * cos(th), rad * sin(th))
	var e := Vector3(cos(u), 0, sin(u))
	return Vector3(0, ALTURA, 0) + e * MAYOR + (e * cos(th) + Vector3.UP * sin(th)) * rad

func _draw_string() -> void:
	if vista != 0:
		return
	# Rizos de los osciladores: la cerrada de la fase 5 (derecha N, izquierda Ñ).
	var sh: PackedFloat64Array = Fisica.StringShape("cerrada", 1.0, PackedInt32Array([osc_n, 0, 0, 0]), PackedFloat64Array([fases[0], 0, 0, 0]),
		PackedInt32Array([osc_nt, 0, 0, 0]), PackedFloat64Array([fases[1], 0, 0, 0]), tau, PUNTOS)
	var r := _r_vis()
	var u0 := 0.0 if k == 1 else PI / 2      # el lado del toro que mira a la cámara
	var th0 := tau * 0.8 * n / (radio * radio + 0.5)       # el momento n hace girar la cuerda (ilustrativo)
	var pts := PackedVector3Array()
	for j in PUNTOS + 1:
		var q := j % PUNTOS
		var sg := TAU * q / PUNTOS
		var th: float
		var u: float
		if w == 0:
			# Sin enrollar: un lazo pequeño sobre la superficie, contráctil.
			th = th0 + 0.35 * sin(sg)
			u = u0 + (0.35 if k == 1 else 0.35 / MAYOR) * cos(sg)
		else:
			th = th0 + w * sg
			u = u0 + (0.12 if k == 1 else 0.06) * sin(sg)   # separa las vueltas para contarlas
		u += sh[2 * q + 1] * (0.04 if k == 1 else 0.02)
		pts.append(_surface(u, th, r + 0.03 + sh[2 * q] * 0.04))
	line.mesh = CableRenderer.tube_mesh(pts, 0.025, 6)

func _cy_mesh() -> ArrayMesh:
	const N := 5
	const G := 18
	var s: PackedFloat64Array = Fisica.CalabiYauSection(N, G, 1.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for parche in N * N:
		var col := Color.from_hsv(float(parche) / (N * N), 0.55, 1.0)
		var base := parche * G * G
		for v in G * G:
			var o := 4 * (base + v)
			verts.append(Vector3(s[o], 0.0, s[o + 1]))
			uvs.append(Vector2(s[o + 2], s[o + 3]))
			cols.append(col)
		for i in G - 1:
			for j in G - 1:
				var a := base + i * G + j
				idx.append_array(PackedInt32Array([a, a + G, a + 1, a + 1, a + G, a + G + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	return m

## Capturas (mflabshot compactas [cy]).
func demo(extra: PackedStringArray) -> void:
	if "cy" in extra:
		vista = 1
		_sync()
		_refresh()

func step(dt: float) -> void:
	tau += dt
	if vista == 0:
		_draw_string()
	else:
		cy_mat.set_shader_parameter("angulo", 0.6 + tau * 0.25)

func reset() -> void:
	tau = 0.0
	_draw_string()

# --- Interfaz ----------------------------------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	_vista_opt = LabUI.option(p, "Vista:", ["Toro", "Calabi-Yau (quíntica)"], vista, _on_vista)
	_teoria_opt = LabUI.option(p, "Teoría:", ["Bosónica (D = 26)", "Tipo II (D = 10)"], 0 if teoria == "bosonica" else 1, _on_teoria)
	_sl["k"] = LabUI.slider(p, "Dimensiones compactas k", 1, dim_total() - 4, 1, k, func(v): _cambiar("k", int(v)), "%d")
	_sl["radio"] = LabUI.slider(p, "Radio R (ℓ_s)", 0.2, 5.0, 0.01, radio, func(v): _cambiar("radio", v), "%.2f")
	LabUI.option(p, "Estado:", PRESETS, 0, _on_preset)
	LabUI.section(p, "Estado de la cuerda")
	_sl["n"] = LabUI.slider(p, "Momento n", -3, 3, 1, n, func(v): _cambiar("n", int(v)), "%d")
	_sl["w"] = LabUI.slider(p, "Enrollamiento w", -3, 3, 1, w, func(v): _cambiar("w", int(v)), "%d")
	_sl["osc_n"] = LabUI.slider(p, "Osciladores N (derecha)", 0, 3, 1, osc_n, func(v): _cambiar("osc_n", int(v)), "%d")
	_sl["osc_nt"] = LabUI.slider(p, "Osciladores Ñ (izquierda)", 0, 3, 1, osc_nt, func(v): _cambiar("osc_nt", int(v)), "%d")
	LabUI.button(p, "Dualidad T: R → α′/R, n ↔ w", dualidad_t)
	LabUI.note(p, "n: momento a lo largo de la dimensión compacta (masa n/R, la de Kaluza-Klein). w: vueltas de la cuerda alrededor de ella (masa wR/α′: la tensión por la longitud). El estado vive en una de las k dimensiones; las otras k − 1 dan las mismas masas. El toro dibujado es ilustrativo: un toro plano no cabe en 3D sin deformarse.")

func _cambiar(campo: String, v) -> void:
	if _syncing:
		return
	remember()
	set(campo, v)
	_refresh()

func _sync() -> void:
	_syncing = true
	_teoria_opt.select(0 if teoria == "bosonica" else 1)
	_vista_opt.select(vista)
	(_sl["k"] as HSlider).max_value = dim_total() - 4
	for c in _sl:
		(_sl[c] as HSlider).value = get(c)
	_syncing = false

func _on_vista(i: int) -> void:
	vista = i
	_refresh()

func _on_teoria(i: int) -> void:
	remember()
	teoria = "bosonica" if i == 0 else "super"
	k = mini(k, dim_total() - 4)
	_sync()
	_refresh()

func _on_preset(i: int) -> void:
	if i == 0:
		return
	remember()
	var est: Array = [[], [0, 0, 0, 0], [0, 0, 1, 1], [1, 0, 1, 1], [0, 1, 1, 1], [1, 1, 1, 0]][i]
	n = est[0]
	w = est[1]
	osc_n = est[2]
	osc_nt = est[3]
	if i == 5:
		teoria = "bosonica"
		radio = 1.0
	_sync()
	_refresh()

func info() -> String:
	var d := dim_total()
	var sup := teoria == "super"
	var s := "%s en D = %d: %d dimensiones grandes y k = %d compactas en un toro T^%d de radio R = %.2f ℓ_s." % [
		"Tipo II" if sup else "Bosónica", d, d - k, k, k, radio]
	if vista == 1:
		return s + "\nQuíntica de CP⁴: χ = %d (clase de Chern) = 2(h¹¹ − h²¹) con h¹¹ = 1, h²¹ = 101 (126 quínticas − 25 de GL(5)). En la heterótica con la inmersión estándar da |χ|/2 = %d generaciones; en la tipo II deja 8 de las 32 supercargas (un toro T⁶ las deja todas). Tiene 6 dimensiones reales: encaja con k = 6 en D = 10. Lo dibujado es una sección real proyectada (ilustrativo)." % [
			Fisica.CompactEuler(5, 4), absi(Fisica.CompactEuler(5, 4)) / 2]
	s += "\nEstado: n = %d, w = %d, N = %d, Ñ = %d" % [n, w, osc_n, osc_nt]
	if not emparejado():
		return s + "\n[color=#ff7070]✖ No cumple el emparejamiento N − Ñ = n·w (%d ≠ %d): no es un estado físico.[/color]" % [osc_n - osc_nt, n * w]
	var m2 := masa2()
	s += "\nα′M² = (n/R)² + (wR)² + 2(N + Ñ − %d) = %.3f + %.3f + %d = %.4f" % [0 if sup else 2, pow(n / radio, 2), pow(w * radio, 2),
		2 * (osc_n + osc_nt - (0 if sup else 2)), m2]
	s += " · " + ("taquión (M² < 0)" if m2 < -1e-9 else ("sin masa" if absf(m2) < 1e-6 else "M = %.4f M_s" % sqrt(m2)))
	s += "\nDualidad T: R′ = α′/R = %.3f ℓ_s con n ↔ w da la misma masa (la cuerda no distingue R de α′/R)." % (1.0 / radio)
	var extra := sin_masa_extra()
	if extra > 0:
		s += "\n✦ Radio autodual: %d estados más sin masa con n, w ≠ 0; 4 de ellos son bosones gauge: U(1)² → SU(2) × SU(2)." % extra
	elif sup and absf(radio - 1.0) < 0.005:
		s += "\nEn la tipo II no hay simetría aumentada en R = √α′ (sin taquión, los estados con n, w ≠ 0 tienen masa)."
	var sp: PackedFloat64Array = Fisica.CompactCircleSpectrum(sup, 1.0, radio, 6)
	var l := []
	for i in range(0, sp.size(), 5):
		l.append("(%d, %d, %d, %d) %s" % [int(sp[i]), int(sp[i + 1]), int(sp[i + 2]), int(sp[i + 3]), str(snappedf(sp[i + 4], 0.001))])
	s += "\nMás ligeros (n, w, N, Ñ) α′M²: " + ", ".join(l)
	s += "\nGravedad en %d dimensiones: G = G_%d / (2πR)^%d (volumen %s ℓ_s^%d): las dimensiones pequeñas no se notan hasta energías ~1/R." % [
		d - k, d, k, LabUI.sci(pow(TAU * radio, k), 2), k]
	return s

func metricas() -> Dictionary:
	return {"entidades": 1}

func estado() -> Dictionary:
	return {"teoria": teoria, "k": k, "radio": radio, "n": n, "w": w, "N": osc_n, "Nt": osc_nt, "vista": vista}

func cargar(d: Dictionary) -> String:
	var t := str(d.get("teoria", ""))
	if not t in ["bosonica", "super"]:
		return "teoría desconocida"
	var kk := int(d.get("k", 0))
	if kk < 1 or kk > (26 if t == "bosonica" else 10) - 4:
		return "k fuera de rango (1 a D − 4)"
	var r := float(d.get("radio", 0.0))
	if r < 0.2 or r > 5.0:
		return "radio fuera de rango (0,2 a 5 ℓ_s)"
	for c in ["n", "w"]:
		if absi(int(d.get(c, 99))) > 3:
			return "«%s» fuera de rango (−3 a 3)" % c
	for c in ["N", "Nt"]:
		if int(d.get(c, -1)) < 0 or int(d.get(c, -1)) > 3:
			return "«%s» fuera de rango (0 a 3)" % c
	teoria = t
	k = kk
	radio = r
	n = int(d["n"])
	w = int(d["w"])
	osc_n = int(d["N"])
	osc_nt = int(d["Nt"])
	vista = clampi(int(d.get("vista", 0)), 0, 1)
	if not _sl.is_empty():
		_sync()
	_refresh()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Espectro en el toro", "nivel": "exacto",
			"modelo": "Cuerda cerrada libre en un toro rectangular T^k sin campo B ni líneas de Wilson; el estado tiene carga en una sola dimensión compacta. Tipo II: niveles tras la GSO (sin taquión)",
			"ecuaciones": "M² = Σ(n_i/R_i)² + Σ(w_iR_i/α′)² + (2/α′)(N + Ñ − 2a), N − Ñ = Σn_iw_i (a = 1 bosónica, 0 tipo II)",
			"unidades": "α′ = 1: R en ℓ_s = √α′, M en M_s = 1/√α′; ħ = c = 1",
			"referencias": "Polchinski, String Theory I, §8.1–8.3; Zwiebach, A First Course in String Theory, cap. 17–18"},
		{"subsistema": "Dualidad T y simetría aumentada", "nivel": "exacto",
			"modelo": "El espectro es igual en R y α′/R con n ↔ w; en R = √α′ la bosónica gana bosones gauge sin masa (SU(2) × SU(2))",
			"ecuaciones": "R → α′/R, n ↔ w", "unidades": "ℓ_s", "referencias": "Polchinski I, §8.3"},
		{"subsistema": "Gravedad en D − k dimensiones", "nivel": "exacto",
			"modelo": "Reducción de Kaluza-Klein a primer orden: la constante de Newton efectiva se divide por el volumen compacto",
			"ecuaciones": "G_{D−k} = G_D / (2πR)^k", "unidades": "ℓ_s", "referencias": "Zwiebach, cap. 3"},
		{"subsistema": "Calabi-Yau (quíntica)", "nivel": "exacto",
			"modelo": "Característica de Euler por la clase de Chern de una hipersuperficie de grado 5 en CP⁴ y números de Hodge (h²¹ = deformaciones de la ecuación)",
			"ecuaciones": "c(X) = (1 + H)⁵/(1 + 5H), χ = 5·[H³] = −200 = 2(h¹¹ − h²¹)", "unidades": "adimensional (recuentos y topología)",
			"referencias": "Candelas, Horowitz, Strominger y Witten, Nucl. Phys. B 258, 46 (1985); Hübsch, Calabi-Yau Manifolds (1992)"},
		{"subsistema": "Toro y Calabi-Yau dibujados", "nivel": "ilustrativo",
			"modelo": "El toro dibujado tiene un radio que crece con R pero no es plano; las vueltas de la cuerda son las de w, el giro por n y los rizos de los osciladores son visuales. La Calabi-Yau es la sección real 2D de la de Fermat z₁⁵ + z₂⁵ = 1 (25 parches) proyectada a 3D con un ángulo que gira",
			"ecuaciones": "z₁ = e^{2πik₁/5} cos(ξ)^{2/5}, z₂ = e^{2πik₂/5} sin(ξ)^{2/5}", "unidades": "sin escala",
			"referencias": "Hanson, Notices of the AMS 41, 1156 (1994)"},
	]
