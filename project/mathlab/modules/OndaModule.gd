extends LabModule
## Ecuación de onda 2D — membrana vibrante resuelta por diferencias finitas (FDTD)
## en C# y deformada en la GPU. Pulsos con el ratón, fuentes continuas que
## interfieren, fronteras fija/libre/absorbente y modos normales del tambor.

const N := 224
const SIZE := 4.0

var sim
var mesh: MeshInstance3D
var mat: ShaderMaterial
var pulse_amp: float = 0.35
var pulse_radius: float = 0.035
var perturb_kind: int = 0            # 0 pulso, 1 fuente continua
var src_freq: float = 1.2
var mode_m: int = 2
var mode_n: int = 3
var _drag_accum: float = 0.0

func title() -> String: return "Ecuación de onda 2D"
func formula() -> String: return "∂²u/∂t² = c² ∇²u − γ ∂u/∂t"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic: pulso gaussiano · arrastre: estela · modo «fuente»: emisor senoidal"
func view() -> Dictionary: return {"target": Vector3(0, 0.0, 0), "dist": 7.2, "yaw": -30.0, "pitch": -34.0}

func setup() -> void:
	scale_xy = SIZE * 0.5
	sim = load("res://mathlab/solvers/FieldSim.cs").new()
	sim.Setup("onda", N, N, 2.0)
	sim.SetParam("c", 1.0)
	sim.SetParam("amortiguamiento", 0.03)
	mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.subdivide_width = N - 1
	pm.subdivide_depth = N - 1
	mesh.mesh = pm
	mat = ShaderMaterial.new()
	mat.shader = load("res://mathlab/shaders/field_surface.gdshader")
	mat.set_shader_parameter("field", sim.GetTexture())
	mat.set_shader_parameter("mode", 0)
	mat.set_shader_parameter("texel", Vector2(1.0 / N, 1.0 / N))
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("value_scale", 1.0)
	mat.set_shader_parameter("height_scale", 1.4)
	mat.set_shader_parameter("color_gain", 6.0)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	register_clip(mat)
	# Marco de la membrana.
	var frame_mat := glow_mat(Color(0.2, 0.7, 1.0), 1.5)
	var h := SIZE * 0.5
	for pair in [[Vector3(-h, 0, -h), Vector3(h, 0, -h)], [Vector3(h, 0, -h), Vector3(h, 0, h)], [Vector3(h, 0, h), Vector3(-h, 0, h)], [Vector3(-h, 0, h), Vector3(-h, 0, -h)]]:
		var r := rod(pair[0], pair[1], 0.012, frame_mat)
		r.name = "Marco"
		add_child(r)
	_initial()

func _initial() -> void:
	sim.Reset()
	sim.ClearSources()
	sim.Perturb(0.35, 0.4, 0.45, 0.04)
	sim.Perturb(0.68, 0.62, 0.3, 0.03)

func reset() -> void:
	_initial()

