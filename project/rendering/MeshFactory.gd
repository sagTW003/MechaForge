class_name MeshFactory
extends RefCounted
## MeshFactory — Mallas procedurales realistas para las piezas.
##
## - chamfer_box: caja con aristas achaflanadas (las aristas captan la luz como
##   una pieza mecanizada real, en vez del borde "infinitamente afilado").
## - tslot_profile: perfil de aluminio estructural con ranuras en T (2020/4040).
## - tube: tubo hueco con espesor de pared.
## - gear: engranaje recto con dientes (módulo, nº de dientes) y cubo con agujero.
## - plate_holes: patrón de orificios pasantes (M5 cada 20 mm) para placas.
## - lens: lente biconvexa (casquetes esféricos) o Fresnel (anillos), eje Y.
## - boxes: varias cajas achaflanadas en una malla (carcasa, soporte de lentes).
## Las mallas se cachean por dimensiones: piezas iguales comparten la malla.

static var _cache: Dictionary = {}

## Añade un triángulo con normal plana orientado hacia "n" (Godot: horario = frente).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)

## Sin UV: los materiales usan mapeo triplanar, que calcula sus propias tangentes.
static func _finish(st: SurfaceTool) -> ArrayMesh:
	return st.commit()

#region CAJA ACHAFLANADA ----------------------------------------------------------

static func chamfer_box(size: Vector3, chamfer: float = -1.0) -> ArrayMesh:
	var e := chamfer
	if e < 0.0:
		e = clampf(minf(size.x, minf(size.y, size.z)) * 0.08, 0.0002, 0.0012)
	var key := "cb_%.5f_%.5f_%.5f_%.5f" % [size.x, size.y, size.z, e]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Caras principales (reducidas por el chaflán).
	for ax in range(3):
		for s: float in [-1.0, 1.0]:
			var u := (ax + 1) % 3
			var v := (ax + 2) % 3
			var n := Vector3.ZERO; n[ax] = s
			var pts := []
			for cu: float in [-1.0, 1.0]:
				for cv: float in [-1.0, 1.0]:
					var p := Vector3.ZERO
					p[ax] = s * h[ax]
					p[u] = cu * (h[u] - e)
					p[v] = cv * (h[v] - e)
					pts.append(p)
			_quad(st, pts[0], pts[1], pts[3], pts[2], n)
	# Chaflanes de las 12 aristas.
	for ax in range(3):            # eje a lo largo de la arista
		var u := (ax + 1) % 3
		var v := (ax + 2) % 3
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				var n := Vector3.ZERO; n[u] = su; n[v] = sv
				n = n.normalized()
				var q := []
				for sa: float in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[ax] = sa * (h[ax] - e); p1[u] = su * h[u]; p1[v] = sv * (h[v] - e)
					var p2 := Vector3.ZERO
					p2[ax] = sa * (h[ax] - e); p2[u] = su * (h[u] - e); p2[v] = sv * h[v]
					q.append(p1); q.append(p2)
				_quad(st, q[0], q[1], q[3], q[2], n)
	# Esquinas (triángulos).
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var a := Vector3(sx * h.x, sy * (h.y - e), sz * (h.z - e))
				var b := Vector3(sx * (h.x - e), sy * h.y, sz * (h.z - e))
				var c := Vector3(sx * (h.x - e), sy * (h.y - e), sz * h.z)
				_tri(st, a, b, c, Vector3(sx, sy, sz).normalized())
	var m := _finish(st)
	_cache[key] = m
	return m

#endregion

#region PERFIL CON RANURA EN T ------------------------------------------------------

