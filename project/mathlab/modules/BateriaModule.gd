extends LabModule
## Batería cuántica (Física moderna, Fase 4): N ≤ 12 espines ½ en cadena, con
##   batería H_B = (ω₀/2) Σσᶻ + J Σ(σˣσˣ + σʸσʸ + Δ σᶻσᶻ) y cargador resonante g Σσˣ.
## Ciclo de carga (cargador encendido), almacenamiento (apagado) y descarga (otra vez
## encendido: la rotación sigue y devuelve la energía). Evolución unitaria exacta en C#
## (Krylov, Fisica.SpinStep) con ħ = 1 y el tiempo en 1/ω₀. Cada esfera de Bloch muestra el
## estado de un espín: arriba, cargado; una flecha más corta que el radio indica que el espín
## está entrelazado con los demás.

const N_MAX := 12
const RING := 2.2
const FASES := ["Carga", "Almacenamiento", "Descarga", "Parada"]

var n := 8
var w0 := 1.0
var g := 1.0
var jj := 0.0
var delta := 0.0
var auto := true
var t_carga := PI / 2.0               # carga completa sin interacción: g·t = π/2
var t_almacen := 1.0
var psi := PackedFloat64Array()
var obs := PackedFloat64Array()
var fase := 0
var t_fase := 0.0
var t := 0.0
var e0 := 0.0                         # ⟨H_B⟩ del estado vacío
var e_min := 0.0                      # mínimo de H_B (para la ergotropía)
var e_max_carga := 0.0                # mayor energía almacenada durante la carga
var p_max := 0.0
var e_fin_carga := 0.0
var hist_t := PackedFloat32Array()
var hist_e := PackedFloat32Array()
var hist_l := PackedFloat32Array()
var arrows: Array = []
var chart: MeshInstance3D

func title() -> String: return "Batería cuántica"
func formula() -> String: return "H_B = (ω₀/2)Σσᶻ + J Σ(σˣσˣ + σʸσʸ + Δσᶻσᶻ)     cargador: g Σσˣ"
func uses_time() -> bool: return true
func fixed_dt() -> float: return 0.02
func view() -> Dictionary: return {"target": Vector3(0, 0.6, 0), "dist": 8.5, "yaw": -20.0, "pitch": -22.0}

func setup() -> void:
	chart = MeshInstance3D.new()
	chart.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	chart.material_override = m
	add_child(chart)
	_build()

## Esferas, estado vacío y referencias de energía.
func _build() -> void:
	for a in arrows:
		a.queue_free()
	arrows.clear()
	for c in get_children():
		if c.has_meta("esfera"):
			c.queue_free()
	for i in n:
		var ang := TAU * i / n
		var at := Vector3(cos(ang) * RING, 0.6, sin(ang) * RING)
		var s := sphere(0.42, glass_mat(Color(0.6, 0.85, 1.0), 0.1))
		s.position = at
		s.set_meta("esfera", true)
		add_child(s)
		var axis := rod(at - Vector3(0, 0.5, 0), at + Vector3(0, 0.5, 0), 0.004, glass_mat(Color(0.8, 0.9, 1.0), 0.4))
		axis.set_meta("esfera", true)
		add_child(axis)
		var arr := arrow(Vector3.ZERO, Vector3(0, 0.42, 0), 0.018, glow_mat(Color(1, 1, 1), 1.5))
		arr.position = at
		add_child(arr)
		arrows.append(arr)
	psi = PackedFloat64Array(Fisica.SpinEmpty(n))
	e_min = Fisica.SpinGroundEnergy(n, w0, jj, delta)
	obs = PackedFloat64Array(Fisica.SpinObservables(psi, n, w0, jj, delta, g))
	e0 = obs[0]
	fase = 0
	t_fase = 0.0
	t = 0.0
	e_max_carga = 0.0
	p_max = 0.0
	e_fin_carga = 0.0
	hist_t.clear()
	hist_e.clear()
	hist_l.clear()
	_refresh()

func _drive() -> float:
	return g if fase == 0 or fase == 2 else 0.0

