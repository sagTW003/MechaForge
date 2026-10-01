class_name PartInstance
extends Node3D
## PartInstance — Una pieza colocada en la escena.
##
## Construye su malla procedural según la definición (caja/cilindro/placa/tubo),
## aplica el material PBR, calcula su masa y expone sus propiedades editables.
## En Fase 1 es puramente visual; en Fase 2 se le añadirá cuerpo físico.

var def_id: String = ""
var def: Dictionary = {}
var material_id: String = "aluminio"
var uid: String = ""
## Transformación al iniciar la simulación (para reiniciar al estado original).
var initial_transform: Transform3D = Transform3D.IDENTITY
## Anclada al mundo: en simulación queda fija (banco de pruebas, pista, soporte).
var anchored: bool = false
## Inserción en protoboard (enganche multipín): uid de la placa, pin -> agujero y
## transformación relativa a la placa (jerarquía padre-hijo: se mueve con ella).
var inserted_in: String = ""
var pin_map: Dictionary = {}
var insert_local: Transform3D = Transform3D.IDENTITY
## Estado propio de la pieza que se guarda con el proyecto (p. ej. el modo del
## multímetro, su fusible y la posición de las sondas).
var estado: Dictionary = {}

var _mesh_instance: MeshInstance3D
var _detail: Node3D
var _pick_body: StaticBody3D
var _selection_box: MeshInstance3D
var _selected: bool = false

## Capa de colisión reservada para el "picking" (selección con ratón) en Fase 1.
const PICK_LAYER := 2

func setup(definition: Dictionary, instance_uid: String = "") -> void:
	def = definition.duplicate(true)
	def_id = def.get("id", "?")
	material_id = def.get("material", "aluminio")
	uid = instance_uid if instance_uid != "" else _new_uid()
	anchored = bool(def.get("fijo", false))
	name = "Part_%s" % uid
	# La protoboard genera su matriz de terminales (columnas + rieles) con grupos.
	if def.get("apariencia", "") == "protoboard":
		def["terminales"] = gen_protoboard_terminals(def.get("dimensiones_mm", {}))
	# Integrados DIP (555, Arduino Nano): patas en dos filas, paso 2.54 mm.
	if def.has("dip"):
		def["terminales"] = gen_dip_terminals(def)
	_build_visual()

## Protoboard MB-102 de 830 puntos (medidas reales, paso 0.1" = 2.54 mm):
##   63 columnas; filas a–e (arriba) y f–j (abajo) separadas por el canal central
##   de 7.62 mm; cada columna de 5 agujeros es un grupo interno (TAc / TBc).
##   4 rieles de 50 puntos (grupos de 5 con un hueco): P1 (+, rojo) y N1 (−, azul)
##   arriba; P2 (+) y N2 (−) abajo.
## Los ids se conservan: "a{columna}_{fila}" (fila 0 = e, junto al canal, … 4 = a),
## "b{columna}_{fila}" (0 = f … 4 = j) y "P1_k", "N1_k", "P2_k", "N2_k".
const BB_PITCH := 2.54
const BB_COLS := 63
const BB_RAIL_Z := [22.86, 20.32, -20.32, -22.86]      # P1, N1, P2, N2 (mm)
const BB_RAIL_IDS := ["P1", "N1", "P2", "N2"]
const BB_RAIL_TIPO := ["power", "gnd", "power", "gnd"]

static func bb_column_x(c: int) -> float:
	return (float(c) - (BB_COLS - 1) * 0.5) * BB_PITCH

static func bb_row_z(top: bool, r: int) -> float:
	var z := 3.81 + r * BB_PITCH
	return z if top else -z

## Posiciones X (mm) de los 50 agujeros de un riel (grupos de 5 + hueco).
static func bb_rail_x() -> Array:
	var xs := []
	for k in range(59):
		if k % 6 != 5:
			xs.append((float(k) - 29.0) * BB_PITCH)
	return xs

static func gen_protoboard_terminals(dm: Dictionary) -> Array:
	var yt := float(dm.get("y", 9.0)) * 0.5
	var terms := []
	for c in range(BB_COLS):
		var px := bb_column_x(c)
		for r in range(5):
			terms.append({"id": "a%d_%d" % [c, r], "tipo": "signal", "grupo": "TA%d" % c, "pos_mm": [px, yt, bb_row_z(true, r)]})
			terms.append({"id": "b%d_%d" % [c, r], "tipo": "signal", "grupo": "TB%d" % c, "pos_mm": [px, yt, bb_row_z(false, r)]})
	var rx := bb_rail_x()
	for i in range(4):
		for k in range(rx.size()):
			terms.append({"id": "%s_%d" % [BB_RAIL_IDS[i], k], "tipo": BB_RAIL_TIPO[i], "grupo": BB_RAIL_IDS[i],
				"pos_mm": [rx[k], yt, BB_RAIL_Z[i]], "fino": true})
	for t in terms:
		t["fino"] = true      # marcadores pequeños: los agujeros están a 2.54 mm
	return terms

