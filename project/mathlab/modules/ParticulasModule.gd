extends LabModule
## Partículas cargadas y fuerza de Coulomb (Física moderna, Fase 3; la Fase 4 lo
## amplía con el Modelo Estándar). Cargas clásicas en unidades atómicas
## (e = mₑ = a₀ = ħ = 1; tiempo en ħ/Eₕ = 2,4189·10⁻¹⁷ s) integradas con Verlet de
## velocidades a paso fijo. Con GPU, el paso entero corre en ella sobre buffers fijos
## (kernels/verlet.glsl y coulomb.glsl) y la CPU solo lee las posiciones para dibujarlas;
## sin GPU, la referencia en C# (Fisica).

const PRESETS := ["plasma", "atomo"]
const PRESET_NAMES := ["Plasma neutro (electrones y protones)", "Átomo clásico (órbita de Kepler)"]
const R_VIEW := 2.6
const N_MAX_GPU := 20000
const N_MAX_CPU := 3000               # sin GPU, O(N²) en C#: más se vuelve lento
const K_VERLET := "res://mathlab/fisica/kernels/verlet.glsl"
const K_COULOMB := "res://mathlab/fisica/kernels/coulomb.glsl"
const B_AU_T := 2.3505175707e5        # tesla por unidad atómica de campo magnético
const LINEAS_MAX := 200

var preset := 0
var n_cargas := 2000
var eps := 0.1                        # suavizado (a₀)
## Paso fijo (ħ/Eₕ). Un par que cae hasta r ~ ε pasa a v ~ √(2/ε): con ε = 0,1 cruza ε en
## ~0,02 ħ/Eₕ, unos 11 pasos (con ε = 0,05 y Δt = 0,005, uno solo, y la energía derivaba un 1 %).
var dt := 0.002
var caja := 4.0                       # semilado del cubo con paredes (a₀); 0 = sin paredes
## Campo magnético uniforme según z, en unidades atómicas (ħ/ea₀² = 2,35051757·10⁵ T, CODATA 2022).
var bz := 0.0
var lineas := false                   # líneas del campo E (hasta LINEAS_MAX cargas)
var p := PackedFloat32Array()         # x, y, z, q
var v := PackedFloat32Array()         # vx, vy, vz, 1/m
var f := PackedFloat32Array()         # Fx, Fy, Fz, U_i (energía potencial de cada carga)
var t := 0.0
var e0 := 0.0
var energia := PackedFloat64Array()   # cinética, potencial, px, py, pz
var mp := 1836.152673426
var gpu: GpuCompute
var mm: MultiMeshInstance3D
var box_node: Node3D
var lines_mesh: MeshInstance3D
var _lines_t := 0.0
var _dirty := true
var _sel := -1
var _bp: RID                          # buffers fijos de la GPU: posiciones, velocidades, fuerzas
var _bv: RID
var _bf: RID
var _stale := false                   # la GPU va por delante de p…
var _stale_vf := false                # …y de v y f (se leen solo cuando hacen falta)

func title() -> String: return "Partículas y fuerza de Coulomb"
func formula() -> String: return "Fᵢ = Σⱼ qᵢqⱼ (rᵢ − rⱼ) / (|rᵢ − rⱼ|² + ε²)^{3/2}"
func uses_time() -> bool: return true
func fixed_dt() -> float: return dt
func view() -> Dictionary: return {"target": Vector3.ZERO, "dist": 8.0, "yaw": -30.0, "pitch": -25.0}

func setup() -> void:
	mp = Fisica.Constantes()["mp_me"]
	gpu = GpuCompute.create()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	sm.material = vcolor_mat(1.0, 0.35)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = sm
	mm = MultiMeshInstance3D.new()
	mm.multimesh = multi
	add_child(mm)
	_build()

func n_max() -> int:
	return N_MAX_GPU if gpu else N_MAX_CPU

func _eps2() -> float:
	return 0.0 if preset == 1 else eps * eps          # la órbita de Kepler, sin suavizar

func _box() -> float:
	return caja if preset == 0 else 0.0

## Condiciones iniciales del preset (con la semilla del laboratorio).
func _build() -> void:
	t = 0.0
	_sel = -1
	if preset == 0:
		_plasma()
	else:
		_atomo()
	scale_xy = R_VIEW / (maxf(caja, 1.5) if preset == 0 else 1.4)
	scale_z = scale_xy
	_rebase()
	_dirty = true
	_refresh_box()

