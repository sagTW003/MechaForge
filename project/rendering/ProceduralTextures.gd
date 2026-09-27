class_name ProceduralTextures
extends RefCounted
## ProceduralTextures — Texturas PBR procedurales (sin archivos externos).
##
## Genera, para cada "patrón" de material, tres mapas que se repiten sin costuras:
##   - albedo  (color con variaciones sutiles / dibujo del material)
##   - rough   (rugosidad por píxel: canal R)
##   - normal  (microrelieve derivado de un mapa de alturas)
## Patrones: cepillado (aluminio, inox), granallado (anodizado), laminado (acero),
## cobre oxidado, plástico, caucho, madera, concreto, fibra de carbono (sarga 2x2),
## PCB (máscara verde con pistas y vías), estaño y vidrio.
##
## generate() es puro (solo Image) y se puede ejecutar en un hilo de trabajo;
## MaterialLibrary crea las texturas en el hilo principal al terminar.

const SIZE := 256

## Repeticiones por metro (mapeo triplanar en espacio local de la pieza).
const SCALE := {
	"cepillado": 8.0, "granallado": 30.0, "laminado": 5.0, "cobre": 8.0,
	"plastico": 25.0, "caucho": 30.0, "madera": 4.0, "concreto": 3.0,
	"carbono": 50.0, "pcb": 20.0, "estano": 40.0, "vidrio": 5.0,
}

static func scale_for(pattern: String) -> float:
	return SCALE.get(pattern, 10.0)