## Terminales de un encapsulado DIP: N patas en dos filas separadas "fila_mm",
## paso 2.54 mm, numeradas en sentido antihorario visto desde arriba (pata 1 en
## la fila +Z, extremo −X, junto a la muesca). La punta de cada pata queda a la
## altura de la cara inferior (superficie de la protoboard al insertar).
static func dip_pin_positions(def: Dictionary) -> Array:
	var dp: Dictionary = def.get("dip", {})
	var n := int(dp.get("pines", 8))
	var half := n / 2
	var fila := float(dp.get("fila_mm", 7.62))
	var y := -float(def.get("dimensiones_mm", {}).get("y", 6.0)) * 0.5
	var out := []
	for i in range(n):
		var k := i if i < half else (n - 1 - i)
		var x := (float(k) - (half - 1) * 0.5) * BB_PITCH
		var z := fila * 0.5 if i < half else -fila * 0.5
		out.append(Vector3(x, y, z))
	return out

static func gen_dip_terminals(def: Dictionary) -> Array:
	var dp: Dictionary = def.get("dip", {})
	var names: Array = dp.get("nombres", [])
	var pos := dip_pin_positions(def)
	var terms := []
	for i in range(pos.size()):
		var nm: String = str(names[i]) if i < names.size() else str(i + 1)
		var tipo := "signal"
		if nm in ["VCC", "5V", "3V3", "VIN"]:
			tipo = "power"
		elif nm.begins_with("GND"):
			tipo = "gnd"
		var p: Vector3 = pos[i]
		terms.append({"id": nm, "tipo": tipo, "pos_mm": [p.x, p.y, p.z], "pata": i + 1, "fino": true})
	return terms

## ¿Se inserta en la protoboard (patas en los agujeros)?
func is_insertable() -> bool:
	return bool(def.get("insercion", false))

func is_inserted() -> bool:
	return inserted_in != ""

func is_breadboard() -> bool:
	return def.get("apariencia", "") == "protoboard"

func _new_uid() -> String:
	return "p%d_%d" % [Time.get_ticks_usec(), randi() % 100000]

func _build_visual() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()
		_mesh_instance = null
	if _detail:
		_detail.queue_free()
		_detail = null
	# Aspecto detallado (componentes electrónicos, protoboard, etc.) si aplica.
	var detail := PartVisuals.build(def)
	if detail:
		_detail = detail
		add_child(_detail)
	else:
		_mesh_instance = _make_mesh_node()
		add_child(_mesh_instance)
	_build_pick_body()

## Malla principal con su material (y detalles como los orificios de placa).
func _make_mesh_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh()
	mi.material_override = MaterialLibrary.get_visual(material_id)
	if def.get("forma", "") == "custom":
		mi.scale = Vector3.ONE * float(def.get("_scale", 1.0))
		if def.has("_offset"):
			mi.position = def["_offset"]
	if has_holes():
		var holes := MeshFactory.plate_holes(PartLibrary.dims_m(def))
		if holes:
			mi.add_child(holes)
	return mi

## Placas estructurales con patrón de orificios (M5 cada 20 mm).
func has_holes() -> bool:
	return def.get("forma", "") == "placa" and bool(def.get("agujeros", def.get("categoria", "") == "estructural"))

## Radio de colisión de un engranaje: el de pie, para que los dientes no choquen
## (el engrane lo resuelve la restricción de engranaje, no el contacto).
func _gear_collision_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = maxf(0.001, PartLibrary.gear_root_radius_m(def))
	s.height = PartLibrary.dims_m(def).y
	return s

## Cuerpo estático solo para selección con el ratón (raycast físico).
func _build_pick_body() -> void:
	if _pick_body:
		_pick_body.queue_free()
	_pick_body = StaticBody3D.new()
	_pick_body.collision_layer = PICK_LAYER
	_pick_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var forma: String = def.get("forma", "caja")
	if forma == "engranaje":
		var gs := CylinderShape3D.new()
		gs.radius = PartLibrary.gear_tip_radius_m(def)
		gs.height = PartLibrary.dims_m(def).y
		cs.shape = gs
	elif forma == "cilindro" or forma == "tubo":
		var d: Dictionary = def.get("dimensiones_mm", {})
		var shape := CylinderShape3D.new()
		shape.radius = float(d.get("radio", 10.0)) / 1000.0
		shape.height = float(d.get("altura", 100.0)) / 1000.0
		cs.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = PartLibrary.dims_m(def)
		cs.shape = shape
	_pick_body.add_child(cs)
	add_child(_pick_body)