func step(dt: float) -> void:
	if fase == 3:
		return
	psi = PackedFloat64Array(Fisica.SpinStep(psi, n, jj, delta, _drive(), dt))
	t += dt
	t_fase += dt
	obs = PackedFloat64Array(Fisica.SpinObservables(psi, n, w0, jj, delta, _drive()))
	var e := stored()
	if fase == 0:
		e_max_carga = maxf(e_max_carga, e)
		if t_fase > 0.0:
			p_max = maxf(p_max, e / t_fase)
	if auto:
		if fase == 0 and t_fase >= t_carga:
			_set_fase(1)
		elif fase == 1 and t_fase >= t_almacen:
			_set_fase(2)
		elif fase == 2 and t_fase >= t_carga:
			_set_fase(3)
	hist_t.append(t)
	hist_e.append(e)
	hist_l.append(obs[3])
	_refresh()

func _set_fase(f: int) -> void:
	if fase == 0 and f != 0:
		e_fin_carga = stored()
	fase = f
	t_fase = 0.0

func reset() -> void:
	_build()

## Energía almacenada respecto del estado vacío.
func stored() -> float:
	return obs[0] - e0

## Flechas de Bloch (longitud |r|: 1 si el espín está en un estado puro) y la gráfica.
func _refresh() -> void:
	for i in arrows.size():
		var r := Vector3(obs[4 + 3 * i], obs[6 + 3 * i], -obs[5 + 3 * i])   # Bloch z → arriba en el mundo
		var len := r.length()
		var a: Node3D = arrows[i]
		if len < 1e-6:
			a.visible = false
			continue
		a.visible = true
		# Quaternion(UP, −UP) da un giro de 180° sobre Y, que deja la flecha arriba: el espín
		# vacío (|↓⟩) se vería cargado. Para apuntar abajo, giro sobre X.
		var dir := r / len
		var q := Quaternion(Vector3.UP, dir) if dir.y > -0.9999 else Quaternion(Vector3.RIGHT, PI)
		a.basis = Basis(q) * Basis.from_scale(Vector3(1, len, 1))
	var im: ImmediateMesh = chart.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x0 := -3.0
	var w := 6.0
	var y0 := 1.6                     # detrás del anillo y por encima de las esferas
	var h := 1.2
	var e_ref := maxf(n * w0, 1e-9)
	for k in 2:
		var c := Color(0.5, 0.6, 0.7)
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x0, y0 + h * k, -RING - 2.2))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x0 + w, y0 + h * k, -RING - 2.2))
	var tmax := maxf(t_carga * 2.0 + t_almacen, 0.1)
	for series in 2:
		var data := hist_e if series == 0 else hist_l
		var col := Color(1.0, 0.75, 0.3) if series == 0 else Color(0.4, 0.9, 0.6)
		for k in range(1, data.size()):
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(x0 + w * minf(hist_t[k - 1] / tmax, 1.0), y0 + h * data[k - 1] / e_ref, -RING - 2.2))
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(x0 + w * minf(hist_t[k] / tmax, 1.0), y0 + h * data[k] / e_ref, -RING - 2.2))
	im.surface_end()

func build_ui(p: VBoxContainer) -> void:
	LabUI.slider(p, "Espines N (dimensión 2ᴺ)", 1, N_MAX, 1, n, _on_n, "%d")
	LabUI.slider(p, "Separación ω₀", 0.5, 2.0, 0.05, w0, _on_w0, "%.2f")
	LabUI.slider(p, "Cargador g", 0.1, 2.0, 0.05, g, _on_g, "%.2f")
	LabUI.slider(p, "Interacción J", -0.5, 0.5, 0.01, jj, _on_j, "%.2f")
	LabUI.slider(p, "Anisotropía Δ", -1.0, 1.0, 0.05, delta, _on_delta, "%.2f")
	LabUI.check(p, "Ciclo automático (carga, almacenamiento, descarga)", auto, func(v): auto = v)
	LabUI.slider(p, "Duración de la carga (1/ω₀)", 0.1, 6.0, 0.05, t_carga, func(v): t_carga = v, "%.2f")
	LabUI.slider(p, "Duración del almacenamiento", 0.0, 6.0, 0.1, t_almacen, func(v): t_almacen = v, "%.1f")
	var row := LabUI.row(p)
	for f in 4:
		var ff := f
		LabUI.button(row, FASES[f], func(): _set_fase(ff))
	LabUI.note(p, "Sin interacción (J = 0) cada espín gira solo y la carga es completa en g·t = π/2. Con J ≠ 0 los espines se entrelazan: la energía de la batería sigue ahí (ergotropía global), pero ya no se puede sacar espín a espín (ergotropía local, verde en la gráfica). La gráfica naranja es la energía almacenada en unidades de Nω₀.")

func _on_n(v: float) -> void:
	remember()
	n = int(v)
	_build()

func _on_w0(v: float) -> void:
	remember()
	w0 = v
	_build()

