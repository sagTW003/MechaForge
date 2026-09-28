class_name NodeNetlist
extends RefCounted
## NodeNetlist — Traduce la geometría 3D a un grafo de nodos eléctricos.
##
## Cada terminal es una clave "uid:terminal". Se FUNDEN en un mismo nodo (union-find):
##   · los agujeros de una tira interna de la protoboard (columna de 5 o riel);
##   · cada pata insertada con su agujero (enganche multipín).
## Los cables, resistencias, fuentes, salidas de integrados, diodos y el propio
## multímetro son ELEMENTOS entre nodos: así se conoce la corriente de cada uno
## (calentamiento de un cable en cortocircuito, fusible del amperímetro…).
##
## Uso: topología cacheada (links) + elementos por paso:
##   var nl := NodeNetlist.new(); nl.add_point(k); nl.link(a, b)   # topología
##   nl.begin(); nl.add_branch(...); nl.add_diode(...); nl.finalize(tierra)
##   → nl.node_count, nl.branch_rows(), nl.diode_rows() para Electronics.SolveNetlist

var _parent: Dictionary = {}
var _root_cache: Dictionary = {}

# --- Por paso ---
var node_of: Dictionary = {}        # raíz -> índice de nodo (0 = tierra)
var node_count: int = 1
var branches: Array = []            # [{a, b, r, e, meta}]  (claves)
var diodes: Array = []              # [{a, k, is, nvt, rs, meta}]
var ground_root: String = ""

func add_point(k: String) -> void:
	if not _parent.has(k):
		_parent[k] = k

func has_point(k: String) -> bool:
	return _parent.has(k)

func find(k: String) -> String:
	if _root_cache.has(k):
		return _root_cache[k]
	if not _parent.has(k):
		_parent[k] = k
	var r := k
	while _parent[r] != r:
		r = _parent[r]
	var x := k
	while _parent[x] != r:
		var nx: String = _parent[x]
		_parent[x] = r
		x = nx
	return r

func link(a: String, b: String) -> void:
	var ra := find(a)
	var rb := find(b)
	if ra != rb:
		_parent[ra] = rb
	_root_cache.clear()

## Congela la topología: memoriza la raíz de cada clave (consultas O(1)).
func freeze() -> void:
	_root_cache.clear()
	for k in _parent.keys():
		_root_cache[k] = find(k)

func same_node(a: String, b: String) -> bool:
	return find(a) == find(b)

## Claves del mismo nodo que "k" (p. ej. todos los agujeros de una tira).
func members(k: String) -> Array:
	var r := find(k)
	var out := []
	for x in _parent.keys():
		if find(x) == r:
			out.append(x)
	return out

# --- Elementos (se rehacen en cada paso) ---

func begin() -> void:
	branches = []
	diodes = []
	node_of = {}
	node_count = 1
	ground_root = ""

## Rama entre las claves a y b: corriente a→b = (Va − Vb − e) / r.
func add_branch(a: String, b: String, r: float, e: float, meta: Dictionary) -> int:
	branches.append({"a": a, "b": b, "r": maxf(1.0e-6, r), "e": e, "meta": meta})
	return branches.size() - 1

func add_diode(a: String, k: String, i_sat: float, nvt: float, rs: float, meta: Dictionary) -> int:
	diodes.append({"a": a, "k": k, "is": i_sat, "nvt": nvt, "rs": rs, "meta": meta})
	return diodes.size() - 1

## Asigna índices de nodo: la tierra (0) es el nodo de "ground_key" (el borne
## negativo de la primera fuente); los demás nodos usados, 1..N−1.
func finalize(ground_key: String) -> void:
	node_of = {}
	ground_root = find(ground_key) if ground_key != "" else ""
	if ground_root != "":
		node_of[ground_root] = 0
	var next := 1
	for e in branches:
		for k in [e["a"], e["b"]]:
			var r := find(k)
			if not node_of.has(r):
				if ground_root == "":
					ground_root = r
					node_of[r] = 0
				else:
					node_of[r] = next
					next += 1
	for d in diodes:
		for k in [d["a"], d["k"]]:
			var r := find(k)
			if not node_of.has(r):
				if ground_root == "":
					ground_root = r
					node_of[r] = 0
				else:
					node_of[r] = next
					next += 1
	node_count = next

## Índice de nodo de una clave (−1 si no pertenece a ningún elemento: flotante).
func index_of(k: String) -> int:
	return node_of.get(find(k), -1)

func branch_rows() -> Array:
	var out := []
	for e in branches:
		out.append([node_of[find(e["a"])], node_of[find(e["b"])], e["r"], e["e"]])
	return out

func diode_rows() -> Array:
	var out := []
	for d in diodes:
		out.append([node_of[find(d["a"])], node_of[find(d["k"])], d["is"], d["nvt"], d["rs"]])
	return out

## Resuelve con el solver C# (autoload Electronics). Devuelve el diccionario del
## solver más "ok_nodes" (hay algo que resolver).
func solve() -> Dictionary:
	if branches.is_empty() and diodes.is_empty():
		return {"ok": true, "v": PackedFloat64Array([0.0]), "ib": PackedFloat64Array(), "id": PackedFloat64Array(), "vd": PackedFloat64Array(), "empty": true}
	return Electronics.SolveNetlist(node_count, branch_rows(), diode_rows())

## Tensión de una clave en el resultado (NAN si la clave está flotante).
func voltage(res: Dictionary, k: String) -> float:
	var i := index_of(k)
	var v: PackedFloat64Array = res.get("v", PackedFloat64Array())
	if i < 0 or i >= v.size():
		return NAN
	return v[i]