## Contorno 2D (en el plano XZ) de un perfil cuadrado de lado "side" (m).
static func _tslot_outline(side: float) -> PackedVector2Array:
	var mm := 0.001
	var big := side > 0.03
	var slots := maxi(1, int(round(side / 0.02)))
	# Cotas de la ranura (serie 20 u 8 para 40x40).
	var o := (8.2 if big else 6.2) * mm       # apertura
	var lip := (2.2 if big else 1.8) * mm     # espesor del labio
	var w := (14.5 if big else 11.0) * mm     # ancho de la cavidad
	var d1 := (4.3 if big else 3.3) * mm      # profundidad hasta el inicio del trapecio
	var d2 := (8.0 if big else 6.1) * mm      # profundidad total
	var wb := (7.0 if big else 6.0) * mm      # ancho del fondo
	var hs := side * 0.5
	var out := PackedVector2Array()
	# Recorre los 4 lados; en cada lado, coordenada "t" a lo largo y "d" hacia dentro.
	var corners := [Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs), Vector2(-hs, -hs)]
	for sidx in range(4):
		var p0: Vector2 = corners[sidx]
		var p1: Vector2 = corners[(sidx + 1) % 4]
		var along := (p1 - p0).normalized()
		var inward := Vector2(-along.y, along.x)
		# Asegura que "inward" apunte al centro.
		if inward.dot(-p0) < 0.0:
			inward = -inward
		var mid := (p0 + p1) * 0.5
		out.append(p0)
		for k in range(slots):
			var off := (float(k) - (slots - 1) * 0.5) * (side / slots)
			var c := mid + along * off
			var prof := [
				Vector2(-o * 0.5, 0.0), Vector2(-o * 0.5, lip), Vector2(-w * 0.5, lip),
				Vector2(-w * 0.5, d1), Vector2(-wb * 0.5, d2), Vector2(wb * 0.5, d2),
				Vector2(w * 0.5, d1), Vector2(w * 0.5, lip), Vector2(o * 0.5, lip), Vector2(o * 0.5, 0.0),
			]
			for q in prof:
				out.append(c + along * q.x + inward * q.y)
	return out

## Perfil estructural: sección en T extruida a lo largo del eje más largo.
static func tslot_profile(size: Vector3) -> ArrayMesh:
	var key := "ts_%.5f_%.5f_%.5f" % [size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]
	# Eje de extrusión = dimensión mayor; la sección usa el lado menor de las otras.
	var ax := 1
	if size.x >= size.y and size.x >= size.z: ax = 0
	elif size.z >= size.y and size.z >= size.x: ax = 2
	var u := (ax + 1) % 3
	var v := (ax + 2) % 3
	var side := minf(size[u], size[v])
	var length := size[ax]
	var outline := _tslot_outline(side)
	var m := _extrude(outline, length, ax, u, v)
	_cache[key] = m
	return m

## Extruye un polígono 2D (coordenadas u,v) a lo largo del eje "ax".
static func _extrude(outline: PackedVector2Array, length: float, ax: int, u: int, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length * 0.5
	var ccw := _signed_area(outline) > 0.0
	var P := func(p2: Vector2, a: float) -> Vector3:
		var p := Vector3.ZERO
		p[u] = p2.x; p[v] = p2.y; p[ax] = a
		return p
	# Paredes laterales.
	for i in range(outline.size()):
		var a2: Vector2 = outline[i]
		var b2: Vector2 = outline[(i + 1) % outline.size()]
		var e := (b2 - a2)
		if e.length() < 1.0e-7:
			continue
		var n2 := Vector2(e.y, -e.x).normalized()
		if not ccw:
			n2 = -n2
		var n := Vector3.ZERO; n[u] = n2.x; n[v] = n2.y
		_quad(st, P.call(a2, -hl), P.call(b2, -hl), P.call(b2, hl), P.call(a2, hl), n)
	# Tapas.
	var idx := Geometry2D.triangulate_polygon(outline)
	for s: float in [-1.0, 1.0]:
		var n := Vector3.ZERO; n[ax] = s
		for t in range(0, idx.size(), 3):
			_tri(st, P.call(outline[idx[t]], s * hl), P.call(outline[idx[t + 1]], s * hl), P.call(outline[idx[t + 2]], s * hl), n)
	return _finish(st)

static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

#endregion

#region TUBO HUECO --------------------------------------------------------------------

static func tube(r_out: float, r_in: float, height: float, segs: int = 32) -> ArrayMesh:
	var key := "tb_%.5f_%.5f_%.5f" % [r_out, r_in, height]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hh := height * 0.5
	for i in range(segs):
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var dm := (d0 + d1).normalized()
		# Exterior e interior (normales suaves por segmento).
		_smooth_quad(st, d0 * r_out + Vector3.UP * -hh, d1 * r_out + Vector3.UP * -hh,
			d1 * r_out + Vector3.UP * hh, d0 * r_out + Vector3.UP * hh, d0, d1, dm)
		if r_in > 0.0:
			_smooth_quad(st, d0 * r_in + Vector3.UP * -hh, d1 * r_in + Vector3.UP * -hh,
				d1 * r_in + Vector3.UP * hh, d0 * r_in + Vector3.UP * hh, -d0, -d1, -dm)
		# Tapas anulares.
		for s: float in [-1.0, 1.0]:
			var y := Vector3.UP * s * hh
			if r_in > 0.0:
				_quad(st, d0 * r_in + y, d1 * r_in + y, d1 * r_out + y, d0 * r_out + y, Vector3.UP * s)
			else:
				_tri(st, y, d0 * r_out + y, d1 * r_out + y, Vector3.UP * s)
	var m := _finish(st)
	_cache[key] = m
	return m

## Quad con normales por vértice (superficies curvas). "dm" orienta el triángulo.
static func _smooth_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, dm: Vector3) -> void:
	var verts := [[a, na], [b, nb], [c, nb], [a, na], [c, nb], [d, na]]
	for t in [0, 3]:
		var p0: Vector3 = verts[t][0]
		var p1: Vector3 = verts[t + 1][0]
		var p2: Vector3 = verts[t + 2][0]
		var order := [t, t + 1, t + 2]
		if (p1 - p0).cross(p2 - p0).dot(dm) > 0.0:
			order = [t, t + 2, t + 1]
		for k in order:
			st.set_normal(verts[k][1])
			st.add_vertex(verts[k][0])

