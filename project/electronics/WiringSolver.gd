class_name WiringSolver
extends RefCounted
## WiringSolver — Construye el circuito a partir del cableado visual y lo resuelve.
##
## Une terminales conectados por cables en "nodos eléctricos" (net-list, con
## union-find), identifica la tierra (GND de la batería) y arma el circuito para
## el solver eléctrico en C# (autoload Electronics).
##
## Formato de entrada:
##   components: [ {uid, kind:"bateria"|"carga", voltaje, capacidad_mah,
##                  resistencia, a:"uid:term", b:"uid:term"}, ... ]
##   wires: [ {a:"uid:term", b:"uid:term"}, ... ]

static func _find(parent: Dictionary, x: String) -> String:
	if not parent.has(x):
		parent[x] = x
	var root := x
	while parent[root] != root:
		root = parent[root]
	# compresión de camino
	while parent[x] != root:
		var nxt: String = parent[x]
		parent[x] = root
		x = nxt
	return root

static func _union(parent: Dictionary, a: String, b: String) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb

## Resuelve el circuito. Devuelve:
##   { ok, wired (bool), current, power, autonomy_h, nets, batteries, loads, reason }
static func solve(components: Array, wires: Array) -> Dictionary:
	var parent := {}
	# Registra todos los terminales.
	for c in components:
		_find(parent, c["a"]); _find(parent, c["b"])
	for w in wires:
		_find(parent, w["a"]); _find(parent, w["b"])
		_union(parent, w["a"], w["b"])

	# Elemento por componente entre las raíces de sus dos terminales.
	var elems := []
	var ground := ""
	var batteries := 0
	var loads := 0
	var first_capacity := 0.0
	for c in components:
		var ra := _find(parent, c["a"])
		var rb := _find(parent, c["b"])
		elems.append({"a": ra, "b": rb, "kind": c["kind"], "v": c.get("voltaje", 0.0), "r": c.get("resistencia", 1.0)})
		if c["kind"] == "bateria":
			batteries += 1
			if ground == "":
				ground = rb  # el GND de la primera batería es la referencia
				first_capacity = c.get("capacidad_mah", 0.0)
		else:
			loads += 1

	if ground == "":
		return {"ok": false, "wired": wires.size() > 0, "current": 0.0, "power": 0.0,
			"autonomy_h": INF, "nets": 0, "batteries": batteries, "loads": loads,
			"reason": "Falta una batería con GND."}

	# Nodos alcanzables desde tierra a través de los elementos.
	var adj := {}
	for e in elems:
		adj.get_or_add(e["a"], []).append(e["b"])
		adj.get_or_add(e["b"], []).append(e["a"])
	var reachable := {}
	var stack := [ground]
	reachable[ground] = true
	while not stack.is_empty():
		var n: String = stack.pop_back()
		for m in adj.get(n, []):
			if not reachable.has(m):
				reachable[m] = true
				stack.append(m)

	# Índices de nodo: la tierra es 0.
	var node_index := {ground: 0}
	var next_idx := 1
	for net in reachable:
		if net != ground:
			node_index[net] = next_idx
			next_idx += 1

	var resistors := []
	var sources := []
	for e in elems:
		if not reachable.has(e["a"]) or not reachable.has(e["b"]):
			continue
		var ia: int = node_index[e["a"]]
		var ib: int = node_index[e["b"]]
		if ia == ib:
			continue  # cortocircuito del elemento, se ignora
		if e["kind"] == "bateria":
			sources.append([ia, ib, e["v"]])
		else:
			resistors.append([ia, ib, maxf(0.001, e["r"])])

	if sources.is_empty() or resistors.is_empty():
		return {"ok": true, "wired": true, "current": 0.0, "power": 0.0,
			"autonomy_h": INF, "nets": next_idx, "batteries": batteries, "loads": loads,
			"reason": "Circuito abierto (sin lazo batería→carga)."}

	var res: Dictionary = Electronics.SolveCircuit(next_idx, resistors, sources)
	var cur: float = res.get("main_current", 0.0)
	return {
		"ok": res.get("ok", false), "wired": true,
		"current": cur, "power": res.get("total_power", 0.0),
		"autonomy_h": Electronics.Autonomy(cur, first_capacity) if first_capacity > 0.0 else INF,
		"nets": next_idx, "batteries": batteries, "loads": loads, "reason": "",
	}
