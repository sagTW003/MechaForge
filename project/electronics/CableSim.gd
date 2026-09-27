class_name CableSim
extends RefCounted
## CableSim — Física de cables: cuerda Verlet con gravedad, longitud fija y colisiones.
##
## El cable se modela como una cadena de N puntos con distancia de reposo fija
## (longitud = distancia × holgura). Con los extremos anclados a los terminales,
## la gravedad produce la curva natural (catenaria) y cada punto se expulsa de las
## piezas sólidas (cajas orientadas) y del suelo, de modo que el cable no atraviesa
## componentes. Los extremos salen verticales del conector (como un Dupont real).
## El resultado se suaviza con Catmull-Rom para construir el tubo.

const RADIUS := 0.0016

## Obstáculo: {"xf": Transform3D, "half": Vector3}. Devuelve los puntos del cable.
static func solve(p1: Vector3, p2: Vector3, obstacles: Array, slack: float = 1.15, segs: int = 22, iters: int = 80) -> PackedVector3Array:
	var lead := 0.006                      # tramo vertical saliendo del conector
	var a := p1 + Vector3.UP * lead
	var b := p2 + Vector3.UP * lead
	var span := a.distance_to(b)
	var length := maxf(span * slack, span + 0.01)
	var rest := length / segs
	var pts := PackedVector3Array()
	var prev := PackedVector3Array()
	# Estimación inicial: parábola con caída.
	var sag := sqrt(maxf(0.0, length * length - span * span)) * 0.5
	for i in range(segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
		prev.append(p)
	var grav := Vector3(0, -rest * 0.08, 0)
	# Obstáculos cercanos (filtro por caja envolvente del cable).
	var bounds := AABB(a, Vector3.ZERO).expand(b)
	bounds = bounds.grow(maxf(0.02, sag * 2.0 + 0.02))
	bounds.position.y -= sag * 2.0
	bounds.size.y += sag * 2.0
	var near := []
	for o in obstacles:
		var xf: Transform3D = o["xf"]
		var h: Vector3 = o["half"]
		var r := h.length()
		if bounds.grow(r).has_point(xf.origin):
			near.append({"inv": xf.affine_inverse(), "xf": xf, "half": h + Vector3.ONE * RADIUS})
	for it in range(iters):
		# Integración (Verlet con amortiguamiento).
		for i in range(1, segs):
			var p := pts[i]
			var v := (p - prev[i]) * 0.92
			prev[i] = p
			pts[i] = p + v + grav
		# Restricciones de longitud (varias pasadas) con extremos fijos.
		for _k in range(3):
			pts[0] = a
			pts[segs] = b
			for i in range(segs):
				var d := pts[i + 1] - pts[i]
				var dl := d.length()
				if dl < 1e-9:
					continue
				var corr := d * (1.0 - rest / dl) * 0.5
				if i == 0:
					pts[i + 1] -= corr * 2.0
				elif i + 1 == segs:
					pts[i] += corr * 2.0
				else:
					pts[i] += corr
					pts[i + 1] -= corr
		# Colisiones: suelo y piezas (salvo el primer/último tramo, que nace en el terminal).
		for i in range(1, segs):
			var p := pts[i]
			if p.y < RADIUS:
				p.y = RADIUS
			if i > 1 and i < segs - 1:
				for o in near:
					p = _push_out(p, o)
			pts[i] = p
	pts[0] = a
	pts[segs] = b
	# Relajación (Laplaciano): quita el zigzag del cable apoyado sobre superficies,
	# volviendo a respetar suelo y piezas tras cada pasada.
	for _pass in range(4):
		var prevp := pts.duplicate()
		for i in range(2, segs - 1):
			var q := prevp[i] * 0.5 + (prevp[i - 1] + prevp[i + 1]) * 0.25
			q.y = maxf(q.y, RADIUS)
			for o in near:
				q = _push_out(q, o)
			pts[i] = q
	# Añade los puntos del conector y suaviza.
	var raw := PackedVector3Array()
	raw.append(p1)
	raw.append_array(pts)
	raw.append(p2)
	var smooth := _catmull(raw, 3)
	# El suavizado puede recortar esquinas: se vuelve a expulsar (salvo los extremos).
	for i in range(6, smooth.size() - 6):
		var p := smooth[i]
		for o in near:
			p = _push_out(p, o)
		p.y = maxf(p.y, RADIUS)
		smooth[i] = p
	return smooth

## Expulsa un punto del interior de una caja orientada hacia la cara más cercana.
static func _push_out(p: Vector3, o: Dictionary) -> Vector3:
	var inv: Transform3D = o["inv"]
	var h: Vector3 = o["half"]
	var lp := inv * p
	if absf(lp.x) >= h.x or absf(lp.y) >= h.y or absf(lp.z) >= h.z:
		return p
	var dx := h.x - absf(lp.x)
	var dy := h.y - absf(lp.y)
	var dz := h.z - absf(lp.z)
	# Preferencia hacia arriba: los cables descansan sobre las piezas.
	if lp.y >= 0.0 and dy <= minf(dx, dz) * 2.0:
		lp.y = h.y
	elif dy <= dx and dy <= dz:
		lp.y = -h.y if lp.y < 0.0 else h.y
	elif dx <= dz:
		lp.x = h.x if lp.x >= 0.0 else -h.x
	else:
		lp.z = h.z if lp.z >= 0.0 else -h.z
	return (o["xf"] as Transform3D) * lp

## Subdivisión Catmull-Rom (curva suave que pasa por todos los puntos).
static func _catmull(pts: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in range(n - 1):
		var p0 := pts[maxi(0, i - 1)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(n - 1, i + 2)]
		for s in range(sub):
			var t := float(s) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out

## Longitud de una polilínea (para informar de la longitud del cable).
static func polyline_length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(pts.size() - 1):
		l += pts[i].distance_to(pts[i + 1])
	return l
