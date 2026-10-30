extends LabModule
## Cuerdas y modos normales (Física moderna, Fase 5). Cuerda relativista libre en el gauge del
## cono de luz: las D − 2 direcciones transversales oscilan con modos normales y cada estado
## cuántico es una partícula con α′M² = N − a (abierta) o 4(N − a) (cerrada, con N = Ñ).
## «Una cuerda»: eliges los cuantos de cada modo y ves su forma (la de un estado coherente con
## esas ocupaciones), su masa, su espín y qué partícula es. «Muchas cuerdas»: miles evaluadas
## en la GPU (shaders/cuerdas.gdshader), coloreadas por su nivel de masa.

const SHADER := preload("res://mathlab/fisica/shaders/cuerdas.gdshader")
const MODOS := 4
const PUNTOS := 160
const LARGO := 4.0                    # dibujo de una abierta (mundo) y diámetro de una cerrada
const NIVEL_COL := [Color(1.0, 0.35, 0.35), Color(0.4, 0.9, 1.0), Color(0.55, 1.0, 0.5), Color(1.0, 0.85, 0.35), Color(0.9, 0.55, 1.0)]
const PRESETS := ["Personalizado", "Vacío (N = 0)", "Bosón gauge: α₋₁ʸ", "Nivel 2: α₋₁ʸ α₋₁ᶻ", "Nivel 2: α₋₂ʸ",
	"Gravitón (cerrada)", "Cerrada con N ≠ Ñ"]

var teoria := "bosonica"              # «bosonica» (D = 26) o «super» (D = 10)
var cuerda := "abierta"               # «abierta» o «cerrada»
var contorno := "NN"                  # abierta: NN (extremos libres) o DD (extremos fijos)
var alpha := 1.0                      # α′ = ℓ_s² (unidades de cuerda)
var oc_y := [1, 0, 0, 0]              # cuantos por modo n = 1…4: polarización y (cerrada: hacia la derecha)
var oc_z := [0, 0, 0, 0]              # polarización z (cerrada: hacia la izquierda)
var fase_y := [0.0, 0.0, 0.0, 0.0]
var fase_z := [0.0, 0.0, 0.0, 0.0]
var vista := 0                        # 0 una cuerda, 1 muchas
var n_cuerdas := 1000
var tau := 0.0
var beads: MultiMeshInstance3D
var line: MeshInstance3D
var marcas: Node3D
var many: MultiMeshInstance3D
var many_mat: ShaderMaterial
var _sliders: Array = []
var _syncing := false

func title() -> String: return "Cuerdas y modos normales"
func formula() -> String: return "α′M² = N − a  (abierta)     α′M² = 4(N − a), N = Ñ  (cerrada)"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3(0, 0.6, 0), "dist": 7.0, "yaw": -25.0, "pitch": -18.0}

func setup() -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = vcolor_mat(1.0, 0.8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = PUNTOS
	beads = MultiMeshInstance3D.new()
	beads.multimesh = mm
	add_child(beads)
	line = MeshInstance3D.new()
	line.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.95, 0.8)
	line.material_override = lm
	add_child(line)
	marcas = Node3D.new()
	add_child(marcas)
	_build_many()
	_new_phases()
	_refresh_view()

## Fases al azar de los modos (con la semilla del laboratorio).
func _new_phases() -> void:
	for i in MODOS:
		fase_y[i] = rng.randf() * TAU
		fase_z[i] = rng.randf() * TAU

# --- Física del estado -------------------------------------------------------------------

func n_right() -> int:
	var n := 0
	for i in MODOS:
		n += (i + 1) * int(oc_y[i])
	return n

func n_left() -> int:
	var n := 0
	for i in MODOS:
		n += (i + 1) * int(oc_z[i])
	return n

## Nivel del estado (N, o N_b en la supercuerda) y si es físico (en la cerrada, N = Ñ).
func nivel() -> int:
	return n_right() if cuerda == "cerrada" else n_right() + n_left()

