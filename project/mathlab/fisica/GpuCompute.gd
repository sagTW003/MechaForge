class_name GpuCompute
extends RefCounted
## GpuCompute — Cálculo en la GPU con compute shaders de RenderingDevice.
##
## Un RenderingDevice local por instancia. Los kernels son .glsl con «#[compute]», que
## Godot importa como RDShaderFile. Sin RenderingDevice (sin ventana o con el
## renderizador Compatibility) create() devuelve null y el módulo usa la referencia en
## C# (autoload Fisica). Los RIDs se liberan con liberar() o al soltar el objeto.

var rd: RenderingDevice
var _rids: Array[RID] = []          # en orden de creación; se liberan al revés
var _kernels := {}                  # ruta → {shader, pipeline}

## null si no hay RenderingDevice.
static func create() -> GpuCompute:
	var dev := RenderingServer.create_local_rendering_device()
	if dev == null:
		return null
	var g := GpuCompute.new()
	g.rd = dev
	return g

func device_name() -> String:
	return rd.get_device_name()

## Shader y pipeline de un kernel (se compilan una vez por instancia).
func kernel(path: String) -> Dictionary:
	if not _kernels.has(path):
		var file: RDShaderFile = load(path)
		var sh := rd.shader_create_from_spirv(file.get_spirv())
		var k := {"shader": sh, "pipeline": rd.compute_pipeline_create(sh)}
		_rids.append(sh)
		_rids.append(k["pipeline"])
		_kernels[path] = k
	return _kernels[path]

func buffer(bytes: PackedByteArray) -> RID:
	var b := rd.storage_buffer_create(bytes.size(), bytes)
	_rids.append(b)
	return b

func write(b: RID, bytes: PackedByteArray) -> void:
	rd.buffer_update(b, 0, bytes.size(), bytes)

func read(b: RID) -> PackedByteArray:
	return rd.buffer_get_data(b)

## Ejecuta el kernel con los buffers en los bindings 0, 1, … del set 0 y espera.
func run(k: Dictionary, buffers: Array, push: PackedByteArray, groups_x: int) -> void:
	var uniforms := []
	for i in buffers.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buffers[i])
		uniforms.append(u)
	var us := rd.uniform_set_create(uniforms, k["shader"], 0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, k["pipeline"])
	rd.compute_list_bind_uniform_set(cl, us, 0)
	if not push.is_empty():
		rd.compute_list_set_push_constant(cl, push, push.size())
	rd.compute_list_dispatch(cl, groups_x, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(us)

func liberar() -> void:
	if rd == null:
		return
	_release(rd, _rids)
	_rids.clear()
	_kernels.clear()
	rd = null

## Un RenderingDevice no es RefCounted: si nadie llama a liberar(), se libera aquí.
## Con una función estática: al borrar un RefCounted, «self» ya es nulo y no se le
## pueden llamar métodos.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		_release(rd, _rids)

static func _release(dev: RenderingDevice, rids: Array[RID]) -> void:
	for i in range(rids.size() - 1, -1, -1):
		dev.free_rid(rids[i])
	dev.free()

## Fuerzas de Coulomb en la GPU (kernels/coulomb.glsl). p = [x, y, z, q] por carga.
func coulomb(p: PackedFloat32Array, eps2: float) -> PackedFloat32Array:
	var n := p.size() / 4
	var bp := buffer(p.to_byte_array())
	var zeros := PackedByteArray()
	zeros.resize(p.size() * 4)
	var bf := buffer(zeros)
	var push := PackedByteArray()
	push.resize(8)
	push.encode_u32(0, n)
	push.encode_float(4, eps2)
	run(kernel("res://mathlab/fisica/kernels/coulomb.glsl"), [bp, bf], push, ceili(n / 64.0))
	var out := read(bf).to_float32_array()
	_free_now([bp, bf])
	return out

func _free_now(rids: Array) -> void:
	for r in rids:
		rd.free_rid(r)
		_rids.erase(r)