#endregion

#region ENGRANAJE -----------------------------------------------------------------------

## Engranaje recto: z dientes de módulo "module" (m), ancho "width" (m), eje Y.
static func gear(z: int, module: float, width: float, bore: float = 0.0) -> ArrayMesh:
	z = maxi(6, z)
	var key := "gr_%d_%.5f_%.5f_%.5f" % [z, module, width, bore]
	if _cache.has(key):
		return _cache[key]
	var rp := module * z * 0.5            # radio primitivo
	var ra := rp + module                 # radio de cabeza
	var rf := rp - 1.25 * module          # radio de pie
	var outline := PackedVector2Array()
	# Perfil de diente aproximado (flancos curvos por 3 puntos por lado).
	var pitch_ang := TAU / z
	for i in range(z):
		var a0 := pitch_ang * i
		var pts := [
			[rf, -0.30], [rf + (rp - rf) * 0.5, -0.24], [rp, -0.20], [rp + (ra - rp) * 0.6, -0.14], [ra, -0.10],
			[ra, 0.10], [rp + (ra - rp) * 0.6, 0.14], [rp, 0.20], [rf + (rp - rf) * 0.5, 0.24], [rf, 0.30],
		]
		for p in pts:
			var ang: float = a0 + float(p[1]) * pitch_ang
			outline.append(Vector2(cos(ang), sin(ang)) * float(p[0]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	# Flancos.
	for i in range(outline.size()):
		var a2: Vector2 = outline[i]
		var b2: Vector2 = outline[(i + 1) % outline.size()]
		var e := b2 - a2
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a2 + b2) * 0.5) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0, n2.y)
		_quad(st, Vector3(a2.x, -hw, a2.y), Vector3(b2.x, -hw, b2.y), Vector3(b2.x, hw, b2.y), Vector3(a2.x, hw, a2.y), n)
	# Caras (abanico desde el centro: el contorno es estrellado).
	for s: float in [-1.0, 1.0]:
		var y := s * hw
		for i in range(outline.size()):
			var a2: Vector2 = outline[i]
			var b2: Vector2 = outline[(i + 1) % outline.size()]
			_tri(st, Vector3(0, y, 0), Vector3(a2.x, y, a2.y), Vector3(b2.x, y, b2.y), Vector3.UP * s)
	var m := st.commit()
	# Cubo (hub) con agujero del eje.
	var hub_r := maxf(bore * 1.0, rf * 0.45)
	var hub_h := width * 1.6
	var bore_r := minf(bore * 0.5, hub_r * 0.7) if bore > 0.0 else hub_r * 0.35
	var hub := tube(hub_r, bore_r, hub_h, 28)
	var st2 := SurfaceTool.new()
	st2.create_from(m, 0)
	st2.append_from(hub, 0, Transform3D.IDENTITY)
	var merged := st2.commit()
	_cache[key] = merged
	return merged

#endregion

#region SOLDADURA ----------------------------------------------------------------------