func step(dt: float) -> void:
	sim.Step(minf(dt, 0.05), 600)

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Membrana:", ["Cuadrada", "Circular (tambor)"], 0, func(i):
		sim.SetParam("forma", i)
		_set_frame_visible(i == 0)
		sim.Reset())
	LabUI.option(p, "Frontera:", ["Fija (Dirichlet)", "Libre (Neumann)", "Absorbente (Mur)"], 0, func(i): sim.SetParam("frontera", i))
	LabUI.slider(p, "Velocidad de onda c", 0.2, 2.5, 0.05, 1.0, func(v): sim.SetParam("c", v))
	LabUI.slider(p, "Amortiguamiento γ", 0.0, 1.0, 0.01, 0.03, func(v): sim.SetParam("amortiguamiento", v))
	LabUI.section(p, "Perturbador")
	LabUI.option(p, "Clic crea:", ["Pulso gaussiano", "Fuente continua"], 0, func(i): perturb_kind = i)
	LabUI.slider(p, "Amplitud", 0.05, 1.0, 0.01, pulse_amp, func(v): pulse_amp = v)
	LabUI.slider(p, "Radio del pulso", 0.01, 0.12, 0.005, pulse_radius, func(v): pulse_radius = v, "%.3f")
	LabUI.slider(p, "Frecuencia de la fuente (Hz)", 0.2, 4.0, 0.05, src_freq, func(v): src_freq = v)
	var r := LabUI.row(p)
	LabUI.button(r, "Interferencia (2 fuentes)", func():
		sim.Reset()
		sim.ClearSources()
		sim.SetParam("frontera", 2)
		sim.AddSource(0.38, 0.5, src_freq, 1.0)
		sim.AddSource(0.62, 0.5, src_freq, 1.0))
	LabUI.button(r, "Quitar fuentes", func(): sim.ClearSources())
	LabUI.section(p, "Modos normales")
	var r2 := LabUI.row(p)
	LabUI.spin(r2, "m", 0, 4, 1, mode_m, func(v): mode_m = int(v))
	LabUI.spin(r2, "n", 1, 4, 1, mode_n, func(v): mode_n = int(v))
	LabUI.button(p, "Excitar el modo (m, n)", func():
		sim.ClearSources()
		sim.SetParam("amortiguamiento", 0.0)
		sim.NormalMode(mode_m, mode_n, 0.3))
	LabUI.note(p, "Cuadrada: u = sin(mπx) sin(nπy). Circular: u = Jₘ(αₘₙ r) cos(mθ), con αₘₙ el n-ésimo cero de la función de Bessel Jₘ. Sin amortiguamiento el modo permanece como onda estacionaria (las líneas nodales no se mueven).")

func _set_frame_visible(v: bool) -> void:
	for c in get_children():
		if c.name.begins_with("Marco"):
			c.visible = v

func _height(x: float, z: float) -> float:
	var s: Vector4 = sim.Sample(x / SIZE + 0.5, z / SIZE + 0.5)
	return s.x if s.w > 0.5 else 0.0

func pick(origin: Vector3, dir: Vector3):
	return ray_heightfield(origin, dir, _height, SIZE * 0.5)

func hover_text(hit: Vector3) -> String:
	var s: Vector4 = sim.Sample(hit.x / SIZE + 0.5, hit.z / SIZE + 0.5)
	var m := to_math(hit)
	return "x = %.3f   y = %.3f\nu = %+.4f\n∂u/∂t·Δt = %+.5f" % [m.x, m.y, s.x, s.y]

func perturb(hit: Vector3, first: bool) -> void:
	var u := hit.x / SIZE + 0.5
	var v := hit.z / SIZE + 0.5
	if perturb_kind == 1:
		if first:
			sim.AddSource(u, v, src_freq, pulse_amp * 2.0)
		return
	if first:
		sim.Perturb(u, v, pulse_amp, pulse_radius)
	else:
		sim.Perturb(u, v, pulse_amp * 0.25, pulse_radius)

func critical_points() -> Array:
	var out := []
	var best := -INF
	var worst := INF
	var pmax := Vector3.ZERO
	var pmin := Vector3.ZERO
	for j in range(0, 48):
		for i in range(0, 48):
			var u := (i + 0.5) / 48.0
			var v := (j + 0.5) / 48.0
			var s: Vector4 = sim.Sample(u, v)
			if s.w < 0.5:
				continue
			if s.x > best:
				best = s.x
				pmax = Vector3((u - 0.5) * SIZE, s.x, (v - 0.5) * SIZE)
			if s.x < worst:
				worst = s.x
				pmin = Vector3((u - 0.5) * SIZE, s.x, (v - 0.5) * SIZE)
	out.append({"pos": pmax, "nombre": "Cresta máxima (u = %.3f)" % best, "dist": 2.2})
	out.append({"pos": pmin, "nombre": "Valle más profundo (u = %.3f)" % worst, "dist": 2.2})
	return out

func info() -> String:
	var cour: float = 0.5
	return "t = %.2f s · energía = %.4f\nmáx u = %+.3f · mín u = %+.3f · fuentes: %d\nCourant cΔt/h = %.2f (estable ≤ 0.707)" % [
		float(sim.Time), float(sim.Energy()), float(sim.MaxValue()), float(sim.MinValue()), int(sim.SourceCount()), cour]
