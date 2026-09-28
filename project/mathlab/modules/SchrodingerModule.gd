extends LabModule
## Ecuación de Schrödinger dependiente del tiempo 2D (ħ = m = 1): un paquete de
## ondas gaussiano evoluciona frente a barreras, rendijas, pozos u osciladores.
## Altura = densidad de probabilidad |ψ|²; color = fase arg ψ; las barreras se
## dibujan como paredes de vidrio. Efecto túnel medido en vivo.

const N := 192
const SIZE := 4.0
const L := 20.0
const PRESETS := ["libre", "barrera", "doble_rendija", "pozo", "armonico"]
const PRESET_NAMES := ["Partícula libre", "Barrera (efecto túnel)", "Doble rendija", "Pozo finito", "Oscilador armónico"]

var sim
var mesh: MeshInstance3D
var walls: MeshInstance3D
var mat: ShaderMaterial
var wall_mat: ShaderMaterial
var preset: int = 1
var v0: float = 5.0
var width: float = 0.6
var k0: float = 3.0
var sigma: float = 1.0
var x0: float = -5.0
var action: int = 0            # 0 pintar barrera, 1 lanzar paquete aquí, 2 borrar potencial
var paint_v: float = 6.0

func title() -> String: return "Ecuación de Schrödinger"
func formula() -> String: return "iħ ∂ψ/∂t = −(ħ²/2m) ∇²ψ + V ψ"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic/arrastre: pinta barreras de potencial o lanza un paquete desde ese punto"
func view() -> Dictionary: return {"target": Vector3(0, 0.1, 0), "dist": 7.0, "yaw": -20.0, "pitch": -40.0}

func setup() -> void:
	scale_xy = SIZE * 0.5
	sim = load("res://mathlab/solvers/FieldSim.cs").new()
	sim.Setup("schrodinger", N, N, L)
	sim.SetParam("vmax", 10.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.subdivide_width = N - 1
	pm.subdivide_depth = N - 1
	mesh = MeshInstance3D.new()
	mesh.mesh = pm
	mat = ShaderMaterial.new()
	mat.shader = load("res://mathlab/shaders/field_surface.gdshader")
	mat.set_shader_parameter("field", sim.GetTexture())
	mat.set_shader_parameter("mode", 2)
	mat.set_shader_parameter("texel", Vector2(1.0 / N, 1.0 / N))
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("value_scale", 9.0)
	mat.set_shader_parameter("show_grid", false)
	mesh.material_override = mat
	add_child(mesh)
	walls = MeshInstance3D.new()
	walls.mesh = pm
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://mathlab/shaders/field_glass.gdshader")
	wall_mat.set_shader_parameter("field", sim.GetTexture())
	wall_mat.set_shader_parameter("mode", 3)
	wall_mat.set_shader_parameter("texel", Vector2(1.0 / N, 1.0 / N))
	wall_mat.set_shader_parameter("world_size", SIZE)
	wall_mat.set_shader_parameter("height_scale", 0.9)
	walls.material_override = wall_mat
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(walls)
	register_clip(mat)
	register_clip(wall_mat)
	_launch()

func _launch() -> void:
	sim.SetPotential(PRESETS[preset], v0, width if preset != 4 else 0.6)
	var u0 := (x0 / L) + 0.5
	var kk := k0 if preset != 4 else 0.0
	if preset == 3:
		u0 = 0.5 - 0.1
		kk = k0 * 0.5
	sim.InitPacket(u0, 0.5, kk, 0.0, sigma)

func reset() -> void:
	_launch()

func step(dt: float) -> void:
	sim.Step(minf(dt, 0.05), 400)

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Potencial:", PRESET_NAMES, preset, func(i):
		preset = i
		_launch())
	LabUI.slider(p, "Altura V₀", 0.0, 12.0, 0.1, v0, func(v):
		v0 = v
		sim.SetPotential(PRESETS[preset], v0, width if preset != 4 else 0.6), "%.1f")
	LabUI.slider(p, "Anchura de la barrera", 0.1, 2.0, 0.05, width, func(v):
		width = v
		sim.SetPotential(PRESETS[preset], v0, width if preset != 4 else 0.6))
	LabUI.section(p, "Paquete de ondas")
	LabUI.slider(p, "Momento k₀ (energía ≈ k₀²/2)", 0.0, 6.0, 0.1, k0, func(v): k0 = v, "%.1f")
	LabUI.slider(p, "Anchura σ", 0.4, 2.5, 0.05, sigma, func(v): sigma = v)
	LabUI.slider(p, "Posición inicial x₀", -8.0, 8.0, 0.1, x0, func(v): x0 = v, "%.1f")
	LabUI.button(p, "🚀 Lanzar paquete", _launch)
	LabUI.section(p, "Perturbador")
	LabUI.option(p, "Clic:", ["Pintar barrera", "Lanzar paquete aquí (→)", "Borrar potencial"], 0, func(i): action = i)
	LabUI.slider(p, "Altura pintada", 1.0, 20.0, 0.5, paint_v, func(v): paint_v = v, "%.1f")
	LabUI.note(p, "La probabilidad de atravesar la barrera decae exponencialmente con su anchura y con √(2(V₀ − E)): prueba V₀ = 5, k₀ = 3 (E ≈ 4.5 < V₀) y cambia la anchura. El color es la fase: sus franjas muestran la longitud de onda de De Broglie λ = 2π/k.")

