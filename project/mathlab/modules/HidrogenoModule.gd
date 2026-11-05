extends LabModule
## Átomo de hidrógeno (Física moderna, Fase 3): los orbitales exactos
## ψₙₗₘ = Rₙₗ(r)·Yₗᵐ(θ, φ) como una nube de puntos con la densidad |ψ|² (muestreo exacto
## en C#, Fisica.HydrogenSample) y la fase de ψ como color. El estado es estacionario:
## con el tiempo solo gira la fase global, e^{−iEₙt/ħ}, y |ψ|² no cambia.
## Unidades atómicas: a₀ = 1, Eₕ = 27,211386 eV, ħ/Eₕ = 2,4189·10⁻¹⁷ s (CODATA 2022).

const SHADER := preload("res://mathlab/fisica/shaders/nube_orbital.gdshader")
const R_VIEW := 2.4                  # radio que ocupa el 95 % de la probabilidad, en el mundo
const SPDF := ["s", "p", "d", "f", "g", "h"]

var n := 2
var l := 1
var m := 0
var puntos := 60000
var animar := true
var t := 0.0
var pts := PackedFloat32Array()
var r_mean := 0.0                    # ⟨r⟩ de la muestra
var r95 := 1.0
var cloud: MultiMeshInstance3D
var mat: ShaderMaterial
var mean_sphere: MeshInstance3D
var _l_slider: HSlider
var _m_slider: HSlider
var _syncing := false

func title() -> String: return "Átomo de hidrógeno"
func formula() -> String: return "ψₙₗₘ = Rₙₗ(r)·Yₗᵐ(θ, φ)     Eₙ = −13,6057 eV / n²"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3.ZERO, "dist": 7.5, "yaw": -30.0, "pitch": -24.0}

func setup() -> void:
	puntos = [15000, 30000, 60000][calidad()]
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	register_clip(mat)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	cloud = MultiMeshInstance3D.new()
	cloud.multimesh = mm
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud)
	add_child(sphere(0.05, glow_mat(Color(1.0, 0.45, 0.35), 3.0)))      # protón
	mean_sphere = sphere(1.0, glass_mat(Color(0.6, 0.85, 1.0), 0.06))
	add_child(mean_sphere)
	add_child(axes(R_VIEW * 1.2))
	_rebuild()

## Vuelve a muestrear la nube (semilla del laboratorio: misma semilla, misma nube).
func _rebuild() -> void:
	r95 = Fisica.HydrogenRadius(n, l, 0.95)
	scale_xy = R_VIEW / r95
	scale_z = scale_xy
	pts = PackedFloat32Array(Fisica.HydrogenSample(n, l, m, puntos, rng.randi()))
	var acc := 0.0
	for i in puntos:
		acc += sqrt(pts[4 * i] ** 2 + pts[4 * i + 1] ** 2 + pts[4 * i + 2] ** 2)
	r_mean = acc / maxi(1, puntos)
	cloud.multimesh.instance_count = puntos
	cloud.multimesh.buffer = PackedFloat32Array(Fisica.OrbitalInstances(pts, scale_xy))
	mean_sphere.scale = Vector3.ONE * Fisica.HydrogenMeanR(n, l) * scale_xy
	_set_phase()

## −Eₙt/ħ con Eₙ = −1/(2n²) en unidades atómicas.
func _set_phase() -> void:
	mat.set_shader_parameter("phase_offset", t / (2.0 * n * n))

func step(dt: float) -> void:
	if animar:
		t += dt
		_set_phase()

func reset() -> void:
	t = 0.0
	_rebuild()

func build_ui(p: VBoxContainer) -> void:
	LabUI.slider(p, "n (nivel de energía)", 1, 6, 1, n, func(v):
		_set_quantum(int(v), l, m), "%d")
	_l_slider = LabUI.slider(p, "l (momento angular)", 0, n - 1, 1, l, func(v):
		_set_quantum(n, int(v), m), "%d")
	_m_slider = LabUI.slider(p, "m (proyección en z)", -l, l, 1, m, func(v):
		_set_quantum(n, l, int(v)), "%d")
	LabUI.slider(p, "Puntos de la nube", 5000, 200000, 5000, puntos, func(v):
		remember()
		puntos = int(v)
		_rebuild(), "%d")
	LabUI.check(p, "Girar la fase con el tiempo (e^{−iEₙt/ħ})", animar, func(v): animar = v)
	LabUI.note(p, "Cada punto es una posición posible del electrón, muestreada de |ψ|²; el color es la fase de ψ (la misma rueda que en Schrödinger). La esfera translúcida marca ⟨r⟩. Usa «Cortes» para ver por dentro las superficies nodales (n − l − 1 radiales y l angulares).")

## Cambio desde los deslizadores: se puede deshacer.
func _set_quantum(nn: int, ll: int, mm: int) -> void:
	if _syncing:
		return
	remember()
	_apply_quantum(nn, ll, mm)