## Menisco de soldadura: perfil cóncavo (tensión superficial) de radio de base R
## que sube abrazando un hilo de radio rw hasta la altura H. Base en y=0.
static func solder_fillet(R: float, rw: float, H: float, segs: int = 20, rows: int = 8) -> ArrayMesh:
	var key := "sf_%.5f_%.5f_%.5f" % [R, rw, H]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := []          # [radio, altura, normal2D]
	for j in range(rows + 1):
		var t := float(j) / rows
		var y := H * t
		var r := rw + (R - rw) * pow(1.0 - t, 2.0)
		var dr := -2.0 * (R - rw) * (1.0 - t) / H           # dr/dy
		var n2 := Vector2(1.0, -dr).normalized()             # (radial, vertical)
		prof.append([r, y, n2])
	# Casquete superior redondeado.
	prof.append([rw * 0.5, H + rw * 0.35, Vector2(0.5, 0.86)])
	prof.append([0.0, H + rw * 0.45, Vector2(0.0, 1.0)])
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for j in range(prof.size() - 1):
			var pa: Array = prof[j]
			var pb: Array = prof[j + 1]
			var v00 := d0 * float(pa[0]) + Vector3.UP * float(pa[1])
			var v10 := d1 * float(pa[0]) + Vector3.UP * float(pa[1])
			var v01 := d0 * float(pb[0]) + Vector3.UP * float(pb[1])
			var v11 := d1 * float(pb[0]) + Vector3.UP * float(pb[1])
			var na: Vector2 = pa[2]
			var nb: Vector2 = pb[2]
			var n00 := (d0 * na.x + Vector3.UP * na.y).normalized()
			var n10 := (d1 * na.x + Vector3.UP * na.y).normalized()
			var n01 := (d0 * nb.x + Vector3.UP * nb.y).normalized()
			var n11 := (d1 * nb.x + Vector3.UP * nb.y).normalized()
			var tris := [[v00, n00, v10, n10, v11, n11], [v00, n00, v11, n11, v01, n01]]
			for tr in tris:
				var A: Vector3 = tr[0]; var B: Vector3 = tr[2]; var C: Vector3 = tr[4]
				var nav: Vector3 = (tr[1] + tr[3] + tr[5]) as Vector3
				var order := [0, 2, 4]
				if (B - A).cross(C - A).dot(nav) > 0.0:
					order = [0, 4, 2]
				for o in order:
					st.set_normal(tr[o + 1])
					st.add_vertex(tr[o])
		# Base plana.
		_tri(st, Vector3.ZERO, d0 * R, d1 * R, Vector3.DOWN)
	var m := st.commit()
	_cache[key] = m
	return m

#endregion

#region ORIFICIOS DE PLACA -------------------------------------------------------------

## Posiciones (locales, m) de los orificios de una placa: rejilla de 20 mm.
static func plate_hole_positions(size: Vector3, pitch: float = 0.02) -> PackedVector3Array:
	var out := PackedVector3Array()
	var nx := int(floor((size.x - pitch * 0.5) / pitch))
	var nz := int(floor((size.z - pitch * 0.5) / pitch))
	if nx < 1 or nz < 1:
		return out
	for i in range(nx):
		for k in range(nz):
			var x := (float(i) - (nx - 1) * 0.5) * pitch
			var z := (float(k) - (nz - 1) * 0.5) * pitch
			out.append(Vector3(x, 0, z))
	return out

## Instancia múltiple de discos oscuros que simulan los orificios pasantes.
static func plate_holes(size: Vector3) -> MultiMeshInstance3D:
	var pos := plate_hole_positions(size)
	if pos.is_empty():
		return null
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0027
	cyl.bottom_radius = 0.0027
	cyl.height = size.y + 0.0004
	cyl.radial_segments = 16
	cyl.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.015, 0.015, 0.018)
	mat.roughness = 0.9
	cyl.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cyl
	mm.instance_count = pos.size()
	for i in range(pos.size()):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Orificios"
	mmi.multimesh = mm
	return mmi

#endregion

#region LENTES Y PIEZAS DE VARIAS CAJAS ---------------------------------------