func emparejado() -> bool:
	return cuerda != "cerrada" or n_right() == n_left()

func alpha_m2() -> float:
	return Fisica.StringAlphaM2(teoria, cuerda, nivel())

func degeneracion(l: int) -> int:
	if teoria == "bosonica":
		var c: PackedInt64Array = Fisica.StringBosonicLevels(24, maxi(l, 1))
		return c[l] * (c[l] if cuerda == "cerrada" else 1)
	var sl: Dictionary = Fisica.StringSuperLevels(maxi(l, 1))
	var d: int = (sl["ns"] as PackedInt64Array)[l] + (sl["r"] as PackedInt64Array)[l]
	return d * (d if cuerda == "cerrada" else 1)

# --- Dibujo ------------------------------------------------------------------------------

func _refresh_view() -> void:
	beads.visible = vista == 0
	line.visible = vista == 0
	marcas.visible = vista == 0
	many.visible = vista == 1
	for c in marcas.get_children():
		c.queue_free()
	if vista == 0 and cuerda == "abierta" and contorno == "DD":
		# Extremos fijos: en dos placas (las D-branas completas, en la fase 6).
		for sx in [-1.0, 1.0]:
			var pm := PlaneMesh.new()
			pm.size = Vector2(1.6, 1.6)
			pm.orientation = PlaneMesh.FACE_X
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = glass_mat(Color(0.5, 0.8, 1.0), 0.18)
			mi.position = Vector3(sx * LARGO / 2, 0.6, 0)
			marcas.add_child(mi)
	_draw_one()

func _shape() -> PackedFloat64Array:
	var cont := "cerrada" if cuerda == "cerrada" else contorno
	return Fisica.StringShape(cont, alpha, PackedInt32Array(oc_y), PackedFloat64Array(fase_y), PackedInt32Array(oc_z), PackedFloat64Array(fase_z), tau, PUNTOS)

## Punto k de la cuerda en el mundo: la abierta estirada a lo largo de x según σ, la cerrada
## en un anillo; el desplazamiento transversal (en ℓ_s) a escala 0,35 mundo/ℓ_s.
func _point(k: int, sh: PackedFloat64Array) -> Vector3:
	var esc := 0.35
	if cuerda == "cerrada":
		var sg := TAU * k / PUNTOS
		var rad := LARGO / 2.0 * 0.6 + sh[2 * k] * esc
		return Vector3(rad * cos(sg), 0.6 + sh[2 * k + 1] * esc, rad * sin(sg))
	return Vector3((float(k) / (PUNTOS - 1) - 0.5) * LARGO, 0.6 + sh[2 * k] * esc, sh[2 * k + 1] * esc)

func _draw_one() -> void:
	if vista != 0:
		return
	var sh := _shape()
	var col: Color = NIVEL_COL[mini(nivel(), NIVEL_COL.size() - 1)] if emparejado() else Color(0.6, 0.6, 0.6)
	var im: ImmediateMesh = line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in PUNTOS:
		im.surface_add_vertex(_point(k, sh))
	if cuerda == "cerrada":
		im.surface_add_vertex(_point(0, sh))
	im.surface_end()
	var mm := beads.multimesh
	for k in PUNTOS:
		var extremo := cuerda == "abierta" and (k == 0 or k == PUNTOS - 1)
		var r := 0.07 if extremo else 0.035
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * r), _point(k, sh)))
		mm.set_instance_color(k, Color(1.0, 0.95, 0.6) if extremo else col)

