extends LabModule
## Desintegraciones y cámara de burbujas (Física moderna, Fase 4). Una partícula inestable de
## la tabla del PDG nace en el centro con momento p según x, en un campo B uniforme según z;
## vuela una distancia βγcτ·(−ln U), se desintegra en un canal elegido con las fracciones del
## PDG y sus productos siguen (hasta 4 generaciones). En cada vértice se comprueban la carga,
## el número bariónico, los números leptónicos, la energía, la paridad de fermiones y el
## cuadrimomento. Cinemática relativista exacta en C# (Fisica.DecayEvent); unidades del
## laboratorio de partículas: GeV/c, T y m.

const RADIO_M := 1.0                  # cámara: cilindro de radio y semialtura 1 m
const S_VIEW := 2.5                   # mundo por metro
const COL_POS := Color(1.0, 0.45, 0.35)
const COL_NEG := Color(0.4, 0.7, 1.0)
const COL_NEU := Color(0.8, 0.8, 0.8)

var ids_decaen: Array = []
var ids_todas: Array = []
var particula := "K+"
var p_gev := 0.5
var b_t := 1.5
var cadena := true
var trazas: Array = []
var _anim := 0.0
var lines: MeshInstance3D
var bubbles: MultiMeshInstance3D
var marks: Node3D
var _ficha: Label
var _ficha_opt: OptionButton
var _ficha_ids: Array = []

func title() -> String: return "Desintegraciones y cámara de burbujas"
func formula() -> String: return "L = βγcτ·(−ln U)     R = p⊥ / (0,2998·|q|·B)"
func uses_time() -> bool: return true
func view() -> Dictionary: return {"target": Vector3.ZERO, "dist": 7.5, "yaw": 0.0, "pitch": -62.0}

func setup() -> void:
	scale_xy = S_VIEW
	scale_z = S_VIEW
	ids_todas = Array(Fisica.ParticleIds())
	for id in ids_todas:
		if not (Fisica.ParticleInfo(id)["canales"] as Array).is_empty():
			ids_decaen.append(id)
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIO_M * S_VIEW
	cyl.bottom_radius = RADIO_M * S_VIEW
	cyl.height = 2.0 * RADIO_M * S_VIEW
	var cham := MeshInstance3D.new()
	cham.mesh = cyl
	cham.material_override = glass_mat(Color(0.55, 0.8, 1.0), 0.08)
	add_child(cham)
	add_child(arrow(Vector3(-RADIO_M * S_VIEW * 1.15, -0.8, 0), Vector3(-RADIO_M * S_VIEW * 1.15, 0.8, 0), 0.02, glow_mat(Color(0.4, 0.8, 1.0), 2.0)))
	add_child(label3d("B", Vector3(-RADIO_M * S_VIEW * 1.15, 0.95, 0), Color(0.5, 0.85, 1.0)))
	lines = MeshInstance3D.new()
	lines.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.material_override = lm
	add_child(lines)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = vcolor_mat(0.85, 0.5)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = sm
	bubbles = MultiMeshInstance3D.new()
	bubbles.multimesh = multi
	add_child(bubbles)
	marks = Node3D.new()
	add_child(marks)
	shoot()

## Un suceso nuevo (semilla del laboratorio: misma semilla, mismos sucesos).
func shoot() -> void:
	trazas = Array(Fisica.DecayEvent(particula, p_gev, b_t, RADIO_M, 4 if cadena else 1, rng.randi()))
	_anim = 0.0
	_build_marks()
	_draw()

func step(dt: float) -> void:
	if _anim < 4.0:
		_anim += dt
		_draw()

func reset() -> void:
	shoot()

## Generación de cada traza (0 la primera): las hijas aparecen después que su madre.
func _depth(i: int) -> int:
	var d := 0
	var j: int = trazas[i]["padre"]
	while j >= 0:
		d += 1
		j = trazas[j]["padre"]
	return d

