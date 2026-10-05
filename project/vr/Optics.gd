class_name Optics
extends RefCounted
## Optics — Óptica del visor casero con el modelo de lente delgada.
##
## Con la pantalla a una distancia d de la lente, por dentro de su focal f (d < f),
## la lente forma una imagen virtual derecha a v = d·f/(f − d) por detrás de la
## pantalla, aumentada m = f/(f − d). El ojo, a e de la lente (eye relief), ve un
## punto de la pantalla que está a x del eje con un ángulo
##   tan θ = x·m/(v + e) = x·f / (d·f + e·(f − d))
## (si d = f la imagen está en el infinito y tan θ = x/f). El borde de la lente
## limita el campo a tan α = r/e. Con dos lentes cada ojo ve su mitad de pantalla
## (imagen lado a lado): la mitad derecha del espectador es la de −X de la pantalla
## (la pantalla mira a +Y; su +Z es arriba).
##
## Fuera del eje la lente no es ideal: con distorsión de cojín el ojo ve en la
## dirección D(t) = t·(1 + k1·|t|² + k2·|t|⁴) el punto que la lente delgada pondría en
## t (modelo radial de Cardboard, t en tangentes del ángulo). Y como el índice cambia
## con el color (número de Abbe V), la escala tan θ / x es algo mayor para el azul que
## para el rojo: aberración cromática lateral.

const EYE_RELIEF_MM := 15.0
const IPD_MIN_MM := 54.0
const IPD_MAX_MM := 74.0
const ABBE_DEFAULT := 57.0      # PMMA (acrílico)

## Tangente del ángulo con que el ojo ve un punto a x (m) del eje óptico.
static func view_tan(x: float, d: float, f: float, e: float) -> float:
	var den := d * f + e * (f - d)
	return x * f / den if den > 1e-12 else INF

## Escala de la lente ideal: tan θ = s·x (x en m sobre la pantalla).
static func tan_scale(d: float, f: float, e: float) -> float:
	return view_tan(1.0, d, f, e)

## Dirección (tangentes) con que el ojo ve el punto que la lente ideal pondría en t.
static func distort(t: Vector2, k1: float, k2: float) -> Vector2:
	var r2 := t.length_squared()
	return t * (1.0 + k1 * r2 + k2 * r2 * r2)

## Inversa de distort (radial, por Newton): qué t de la lente ideal acaba en te.
static func undistort(te: Vector2, k1: float, k2: float) -> Vector2:
	var re := te.length()
	if re < 1e-12:
		return te
	var r := re
	for i in range(40):
		var r2 := r * r
		var dr := (r * (1.0 + k1 * r2 + k2 * r2 * r2) - re) / (1.0 + 3.0 * k1 * r2 + 5.0 * k2 * r2 * r2)
		r -= dr
		if absf(dr) < 1e-13:
			break
	return te * (r / re)

## Aberración cromática lateral: cambio relativo δ de la escala s para el azul (F,
## 486 nm: s·(1 + δ)) y el rojo (C, 656 nm: s·(1 − δ)) respecto del verde. Con
## 1/f ∝ n − 1, Δf/f = ∓1/(2V); y d ln s / d ln f = −e·d / (d·f + e·(f − d)).
static func chroma_shift(d: float, f: float, e: float, abbe: float) -> float:
	var den := d * f + e * (f - d)
	return e * d / (den * 2.0 * abbe) if den > 1e-12 and abbe > 0.0 else 0.0

static func image_distance(d: float, f: float) -> float:
	return d * f / (f - d) if d < f else INF

static func magnification(d: float, f: float) -> float:
	return f / (f - d) if d < f else INF

static func eye_relief_m(lens: PartInstance) -> float:
	return float(lens.estado.get("ojo_mm", EYE_RELIEF_MM)) / 1000.0