## Lente de eje Y: biconvexa (radio de curvatura R, casquetes de altura h, canto
## "edge") o Fresnel (lámina de grosor "edge" con anillos en la cara superior).
static func lens(r: float, R: float, h: float, edge: float, fresnel: bool, segs: int = 48) -> ArrayMesh:
	var key := "ln_%.5f_%.5f_%.5f_%.5f_%s" % [r, R, h, edge, str(fresnel)]
	if _cache.has(key):
		return _cache[key]
	# Perfil (ρ, y) de la mitad superior como tramos [p0, n0, p1, n1] (normales 2D).
	var top := []
	var y0 := edge * 0.5
	if fresnel:
		var zones := 8
		var depth := minf(edge * 0.35, 0.0006)
		for k in range(zones):
			var r0 := r * k / zones
			var r1 := r * (k + 1) / zones
			var fn := Vector2(depth, r1 - r0).normalized()
			top.append([Vector2(r0, y0), fn, Vector2(r1, y0 - depth), fn])
			top.append([Vector2(r1, y0 - depth), Vector2(1, 0), Vector2(r1, y0), Vector2(1, 0)])
	else:
		var rings := 14
		var yc := y0 - (R - h)            # centro de la esfera del casquete superior
		var prev := Vector2(0.0, y0 + h)
		for i in range(1, rings + 1):
			var rho := r * float(i) / rings
			var p := Vector2(rho, yc + sqrt(maxf(0.0, R * R - rho * rho)))
			var n0 := Vector2(prev.x, prev.y - yc) / R
			var n1 := Vector2(p.x, p.y - yc) / R
			top.append([prev, n0, p, n1])
			prev = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sgn: float in [1.0, -1.0]:
		for sg in top:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[2]
			var na: Vector2 = sg[1]
			var nb: Vector2 = sg[3]
			if sgn < 0.0:
				if fresnel:
					continue        # cara inferior plana (abajo)
				a.y = -a.y; b.y = -b.y; na.y = -na.y; nb.y = -nb.y
			_lathe_band(st, a, na, b, nb, segs)
	if fresnel:
		_lathe_band(st, Vector2(0, -y0), Vector2(0, -1), Vector2(r, -y0), Vector2(0, -1), segs)
	# Canto.
	_lathe_band(st, Vector2(r, -y0), Vector2(1, 0), Vector2(r, y0), Vector2(1, 0), segs)
	var m := _finish(st)
	_cache[key] = m
	return m

## Superficie de revolución entre dos puntos del perfil (ρ, y) con sus normales.
static func _lathe_band(st: SurfaceTool, a: Vector2, na: Vector2, b: Vector2, nb: Vector2, segs: int) -> void:
	for i in range(segs):
		var t0 := TAU * float(i) / segs
		var t1 := TAU * float(i + 1) / segs
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		var p := [d0 * a.x + Vector3.UP * a.y, d1 * a.x + Vector3.UP * a.y, d1 * b.x + Vector3.UP * b.y, d0 * b.x + Vector3.UP * b.y]
		var n := [(d0 * na.x + Vector3.UP * na.y).normalized(), (d1 * na.x + Vector3.UP * na.y).normalized(),
			(d1 * nb.x + Vector3.UP * nb.y).normalized(), (d0 * nb.x + Vector3.UP * nb.y).normalized()]
		var dm: Vector3 = (n[0] + n[1] + n[2] + n[3]).normalized()
		for tri in [[0, 1, 2], [0, 2, 3]]:
			var q0: Vector3 = p[tri[0]]
			var q1: Vector3 = p[tri[1]]
			var q2: Vector3 = p[tri[2]]
			if (q1 - q0).cross(q2 - q0).length_squared() < 1e-18:
				continue        # triángulo degenerado (en el eje)
			var order: Array = tri if (q1 - q0).cross(q2 - q0).dot(dm) <= 0.0 else [tri[0], tri[2], tri[1]]
			for k in order:
				st.set_normal(n[k])
				st.add_vertex(p[k])

## Varias cajas achaflanadas en una sola malla: [{c: centro, s: tamaño}] en metros.
static func boxes(list: Array) -> ArrayMesh:
	var sig := PackedStringArray()
	for b in list:
		sig.append("%s%s" % [str(b["c"]), str(b["s"])])
	var key := "bx_%d" % "|".join(sig).hash()
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in list:
		st.append_from(chamfer_box(b["s"]), 0, Transform3D(Basis.IDENTITY, b["c"]))
	var m := st.commit()
	_cache[key] = m
	return m

#endregion
