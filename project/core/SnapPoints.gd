class_name SnapPoints
extends RefCounted
## SnapPoints — Puntos de encaje inteligente entre piezas.
##
## Cada pieza expone puntos con posición, normal (hacia fuera) y tipo:
##   "orificio" — agujeros de placas (rejilla de 20 mm) y de montaje de PCB.
##   "eje"      — extremos de ejes/cilindros, cubo de engranajes, eje de motor.
##   "extremo"  — caras de los extremos de perfiles y vigas.
##   "ranura"   — puntos a lo largo de las ranuras en T de los perfiles (cada 20 mm).
##   "cara"     — centro de cada cara (cualquier pieza de caja/placa).
##   "base"     — cara inferior de componentes (para posarlos).
## find_snap() busca, entre la pieza que se mueve y sus vecinas, el par de puntos
## más cercano con normales opuestas (cara contra cara) y devuelve el desplazamiento
## que los hace coincidir. Solo se consideran piezas cercanas (filtro por AABB).

const PITCH := 0.02

## Afinidad entre tipos: bonificación (se resta a la distancia) para priorizar
## encajes con sentido mecánico (eje en orificio, perfil contra ranura...).
const BONUS := {
	"eje|orificio": 0.006, "orificio|eje": 0.006,
	"extremo|ranura": 0.004, "ranura|extremo": 0.004,
	"orificio|orificio": 0.004, "extremo|orificio": 0.004, "orificio|extremo": 0.004,
	"base|orificio": 0.003, "orificio|base": 0.003, "extremo|extremo": 0.002,
}

## Puntos en coordenadas LOCALES de la pieza: [{p, n, k}].
static func local_points(def: Dictionary) -> Array:
	var out := []
	var forma: String = def.get("forma", "caja")
	var d := PartLibrary.dims_m(def)
	var h := d * 0.5
	match forma:
		"cilindro", "tubo":
			out.append({"p": Vector3(0, h.y, 0), "n": Vector3.UP, "k": "eje"})
			out.append({"p": Vector3(0, -h.y, 0), "n": Vector3.DOWN, "k": "eje"})
		"engranaje":
			out.append({"p": Vector3(0, h.y, 0), "n": Vector3.UP, "k": "eje"})
			out.append({"p": Vector3(0, -h.y, 0), "n": Vector3.DOWN, "k": "eje"})
		"custom":
			out.append({"p": Vector3(0, -h.y, 0), "n": Vector3.DOWN, "k": "base"})
		_:
			# Centros de las 6 caras.
			for ax in range(3):
				for s: float in [-1.0, 1.0]:
					var n := Vector3.ZERO; n[ax] = s
					out.append({"p": n * h[ax], "n": n, "k": "cara"})
			if def.get("perfil", "") == "tslot" or def.get("categoria", "") == "estructural" and forma == "caja":
				_profile_points(d, out)
			if forma == "placa" and def.get("categoria", "") == "estructural":
				for hp in MeshFactory.plate_hole_positions(d):
					out.append({"p": hp + Vector3(0, h.y, 0), "n": Vector3.UP, "k": "orificio"})
					out.append({"p": hp - Vector3(0, h.y, 0), "n": Vector3.DOWN, "k": "orificio"})
	# Componentes: base y detalles según su apariencia.
	match def.get("apariencia", ""):
		"placa_pcb":
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var c := Vector3(sx * (h.x - 0.0035), -h.y, sz * (h.z - 0.0035))
					out.append({"p": c, "n": Vector3.DOWN, "k": "orificio"})
		"motor":
			out.append({"p": Vector3(0, h.y * 1.0 + d.y * 0.47, 0), "n": Vector3.UP, "k": "eje"})
			out.append({"p": Vector3(0, -h.y, 0), "n": Vector3.DOWN, "k": "base"})
		"servo":
			out.append({"p": Vector3(0, h.y * 1.1, d.z * 0.25), "n": Vector3.UP, "k": "eje"})
			out.append({"p": Vector3(0, -h.y, 0), "n": Vector3.DOWN, "k": "base"})
		"", _:
			pass
	return out