## Analiza el visor de la escena: cada lente con la pantalla que corta su eje.
## xf (opcional) da la transformación de cada pieza (la de la simulación en vivo).
static func analyze(parts_root: Node, xf := Callable()) -> Dictionary:
	var gx := func(p: PartInstance) -> Transform3D: return xf.call(p) if xf.is_valid() else p.global_transform
	var screens := []
	var lenses := []
	for c in parts_root.get_children():
		if c is PartInstance:
			if (c as PartInstance).def.has("pantalla"):
				screens.append(c)
			if (c as PartInstance).def.has("optica"):
				lenses.append(c)
	if screens.is_empty() or lenses.is_empty():
		return {"ok": false, "motivo": "Hace falta una pantalla (o un móvil) y al menos una lente."}
	var avisos := []
	var hits := []
	for L in lenses:
		var lp := L as PartInstance
		var lx: Transform3D = gx.call(lp)
		var c := lx.origin
		var a := lx.basis.y.normalized()
		var best := {}
		for S in screens:
			var sp := S as PartInstance
			var sx: Transform3D = gx.call(sp)
			var sb := sx.basis
			var n := sb.y.normalized()
			var p0 := sx.origin + n * PartLibrary.dims_m(sp.def).y * 0.5
			var an := a.dot(n)
			var side := (c - p0).dot(n)
			if absf(an) < 0.5 or side <= 0.0:
				continue           # eje casi paralelo, o lente detrás de la pantalla
			var t := -side / an
			var hit := c + a * t
			var cand := {"screen": sp, "d": absf(t), "u": (hit - p0).dot(sb.x.normalized()), "w": (hit - p0).dot(sb.z.normalized())}
			if best.is_empty() or float(cand["d"]) < float(best["d"]):
				best = cand
		if best.is_empty():
			avisos.append("La lente «%s» no apunta a la cara de ninguna pantalla." % lp.def.get("nombre", lp.uid))
			continue
		best["lens"] = lp
		hits.append(best)
	if hits.is_empty():
		return {"ok": false, "motivo": avisos[0], "avisos": avisos}
	var scr: PartInstance = hits[0]["screen"]
	var info: Dictionary = scr.def.get("pantalla", {})
	var area: Array = info.get("area_mm", [100.0, 60.0])
	var res: Array = info.get("res", [1920, 1080])
	var aw := float(area[0]) / 1000.0
	var ah := float(area[1]) / 1000.0
	var same := hits.filter(func(h): return h["screen"] == scr)
	var stereo := same.size() >= 2
	var out_lenses := []
	for h in same:
		var lp: PartInstance = h["lens"]
		var lg := PartLibrary.lens_geometry(lp.def)
		var f: float = lg["f"]
		var r: float = lg["r"]
		var e := eye_relief_m(lp)
		var d: float = h["d"]
		var u: float = h["u"]
		var w: float = h["w"]
		# Mitad de pantalla de cada ojo (izquierda del espectador = +X de la pantalla).
		var lado := "única"
		var u0 := -aw / 2.0
		var u1 := aw / 2.0
		if stereo:
			lado = "izquierda" if u >= 0.0 else "derecha"
			u0 = 0.0 if u >= 0.0 else -aw / 2.0
			u1 = aw / 2.0 if u >= 0.0 else 0.0
		var x_out := maxf(0.0, (u1 - u) if u >= 0.0 else (u - u0))     # hacia la sien
		var x_in := maxf(0.0, (u - u0) if u >= 0.0 else (u1 - u))      # hacia la nariz
		var up := maxf(0.0, ah / 2.0 - w)
		var down := maxf(0.0, ah / 2.0 + w)
		var alpha := rad_to_deg(atan(r / e))
		var ang := func(x: float) -> float: return rad_to_deg(atan(view_tan(x, d, f, e)))
		var limited := float(ang.call(maxf(x_out, maxf(up, down)))) > alpha
		var fov_h := minf(ang.call(x_out), alpha) + minf(ang.call(x_in), alpha)
		var fov_v := minf(ang.call(up), alpha) + minf(ang.call(down), alpha)
		var px_mm := float(res[0]) / (aw * 1000.0)
		var mm_per_rad := (d * f + e * (f - d)) / f * 1000.0
		var enfocado := d < f
		var v := image_distance(d, f)
		var center := (u0 + u1) / 2.0
		var item := {
			"uid": lp.uid, "nombre": lp.def.get("nombre", ""), "lado": lado,
			"focal_mm": f * 1000.0, "diametro_mm": r * 2000.0, "distancia_mm": d * 1000.0, "ojo_mm": e * 1000.0,
			"enfocado": enfocado, "aumento": magnification(d, f),
			"imagen_m": (v + e) if enfocado else INF,
			"fov_h": fov_h, "fov_v": fov_v, "ppd": px_mm * mm_per_rad * PI / 180.0,
			"desalineacion_mm": (u - center) * 1000.0, "altura_mm": w * 1000.0, "limita_lente": limited,
			# En metros, para el render estéreo (HeadsetRig): corte del eje con la cara de
			# la pantalla (u, w en sus ejes X y Z), su mitad (u0..u1), distancias y lente.
			"u_m": u, "w_m": w, "u0_m": u0, "u1_m": u1, "d_m": d, "e_m": e, "f_m": f, "r_m": r,
			"k1": float(lp.def.get("optica", {}).get("k1", 0.0)), "k2": float(lp.def.get("optica", {}).get("k2", 0.0)),
			"abbe": float(lp.def.get("optica", {}).get("abbe", ABBE_DEFAULT)),
		}
		out_lenses.append(item)
		var nom := "La lente %s" % lado if stereo else "La lente"
		if not enfocado:
			avisos.append("%s está a %.1f mm de la pantalla, más allá de su focal (%.0f mm): la imagen sale borrosa. Acércala a menos de %.0f mm." % [nom, d * 1000.0, f * 1000.0, f * 1000.0])
		elif v + e < 0.25:
			avisos.append("%s forma la imagen a solo %.2f m del ojo: cansa la vista. Separa la pantalla hasta casi la focal (%.0f mm)." % [nom, v + e, f * 1000.0])
		if absf(u - center) > 0.002:
			avisos.append("%s no está centrada en su mitad de pantalla (%.1f mm): las imágenes no coinciden con los ejes; ajusta la separación de las lentes o la del render." % [nom, (u - center) * 1000.0])
		if limited:
			avisos.append("%s recorta el campo de visión con su borde (Ø%.0f mm con el ojo a %.0f mm)." % [nom, r * 2000.0, e * 1000.0])
	var result := {"ok": true, "pantalla": {"uid": scr.uid, "nombre": scr.def.get("nombre", ""),
		"area_mm": [aw * 1000.0, ah * 1000.0], "res": res}, "lentes": out_lenses, "estereo": stereo}
	if stereo:
		var hl: Dictionary = same[0]
		var hr: Dictionary = same[1]
		var ipd := absf(float(hl["u"]) - float(hr["u"])) * 1000.0
		var dv := absf(float(hl["w"]) - float(hr["w"])) * 1000.0
		result["ipd_mm"] = ipd
		result["desnivel_mm"] = dv
		if ipd < IPD_MIN_MM or ipd > IPD_MAX_MM:
			avisos.append("Distancia entre lentes de %.1f mm, fuera del rango habitual de los ojos (%.0f–%.0f mm)." % [ipd, IPD_MIN_MM, IPD_MAX_MM])
		if dv > 1.0:
			avisos.append("Las lentes están a distinta altura (%.1f mm): da visión doble." % dv)
	result["avisos"] = avisos
	return result