## Electrones y protones al azar en el cubo, con la misma energía térmica media y sin
## momento total (el centro de masas queda quieto).
func _plasma() -> void:
	var nn := clampi(n_cargas - n_cargas % 2, 2, n_max())
	var half := (caja if caja > 0.0 else 4.0) * 0.8
	p.resize(nn * 4)
	v.resize(nn * 4)
	var pm := Vector3.ZERO
	var mt := 0.0
	for i in nn:
		var proton := i % 2 == 1
		var m := mp if proton else 1.0
		var sigma := 0.3 / sqrt(m)
		for k in 3:
			p[4 * i + k] = rng.randf_range(-half, half)
			v[4 * i + k] = rng.randfn(0.0, sigma)
		p[4 * i + 3] = 1.0 if proton else -1.0
		v[4 * i + 3] = 1.0 / m
		pm += m * Vector3(v[4 * i], v[4 * i + 1], v[4 * i + 2])
		mt += m
	for i in nn:
		v[4 * i] -= pm.x / mt
		v[4 * i + 1] -= pm.y / mt
		v[4 * i + 2] -= pm.z / mt

## Protón y electrón en órbita circular de radio a₀ alrededor del centro de masas:
## μv²/r = 1/r² con μ = mₚ/(mₚ + 1).
func _atomo() -> void:
	var vr := sqrt((mp + 1.0) / mp)
	p = PackedFloat32Array([-1.0 / (mp + 1.0), 0, 0, 1.0, mp / (mp + 1.0), 0, 0, -1.0])
	v = PackedFloat32Array([0, -vr / (mp + 1.0), 0, 1.0 / mp, 0, vr * mp / (mp + 1.0), 0, 1.0])

func _forces(pp: PackedFloat32Array) -> PackedFloat32Array:
	if gpu:
		return gpu.coulomb(pp, _eps2())
	return PackedFloat32Array(Fisica.CoulombForces(pp, _eps2()))

## Sin campo B, Verlet de velocidades: medio impulso, deriva, fuerzas nuevas, medio impulso.
## Con campo B, Boris (1970): medio impulso eléctrico, rotación magnética, medio impulso con
## las mismas fuerzas, deriva y fuerzas nuevas (las velocidades quedan a medio paso).
func step(h: float) -> void:
	if gpu:
		var n := p.size() / 4
		var g := ceili(n / 64.0)
		var kv: Dictionary = gpu.kernel(K_VERLET)
		var bufs := [_bp, _bv, _bf]
		var fuerzas := [gpu.kernel(K_COULOMB), [_bp, _bf], _push_coulomb(n), g]
		var pasos: Array
		if bz == 0.0:
			pasos = [[kv, bufs, _push_verlet(n, 0, h * 0.5, 0.0), g], [kv, bufs, _push_verlet(n, 1, h, _box()), g],
				fuerzas, [kv, bufs, _push_verlet(n, 0, h * 0.5, 0.0), g]]
		else:
			pasos = [[kv, bufs, _push_verlet(n, 0, h * 0.5, 0.0), g], [kv, bufs, _push_verlet(n, 2, h, bz), g],
				[kv, bufs, _push_verlet(n, 0, h * 0.5, 0.0), g], [kv, bufs, _push_verlet(n, 1, h, _box()), g], fuerzas]
		# Se graba sin esperar: los pasos de un fotograma se envían juntos al leer (sync).
		gpu.run_many(pasos, false)
		_stale = true
		t += h
		_dirty = true
		return
	v = PackedFloat32Array(Fisica.CoulombKick(v, f, h * 0.5))
	if bz != 0.0:
		v = PackedFloat32Array(Fisica.CoulombRotate(p, v, bz, h))
		v = PackedFloat32Array(Fisica.CoulombKick(v, f, h * 0.5))
	var pv := PackedFloat32Array(Fisica.CoulombDrift(p, v, h, _box()))
	var k := p.size()
	p = pv.slice(0, k)
	v = pv.slice(k)
	f = _forces(p)
	if bz == 0.0:
		v = PackedFloat32Array(Fisica.CoulombKick(v, f, h * 0.5))
	t += h
	_dirty = true