func _color(tr: Dictionary) -> Color:
	var q: int = tr["carga3"]
	return COL_POS if q > 0 else (COL_NEG if q < 0 else COL_NEU)

## Trazas: cargadas continuas (con burbujas), neutras discontinuas y neutrinos casi invisibles.
func _draw() -> void:
	var im: ImmediateMesh = lines.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var bub: Array = []
	for i in trazas.size():
		var tr: Dictionary = trazas[i]
		var pts: PackedVector3Array = tr["puntos"]
		var shown := int(ceil(pts.size() * clampf(_anim * 1.5 - _depth(i) * 0.6, 0.0, 1.0)))
		var col := _color(tr)
		if bool(tr["neutrino"]):
			col.a = 0.18
		elif tr["carga3"] == 0:
			col.a = 0.55
		for k in range(1, shown):
			if tr["carga3"] == 0 and k % 2 == 0:
				continue                      # discontinua: las neutras no dejan burbujas
			im.surface_set_color(col)
			im.surface_add_vertex(to_world(pts[k - 1].x, pts[k - 1].y, pts[k - 1].z))
			im.surface_set_color(col)
			im.surface_add_vertex(to_world(pts[k].x, pts[k].y, pts[k].z))
			if tr["carga3"] != 0 and bub.size() < 6000:
				bub.append([to_world(pts[k].x, pts[k].y, pts[k].z), col])
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
	var mm := bubbles.multimesh
	mm.instance_count = bub.size()
	for i in bub.size():
		var j := Vector3(sin(i * 12.9898), sin(i * 78.233), sin(i * 37.719)) * 0.006
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.011), bub[i][0] + j))
		mm.set_instance_color(i, bub[i][1])

## Vértices de desintegración y el símbolo de cada partícula al nacer.
func _build_marks() -> void:
	for c in marks.get_children():
		c.queue_free()
	for i in trazas.size():
		var tr: Dictionary = trazas[i]
		var pts: PackedVector3Array = tr["puntos"]
		if pts.is_empty() or bool(tr["neutrino"]):
			continue
		var a := to_world(pts[0].x, pts[0].y, pts[0].z)
		if i < 24:
			marks.add_child(label3d(tr["simbolo"], a + Vector3(0, 0.12, 0), _color(tr).lightened(0.3), 0.0035))
		if bool(tr["decae"]):
			var b := to_world(pts[pts.size() - 1].x, pts[pts.size() - 1].y, pts[pts.size() - 1].z)
			marks.add_child(_mark(b))

func _mark(at: Vector3) -> MeshInstance3D:
	var s := sphere(0.03, glow_mat(Color(1.0, 0.9, 0.4), 4.0))
	s.position = at
	return s

func build_ui(pnl: VBoxContainer) -> void:
	var names: Array = []
	for id in ids_decaen:
		names.append("%s  %s" % [Fisica.ParticleInfo(id)["simbolo"], Fisica.ParticleInfo(id)["nombre"]])
	LabUI.option(pnl, "Partícula:", names, maxi(0, ids_decaen.find(particula)), _on_particula)
	LabUI.slider(pnl, "Momento p (GeV/c)", 0.02, 5.0, 0.01, p_gev, _on_p, "%.2f")
	LabUI.slider(pnl, "Campo B (T)", 0.0, 4.0, 0.05, b_t, _on_b, "%.2f")
	LabUI.check(pnl, "Seguir la cadena (los productos también se desintegran)", cadena, _on_cadena)
	LabUI.button(pnl, "🎯 Disparar otra", shoot)
	LabUI.section(pnl, "Ficha de partícula")
	LabUI.text_field(pnl, "Buscar:", "", "nombre o símbolo (p. ej. kaon, μ, Σ)", _on_buscar)
	_ficha_opt = LabUI.option(pnl, "Ficha:", [], 0, _on_ficha)
	_ficha = LabUI.note(pnl, "")
	_on_buscar("")
	LabUI.note(pnl, "Las trazas rojas son de carga positiva, las azules negativa; las neutras van discontinuas y los neutrinos casi transparentes. En la vista superior (2) se ven las circunferencias: R = p⊥/(0,3·|q|·B). Los puntos amarillos son los vértices de desintegración.")

