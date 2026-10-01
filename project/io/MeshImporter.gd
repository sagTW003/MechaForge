class_name MeshImporter
extends RefCounted
## MeshImporter — Carga mallas externas en tiempo de ejecución.
##
## Soporta GLTF/GLB (vía GLTFDocument), OBJ y STL (parsers propios). Devuelve un
## Mesh listo para usar como pieza personalizada. Unidades: se asume que el
## archivo está en metros; MechaForge reescala si es enorme.
##
## Física de la pieza importada:
##   - Masa real: volumen, centroide e inercia de la propia malla (core/MeshMass.cs,
##     teorema de la divergencia) en def["_masa"]. Solo vale si la malla es estanca
##     ("cerrada"); si no, la pieza usa la caja envolvente como antes.
##   - Colisión: casco convexo o descomposición en varias piezas convexas (V-HACD),
##     que conserva las cavidades (una carcasa hueca, el alojamiento de una lente).

## Cascos convexos ya calculados (la descomposición tarda): clave -> Array.
static var _hull_cache: Dictionary = {}

## Definición de pieza personalizada a partir de un archivo 3D (autoescala a
## metros). Guarda la ruta de origen para volver a importarla al abrir el proyecto.
static func make_part_def(path: String) -> Dictionary:
	var mesh := load_mesh(path)
	if mesh == null:
		return {}
	var aabb := mesh.get_aabb()
	var maxd := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var scale := 1.0
	if maxd > 2.0:
		scale = 0.001            # probablemente en milímetros
	elif maxd < 0.005 and maxd > 0.0:
		scale = 0.05 / maxd
	var dim := aabb.size * scale
	var def := {
		"id": "import_%s" % path.md5_text().substr(0, 8),
		"nombre": path.get_file().get_basename(),
		"categoria": "importado", "material": "aluminio", "forma": "custom",
		"_mesh": mesh, "_scale": scale, "_offset": -aabb.get_center() * scale, "_source": path,
		"dimensiones_mm": {"x": dim.x * 1000.0, "y": dim.y * 1000.0, "z": dim.z * 1000.0},
	}
	def["_masa"] = mass_properties(def)
	return def

