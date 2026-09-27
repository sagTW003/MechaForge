class_name MeshImporter
extends RefCounted
## MeshImporter — Carga mallas externas en tiempo de ejecución.
##
## Soporta GLTF/GLB (vía GLTFDocument), OBJ y STL (parsers propios). Devuelve un
## Mesh listo para usar como pieza personalizada. Unidades: se asume que el
## archivo está en metros; MechaForge reescala si es enorme.

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
	return {
		"id": "import_%s" % path.md5_text().substr(0, 8),
		"nombre": path.get_file().get_basename(),
		"categoria": "importado", "material": "aluminio", "forma": "custom",
		"_mesh": mesh, "_scale": scale, "_offset": -aabb.get_center() * scale, "_source": path,
		"dimensiones_mm": {"x": dim.x * 1000.0, "y": dim.y * 1000.0, "z": dim.z * 1000.0},
	}

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
			# Triangula en abanico.
			for t in range(1, idx.size() - 1):
				st.add_vertex(verts[idx[0]])
				st.add_vertex(verts[idx[t]])
				st.add_vertex(verts[idx[t + 1]])
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
		for v in vs:
			st.add_vertex(v)
	st.generate_normals()
	f.close()
	return st.commit()

static func _load_stl_ascii(f: FileAccess) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("vertex"):
			var p := line.split(" ", false)
			if p.size() >= 4:
				st.add_vertex(Vector3(float(p[1]), float(p[2]), float(p[3])))
				count += 1
	f.close()
	if count < 3:
		return null
	st.generate_normals()
	return st.commit()