## n, l, m dentro de lo permitido (0 ≤ l < n, |m| ≤ l), con los deslizadores al día.
func _apply_quantum(nn: int, ll: int, mm: int) -> void:
	n = nn
	l = clampi(ll, 0, n - 1)
	m = clampi(mm, -l, l)
	_syncing = true
	if _l_slider:
		_l_slider.max_value = n - 1
		_l_slider.value = l
	if _m_slider:
		_m_slider.min_value = -l
		_m_slider.max_value = l
		_m_slider.value = m
	_syncing = false
	_rebuild()

## Plano ecuatorial (z = 0).
func pick(origin: Vector3, dir: Vector3):
	var hit = ray_plane_y(origin, dir, 0.0)
	return hit if hit != null and (hit as Vector3).length() < R_VIEW * 1.6 else null

func hover_text(hit: Vector3) -> String:
	var q := to_math(hit)
	var psi: PackedFloat64Array = Fisica.HydrogenPsi(n, l, m, q.x, q.y, q.z)
	return "x = %.2f a₀   y = %.2f a₀ (plano z = 0)\nr = %.2f a₀\n|ψ|² = %s a₀⁻³\narg ψ = %.2f rad" % [
		q.x, q.y, q.length(), LabUI.sci(psi[0] * psi[0] + psi[1] * psi[1], 3), atan2(psi[1], psi[0])]

func critical_points() -> Array:
	return [{"pos": to_global(Vector3.ZERO), "nombre": "Núcleo (protón)", "dist": 3.0},
		{"pos": to_global(to_world(Fisica.HydrogenMeanR(n, l), 0.0, 0.0)), "nombre": "⟨r⟩ = %.2f a₀" % Fisica.HydrogenMeanR(n, l), "dist": 4.0}]

func info() -> String:
	var e: float = Fisica.HydrogenEnergyEv(n, false)
	var mr: float = Fisica.HydrogenMeanR(n, l)
	var sd := sqrt(Fisica.HydrogenMeanR2(n, l) - mr * mr)
	return "Orbital %d%s, m = %d · Eₙ = %.6f eV (con masa reducida %.6f eV)\n⟨r⟩ = %.3f a₀ (muestra: %.3f ± %.3f) · 95 %% dentro de r = %.2f a₀\nNodos: %d radiales, %d angulares · degeneración n² = %d · t = %.2f ħ/Eₕ" % [
		n, SPDF[l], m, e, Fisica.HydrogenEnergyEv(n, true), mr, r_mean, sd / sqrt(maxf(1.0, puntos)), r95, n - l - 1, l, n * n, t]

func metricas() -> Dictionary:
	return {"entidades": puntos}

func estado() -> Dictionary:
	return {"n": n, "l": l, "m": m, "puntos": puntos}

func cargar(d: Dictionary) -> String:
	for k in ["n", "l", "m", "puntos"]:
		if not typeof(d.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			return "falta «%s»" % k
	var nn := int(d["n"])
	var ll := int(d["l"])
	var mm := int(d["m"])
	if nn < 1 or nn > 6 or ll < 0 or ll >= nn or absi(mm) > ll:
		return "números cuánticos no válidos (n = %d, l = %d, m = %d): 1 ≤ n ≤ 6, 0 ≤ l < n, |m| ≤ l" % [nn, ll, mm]
	puntos = clampi(int(d["puntos"]), 1000, 200000)
	_apply_quantum(nn, ll, mm)
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Orbitales y energías", "nivel": "exacto",
			"modelo": "Ecuación de Schrödinger no relativista con núcleo puntual infinitamente pesado (la energía con masa reducida se da aparte); sin estructura fina, espín ni corrimiento de Lamb",
			"ecuaciones": "Eₙ = −Eₕ/(2n²); ψ = Rₙₗ(r)·Yₗᵐ(θ, φ); ⟨r⟩ = a₀(3n² − l(l+1))/2",
			"unidades": "atómicas: a₀ = 5,29177·10⁻¹¹ m, Eₕ = 27,211386 eV, ħ/Eₕ = 2,4189·10⁻¹⁷ s (CODATA 2022)",
			"referencias": "Griffiths, Introduction to Quantum Mechanics, §4.2; Bransden y Joachain, Physics of Atoms and Molecules, cap. 3"},
		{"subsistema": "Nube de puntos", "nivel": "exacto",
			"modelo": "Muestreo exacto de |ψ|²: r por la inversa de la acumulada de r²R², θ por la de sin θ·|Pₗᵐ|², φ uniforme; el error de ⟨r⟩ de la muestra es estadístico (∝ 1/√N)",
			"ecuaciones": "|ψₙₗₘ|² = Rₙₗ²(r)·|Θₗₘ(θ)|²/2π", "unidades": "a₀", "referencias": ""},
		{"subsistema": "Evolución temporal", "nivel": "exacto",
			"modelo": "Estado estacionario: la fase global gira con ω = Eₙ/ħ y la densidad no cambia",
			"ecuaciones": "ψ(t) = ψ·e^{−iEₙt/ħ}", "unidades": "t en ħ/Eₕ", "referencias": ""},
	]