## Triángulos de la malla de una pieza importada, en metros y en el espacio de la
## pieza (escala y centrado aplicados): 3 vértices por triángulo.
static func triangles(def: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: Mesh = def.get("_mesh")
	if mesh == null:
		return out
	var sc := float(def.get("_scale", 1.0))
	var off: Vector3 = def.get("_offset", Vector3.ZERO)
	for s in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			for i in (idx as PackedInt32Array):
				out.append(v[i] * sc + off)
		else:
			for p in v:
				out.append(p * sc + off)
	return out

## Volumen (m³), área (m²), centroide (m, espacio de la pieza), inercia por unidad
## de densidad respecto al centroide [Ixx, Iyy, Izz, Ixy, Ixz, Iyz] y si es estanca.
static func mass_properties(def: Dictionary) -> Dictionary:
	var tris := triangles(def)
	var scr = load("res://core/MeshMass.cs")
	if tris.is_empty() or scr == null:
		return {"volumen": 0.0, "area": 0.0, "centroide": Vector3.ZERO, "inercia": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "cerrada": false, "triangulos": 0}
	var mm = scr.new()
	var r: Dictionary = mm.Compute(tris)
	return r

## Formas de colisión convexas de una pieza importada, en el espacio de la pieza:
## lista de nubes de puntos (PackedVector3Array). "multiple" = descomposición V-HACD
## (varias piezas, respeta huecos); si no, un único casco convexo.
static func convex_hulls(def: Dictionary, multiple: bool) -> Array:
	var mesh: Mesh = def.get("_mesh")
	if mesh == null:
		return []
	# La clave es la propia malla: al reimportar el archivo se vuelve a calcular.
	var key := "%d|%s|%s" % [mesh.get_instance_id(), str(def.get("_scale", 1.0)), "m" if multiple else "1"]
	if _hull_cache.has(key):
		return _hull_cache[key]
	var sc := float(def.get("_scale", 1.0))
	var off: Vector3 = def.get("_offset", Vector3.ZERO)
	var out := []
	if multiple:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var cs := MeshConvexDecompositionSettings.new()
		cs.max_convex_hulls = 32
		cs.max_concavity = 0.001
		cs.resolution = 100000
		mi.create_multiple_convex_collisions(cs)
		for body in mi.get_children():
			for c in body.get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
					var pts: PackedVector3Array = ((c as CollisionShape3D).shape as ConvexPolygonShape3D).points
					out.append(_to_part(pts, (c as CollisionShape3D).transform, sc, off))
		mi.free()
	else:
		var sh := mesh.create_convex_shape(true, false)
		if sh:
			out.append(_to_part(sh.points, Transform3D.IDENTITY, sc, off))
	_hull_cache[key] = out
	return out

static func _to_part(pts: PackedVector3Array, xf: Transform3D, sc: float, off: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in range(pts.size()):
		out[i] = (xf * pts[i]) * sc + off
	return out

## Carga un archivo 3D y devuelve un Mesh, o null si falla.
static func load_mesh(path: String) -> Mesh:
	match path.get_extension().to_lower():
		"glb", "gltf": return _load_gltf(path)
		"obj": return _load_obj(path)
		"stl": return _load_stl(path)
		_: return null

static func _load_gltf(path: String) -> Mesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		return null
	var mi := _find_mesh(scene)
	var m: Mesh = mi.mesh if mi else null
	scene.queue_free()
	return m

static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null

static func _load_obj(path: String) -> Mesh:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var verts: Array[Vector3] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in txt.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 0:
			continue
		if parts[0] == "v" and parts.size() >= 4:
			verts.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
		elif parts[0] == "f" and parts.size() >= 4:
			var idx := []
			for k in range(1, parts.size()):
				var tok := parts[k].split("/")[0]
				var vi := int(tok)
				if vi < 0:
					vi = verts.size() + vi
				else:
					vi -= 1
				if vi >= 0 and vi < verts.size():
					idx.append(vi)
			# Triangula en abanico. OBJ y STL definen la cara frontal en sentido
			# antihorario y Godot en horario: se invierte el orden (si no, la pieza se
			# ve del revés, con las caras ocultas y la luz al contrario).
			for t in range(1, idx.size() - 1):
				st.add_vertex(verts[idx[0]])
				st.add_vertex(verts[idx[t + 1]])
				st.add_vertex(verts[idx[t]])
	st.generate_normals()
	return st.commit()

static func _load_stl(path: String) -> Mesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var size := f.get_length()
	# Detecta ASCII (empieza por "solid" y no parece binario).
	var head := f.get_buffer(5).get_string_from_ascii()
	f.seek(0)
	if head == "solid" and size < 84 + 50:
		return _load_stl_ascii(f)
	# Comprueba tamaño binario: 84 + 50*n.
	f.seek(80)
	var n := f.get_32()
	if size == 84 + 50 * n:
		return _load_stl_binary(f, n)
	f.seek(0)
	return _load_stl_ascii(f)

static func _load_stl_binary(f: FileAccess, n: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		f.get_float(); f.get_float(); f.get_float()  # normal (ignorada)
		var vs := []
		for k in range(3):
			vs.append(Vector3(f.get_float(), f.get_float(), f.get_float()))
		f.get_16()  # attribute byte count
		for k in [0, 2, 1]:      # antihorario (STL) → horario (Godot)
			st.add_vertex(vs[k])
	st.generate_normals()
	f.close()
	return st.commit()

static func _load_stl_ascii(f: FileAccess) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var tri := []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("vertex"):
			var p := line.split(" ", false)
			if p.size() >= 4:
				tri.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
				count += 1
				if tri.size() == 3:
					for k in [0, 2, 1]:      # antihorario (STL) → horario (Godot)
						st.add_vertex(tri[k])
					tri.clear()
	f.close()
	if count < 3:
		return null
	st.generate_normals()
	return st.commit()
