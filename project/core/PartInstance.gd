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
	name = "Part_%s" % uid
	_build_visual()

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
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.mesh = _make_mesh()
		_mesh_instance.material_override = MaterialLibrary.get_visual(material_id)
		add_child(_mesh_instance)
	_build_pick_body()

## Cuerpo estático solo para selección con el ratón (raycast físico).
func _build_pick_body() -> void:
	if _pick_body:
		_pick_body.queue_free()
	_pick_body = StaticBody3D.new()
	_pick_body.collision_layer = PICK_LAYER
	_pick_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var forma: String = def.get("forma", "caja")
	if forma == "cilindro" or forma == "tubo":
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
	match forma:
		"cilindro", "tubo":
			var d: Dictionary = def.get("dimensiones_mm", {})
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = h
			cyl.radial_segments = 24
			return cyl
		_:
			var box := BoxMesh.new()
			box.size = PartLibrary.dims_m(def)
			return box

## Masa en kg = densidad(material) * volumen.
func mass_kg() -> float:
	return MaterialLibrary.density(material_id) * PartLibrary.volume_m3(def)

func friction() -> float:
	return MaterialLibrary.friction(material_id)

func restitution() -> float:
	return MaterialLibrary.restitution(material_id)

## Crea la forma de colisión que corresponde a la geometría de la pieza.
func make_collision_shape() -> Shape3D:
	var forma: String = def.get("forma", "caja")
	if forma == "cilindro" or forma == "tubo":
		var d: Dictionary = def.get("dimensiones_mm", {})
		var s := CylinderShape3D.new()
		s.radius = float(d.get("radio", 10.0)) / 1000.0
		s.height = float(d.get("altura", 100.0)) / 1000.0
		return s
	var s2 := BoxShape3D.new()
	s2.size = PartLibrary.dims_m(def)
	return s2

## Crea una MeshInstance3D independiente con la misma malla y material,
## para usarla en el cuerpo rígido durante la simulación.
func make_visual_clone() -> Node3D:
	var detail := PartVisuals.build(def)
	if detail:
		return detail
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh()
	mi.material_override = MaterialLibrary.get_visual(material_id)
	return mi

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
	}