func _uv(hit: Vector3) -> Vector2:
	return Vector2(hit.x / SIZE + 0.5, hit.z / SIZE + 0.5)

func _height(x: float, z: float) -> float:
	var s: Vector4 = sim.Sample(x / SIZE + 0.5, z / SIZE + 0.5)
	return s.x * 9.0

func pick(origin: Vector3, dir: Vector3):
	return ray_heightfield(origin, dir, _height, SIZE * 0.5)

func hover_text(hit: Vector3) -> String:
	var uv := _uv(hit)
	var s: Vector4 = sim.Sample(uv.x, uv.y)
	return "x = %.2f   y = %.2f\n|ψ|² = %.4f\narg ψ = %.2f rad\nV = %.2f" % [(uv.x - 0.5) * L, (0.5 - uv.y) * L, s.x, atan2(s.z, s.y), s.w * 10.0]

func perturb(hit: Vector3, first: bool) -> void:
	var uv := _uv(hit)
	match action:
		0: sim.Perturb(uv.x, uv.y, paint_v * (0.6 if first else 0.25), 0.012)
		1:
			if first: sim.InitPacket(uv.x, uv.y, k0, 0.0, sigma)
		2: sim.Perturb(uv.x, uv.y, -paint_v, 0.02)

func critical_points() -> Array:
	var best := -INF
	var pb := Vector3.ZERO
	for j in range(48):
		for i in range(48):
			var u := (i + 0.5) / 48.0
			var v := (j + 0.5) / 48.0
			var d: float = sim.Sample(u, v).x
			if d > best:
				best = d
				pb = Vector3((u - 0.5) * SIZE, d * 9.0, (v - 0.5) * SIZE)
	var out := [{"pos": pb, "nombre": "Máximo de |ψ|² (%.3f)" % best, "dist": 2.2}]
	if preset in [1, 2]:
		out.append({"pos": Vector3(0, 0.4, 0), "nombre": "Barrera de potencial", "dist": 2.6})
	return out

func info() -> String:
	var ex: Vector2 = sim.ExpectedPosition()
	var trans: float = sim.ProbabilityBeyond(0.5 + width / L)
	var t := "t = %.2f · norma ∫|ψ|² = %.4f\n⟨x⟩ = %.2f · ⟨y⟩ = %.2f · E ≈ k₀²/2 = %.2f" % [float(sim.Time), float(sim.Norm()), ex.x, ex.y, k0 * k0 * 0.5]
	if preset in [1, 2]:
		t += "\nProbabilidad transmitida (x > barrera): [color=#ffcc55]%.1f %%[/color]" % (trans * 100.0)
	return t
