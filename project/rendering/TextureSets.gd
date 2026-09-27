class_name TextureSets
extends RefCounted
## TextureSets — Materiales PBR a partir de texturas fotográficas reales.
##
## Las texturas están en res://assets/textures/<Id>/ (ambientCG, licencia CC0):
##   <Id>_<res>-JPG_Color.jpg, _NormalGL.jpg, _Roughness.jpg y, si es metal, _Metalness.jpg
## material() crea (y cachea) un StandardMaterial3D con mapeo triplanar en el espacio
## local de la pieza (la textura mantiene su tamaño real en metros) y un tinte,
## de modo que un mismo juego sirve para plástico negro, azul o blanco.
## Si el juego no existe devuelve null (se usa entonces el material procedural).

const DIR := "res://assets/textures"
const RESOLUTIONS := ["1K", "2K", "4K"]

static var _cache: Dictionary = {}
static var _tex: Dictionary = {}

## Opciones: tint (Color), scale (repeticiones por metro), rough (multiplicador),
## metallic (-1 = usar el mapa; 0..1 = valor fijo), normal (intensidad), clearcoat.
static func material(id: String, opts: Dictionary = {}) -> StandardMaterial3D:
	var key := id + JSON.stringify(opts)
	if _cache.has(key):
		return _cache[key]
	var col := _texture(id, "Color")
	if col == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = col
	m.albedo_color = opts.get("tint", Color.WHITE)
	var rough := _texture(id, "Roughness")
	if rough:
		m.roughness_texture = rough
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = float(opts.get("rough", 1.0))
	var nrm := _texture(id, "NormalGL")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = float(opts.get("normal", 1.0))
	var met := float(opts.get("metallic", -1.0))
	var metal_tex := _texture(id, "Metalness")
	if met < 0.0 and metal_tex:
		m.metallic_texture = metal_tex
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.metallic = 1.0
	else:
		m.metallic = maxf(met, 0.0)
	m.metallic_specular = 0.5
	if opts.has("clearcoat"):
		m.clearcoat_enabled = true
		m.clearcoat = float(opts["clearcoat"])
		m.clearcoat_roughness = 0.15
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * float(opts.get("scale", 10.0))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

static func has_set(id: String) -> bool:
	return _texture(id, "Color") != null

## Textura suelta de un juego (p. ej. para shaders propios).
static func texture(id: String, map: String) -> Texture2D:
	return _texture(id, map)

static func _texture(id: String, map: String) -> Texture2D:
	var key := id + ":" + map
	if _tex.has(key):
		return _tex[key]
	var t: Texture2D = null
	for r in RESOLUTIONS:
		var path := "%s/%s/%s_%s-JPG_%s.jpg" % [DIR, id, id, r, map]
		if ResourceLoader.exists(path):
			t = load(path)
			break
	_tex[key] = t
	return t