func _on_particula(i: int) -> void:
	remember()
	particula = ids_decaen[i]
	shoot()

func _on_p(val: float) -> void:
	remember()
	p_gev = val
	shoot()

func _on_b(val: float) -> void:
	remember()
	b_t = val
	shoot()

func _on_cadena(on: bool) -> void:
	remember()
	cadena = on
	shoot()

func _on_buscar(texto: String) -> void:
	var q := texto.strip_edges().to_lower()
	_ficha_ids.clear()
	_ficha_opt.clear()
	for id in ids_todas:
		var inf: Dictionary = Fisica.ParticleInfo(id)
		var etiqueta := "%s  %s" % [inf["simbolo"], inf["nombre"]]
		if q == "" or etiqueta.to_lower().contains(q) or str(id).to_lower().contains(q):
			_ficha_ids.append(id)
			_ficha_opt.add_item(etiqueta)
	if not _ficha_ids.is_empty():
		_ficha_opt.select(0)
		_on_ficha(0)
	else:
		_ficha.text = "Ninguna partícula coincide."

func _on_ficha(i: int) -> void:
	if i < 0 or i >= _ficha_ids.size():
		return
	_ficha.text = ficha(_ficha_ids[i])

## Inspector: propiedades de la tabla del PDG.
func ficha(id: String) -> String:
	var f: Dictionary = Fisica.ParticleInfo(id)
	var t := "%s (%s, %s)\nm = %s MeV · q = %s e · espín %s · B = %s · Lₑ = %d, L_μ = %d, L_τ = %d" % [
		f["simbolo"], f["nombre"], f["tipo"], _num(f["masa_MeV"]), f["carga"], f["espin"], f["B"], f["Le"], f["Lmu"], f["Ltau"]]
	if str(f["quarks"]) != "":
		t += " · quarks %s" % f["quarks"]
	if str(f["color"]) != "neutro":
		t += " · color: %s" % f["color"]
	var vida: float = f["vida_s"]
	t += "\nvida media: %s" % ("estable" if vida < 0.0 else "%s s (cτ = %s m)" % [LabUI.sci(vida, 4), LabUI.sci(vida * 299792458.0, 3)])
	for c in f["canales"]:
		t += "\n  %s   %s %%" % [c["texto"], _num(float(c["br"]) * 100.0)]
	if str(f["nota"]) != "":
		t += "\n" + str(f["nota"])
	return t

static func _num(x: float) -> String:
	return LabUI.sci(x, 5) if x != 0.0 and (absf(x) < 0.01 or absf(x) >= 1e5) else str(snappedf(x, 1e-6))

func info() -> String:
	var t := "%s con p = %.2f GeV/c en B = %.2f T · %d trazas" % [Fisica.ParticleInfo(particula)["simbolo"], p_gev, b_t, trazas.size()]
	var shown := 0
	for tr in trazas:
		if not bool(tr["decae"]) or shown >= 6:
			continue
		shown += 1
		var p0: PackedFloat64Array = tr["p0"]
		var inf: Dictionary = Fisica.ParticleInfo(tr["id"])
		var m: float = inf["masa_MeV"] / 1000.0
		var bgct: float = sqrt(p0[1] ** 2 + p0[2] ** 2 + p0[3] ** 2) / m * 299792458.0 * float(inf["vida_s"])
		var viol: PackedStringArray = tr["violaciones"]
		t += "\n%s · vuela %s m (βγcτ = %s m) · %s" % [tr["canal"], _num(tr["longitud_m"]), _num(bgct),
			"[color=#7dffa0]conserva todo ✓[/color]" if viol.is_empty() else "[color=#ff7070]" + ", ".join(viol) + "[/color]"]
	return t