func _make_mesh() -> Mesh:
	var forma: String = def.get("forma", "caja")
	if forma == "custom" and def.has("_mesh"):
		return def["_mesh"]
	var d: Dictionary = def.get("dimensiones_mm", {})
	match forma:
		"esfera":
			var sph := SphereMesh.new()
			sph.radius = float(d.get("radio", 10.0)) / 1000.0
			sph.height = sph.radius * 2.0
			sph.radial_segments = 32
			sph.rings = 16
			return sph
		"cilindro":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = h
			cyl.radial_segments = 32
			return cyl
		"tubo":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			var e := float(d.get("espesor", 2.0)) / 1000.0
			return MeshFactory.tube(r, maxf(0.0, r - e), h, 40)
		"engranaje":
			return MeshFactory.gear(PartLibrary.gear_teeth(def), PartLibrary.gear_module_m(def),
				float(d.get("ancho", 8.0)) / 1000.0, float(d.get("agujero", 5.0)) / 1000.0)
		_:
			var size := PartLibrary.dims_m(def)
			if def.get("perfil", "") == "tslot":
				return MeshFactory.tslot_profile(size)
			return MeshFactory.chamfer_box(size)

## Masa en kg = densidad(material) * volumen. Con filamento de impresión 3D el
## volumen es el de las paredes más el relleno (printed_volume_m3).
func mass_kg() -> float:
	var rho := MaterialLibrary.density(material_id)
	if MaterialLibrary.is_printable(material_id):
		return rho * printed_volume_m3()
	return rho * PartLibrary.volume_m3(def)

## Ajustes de impresión 3D de la pieza (se guardan en "estado"): relleno (0..1) y
## grosor de las paredes en mm (perímetros + capas superior e inferior).
const PRINT_DEFAULTS := {"relleno": 0.2, "paredes_mm": 0.8}

func print_settings() -> Dictionary:
	var ps: Dictionary = PRINT_DEFAULTS.duplicate()
	ps.merge(estado.get("impresion", {}), true)
	return ps

func set_print_setting(key: String, value: float) -> void:
	var ps: Dictionary = estado.get("impresion", {}).duplicate()
	ps[key] = value
	estado["impresion"] = ps

## Volumen de plástico de una pieza impresa: una cáscara de "paredes_mm" (área ×
## grosor, nunca más que la pieza) más el relleno del interior. Aproximación: la
## densidad resultante se reparte uniforme (centroide e inercia del sólido).
func printed_volume_m3() -> float:
	var v := PartLibrary.volume_m3(def)
	var ps := print_settings()
	var shell := minf(v, PartLibrary.area_m2(def) * maxf(0.0, float(ps["paredes_mm"])) / 1000.0)
	return shell + clampf(float(ps["relleno"]), 0.0, 1.0) * (v - shell)

## Centro de masa en el espacio de la pieza (el de la malla si es importada y estanca).
func com_local() -> Vector3:
	if PartLibrary.has_mesh_mass(def):
		return def["_masa"]["centroide"]
	return Vector3.ZERO

## Inercia diagonal (kg·m²) respecto al centro de masa, en los ejes de la pieza, para
## piezas importadas con malla estanca. Vector3.ZERO = la calcula el motor por la forma.
## Los productos de inercia de la malla no se usan (el motor solo admite la diagonal).
func inertia_local() -> Vector3:
	if not PartLibrary.has_mesh_mass(def):
		return Vector3.ZERO
	var v := PartLibrary.volume_m3(def)
	var rho_eff := mass_kg() / v if v > 0.0 else 0.0
	var it: Array = def["_masa"]["inercia"]
	return Vector3(float(it[0]), float(it[1]), float(it[2])) * rho_eff

func friction() -> float:
	return MaterialLibrary.friction(material_id)

func restitution() -> float:
	return MaterialLibrary.restitution(material_id)

## Crea la forma de colisión que corresponde a la geometría de la pieza.
func make_collision_shape() -> Shape3D:
	var forma: String = def.get("forma", "caja")
	if forma == "engranaje":
		return _gear_collision_shape()
	if forma == "esfera":
		var ss := SphereShape3D.new()
		ss.radius = float(def.get("dimensiones_mm", {}).get("radio", 10.0)) / 1000.0
		return ss
	if forma == "cilindro" or forma == "tubo":
		var d: Dictionary = def.get("dimensiones_mm", {})
		var s := CylinderShape3D.new()
		s.radius = float(d.get("radio", 10.0)) / 1000.0
		s.height = float(d.get("altura", 100.0)) / 1000.0
		return s
	var s2 := BoxShape3D.new()
	s2.size = PartLibrary.dims_m(def)
	return s2