## Genera {albedo: Image, rough: Image, normal: Image} para un patrón y color base.
static func generate(pattern: String, base: Color, base_rough: float, seed: int = 1) -> Dictionary:
	var n := SIZE
	var h := PackedFloat32Array(); h.resize(n * n)       # alturas 0..1
	var alb := PackedByteArray(); alb.resize(n * n * 3)
	var rgh := PackedByteArray(); rgh.resize(n * n)
	var fine := _noise(seed, 0.35, 3)
	var mid := _noise(seed + 7, 0.06, 4)
	var low := _noise(seed + 13, 0.015, 3)
	for y in range(n):
		for x in range(n):
			var i := y * n + x
			var c := base
			var r := base_rough
			var hv := 0.5
			match pattern:
				"cepillado", "cobre":
					# Estrías finas a lo largo de V (el largo de los perfiles).
					var s := _tile(fine, x * 3.0, y * 0.04, n * 3.0, n * 0.04)
					var s2 := _tile(mid, x * 1.5, y * 0.02, n * 1.5, n * 0.02)
					hv = 0.5 + s * 0.35 + s2 * 0.15
					c = base * (0.93 + s * 0.06 + s2 * 0.03)
					r = base_rough + s * 0.06 + s2 * 0.04
					if pattern == "cobre":
						# Oxidación en manchas: más oscuro/marrón y más rugoso.
						var ox := clampf(_tile(low, x, y, n, n) * 1.8 - 0.25, 0.0, 1.0)
						c = c.lerp(Color(0.42, 0.24, 0.15), ox * 0.55)
						r += ox * 0.25
				"granallado":
					var g := _tile(fine, x * 2.5, y * 2.5, n * 2.5, n * 2.5)
					hv = 0.5 + g * 0.5
					c = base * (0.96 + g * 0.05)
					r = base_rough + g * 0.05
				"laminado":
					# Acero: manchas de laminado + grano fino.
					var b := _tile(low, x, y, n, n)
					var g := _tile(fine, x * 2.0, y * 2.0, n * 2.0, n * 2.0)
					hv = 0.5 + g * 0.3 + b * 0.2
					c = base * (0.88 + b * 0.12 + g * 0.03)
					r = base_rough + b * 0.18 - 0.05 + g * 0.05
				"plastico", "caucho":
					var g := _tile(fine, x * 3.0, y * 3.0, n * 3.0, n * 3.0)
					var b := _tile(mid, x, y, n, n)
					hv = 0.5 + g * 0.5
					c = base * (0.97 + b * 0.04)
					r = base_rough + g * 0.05 + b * 0.04
				"concreto":
					var g := _tile(fine, x * 2.0, y * 2.0, n * 2.0, n * 2.0)
					var b := _tile(mid, x, y, n, n)
					var sp := 1.0 if _hash(x, y, seed) > 0.985 else 0.0
					hv = 0.5 + g * 0.35 + b * 0.25 - sp * 0.4
					c = base * (0.85 + b * 0.18 + g * 0.05 - sp * 0.3)
					r = clampf(base_rough + g * 0.05, 0.0, 1.0)
				"madera":
					# Vetas: anillos deformados por ruido, a lo largo de V.
					var warp := _tile(mid, x * 0.6, y * 0.08, n * 0.6, n * 0.08)
					var ring := 0.5 + 0.5 * sin((float(x) / n * 18.0 + warp * 3.0) * TAU)
					ring = pow(ring, 3.0)
					var g := _tile(fine, x * 3.0, y * 0.3, n * 3.0, n * 0.3)
					hv = 0.5 - ring * 0.3 + g * 0.1
					c = base.lerp(base * 0.62, ring) * (0.95 + g * 0.06)
					r = base_rough + ring * 0.08
				"carbono":
					var cc := _carbon(x, y, n, fine)
					hv = cc.x
					c = Color(0.035, 0.037, 0.042).lerp(Color(0.16, 0.165, 0.18), cc.y)
					r = 0.28 + (1.0 - cc.y) * 0.12
				"pcb":
					var pc := _pcb(x, y, n, seed)
					hv = pc.x
					match int(pc.y):
						1: c = base.lerp(Color(0.18, 0.55, 0.22), 0.55)       # pista bajo máscara
						2: c = Color(0.86, 0.68, 0.3)                          # vía/pad dorado
						3: c = Color(0.92, 0.93, 0.9)                          # serigrafía
						_: c = base * (0.95 + _tile(fine, x, y, n, n) * 0.06)
					r = 0.3 if int(pc.y) == 2 else base_rough
				"estano":
					var b := _tile(mid, x * 2.0, y * 2.0, n * 2.0, n * 2.0)
					hv = 0.5 + b * 0.5
					c = base * (0.95 + b * 0.06)
					r = base_rough + b * 0.08
				"vidrio":
					# Huellas/polvo muy sutiles solo en la rugosidad.
					var b := clampf(_tile(mid, x, y, n, n) * 2.0 - 0.6, 0.0, 1.0)
					hv = 0.5
					r = base_rough + b * 0.12
				_:
					pass
			h[i] = clampf(hv, 0.0, 1.0)
			alb[i * 3] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			alb[i * 3 + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			alb[i * 3 + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			rgh[i] = int(clampf(r, 0.02, 1.0) * 255.0)
	var hb := PackedByteArray(); hb.resize(n * n)
	for i in range(n * n):
		hb[i] = int(h[i] * 255.0)
	var albedo := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, alb)
	var rough := Image.create_from_data(n, n, false, Image.FORMAT_L8, rgh)
	var height := Image.create_from_data(n, n, false, Image.FORMAT_L8, hb)
	height.convert(Image.FORMAT_RGBA8)
	height.bump_map_to_normal_map(_bump_strength(pattern))
	albedo.generate_mipmaps()
	rough.generate_mipmaps()
	height.generate_mipmaps(true)
	return {"albedo": albedo, "rough": rough, "normal": height}

static func _bump_strength(pattern: String) -> float:
	match pattern:
		"carbono": return 3.0
		"pcb": return 4.0
		"madera": return 2.0
		"concreto": return 3.0
		"vidrio": return 0.1
		_: return 1.5

static func _noise(seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = octaves
	return fn

## Ruido repetible sin costuras: mezcla bilineal de 4 muestras desplazadas un
## periodo (w, h). Devuelve aproximadamente -1..1.
static func _tile(fn: FastNoiseLite, x: float, y: float, w: float, h: float) -> float:
	var u := fmod(x, w) / w
	var v := fmod(y, h) / h
	var a := fn.get_noise_2d(x, y)
	var b := fn.get_noise_2d(x - w, y)
	var c := fn.get_noise_2d(x, y - h)
	var d := fn.get_noise_2d(x - w, y - h)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)

static func _hash(x: int, y: int, seed: int) -> float:
	var k := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	k = (k ^ (k >> 13)) * 1274126177
	return float(k & 0xFFFF) / 65535.0

## Sarga 2x2 de fibra de carbono. Devuelve (altura, brillo de la fibra).
static func _carbon(x: int, y: int, n: int, fine: FastNoiseLite) -> Vector2:
	var tows := 8
	var cell := float(n) / tows
	var ci := int(x / cell)
	var cj := int(y / cell)
	var fu := fmod(float(x), cell) / cell
	var fv := fmod(float(y), cell) / cell
	var warp := ((ci + cj) % 4) < 2           # fibra a lo largo de V o de U
	var across := fu if warp else fv          # posición transversal dentro del haz
	var bulge := sin(across * PI)             # abombado del haz
	var streak := _tile(fine, (x if warp else y) * 4.0, (y if warp else x) * 0.15, n * 4.0, n * 0.15)
	var shine := clampf(0.25 + bulge * 0.55 + streak * 0.2, 0.0, 1.0)
	if not warp:
		shine *= 0.7                          # la trama refleja distinto (anisotropía)
	return Vector2(0.3 + bulge * 0.6, shine)

## Dibujo de PCB. Devuelve (altura, clase) — clase 0 máscara, 1 pista, 2 vía, 3 serigrafía.
static func _pcb(x: int, y: int, n: int, seed: int) -> Vector2:
	var grid := 16
	var gx := x % grid
	var gy := y % grid
	var cx := int(x / grid)
	var cy := int(y / grid)
	# Vías en algunos nodos de la rejilla.
	var dx := gx - grid / 2
	var dy := gy - grid / 2
	var d2 := dx * dx + dy * dy
	if _hash(cx, cy, seed + 3) > 0.8:
		if d2 <= 9:
			return Vector2(0.9, 2)
		if d2 <= 14:
			return Vector2(0.75, 1)
	# Pistas horizontales/verticales según la fila/columna.
	var hrow := _hash(cy, 0, seed + 11) > 0.55 and absi(dy) <= 1
	var vcol := _hash(cx, 1, seed + 17) > 0.6 and absi(dx) <= 1
	if hrow and _hash(cx, cy, seed + 5) > 0.25:
		return Vector2(0.7, 1)
	if vcol and _hash(cx, cy, seed + 9) > 0.35:
		return Vector2(0.7, 1)
	# Marcas de serigrafía ocasionales.
	if _hash(cx, cy, seed + 21) > 0.97 and (gx == 2 or gy == 2):
		return Vector2(0.55, 3)
	return Vector2(0.5, 0)
