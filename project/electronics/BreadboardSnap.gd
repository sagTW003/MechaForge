class_name BreadboardSnap
extends RefCounted
## BreadboardSnap — Enganche mecánico multipín en la protoboard MB-102.
##
## Un componente con patas (resistencia, LED, integrado DIP) solo queda insertado
## si TODAS sus patas caen en agujeros válidos de la matriz (paso 2.54 mm):
##   · se endereza (patas hacia abajo) y su giro se ajusta a múltiplos de 90°
##     respecto de la placa;
##   · se prueba el agujero más cercano para la primera pata y sus vecinos, y se
##     elige la traslación con menor desplazamiento en la que todas encajan;
##   · un integrado DIP además debe CRUZAR EL CANAL CENTRAL: una fila de patas en
##     las filas a–e y la otra en f–j (si no, sus patas opuestas quedarían unidas
##     por la misma tira de cobre), y nunca en los rieles de alimentación.
## El resultado es la transformación exacta (patas en los agujeros, cuerpo sobre la
## superficie) y el mapa pata -> agujero que usa el generador de netlist.

const TOL_MM := 0.35          # tolerancia pata ↔ agujero
const MAX_PULL_MM := 7.0      # distancia máxima a la que el agujero "atrae" la pieza
const MAX_ABOVE_MM := 45.0    # altura máxima sobre la placa para considerar la inserción

static var _hole_cache: Dictionary = {}    # clave de placa -> {celda: [[x, z, id, grupo], …]}

## Patas de inserción en coordenadas locales de la pieza (mm): [{id, pos: Vector3}].
## Son los terminales situados en la cara inferior (la punta que entra al agujero).
static func pins(def: Dictionary) -> Array:
	var out := []
	var terms: Array = def.get("terminales", [])
	# Definición de catálogo de un DIP (aún sin instanciar): patas generadas.
	if terms.is_empty() and def.has("dip"):
		terms = PartInstance.gen_dip_terminals(def)
	if terms.is_empty():
		return out
	var ymin := INF
	for t in terms:
		ymin = minf(ymin, float(t["pos_mm"][1]))
	for t in terms:
		var p: Array = t["pos_mm"]
		if absf(float(p[1]) - ymin) < 0.01:
			out.append({"id": str(t["id"]), "pos": Vector3(p[0], p[1], p[2])})
	return out

## Tabla de agujeros de una placa con acceso por celdas de 2.54 mm.
static func _holes(board: PartInstance) -> Dictionary:
	var key := "%s|%s" % [board.def_id, str(board.def.get("dimensiones_mm", {}))]
	if _hole_cache.has(key):
		return _hole_cache[key]
	var cells := {}
	for t in board.def.get("terminales", []):
		var p: Array = t["pos_mm"]
		var c := Vector2i(roundi(float(p[0]) / PartInstance.BB_PITCH), roundi(float(p[2]) / PartInstance.BB_PITCH))
		if not cells.has(c):
			cells[c] = []
		cells[c].append([float(p[0]), float(p[2]), str(t["id"]), str(t.get("grupo", ""))])
	_hole_cache[key] = cells
	return cells

## Agujero más cercano a (x, z) en mm dentro de "tol". Devuelve [x, z, id, grupo] o [].
static func _hole_at(cells: Dictionary, x: float, z: float, tol: float) -> Array:
	var c := Vector2i(roundi(x / PartInstance.BB_PITCH), roundi(z / PartInstance.BB_PITCH))
	var best := []
	var bd := tol
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for h in cells.get(c + Vector2i(dx, dz), []):
				var d := Vector2(h[0] - x, h[1] - z).length()
				if d <= bd:
					bd = d
					best = h
	return best

## Agujeros candidatos para la primera pata: los más cercanos a (x, z).
static func _nearest_holes(cells: Dictionary, x: float, z: float, count: int) -> Array:
	var c := Vector2i(roundi(x / PartInstance.BB_PITCH), roundi(z / PartInstance.BB_PITCH))
	var cand := []
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for h in cells.get(c + Vector2i(dx, dz), []):
				cand.append([Vector2(h[0] - x, h[1] - z).length(), h])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for i in range(mini(count, cand.size())):
		out.append(cand[i][1])
	return out

## Mitad de la placa de un agujero: "A" (filas a–e), "B" (f–j) o "R" (riel).
static func _half(hole_id: String) -> String:
	if hole_id.begins_with("a"):
		return "A"
	if hole_id.begins_with("b"):
		return "B"
	return "R"