## Muchas cuerdas: una malla de líneas compartida y la forma de cada una en el shader.
func _build_many() -> void:
	if many == null:
		var am := ArrayMesh.new()
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for k in 49:
			var s := k / 48.0
			verts.append(Vector3(s - 0.5, 0, 0))
			uvs.append(Vector2(s, 0))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arr)
		many_mat = ShaderMaterial.new()
		many_mat.shader = SHADER
		am.surface_set_material(0, many_mat)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = am
		many = MultiMeshInstance3D.new()
		many.multimesh = multi
		many.custom_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
		add_child(many)
	var multi2 := many.multimesh
	multi2.instance_count = n_cuerdas
	var g := RandomNumberGenerator.new()
	g.seed = rng.seed + 99
	for i in n_cuerdas:
		var lv := g.randi_range(0, 4)
		var b := Basis(Vector3(g.randf() - 0.5, g.randf() - 0.5, g.randf() - 0.5).normalized(), g.randf() * TAU)
		var at := Vector3(g.randf_range(-4.5, 4.5), g.randf_range(0.0, 2.5), g.randf_range(-4.5, 4.5))
		multi2.set_instance_transform(i, Transform3D(b, at))
		var a := 0.03 * sqrt(lv + 0.5)
		multi2.set_instance_custom_data(i, Color(a, a * 0.7 * float(lv >= 2), a * 0.5 * float(lv >= 3), float(g.randf() < 0.3)))
		multi2.set_instance_color(i, NIVEL_COL[lv])

func step(dt: float) -> void:
	tau += dt * 1.5
	if vista == 0:
		_draw_one()
	else:
		many_mat.set_shader_parameter("tau", tau)

func reset() -> void:
	tau = 0.0
	_new_phases()
	if vista == 1:
		_build_many()
	_draw_one()

# --- Interfaz ----------------------------------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Vista:", ["Una cuerda", "Muchas cuerdas (GPU)"], vista, _on_vista)
	LabUI.option(p, "Teoría:", ["Bosónica (D = 26)", "Supercuerda (D = 10)"], 0 if teoria == "bosonica" else 1, _on_teoria)
	LabUI.option(p, "Cuerda:", ["Abierta, libre (N–N)", "Abierta, fija (D–D)", "Cerrada"],
		2 if cuerda == "cerrada" else (1 if contorno == "DD" else 0), _on_cuerda)
	LabUI.option(p, "Estado:", PRESETS, 0, _on_preset)
	LabUI.slider(p, "α′ = ℓ_s² (T = 1/2πα′)", 0.5, 2.0, 0.05, alpha, _on_alpha, "%.2f")
	LabUI.section(p, "Cuantos por modo")
	_sliders.clear()
	for pol in 2:
		for i in MODOS:
			var pp := pol
			var ii := i
			var lab := "%s, n = %d" % [("y" if pol == 0 else "z") if cuerda != "cerrada" else ("derecha" if pol == 0 else "izquierda"), i + 1]
			_sliders.append(LabUI.slider(p, lab, 0, 3, 1, (oc_y if pol == 0 else oc_z)[i], func(v): _on_oc(pp, ii, int(v)), "%d"))
	LabUI.slider(p, "Cuerdas en la vista «muchas»", 100, 5000, 100, n_cuerdas, _on_n, "%d")
	LabUI.note(p, "Abierta: polarizaciones y, z; cerrada: modos hacia la derecha y hacia la izquierda. Cada cuanto en el modo n sube el nivel N en n. La masa sale de N y la constante a (1 en la bosónica; en la supercuerda, con la proyección GSO, α′M² = N_b). En la cerrada, los modos hacia la derecha y hacia la izquierda deben sumar lo mismo (N = Ñ): si no, el estado no es físico. La forma dibujada es la de un estado coherente con esas ocupaciones; en 3D se ven 2 de las D − 2 direcciones transversales.")

func _on_vista(i: int) -> void:
	vista = i
	if vista == 1:
		_build_many()
	_refresh_view()

func _on_teoria(i: int) -> void:
	remember()
	teoria = "bosonica" if i == 0 else "super"
	_draw_one()

func _on_cuerda(i: int) -> void:
	remember()
	cuerda = "cerrada" if i == 2 else "abierta"
	contorno = "DD" if i == 1 else "NN"
	_refresh_view()