## Perfiles/vigas: extremos del eje largo y puntos de ranura a lo largo.
static func _profile_points(d: Vector3, out: Array) -> void:
	var ax := 1
	if d.x >= d.y and d.x >= d.z: ax = 0
	elif d.z >= d.y and d.z >= d.x: ax = 2
	var length := d[ax]
	for o in out:
		if absf((o["n"] as Vector3)[ax]) > 0.5:
			o["k"] = "extremo"
	var n_pts := int(floor(length / PITCH)) - 1
	for i in range(1, n_pts + 1):
		var t := -length * 0.5 + PITCH * i
		for side in range(3):
			if side == ax:
				continue
			for s: float in [-1.0, 1.0]:
				var nrm := Vector3.ZERO; nrm[side] = s
				var p := nrm * d[side] * 0.5
				p[ax] = t
				out.append({"p": p, "n": nrm, "k": "ranura"})

## Puntos en coordenadas de MUNDO para una pieza (usa su transformación actual).
static func world_points(node: Node3D, def: Dictionary, xf: Variant = null) -> Array:
	var t: Transform3D = node.global_transform if xf == null else xf
	var out := []
	for lp in local_points(def):
		out.append({"p": t * (lp["p"] as Vector3), "n": (t.basis * (lp["n"] as Vector3)).normalized(), "k": lp["k"]})
	return out

## AABB en mundo de una pieza (caja orientada -> AABB).
static func world_aabb(node: Node3D, def: Dictionary, xf: Variant = null) -> AABB:
	var t: Transform3D = node.global_transform if xf == null else xf
	var h := PartLibrary.dims_m(def) * 0.5
	var b := t.basis
	var ext := Vector3(
		absf(b.x.x) * h.x + absf(b.y.x) * h.y + absf(b.z.x) * h.z,
		absf(b.x.y) * h.x + absf(b.y.y) * h.y + absf(b.z.y) * h.z,
		absf(b.x.z) * h.x + absf(b.y.z) * h.y + absf(b.z.z) * h.z)
	return AABB(t.origin - ext, ext * 2.0)

## Busca el mejor encaje. "moving_xf" es la transformación candidata de la pieza.
## Devuelve {} o {offset, from, to, kind_from, kind_to, target}.
static func find_snap(moving: Node3D, moving_def: Dictionary, moving_xf: Transform3D, others: Array, max_dist: float = 0.012) -> Dictionary:
	var box := world_aabb(moving, moving_def, moving_xf).grow(max_dist)
	var mine := world_points(moving, moving_def, moving_xf)
	var best := {}
	var best_score := INF
	for o in others:
		if o == moving or not (o is Node3D) or not is_instance_valid(o):
			continue
		var odef: Dictionary = o.def
		if not box.intersects(world_aabb(o, odef)):
			continue
		for q in world_points(o, odef):
			var qp: Vector3 = q["p"]
			if not box.grow(0.001).has_point(qp):
				continue
			for m in mine:
				if (m["n"] as Vector3).dot(q["n"]) > -0.8:
					continue      # deben quedar cara contra cara
				var dist := (m["p"] as Vector3).distance_to(qp)
				if dist > max_dist:
					continue
				var score: float = dist - float(BONUS.get("%s|%s" % [m["k"], q["k"]], 0.0))
				if score < best_score:
					best_score = score
					best = {"offset": qp - (m["p"] as Vector3), "from": m["p"], "to": qp,
						"kind_from": m["k"], "kind_to": q["k"], "target": o}
	return best

const KIND_NAMES := {
	"orificio": "orificio", "eje": "eje", "extremo": "extremo", "ranura": "ranura en T",
	"cara": "cara", "base": "base",
}

static func describe(snap: Dictionary) -> String:
	if snap.is_empty():
		return ""
	return "%s → %s" % [KIND_NAMES.get(snap["kind_from"], snap["kind_from"]), KIND_NAMES.get(snap["kind_to"], snap["kind_to"])]