func metricas() -> Dictionary:
	return {"entidades": trazas.size()}

func pick(origin: Vector3, dir: Vector3):
	var hit = ray_plane_y(origin, dir, 0.0)
	return hit if hit != null and Vector2((hit as Vector3).x, (hit as Vector3).z).length() < RADIO_M * S_VIEW else null

func hover_text(hit: Vector3) -> String:
	var q := to_math(hit)
	return "x = %.3f m   y = %.3f m\nB = %.2f T según z" % [q.x, q.y, b_t]

func critical_points() -> Array:
	var pts := [{"pos": Vector3.ZERO, "nombre": "Vértice inicial", "dist": 3.0}]
	for tr in trazas:
		if bool(tr["decae"]):
			var ps: PackedVector3Array = tr["puntos"]
			var e := ps[ps.size() - 1]
			pts.append({"pos": to_world(e.x, e.y, e.z), "nombre": str(tr["canal"]), "dist": 2.0})
			break
	return pts

func estado() -> Dictionary:
	return {"particula": particula, "p": p_gev, "B": b_t, "cadena": cadena}

func cargar(d: Dictionary) -> String:
	var id := str(d.get("particula", ""))
	if not id in ids_decaen:
		return "partícula sin desintegraciones en la tabla: «%s»" % id
	for k in ["p", "B"]:
		if not typeof(d.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			return "falta «%s»" % k
	if float(d["p"]) <= 0.0 or float(d["B"]) < 0.0:
		return "valores fuera de rango (p > 0, B ≥ 0)"
	particula = id
	p_gev = float(d["p"])
	b_t = float(d["B"])
	cadena = bool(d.get("cadena", true))
	shoot()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "Datos de las partículas", "nivel": "exacto",
			"modelo": "Masas, cargas, espines, números cuánticos, vidas medias y fracciones de desintegración medidos (PDG 2026). Solo los canales principales de cada partícula: si no suman el 100 %, se renormalizan (el τ, 71,5 %)",
			"ecuaciones": "τ = ħ/Γ", "unidades": "MeV, s; ħ = 6,582119569·10⁻²⁵ GeV·s (exacta)",
			"referencias": "Particle Data Group, Review of Particle Physics 2026 (pdglive.lbl.gov)"},
		{"subsistema": "Cinemática de las desintegraciones", "nivel": "exacto",
			"modelo": "Relatividad especial: dos cuerpos con el momento exacto en el reposo, isótropo; vuelo L = βγcτ·(−ln U); conservación del cuadrimomento comprobada en cada vértice",
			"ecuaciones": "p* = √[(M² − (m₁+m₂)²)(M² − (m₁−m₂)²)]/2M;  L = βγcτ·(−ln U)",
			"unidades": "GeV, GeV/c, m", "referencias": "PDG, sección «Kinematics»"},
		{"subsistema": "Tres o más cuerpos", "nivel": "aproximado",
			"modelo": "Espacio de fases plano (GENBOD), sin el elemento de matriz del canal: la conservación es exacta, el reparto de energías entre los productos no",
			"ecuaciones": "dΓ ∝ dΦₙ", "unidades": "GeV", "referencias": "F. James, CERN 68-15 (1968)"},
		{"subsistema": "Trazas en el campo magnético", "nivel": "aproximado",
			"modelo": "Hélices exactas en un campo uniforme, sin pérdida de energía por ionización, sin dispersión múltiple y sin conversión de fotones",
			"ecuaciones": "R[m] = p⊥[GeV/c] / (0,299792458·|q|·B[T])", "unidades": "m, T", "referencias": ""},
		{"subsistema": "Burbujas", "nivel": "ilustrativo",
			"modelo": "Puntos a lo largo de las trazas cargadas como recordatorio de una cámara de burbujas: su densidad no representa la ionización",
			"ecuaciones": "", "unidades": "m (posición sobre la traza)", "referencias": ""},
	]
