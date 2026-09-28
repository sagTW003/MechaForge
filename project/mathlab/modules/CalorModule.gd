extends LabModule
## Ecuación de calor 2D — conducción en una placa de 20 × 20 cm con materiales
## reales (difusividad α), fuentes de calor, disipación al ambiente (Newton) y
## bordes a temperatura fija o aislados. Mapa de calor con isotermas.

const N := 160
const SIZE := 4.0
const MATERIALS := [
	["Madera", 8.2e-8], ["Vidrio", 3.4e-7], ["Acero", 1.2e-5], ["Aluminio", 9.7e-5], ["Cobre", 1.11e-4],
]

var sim
var mesh: MeshInstance3D
var mat: ShaderMaterial
var action: int = 0          # 0 inyectar calor, 1 enfriar, 2 fuente permanente, 3 pintar material
var paint_mat: int = 4
var inject: float = 80.0
var source_rate: float = 25.0
var brush: float = 0.05
var accel: float = 30.0
var relief: bool = true

func title() -> String: return "Ecuación de calor"
func formula() -> String: return "∂T/∂t = ∇·(α ∇T) − κ (T − T∞) + q"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic/arrastre: inyecta calor, enfría, coloca una fuente o pinta un material (ver Perturbador)"
func view() -> Dictionary: return {"target": Vector3(0, 0.2, 0), "dist": 7.0, "yaw": -25.0, "pitch": -48.0}

func setup() -> void:
	scale_xy = SIZE * 0.5
	sim = load("res://mathlab/solvers/FieldSim.cs").new()
	sim.Setup("calor", N, N, 0.2)
	sim.SetParam("ambiente", 20.0)
	mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.subdivide_width = N - 1
	pm.subdivide_depth = N - 1
	mesh.mesh = pm
	mat = ShaderMaterial.new()
	mat.shader = load("res://mathlab/shaders/field_surface.gdshader")
	mat.set_shader_parameter("field", sim.GetTexture())
	mat.set_shader_parameter("mode", 1)
	mat.set_shader_parameter("texel", Vector2(1.0 / N, 1.0 / N))
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("value_offset", 20.0)
	mat.set_shader_parameter("iso_step", 10.0)
	mat.set_shader_parameter("material_tint", PackedVector3Array([Vector3(0.8, 0.55, 0.35), Vector3(0.7, 0.95, 1.0), Vector3(0.75, 0.78, 0.82), Vector3(0.95, 0.96, 1.0), Vector3(1.0, 0.6, 0.4)]))
	mesh.material_override = mat
	add_child(mesh)
	register_clip(mat)
	_initial()

func _initial() -> void:
	sim.FillMaterial(MATERIALS[3][1])
	sim.Reset()
	sim.FillMaterial(MATERIALS[3][1])
	sim.RectMaterial(0.08, 0.45, 0.92, 0.55, MATERIALS[4][1])     # franja de cobre
	sim.PaintMaterial(0.7, 0.25, 0.1, MATERIALS[1][1])           # inclusión de vidrio
	sim.PaintMaterial(0.3, 0.75, 0.08, MATERIALS[2][1])          # isla de acero
	sim.ClearHeatSources()
	sim.SetHeatSource(0.12, 0.5, 0.05, source_rate)
	_update_height()

func reset() -> void:
	_initial()

func step(dt: float) -> void:
	sim.Step(minf(dt, 0.05) * accel, 300)
	var mx: float = sim.MaxValue()
	mat.set_shader_parameter("color_min", 20.0)
	mat.set_shader_parameter("color_max", maxf(40.0, mx))