## Datos del kernel de Verlet: modo 0 impulso, 1 deriva (extra = caja), 2 rotación (extra = B).
func _push_verlet(n: int, modo: int, h: float, extra: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(16)
	b.encode_u32(0, n)
	b.encode_u32(4, modo)
	b.encode_float(8, h)
	b.encode_float(12, extra)
	return b

func _push_coulomb(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_u32(0, n)
	b.encode_float(4, _eps2())
	return b

## Trae de la GPU las posiciones (cada fotograma, para dibujar) y, con todo = true, también
## las velocidades y las fuerzas (información, tooltip y pruebas).
func sync(todo: bool = false) -> void:
	if gpu == null:
		return
	if _stale:
		p = gpu.read(_bp).to_float32_array()
		_stale = false
		_stale_vf = true
	if todo and _stale_vf:
		v = gpu.read(_bv).to_float32_array()
		f = gpu.read(_bf).to_float32_array()
		_stale_vf = false

func reset() -> void:
	_build()

func _process(delta: float) -> void:
	_lines_t += delta
	if lineas and _lines_t >= 0.25:
		_lines_t = 0.0
		_refresh_lines()
	if not _dirty or mm == null:
		return
	sync()
	if mm.multimesh.instance_count != p.size() / 4:
		mm.multimesh.instance_count = p.size() / 4
	mm.multimesh.buffer = PackedFloat32Array(Fisica.ParticleInstances(p, v, scale_xy))
	_dirty = false

## Líneas del campo E (de las positivas a las negativas, RK4 en C#) y, con campo B, sus
## líneas: rectas verticales, porque es uniforme.
func _refresh_lines() -> void:
	if lines_mesh == null:
		lines_mesh = MeshInstance3D.new()
		lines_mesh.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lines_mesh.material_override = m
		add_child(lines_mesh)
	var im: ImmediateMesh = lines_mesh.mesh
	im.clear_surfaces()
	if not lineas:
		return
	var ext := (caja if _box() > 0.0 else 4.0) * 1.2
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	if p.size() / 4 <= LINEAS_MAX:
		sync()
		var pts := PackedFloat32Array(Fisica.FieldLines(p, maxf(_eps2(), 1e-4), 10, 300, 0.03, ext))
		for i in range(0, pts.size() - 3, 3):
			if is_nan(pts[i]) or is_nan(pts[i + 3]):
				continue
			im.surface_set_color(Color(1.0, 0.85, 0.3, 0.55))
			im.surface_add_vertex(to_world(pts[i], pts[i + 1], pts[i + 2]))
			im.surface_set_color(Color(1.0, 0.85, 0.3, 0.55))
			im.surface_add_vertex(to_world(pts[i + 3], pts[i + 4], pts[i + 5]))
	if bz != 0.0:
		for gx in 5:
			for gy in 5:
				var x := (gx - 2) * ext * 0.4
				var y := (gy - 2) * ext * 0.4
				im.surface_set_color(Color(0.4, 0.8, 1.0, 0.35))
				im.surface_add_vertex(to_world(x, y, -ext))
				im.surface_set_color(Color(0.4, 0.8, 1.0, 0.35))
				im.surface_add_vertex(to_world(x, y, ext))
	im.surface_add_vertex(Vector3.ZERO)       # una superficie no puede quedar vacía
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()

## Aristas del cubo con paredes.
func _refresh_box() -> void:
	if box_node:
		box_node.queue_free()
		box_node = null
	if _box() <= 0.0:
		return
	box_node = Node3D.new()
	var b := _box() * scale_xy
	var m := glass_mat(Color(0.5, 0.8, 1.0), 0.35)
	for a in 3:
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var u := Vector3.ZERO
				u[(a + 1) % 3] = s1 * b
				u[(a + 2) % 3] = s2 * b
				var e1 := u
				var e2 := u
				e1[a] = -b
				e2[a] = b
				box_node.add_child(rod(e1, e2, 0.006, m))
	add_child(box_node)

func build_ui(pnl: VBoxContainer) -> void:
	LabUI.option(pnl, "Preset:", PRESET_NAMES, preset, _on_preset)
	LabUI.slider(pnl, "Cargas N (plasma)", 2, n_max(), 2, mini(n_cargas, n_max()), _on_n, "%d")
	LabUI.slider(pnl, "Suavizado ε (a₀)", 0.0, 0.3, 0.005, eps, _on_eps, "%.3f")
	LabUI.slider(pnl, "Paso Δt (ħ/Eₕ)", 0.0005, 0.02, 0.0005, dt, _on_dt, "%.4f")
	LabUI.slider(pnl, "Caja con paredes (semilado, a₀; 0 = sin)", 0.0, 8.0, 0.5, caja, _on_caja, "%.1f")
	LabUI.slider(pnl, "Campo B según z (u.a.; 1 u.a. = 2,35·10⁵ T)", -3.0, 3.0, 0.05, bz, _on_bz, "%.2f")
	LabUI.check(pnl, "Líneas de campo (E hasta %d cargas; B)" % LINEAS_MAX, lineas, _on_lineas)
	LabUI.note(pnl, "Cargas clásicas: los electrones (azules, pequeños) y los protones (rojos, grandes) se atraen y se repelen con la ley de Coulomb. Sin mecánica cuántica no hay átomos estables: un par electrón–protón se acerca hasta r ~ ε. En «Átomo clásico», la órbita de radio a₀ tiene la misma energía que el estado 1s (−13,6 eV), pero un electrón clásico real radiaría y caería al núcleo en unos 10⁻¹¹ s.")

func _on_preset(i: int) -> void:
	remember()
	preset = i
	_build()

func _on_n(val: float) -> void:
	remember()
	n_cargas = int(val)
	if preset == 0:
		_build()

func _on_eps(val: float) -> void:
	remember()
	eps = val
	_rebase()

func _on_dt(val: float) -> void:
	remember()
	dt = val

func _on_bz(val: float) -> void:
	remember()
	bz = val
	if lineas:
		_refresh_lines()

func _on_lineas(on: bool) -> void:
	lineas = on
	_refresh_lines()

func _on_caja(val: float) -> void:
	remember()
	caja = val
	_refresh_box()

## Fuerzas con p y v actuales, buffers de la GPU nuevos y nueva referencia de energía
## (al empezar y al cambiar ε, que cambia la energía potencial).
func _rebase() -> void:
	sync(true)
	f = _forces(p)
	if gpu:
		if _bp.is_valid():
			gpu.free_buffers([_bp, _bv, _bf])
		_bp = gpu.buffer(p.to_byte_array())
		_bv = gpu.buffer(v.to_byte_array())
		_bf = gpu.buffer(f.to_byte_array())
	energia = PackedFloat64Array(Fisica.CoulombEnergyFromForces(v, f))
	e0 = energia[0] + energia[1]

func device() -> String:
	return "GPU (%s)" % gpu.device_name() if gpu else "CPU (C#)"

func info() -> String:
	sync(true)
	energia = PackedFloat64Array(Fisica.CoulombEnergyFromForces(v, f))
	var e := energia[0] + energia[1]
	var pt := Vector3(energia[2], energia[3], energia[4]).length()
	var s := "N = %d · fuerzas en %s · t = %.2f ħ/Eₕ = %s s\nE = %.6f Eₕ (cinética %.5f, potencial %.5f) · deriva |ΔE/E₀| = %s\nMomento total = %s mₑa₀Eₕ/ħ%s" % [
		p.size() / 4, device(), t, LabUI.sci(t * Fisica.Constantes()["tiempo_atomico_s"], 3), e, energia[0], energia[1],
		LabUI.sci(absf(e - e0) / maxf(absf(e0), 1e-12), 2), LabUI.sci(pt, 2), " (las paredes no lo conservan)" if _box() > 0.0 else ""]
	if bz != 0.0:
		s += "\nCampo B = %.2f u.a. = %s T según z (con Boris, las velocidades van a medio paso)" % [bz, LabUI.sci(bz * B_AU_T, 3)]
	if preset == 1:
		var r := Vector3(p[4] - p[0], p[5] - p[1], p[6] - p[2]).length()
		s += "\nr(e–p) = %.5f a₀ · E = %.4f eV (el estado 1s: −13,6057 eV)" % [r, e * Fisica.Constantes()["hartree_eV"]]
	return s

func metricas() -> Dictionary:
	return {"entidades": p.size() / 4, "fuerzas": device()}

## Solo las posiciones (las que se leen cada fotograma): un NaN en las velocidades llega a
## ellas en el paso siguiente.
func finito() -> bool:
	sync()
	return Fisica.AllFinite(p)

func liberar() -> void:
	if gpu:
		gpu.liberar()
		gpu = null

func pick(origin: Vector3, dir: Vector3):
	sync(true)
	_sel = Fisica.NearestToRay(p, scale_xy, origin, dir, 0.12)
	if _sel < 0:
		return null
	return to_world(p[4 * _sel], p[4 * _sel + 1], p[4 * _sel + 2])

func hover_text(_hit: Vector3) -> String:
	if _sel < 0 or _sel >= p.size() / 4:
		return ""
	var i := _sel
	var sp := Vector3(v[4 * i], v[4 * i + 1], v[4 * i + 2]).length()
	return "%s n.º %d\nr = (%.2f, %.2f, %.2f) a₀\n|v| = %.3f a₀Eₕ/ħ (≈ %s m/s)" % [
		"Protón" if p[4 * i + 3] > 0 else "Electrón", i, p[4 * i], p[4 * i + 1], p[4 * i + 2], sp,
		LabUI.sci(sp * Fisica.Constantes()["alpha"] * Fisica.Constantes()["c_m_s"], 2)]

func critical_points() -> Array:
	var pts := [{"pos": Vector3.ZERO, "nombre": "Centro", "dist": 6.0}]
	if preset == 1:
		pts.append({"pos": to_world(p[4], p[5], p[6]), "nombre": "Electrón", "dist": 2.0})
	return pts

func estado() -> Dictionary:
	return {"preset": preset, "n": n_cargas, "eps": eps, "dt": dt, "caja": caja, "B": bz, "lineas": lineas}

func cargar(d: Dictionary) -> String:
	for k in ["preset", "n", "eps", "dt", "caja"]:
		if not typeof(d.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			return "falta «%s»" % k
	if int(d["preset"]) < 0 or int(d["preset"]) >= PRESETS.size():
		return "preset desconocido (%d)" % int(d["preset"])
	if float(d["dt"]) <= 0.0 or float(d["eps"]) < 0.0 or float(d["caja"]) < 0.0 or int(d["n"]) < 2:
		return "valores fuera de rango (Δt > 0, ε ≥ 0, caja ≥ 0, N ≥ 2)"
	preset = int(d["preset"])
	n_cargas = int(d["n"])
	eps = float(d["eps"])
	dt = float(d["dt"])
	caja = float(d["caja"])
	bz = float(d.get("B", 0.0))
	lineas = bool(d.get("lineas", false))
	_build()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Campo magnético (fuerza de Lorentz)", "nivel": "exacto",
			"modelo": "Campo B externo uniforme según z integrado con el esquema de Boris: conserva |v| exactamente y gira 2·atan(qBΔt/2m) por paso (giro de ciclotrón con error O(Δt²)). No incluye el campo magnético que crean las propias cargas en movimiento",
			"ecuaciones": "F = q v × B;  ω_c = qB/m;  r_c = mv⊥/(qB)",
			"unidades": "B en ħ/(e·a₀²) = 2,35051757·10⁵ T (CODATA 2022)", "referencias": "Boris, Proc. 4th Conf. Numerical Simulation of Plasmas (1970); Birdsall y Langdon, Plasma Physics via Computer Simulation, §4.4"},
		{"subsistema": "Líneas de campo E", "nivel": "exacto",
			"modelo": "Curvas tangentes a E (suma de los campos de Coulomb, con el mismo suavizado ε) integradas con Runge-Kutta 4 desde cada carga positiva",
			"ecuaciones": "dr/ds = E/|E|", "unidades": "a₀", "referencias": ""},
		{"subsistema": "Fuerza entre cargas", "nivel": "aproximado",
			"modelo": "Coulomb clásico con suavizado ε (Plummer): sin radiación, sin campo magnético y sin mecánica cuántica; un par electrón–protón no forma un átomo estable, se acerca hasta r ~ ε",
			"ecuaciones": "Fᵢ = Σⱼ≠ᵢ qᵢqⱼ(rᵢ − rⱼ)/(r² + ε²)^{3/2}; U = Σᵢ<ⱼ qᵢqⱼ/√(r² + ε²)",
			"unidades": "atómicas: e = mₑ = a₀ = 1, tiempo ħ/Eₕ = 2,4189·10⁻¹⁷ s, mₚ = 1836,152673 mₑ (CODATA 2022)",
			"referencias": "Jackson, Classical Electrodynamics, cap. 1; Hockney y Eastwood, Computer Simulation Using Particles"},
		{"subsistema": "Integración temporal", "nivel": "exacto",
			"modelo": "Verlet de velocidades a paso fijo (simpléctico): el error de la energía queda acotado, O(Δt²); la deriva medida sale en la información. Las paredes son choques elásticos (conservan la energía, no el momento)",
			"ecuaciones": "v ← v + (Δt/2)F/m;  r ← r + Δt·v;  v ← v + (Δt/2)F/m",
			"unidades": "Δt en ħ/Eₕ", "referencias": "Swope et al., J. Chem. Phys. 76, 637 (1982)"},
		{"subsistema": "Átomo clásico", "nivel": "ilustrativo",
			"modelo": "Órbita de Kepler de un electrón clásico: con r = a₀ su energía es −Eₕ/2, como el estado 1s, pero un electrón acelerado radiaría y caería al núcleo en t = a₀³/(4r_e²c) ≈ 1,6·10⁻¹¹ s (la radiación no se modela). Para el átomo real, el módulo «Átomo de hidrógeno»",
			"ecuaciones": "μv²/r = 1/r²,  μ = mₚmₑ/(mₚ + mₑ);  E = −1/(2r)", "unidades": "a₀, Eₕ", "referencias": "Griffiths, Introduction to Electrodynamics, cap. 11 (fórmula de Larmor)"},
	]
