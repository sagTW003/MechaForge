extends LabModule
## Schrödinger 3D y medición (Física moderna, Fase 8). Ecuación dependiente del tiempo en una
## caja de 20 a₀ con el esquema de Visscher (fisica/Schrodinger3D.cs, en doble y en paralelo):
## paquetes gaussianos, superposiciones (dos paquetes que chocan, estados del oscilador),
## efecto túnel y doble rendija. |ψ|² se ve como un volumen trazado con rayos en la GPU
## (shaders/volumen_psi.gdshader) con la fase en color. Medir: la posición con un detector de
## resolución σ (regla de Born y colapso) o en qué mitad está la partícula.
## Unidades atómicas: a₀, Eₕ, ħ/Eₕ = 2,4189·10⁻¹⁷ s.

const SHADER := preload("res://mathlab/fisica/shaders/volumen_psi.gdshader")
const LADO_AU := 20.0                 # caja física (a₀)
const LADO := 4.0                     # cubo dibujado (mundo)
const ESCALA := 2.0                   # tiempo atómico por segundo del laboratorio a velocidad 1
const SEGURIDAD := 0.8                # Δt = 0,8 del límite de estabilidad
const ALTO := LADO * 0.5 + 0.15       # el cubo, apoyado sobre el pedestal (si no, lo tapa por debajo)
const PRESETS := ["Paquete libre", "Superposición: dos paquetes que chocan", "Oscilador: estado coherente",
	"Oscilador: superposición 0 + 1", "Efecto túnel (barrera)", "Doble rendija"]
const EJES := ["x", "y", "z"]

var preset := 0
var k0 := 1.5                         # número de onda (a₀⁻¹): velocidad ħk/m
var sigma := 1.5                      # anchura del paquete (a₀)
var v0 := 1.5                         # altura de la barrera (Eₕ)
var omega := 0.5                      # frecuencia del oscilador (Eₕ/ħ)
var sigma_det := 0.6                  # resolución del detector de posición (a₀)
var eje := 0                          # eje de la medición «de qué lado»
var n := 64
var sim: RefCounted
var tex: ImageTexture3D
var mat: ShaderMaterial
var cubo: MeshInstance3D
var marca: MeshInstance3D
var medidas := 0
var ultima := ""
var _sucio := true
var _ui := {}                         # campo → control, para ponerlos al día en cargar()
var _syncing := false

func title() -> String: return "Schrödinger 3D y medición"
func formula() -> String: return "iħ ∂ψ/∂t = −(ħ²/2m)∇²ψ + Vψ     P(r) = |ψ(r)|²"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3(0, ALTO, 0), "dist": 9.0, "yaw": -30.0, "pitch": -20.0}
func fixed_dt() -> float: return sim.Dt / ESCALA if sim else 0.0
func finito() -> bool: return sim == null or sim.Finito()

func setup() -> void:
	position = Vector3(0, ALTO, 0)
	scale_xy = LADO / LADO_AU
	scale_z = scale_xy
	n = [32, 48, 64][calidad()]
	sim = load("res://mathlab/fisica/Schrodinger3D.cs").new()
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("lado", LADO)
	register_clip(mat)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * LADO
	cubo = MeshInstance3D.new()
	cubo.mesh = bm
	cubo.material_override = mat
	cubo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cubo)
	var borde := MeshInstance3D.new()
	borde.mesh = bm
	borde.material_override = glass_mat(Color(0.5, 0.75, 1.0), 0.04)
	add_child(borde)
	marca = sphere(0.06, glow_mat(Color(1.0, 0.9, 0.3), 3.0))
	marca.visible = false
	add_child(marca)
	_iniciar()

## Estado inicial del preset (con la semilla del laboratorio no hay azar aquí: solo al medir).
func _iniciar() -> void:
	sim.Setup(n, LADO_AU)
	sim.Limpiar()
	var pot: String = ["libre", "libre", "armonico", "armonico", "barrera", "doble_rendija"][preset]
	sim.SetPotencial(pot, v0 if preset == 4 else 8.0, 1.0 if preset == 4 else 0.6, omega)
	match preset:
		0: sim.AgregarPaquete(-5.0, 0.0, 0.0, k0, 0.0, 0.0, sigma, 1.0, 0.0)
		1:
			sim.AgregarPaquete(-5.0, 0.0, 0.0, k0, 0.0, 0.0, sigma, 1.0, 0.0)
			sim.AgregarPaquete(5.0, 0.0, 0.0, -k0, 0.0, 0.0, sigma, 1.0, 0.0)
		2: sim.AgregarPaquete(3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0 / sqrt(2.0 * omega), 1.0, 0.0)
		3:
			sim.AgregarOscilador(0, 0, 0, omega, 1.0, 0.0)
			sim.AgregarOscilador(1, 0, 0, omega, 1.0, 0.0)
		4: sim.AgregarPaquete(-5.0, 0.0, 0.0, k0, 0.0, 0.0, sigma, 1.0, 0.0)
		5: sim.AgregarPaquete(-5.0, 0.0, 0.0, k0, 0.0, 0.0, maxf(sigma, 2.0), 1.0, 0.0)
	sim.Normalizar()
	sim.Iniciar(SEGURIDAD)
	medidas = 0
	ultima = ""
	marca.visible = false
	_subir()