func _on_alpha(v: float) -> void:
	remember()
	alpha = v
	_draw_one()

func _on_oc(pol: int, i: int, v: int) -> void:
	if _syncing:
		return
	remember()
	(oc_y if pol == 0 else oc_z)[i] = v
	_draw_one()

func _on_n(v: float) -> void:
	n_cuerdas = int(v)
	if vista == 1:
		_build_many()

## Estados de ejemplo: ocupaciones de cada modo.
func _on_preset(i: int) -> void:
	if i == 0:
		return
	remember()
	var y := [0, 0, 0, 0]
	var z := [0, 0, 0, 0]
	match i:
		2: y[0] = 1
		3: y[0] = 1; z[0] = 1
		4: y[1] = 1
		5: y[0] = 1; z[0] = 1
		6: y[0] = 1; z[1] = 1
	if i >= 5:
		cuerda = "cerrada"
	elif cuerda == "cerrada":
		cuerda = "abierta"
	_set_oc(y, z)
	_refresh_view()

func _set_oc(y: Array, z: Array) -> void:
	oc_y = y.duplicate()
	oc_z = z.duplicate()
	_syncing = true
	for k in _sliders.size():
		(_sliders[k] as HSlider).value = (oc_y if k < MODOS else oc_z)[k % MODOS]
	_syncing = false

func info() -> String:
	var dim := 26 if teoria == "bosonica" else 10
	if not emparejado():
		return "[color=#ff7070]✖ Estado no físico: en la cuerda cerrada los modos hacia la derecha (N = %d) y hacia la izquierda (Ñ = %d) deben sumar lo mismo (emparejamiento de niveles).[/color]" % [n_right(), n_left()]
	var l := nivel()
	var am2 := alpha_m2()
	var masa := "M² = %s/α′ < 0 (taquión)" % str(snappedf(am2, 0.001)) if am2 < 0 else ("M = 0" if am2 == 0 else "M = %.4f M_s (M_s = 1/√α′ = %.3f)" % [sqrt(am2), 1.0 / sqrt(alpha)])
	var s := "%s, cuerda %s%s en D = %d · nivel %s = %d · α′M² = %s · %s\n%s\nEstados en este nivel: %d (%s)" % [
		"Bosónica" if teoria == "bosonica" else "Supercuerda", cuerda,
		(" con extremos " + ("fijos (D–D)" if contorno == "DD" else "libres (N–N)")) if cuerda == "abierta" else "", dim,
		"N" if teoria == "bosonica" else "N_b", l, str(snappedf(am2, 0.001)), masa,
		Fisica.StringIdentify(teoria, cuerda, l), degeneracion(l),
		"bosones + fermiones" if teoria == "super" else "polarizaciones de los %d osciladores transversales" % (dim - 2)]
	s += "\nEspectro: " + ", ".join(range(4).map(func(k): return "α′M² = %s (%d)" % [str(snappedf(Fisica.StringAlphaM2(teoria, cuerda, k), 0.01)), degeneracion(k)]))
	s += "\nTensión T = 1/(2πα′) = %.4f · ℓ_s = √α′ = %.3f" % [1.0 / (TAU * alpha), sqrt(alpha)]
	return s

func metricas() -> Dictionary:
	return {"entidades": n_cuerdas if vista == 1 else 1}

func estado() -> Dictionary:
	return {"teoria": teoria, "cuerda": cuerda, "contorno": contorno, "alpha": alpha, "oc_y": oc_y.duplicate(), "oc_z": oc_z.duplicate(),
		"vista": vista, "n_cuerdas": n_cuerdas}