## Intenta insertar una pieza (definición + transformación de mundo) en "board".
## Devuelve {ok, near, xf, map, reason, short, rows}:
##   near  = la pieza está sobre la placa (se intentó la inserción);
##   xf    = transformación de mundo ajustada (si ok);
##   map   = {pata: agujero};
##   short = dos patas en la misma tira interna (componente cortocircuitado).
static func try_insert(def: Dictionary, xf: Transform3D, board: PartInstance) -> Dictionary:
	var res := {"ok": false, "near": false, "reason": ""}
	var ps := pins(def)
	if ps.is_empty() or board == null:
		return res
	var B := board.global_transform
	var local := B.affine_inverse() * xf
	var dm := PartLibrary.dims_m(board.def) * 1000.0
	var c := local.origin * 1000.0
	var top := dm.y * 0.5
	if absf(c.x) > dm.x * 0.5 + 3.0 or absf(c.z) > dm.z * 0.5 + 3.0:
		return res
	if c.y < top - 6.0 or c.y > top + MAX_ABOVE_MM:
		return res
	res["near"] = true
	# 1) Enderezar y ajustar el giro a múltiplos de 90° respecto de la placa.
	var xa := local.basis.x
	var yaw := snappedf(atan2(-xa.z, xa.x), PI * 0.5)
	var rb := Basis(Vector3.UP, yaw)
	var q := []
	for p in ps:
		var v: Vector3 = rb * (p["pos"] as Vector3)
		q.append(Vector2(v.x, v.z))
	var cells := _holes(board)
	var is_dip := def.has("dip")
	var best := {}
	var best_d := INF
	var reason := ""
	# 2) Traslaciones candidatas: la primera pata en uno de los agujeros cercanos.
	for h0 in _nearest_holes(cells, c.x + q[0].x, c.z + q[0].y, 12):
		var t := Vector2(h0[0], h0[1]) - (q[0] as Vector2)
		var disp := t.distance_to(Vector2(c.x, c.z))
		if disp > MAX_PULL_MM:
			continue
		var m := {}
		var used := {}
		var groups := {}
		var all_ok := true
		var short := false
		for i in range(ps.size()):
			var target: Vector2 = t + (q[i] as Vector2)
			var h := _hole_at(cells, target.x, target.y, TOL_MM)
			if h.is_empty() or used.has(h[2]):
				all_ok = false
				break
			used[h[2]] = true
			m[ps[i]["id"]] = h[2]
			var g: String = h[3]
			if g != "" and groups.has(g):
				short = true
			groups[g] = true
		if not all_ok:
			if reason == "":
				reason = "Las patas no coinciden con los agujeros de la protoboard."
			continue
		if is_dip:
			var why := _dip_check(ps, m)
			if why != "":
				reason = why
				continue
		if disp < best_d:
			best_d = disp
			best = {"t": t, "map": m, "short": short}
	if best.is_empty():
		res["reason"] = reason if reason != "" else "Acerca más el componente a los agujeros."
		return res
	# 3) Transformación exacta: patas en los agujeros y cuerpo sobre la superficie.
	var pin_y: float = (ps[0]["pos"] as Vector3).y
	var t2: Vector2 = best["t"]
	var origin := Vector3(t2.x, top - pin_y, t2.y) / 1000.0
	res["ok"] = true
	res["xf"] = B * Transform3D(rb, origin)
	res["map"] = best["map"]
	res["short"] = best["short"]
	res["rows"] = describe(best["map"])
	return res

## Regla del integrado DIP: cada fila de patas entera en una mitad distinta
## (a–e / f–j) y ninguna pata en los rieles.
static func _dip_check(ps: Array, m: Dictionary) -> String:
	var row_half := {}
	for p in ps:
		var half := _half(str(m[p["id"]]))
		if half == "R":
			return "Un integrado no se inserta en los rieles de alimentación."
		var row := 1 if (p["pos"] as Vector3).z > 0.0 else 2
		if row_half.has(row) and row_half[row] != half:
			return "El integrado debe cruzar el canal central: una fila de patas en a–e y la otra en f–j."
		row_half[row] = half
	if row_half.get(1, "") == row_half.get(2, "-"):
		return "El integrado debe cruzar el canal central: una fila de patas en a–e y la otra en f–j."
	return ""

## Nombre legible de un agujero: "a5_2" -> "c6" (fila c, columna 6), "P1_3" -> "+ sup.".
static func hole_name(id: String) -> String:
	var rows_top := ["e", "d", "c", "b", "a"]
	var rows_bot := ["f", "g", "h", "i", "j"]
	if id.begins_with("a") or id.begins_with("b"):
		var parts := id.substr(1).split("_")
		if parts.size() == 2:
			var col := int(parts[0]) + 1
			var r := int(parts[1])
			return "%s%d" % [(rows_top if id.begins_with("a") else rows_bot)[clampi(r, 0, 4)], col]
	var rail := {"P1": "riel + superior", "N1": "riel − superior", "P2": "riel + inferior", "N2": "riel − inferior"}
	var pre := id.split("_")[0]
	return rail.get(pre, id)

## Resumen de columnas/filas ocupadas (para el estado): "columnas 10–13, filas e/f".
static func describe(m: Dictionary) -> String:
	var names := []
	for k in m:
		names.append(hole_name(str(m[k])))
	names.sort()
	if names.size() <= 4:
		return ", ".join(names)
	return "%s … %s (%d patas)" % [names[0], names[names.size() - 1], names.size()]