## Sube el volumen a la textura 3D (una vez por fotograma como mucho).
func _subir() -> void:
	var bytes: PackedByteArray = sim.Volumen()
	var capas: Array[Image] = []
	var capa := n * n * 4
	for k in n:
		capas.append(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes.slice(k * capa, (k + 1) * capa)))
	if tex == null or tex.get_width() != n:
		tex = ImageTexture3D.new()
		tex.create(Image.FORMAT_RGBA8, n, n, n, false, capas)
		mat.set_shader_parameter("volumen", tex)
	else:
		tex.update(capas)
	_sucio = false

func step(_dt: float) -> void:
	sim.Paso(1)
	_sucio = true

func _process(_delta: float) -> void:
	if _sucio and sim:
		_subir()

func reset() -> void:
	_iniciar()

## Capturas (mflabshot schrodinger3d [choque|rendija] [t segundos]).
func demo(extra: PackedStringArray) -> void:
	if "choque" in extra:
		cargar({"preset": 1})
	elif "rendija" in extra:
		cargar({"preset": 5, "k0": 2.0})

# --- Coordenadas: las del laboratorio (to_world / to_math) con 1 a₀ = LADO/LADO_AU del mundo -----
# Así lab_sample(x, y) va en a₀ y lee la columna z de ese punto (api_points por defecto).

func _fisica(w: Vector3) -> Vector3:
	return to_math(to_local(w))

func _mundo(f: Vector3) -> Vector3:
	return to_global(to_world(f.x, f.y, f.z))