func _update_height() -> void:
	mat.set_shader_parameter("value_scale", 0.012 if relief else 0.0)

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for m in MATERIALS:
		names.append("%s (α = %s m²/s)" % [m[0], LabUI.sci(m[1], 1)])
	LabUI.option(p, "Placa de:", names, 3, func(i): sim.FillMaterial(MATERIALS[i][1]))
	LabUI.slider(p, "Aceleración temporal ×", 1.0, 200.0, 1.0, accel, func(v): accel = v, "%.0f")
	LabUI.slider(p, "Disipación al aire κ (1/s)", 0.0, 0.05, 0.001, 0.0, func(v): sim.SetParam("enfriamiento", v), "%.3f")
	LabUI.option(p, "Bordes:", ["Aislados (∂T/∂n = 0)", "A temperatura ambiente"], 1, func(i): sim.SetParam("borde_calor", i))
	LabUI.check(p, "Relieve: altura ∝ temperatura", relief, func(v):
		relief = v
		_update_height())
	LabUI.slider(p, "Isotermas cada (°C)", 0.0, 40.0, 1.0, 10.0, func(v): mat.set_shader_parameter("iso_step", v), "%.0f")
	LabUI.section(p, "Perturbador")
	LabUI.option(p, "Clic:", ["Inyectar calor", "Enfriar", "Fuente permanente", "Pintar material"], 0, func(i): action = i)
	LabUI.slider(p, "Calor por clic (°C)", 10.0, 300.0, 5.0, inject, func(v): inject = v, "%.0f")
	LabUI.slider(p, "Potencia de la fuente (°C/s)", 1.0, 200.0, 1.0, source_rate, func(v): source_rate = v, "%.0f")
	var mnames := []
	for m in MATERIALS:
		mnames.append(m[0])
	LabUI.option(p, "Material a pintar:", mnames, paint_mat, func(i): paint_mat = i)
	LabUI.slider(p, "Tamaño del pincel", 0.01, 0.2, 0.005, brush, func(v): brush = v, "%.3f")
	LabUI.button(p, "Quitar fuentes", func(): sim.ClearHeatSources())
	LabUI.note(p, "El cobre conduce ~1350 veces más rápido que la madera: pinta franjas y mira cómo se deforman las isotermas en las fronteras entre materiales.")

func _uv(hit: Vector3) -> Vector2:
	return Vector2(hit.x / SIZE + 0.5, hit.z / SIZE + 0.5)

func _height(x: float, z: float) -> float:
	var s: Vector4 = sim.Sample(x / SIZE + 0.5, z / SIZE + 0.5)
	return (s.x - 20.0) * (0.012 if relief else 0.0)

func pick(origin: Vector3, dir: Vector3):
	return ray_heightfield(origin, dir, _height, SIZE * 0.5)

func hover_text(hit: Vector3) -> String:
	var uv := _uv(hit)
	var a: float = sim.AlphaAt(uv.x, uv.y)
	var name := "?"
	for m in MATERIALS:
		if absf(float(m[1]) - a) / float(m[1]) < 0.01:
			name = m[0]
	return "x = %.1f cm   y = %.1f cm\nT = %.1f °C\n%s (α = %.1e)" % [(uv.x - 0.5) * 20.0, (0.5 - uv.y) * 20.0, float(sim.ValueAt(uv.x, uv.y)), name, a]

func perturb(hit: Vector3, first: bool) -> void:
	var uv := _uv(hit)
	match action:
		0: sim.Perturb(uv.x, uv.y, inject * (1.0 if first else 0.15), brush * 0.6)
		1: sim.Perturb(uv.x, uv.y, -inject * (0.5 if first else 0.1), brush * 0.6)
		2:
			if first: sim.SetHeatSource(uv.x, uv.y, brush, source_rate)
		3: sim.PaintMaterial(uv.x, uv.y, brush, MATERIALS[paint_mat][1])

func critical_points() -> Array:
	var best := -INF
	var pbest := Vector3.ZERO
	for j in range(40):
		for i in range(40):
			var u := (i + 0.5) / 40.0
			var v := (j + 0.5) / 40.0
			var t: float = sim.ValueAt(u, v)
			if t > best:
				best = t
				pbest = Vector3((u - 0.5) * SIZE, _height((u - 0.5) * SIZE, (v - 0.5) * SIZE), (v - 0.5) * SIZE)
	return [{"pos": pbest, "nombre": "Punto más caliente (%.1f °C)" % best, "dist": 2.5}]

func info() -> String:
	return "t = %.1f s (simulados) · T máx = %.1f °C · T mín = %.1f °C\nEstabilidad explícita: Δt ≤ h²/(4 α_máx) → sub-pasos automáticos" % [float(sim.Time), float(sim.MaxValue()), float(sim.MinValue())]