## Colisión de una pieza importada: "caja" (envolvente), "convexa" (un casco) o
## "multiple" (varias piezas convexas que conservan los huecos; por defecto).
const COLLISION_MODES := ["multiple", "convexa", "caja"]

func collision_mode() -> String:
	var m := str(estado.get("colision", "multiple"))
	return m if m in COLLISION_MODES else "multiple"

## Formas de colisión de la pieza para el simulador: [{shape, xf}] en el espacio de
## la pieza. Las primitivas dan una sola forma; las importadas, según collision_mode().
func make_collision_shapes() -> Array:
	if def.get("forma", "") == "custom" and def.has("_mesh") and collision_mode() != "caja":
		var out := []
		for pts in MeshImporter.convex_hulls(def, collision_mode() == "multiple"):
			if (pts as PackedVector3Array).size() >= 4:
				var cs := ConvexPolygonShape3D.new()
				cs.points = pts
				out.append({"shape": cs, "xf": Transform3D.IDENTITY})
		if not out.is_empty():
			return out
	return [{"shape": make_collision_shape(), "xf": Transform3D.IDENTITY}]

## Crea una MeshInstance3D independiente con la misma malla y material,
## para usarla en el cuerpo rígido durante la simulación.
func make_visual_clone() -> Node3D:
	var detail := PartVisuals.build(def)
	if detail:
		return detail
	return _make_mesh_node()

## Reconstruye la malla/colisión tras cambiar dimensiones o material.
func rebuild() -> void:
	_build_visual()
	if _selected and _selection_box:
		_selection_box.queue_free()
		_selection_box = _make_selection_box()
		add_child(_selection_box)

## Activa/desactiva el cuerpo de selección (se apaga durante la simulación).
func set_pick_enabled(value: bool) -> void:
	if _pick_body:
		_pick_body.collision_layer = PICK_LAYER if value else 0

func set_selected(value: bool) -> void:
	_selected = value
	if value and _selection_box == null:
		_selection_box = _make_selection_box()
		add_child(_selection_box)
	elif not value and _selection_box:
		_selection_box.queue_free()
		_selection_box = null

var _highlight_box: MeshInstance3D

## Resaltado cian (piezas de la unión seleccionada), distinto de la selección.
func set_highlight(on: bool) -> void:
	if on and _highlight_box == null:
		var box := BoxMesh.new()
		box.size = PartLibrary.dims_m(def) * 1.08
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.2, 0.9, 1.0, 0.16)
		m.emission_enabled = true
		m.emission = Color(0.2, 0.9, 1.0)
		m.emission_energy_multiplier = 0.9
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		_highlight_box = MeshInstance3D.new()
		_highlight_box.mesh = box
		_highlight_box.material_override = m
		add_child(_highlight_box)
	elif not on and _highlight_box:
		_highlight_box.queue_free()
		_highlight_box = null

func is_selected() -> bool:
	return _selected

func _make_selection_box() -> MeshInstance3D:
	var aabb := PartLibrary.dims_m(def)
	var box := BoxMesh.new()
	box.size = aabb * 1.04
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.96, 0.65, 0.14, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.65, 0.14)
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	return mi

## Serializa la pieza a un diccionario (para guardado JSON).
func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"def_id": def_id,
		"material": material_id,
		"pos": [position.x, position.y, position.z],
		"rot": [rotation.x, rotation.y, rotation.z],
		"dims_mm": def.get("dimensiones_mm", {}),
		"fijo": anchored,
	}.merged({"import_path": def["_source"]} if def.has("_source") else {}) 		.merged({"insertado": {"placa": inserted_in, "pines": pin_map.duplicate()}} if inserted_in != "" else {}) 		.merged({"estado": estado.duplicate(true)} if not estado.is_empty() else {})

## Restaura inserción y estado guardados (to_dict).
func apply_saved(d: Dictionary) -> void:
	var ins = d.get("insertado", null)
	if typeof(ins) == TYPE_DICTIONARY:
		inserted_in = str(ins.get("placa", ""))
		pin_map = (ins.get("pines", {}) as Dictionary).duplicate()
	var st = d.get("estado", null)
	if typeof(st) == TYPE_DICTIONARY:
		estado = (st as Dictionary).duplicate(true)