## El punto del rayo dentro del cubo con más |ψ|² (para el tooltip).
func pick(origin: Vector3, dir: Vector3):
	var o := to_local(origin)
	var h := Vector3.ONE * LADO * 0.5
	var t0 := 0.0
	var t1 := INF
	for a in 3:
		if absf(dir[a]) < 1e-9:
			if absf(o[a]) > h[a]:
				return null
			continue
		var ta := (-h[a] - o[a]) / dir[a]
		var tb := (h[a] - o[a]) / dir[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 <= t0:
		return null
	var mejor := -1.0
	var donde := origin + dir * t0
	for s in 48:
		var w := origin + dir * lerpf(t0, t1, (s + 0.5) / 48.0)
		var f := _fisica(w)
		var v: PackedFloat64Array = sim.ValorEn(f.x, f.y, f.z)
		if v[0] > mejor:
			mejor = v[0]
			donde = w
	return donde

func hover_text(hit: Vector3) -> String:
	var f := _fisica(hit)
	var v: PackedFloat64Array = sim.ValorEn(f.x, f.y, f.z)
	return "(x, y, z) = (%.2f, %.2f, %.2f) a₀\n|ψ|² = %s a₀⁻³\narg ψ = %.2f rad%s" % [f.x, f.y, f.z, LabUI.sci(v[0], 3), v[1],
		"\nV = %.2f Eₕ (pared)" % v[2] if v[2] > 0.0 else ""]

# --- Medición -----------------------------------------------------------------------------

## Mide la posición: la regla de Born elige dónde y ψ colapsa a un paquete del ancho del detector.
func medir_posicion() -> void:
	var r: PackedFloat64Array = sim.MedirPosicion(rng.randf(), sigma_det)
	medidas += 1
	marca.position = to_local(_mundo(Vector3(r[0], r[1], r[2])))
	marca.visible = true
	ultima = "Medida %d: la partícula apareció en (%.2f, %.2f, %.2f) a₀; ψ colapsó a un paquete de σ ≈ %.2f a₀ y vuelve a evolucionar." % [
		medidas, r[0], r[1], r[2], sigma_det]
	_subir()

## Mide en qué mitad está (plano «eje» = 0): con la doble rendija y el eje y, «por qué rendija pasó».
func medir_lado() -> void:
	var res: PackedFloat64Array = sim.MedirLado(eje, rng.randf())
	medidas += 1
	marca.visible = false
	ultima = "Medida %d: %s %s 0 (tenía probabilidad %.3f); ψ quedó solo en esa mitad%s." % [medidas, EJES[eje], ">" if res[0] > 0 else "<",
		res[1] if res[0] > 0 else 1.0 - res[1], ": ya no hay interferencia entre las dos rendijas" if preset == 5 and eje == 1 else ""]
	_subir()

## Estadística de Born sin medir: 2000 posiciones sacadas de |ψ|² frente a la probabilidad exacta.
func muestrear() -> void:
	var us := PackedFloat64Array()
	for i in 2000:
		us.append(rng.randf())
	var pos: PackedFloat64Array = sim.Muestrear(us)
	var mas := 0
	for i in 2000:
		mas += int(pos[3 * i + eje] > 0.0)
	var p: float = sim.ProbabilidadMas(eje, 0.0)
	ultima = "Regla de Born: de 2000 posiciones sacadas de |ψ|², %d (%.1f %%) tienen %s > 0; la probabilidad exacta es %.1f %% (±%.1f %% esperado)." % [
		mas, 100.0 * mas / 2000.0, EJES[eje], 100.0 * p, 100.0 * sqrt(maxf(p * (1.0 - p), 1e-9) / 2000.0)]

# --- Interfaz -----------------------------------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	_ui["preset"] = LabUI.option(p, "Estado:", PRESETS, preset, func(i): _cambiar("preset", i))
	_ui["k0"] = LabUI.slider(p, "k₀ (a₀⁻¹)", 0.5, 2.5, 0.1, k0, func(v): _cambiar("k0", v), "%.1f")
	_ui["sigma"] = LabUI.slider(p, "Anchura σ (a₀)", 0.8, 2.5, 0.1, sigma, func(v): _cambiar("sigma", v), "%.1f")
	_ui["v0"] = LabUI.slider(p, "Barrera V₀ (Eₕ)", 0.5, 4.0, 0.1, v0, func(v): _cambiar("v0", v), "%.1f")
	_ui["omega"] = LabUI.slider(p, "Oscilador ω (Eₕ/ħ)", 0.3, 1.0, 0.05, omega, func(v): _cambiar("omega", v), "%.2f")
	LabUI.section(p, "Medición")
	_ui["sigma_det"] = LabUI.slider(p, "Resolución del detector σ (a₀)", 0.3, 2.0, 0.1, sigma_det, func(v): sigma_det = v, "%.1f")
	_ui["eje"] = LabUI.option(p, "Lado según el eje:", EJES, eje, func(i): eje = i)
	var r := LabUI.row(p)
	LabUI.button(r, "Medir posición", medir_posicion)
	LabUI.button(r, "Medir lado", medir_lado)
	LabUI.button(p, "Regla de Born: 2000 muestras", muestrear)
	LabUI.note(p, "Opacidad: |ψ|²; color: la fase de ψ (la misma rueda que en el hidrógeno); gris: las paredes del potencial. Medir cambia ψ: la regla de Born elige el resultado y la función de onda colapsa. En la doble rendija, medir el lado según y («por qué rendija») borra la interferencia. Las paredes de la caja reflejan.")

func _cambiar(campo: String, v) -> void:
	if _syncing:
		return
	remember()
	set(campo, v)
	_iniciar()

func info() -> String:
	var e: PackedFloat64Array = sim.Esperado()
	var s := "t = %.2f ħ/Eₕ · Δt = %.4f · rejilla %d³ (h = %.3f a₀)" % [sim.Tiempo, sim.Dt, n, LADO_AU / (n - 1)]
	s += "\nNorma (Visscher) = %.9f · ⟨E⟩ = %.4f Eₕ" % [sim.Norma(), sim.Energia()]
	s += "\n⟨r⟩ = (%.2f, %.2f, %.2f) a₀ · Δx = %.2f, Δy = %.2f, Δz = %.2f a₀ · P(%s > 0) = %.3f" % [e[0], e[1], e[2], e[3], e[4], e[5], EJES[eje], sim.ProbabilidadMas(eje, 0.0)]
	match preset:
		0:
			s += "\nLibre: Δy teórico σ√(1 + (t/2σ²)²) = %.2f a₀" % (sigma * sqrt(1.0 + pow(sim.Tiempo / (2.0 * sigma * sigma), 2)))
		2:
			s += "\nEstado coherente: ⟨x⟩ teórico = x₀ cos ωt = %.2f a₀ (no se ensancha)" % (3.0 * cos(omega * sim.Tiempo))
		3:
			s += "\nSuperposición 0 + 1: ⟨x⟩ = cos(ωt)/√(2ω) = %.2f a₀ y ⟨E⟩ = 2ω = %.3f Eₕ" % [cos(omega * sim.Tiempo) / sqrt(2.0 * omega), 2.0 * omega]
		4:
			s += "\nTransmisión P(x > 0,5 a₀) = %.3f con E ≈ k₀²/2 = %.2f Eₕ frente a V₀ = %.2f Eₕ" % [sim.ProbabilidadMas(0, 0.5), k0 * k0 / 2.0, v0]
	if ultima != "":
		s += "\n" + ultima
	return s

func metricas() -> Dictionary:
	return {"entidades": n * n * n, "medidas": medidas}

func estado() -> Dictionary:
	return {"preset": preset, "k0": k0, "sigma": sigma, "v0": v0, "omega": omega, "sigma_det": sigma_det, "eje": eje}

func cargar(d: Dictionary) -> String:
	var pr := int(d.get("preset", -1))
	if pr < 0 or pr >= PRESETS.size():
		return "estado inicial desconocido"
	var rangos := {"k0": [0.5, 2.5], "sigma": [0.8, 2.5], "v0": [0.5, 4.0], "omega": [0.3, 1.0], "sigma_det": [0.3, 2.0]}
	for c in rangos:
		var v := float(d.get(c, get(c)))
		if v < rangos[c][0] or v > rangos[c][1]:
			return "«%s» fuera de rango (%s a %s)" % [c, str(rangos[c][0]), str(rangos[c][1])]
	preset = pr
	for c in rangos:
		set(c, float(d.get(c, get(c))))
	eje = clampi(int(d.get("eje", 0)), 0, 2)
	_syncing = true
	for c in _ui:
		if _ui[c] is OptionButton:
			(_ui[c] as OptionButton).select(get(c))
		else:
			(_ui[c] as HSlider).value = get(c)      # la etiqueta del valor se actualiza con la señal
	_syncing = false
	_iniciar()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Evolución de ψ", "nivel": "exacto",
			"modelo": "Ecuación de Schrödinger dependiente del tiempo en una caja de 20 a₀ con ψ = 0 en las paredes (reflejan). Esquema de Visscher en doble: estable con Δt ≤ 2/E_máx y conserva exacta su norma; laplaciano de 7 puntos con error O(h²) (un paquete avanza a sin(kh)/h en vez de k)",
			"ecuaciones": "R(t+Δt) = R + Δt·H·I,  I(t+3Δt/2) = I − Δt·H·R(t+Δt),  H = −½∇² + V",
			"unidades": "unidades atómicas: ħ = mₑ = 1, a₀, Eₕ, ħ/Eₕ = 2,4189·10⁻¹⁷ s",
			"referencias": "Visscher, Computers in Physics 5, 596 (1991); Griffiths, Introduction to Quantum Mechanics, cap. 2–4"},
		{"subsistema": "Estados iniciales y superposición", "nivel": "exacto",
			"modelo": "Paquetes gaussianos y estados propios del oscilador isótropo (Hermite); una superposición es la suma normalizada de los estados",
			"ecuaciones": "ψ = e^{−|r−r₀|²/4σ²}e^{ik·r};  φₙ(x) ∝ Hₙ(√ω x) e^{−ωx²/2};  Eₙ = ω(n + 3/2)",
			"unidades": "a₀, Eₕ", "referencias": "Griffiths, cap. 2"},
		{"subsistema": "Medición", "nivel": "aproximado",
			"modelo": "Regla de Born exacta para el resultado; el colapso es instantáneo: proyección gaussiana con la resolución σ del detector (posición) o sobre el semiespacio que salió (lado). Sin dinámica del detector ni decoherencia",
			"ecuaciones": "P(r) = |ψ(r)|²;  ψ → e^{−|r−r₀|²/4σ²}ψ / ‖·‖", "unidades": "a₀",
			"referencias": "Nielsen y Chuang, Quantum Computation and Quantum Information, §2.2.6 (POVM)"},
		{"subsistema": "Volumen dibujado", "nivel": "ilustrativo",
			"modelo": "Trazado de rayos de |ψ|² en la GPU: la fase en color es la exacta de cada celda; la opacidad es una escala visual y las paredes van en gris",
			"ecuaciones": "", "unidades": "sin escala", "referencias": ""},
	]