func cargar(d: Dictionary) -> String:
	if not str(d.get("teoria", "")) in ["bosonica", "super"] or not str(d.get("cuerda", "")) in ["abierta", "cerrada"]:
		return "teoría o cuerda desconocida"
	for k in ["oc_y", "oc_z"]:
		var a = d.get(k)
		if typeof(a) != TYPE_ARRAY or (a as Array).size() != MODOS:
			return "faltan las ocupaciones «%s» (%d modos)" % [k, MODOS]
		for x in a:
			if int(x) < 0 or int(x) > 3:
				return "ocupación fuera de rango (0 a 3)"
	teoria = d["teoria"]
	cuerda = d["cuerda"]
	contorno = "DD" if str(d.get("contorno", "NN")) == "DD" else "NN"
	alpha = clampf(float(d.get("alpha", 1.0)), 0.5, 2.0)
	vista = clampi(int(d.get("vista", 0)), 0, 1)
	n_cuerdas = clampi(int(d.get("n_cuerdas", 1000)), 100, 5000)
	var y: Array = []
	var z: Array = []
	for x in d["oc_y"]:
		y.append(int(x))
	for x in d["oc_z"]:
		z.append(int(x))
	_set_oc(y, z)
	if vista == 1:
		_build_many()
	_refresh_view()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Espectro de masas", "nivel": "exacto",
			"modelo": "Cuerda libre cuantizada en el gauge del cono de luz en su dimensión crítica (26 bosónica, 10 supercuerda); degeneraciones por las funciones de partición; en la supercuerda, proyección GSO (sin taquión) y NS = R nivel a nivel (identidad de Jacobi). No hay interacciones (g_s) ni compactificación: eso, en la fase 6",
			"ecuaciones": "abierta α′M² = N − a (a = 1 bosónica; NS con GSO: α′M² = N_b); cerrada α′M² = 4(N − a), N = Ñ",
			"unidades": "ℓ_s = √α′, M_s = 1/√α′, T = 1/(2πα′); ħ = c = 1",
			"referencias": "Polchinski, String Theory I (cap. 1–4) y II (cap. 10); Zwiebach, A First Course in String Theory (cap. 12–14); Gliozzi, Scherk y Olive, Nucl. Phys. B 122, 253 (1977)"},
		{"subsistema": "Modo → partícula", "nivel": "exacto",
			"modelo": "Nivel más bajo de cada caso: taquión (bosónica), bosón gauge sin masa (abierta), gravitón + B + dilatón (cerrada), multiplete de supergravedad tipo II (supercuerda cerrada); espín máximo de los niveles masivos por la trayectoria de Regge principal. En D dimensiones: la reducción a 4 dimensiones no se hace",
			"ecuaciones": "J_máx = N (abierta bosónica), α′M² = J − 1", "unidades": "ħ", "referencias": "Zwiebach, cap. 12–13"},
		{"subsistema": "Forma de la cuerda", "nivel": "exacto",
			"modelo": "Solución clásica de la ecuación de ondas de las direcciones transversales con extremos libres (Neumann: cos nσ), fijos (Dirichlet: sin nσ) o periódica (cerrada: ondas viajeras a derecha e izquierda)",
			"ecuaciones": "∂²X/∂τ² = ∂²X/∂σ²", "unidades": "ℓ_s", "referencias": "Polchinski I, §1.3–1.4"},
		{"subsistema": "Amplitud del dibujo", "nivel": "aproximado",
			"modelo": "Amplitud de un estado coherente con N_n cuantos en el modo n (A = 2√(2α′N_n/n) abierta, √(2α′N_n/n) cada lado de la cerrada); un estado de número no tiene forma clásica definida",
			"ecuaciones": "|⟨α_n⟩| = √(n·N_n)", "unidades": "ℓ_s", "referencias": ""},
		{"subsistema": "Proyección a 3D y muchas cuerdas", "nivel": "ilustrativo",
			"modelo": "Se dibujan 2 de las D − 2 direcciones transversales y la cuerda estirada según σ; en «muchas cuerdas», posiciones, orientaciones y amplitudes al azar para mostrar el rendimiento, con el color del nivel",
			"ecuaciones": "", "unidades": "sin escala", "referencias": ""},
	]