func _on_g(v: float) -> void:
	remember()
	g = v
	_build()

func _on_j(v: float) -> void:
	remember()
	jj = v
	_build()

func _on_delta(v: float) -> void:
	remember()
	delta = v
	_build()

func info() -> String:
	var e := stored()
	var ergo_g: float = obs[0] - e_min
	var pureza := 0.0
	for i in n:
		pureza += Vector3(obs[4 + 3 * i], obs[5 + 3 * i], obs[6 + 3 * i]).length()
	var s := "%s · t = %.2f/ω₀ (fase %.2f) · N = %d (dimensión %d)\nEnergía almacenada %.4f ω₀ (%.1f %% de Nω₀) · potencia media máx. %.4f ω₀²\nErgotropía global %.4f ω₀ · local Σᵢ %.4f ω₀ · |r| medio %.3f (1: sin entrelazamiento)" % [
		FASES[fase], t, t_fase, n, 1 << n, e, 100.0 * e / (n * w0), p_max, ergo_g, obs[3], pureza / n]
	if e_fin_carga > 0.0 and fase >= 2:
		s += "\nAl acabar la carga: %.4f ω₀ · devuelta en la descarga: %.4f ω₀" % [e_fin_carga, e_fin_carga - e]
	s += "\nNorma |ψ| = %.12f" % obs[2]
	return s

func metricas() -> Dictionary:
	return {"entidades": n, "dimension": 1 << n}

func finito() -> bool:
	return is_finite(obs[2]) and absf(obs[2] - 1.0) < 1e-6

func estado() -> Dictionary:
	return {"n": n, "w0": w0, "g": g, "J": jj, "delta": delta, "auto": auto, "t_carga": t_carga, "t_almacen": t_almacen}

func cargar(d: Dictionary) -> String:
	for k in ["n", "w0", "g", "J", "delta"]:
		if not typeof(d.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			return "falta «%s»" % k
	if int(d["n"]) < 1 or int(d["n"]) > N_MAX or float(d["w0"]) <= 0.0:
		return "valores fuera de rango (1 ≤ N ≤ %d, ω₀ > 0)" % N_MAX
	n = int(d["n"])
	w0 = float(d["w0"])
	g = float(d["g"])
	jj = float(d["J"])
	delta = float(d["delta"])
	auto = bool(d.get("auto", true))
	t_carga = float(d.get("t_carga", PI / 2.0))
	t_almacen = float(d.get("t_almacen", 1.0))
	_build()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Evolución cuántica", "nivel": "exacto",
			"modelo": "Ecuación de Schrödinger de los 2ᴺ estados (N ≤ 12) por subespacios de Krylov (Lanczos con reortogonalización completa, m = 24) y la exponencial exacta de la tridiagonal; la norma se muestra en la información",
			"ecuaciones": "ψ(t + Δt) = e^{−iHΔt} ψ(t)", "unidades": "ħ = 1; energías en ω₀, tiempos en 1/ω₀",
			"referencias": "Saad, SIAM J. Numer. Anal. 29, 209 (1992)"},
		{"subsistema": "Modelo de la batería", "nivel": "aproximado",
			"modelo": "Espines ideales sin disipación ni decoherencia, cadena abierta con interacción XXZ entre vecinos; el cargador es un campo resonante que se enciende y apaga al instante (sistema que rota con ω₀, aproximación de onda rotante)",
			"ecuaciones": "H_B = (ω₀/2)Σσᶻ + J Σ(σˣσˣ + σʸσʸ + Δσᶻσᶻ);  H_rot = J Σ(…) + g Σσˣ",
			"unidades": "ω₀, g, J", "referencias": "Le, Levinsen, Modi, Parish y Pollock, Phys. Rev. A 97, 022106 (2018); Campaioli et al., Phys. Rev. Lett. 118, 150601 (2017)"},
		{"subsistema": "Ergotropía", "nivel": "exacto",
			"modelo": "Global: estado puro, ⟨H_B⟩ − E_mín(H_B) (E_mín por Lanczos). Local: lo que se extrae espín a espín respecto de (ω₀/2)σᶻ, Σᵢ (ω₀/2)(rᶻᵢ + |rᵢ|)",
			"ecuaciones": "𝓔 = Tr(ρH) − min_U Tr(UρU†H)", "unidades": "ω₀",
			"referencias": "Allahverdyan, Balian y Nieuwenhuizen, Europhys. Lett. 67, 565 (2004)"},
	]
