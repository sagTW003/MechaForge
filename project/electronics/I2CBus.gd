class_name I2CBus
extends RefCounted
## I2CBus — Comprueba el cableado del bus I²C entre las IMU (módulo GY-521 con
## MPU-6050) y las placas que tienen I²C (ESP32: GPIO21/22; Arduino Nano: A4/A5).
##
## Un módulo SIN ningún cable funciona como antes (conexión directa ideal). Con
## cables, el cableado manda y el sensor solo responde si:
##   · VCC–GND recibe entre 3.0 y 5.5 V (el GY-521 lleva regulador a 3.3 V);
##   · SDA y SCL llegan a los pines SDA y SCL de una misma placa (no cruzados);
##   · su GND es común con el de esa placa;
##   · ninguna otra IMU de ese bus usa su dirección (0x68, o 0x69 con AD0 alto).
## La conectividad sigue cables, tiras de la protoboard y patas insertadas.

const V_MIN := 3.0
const V_MAX := 5.5

## Dirección I²C de un dispositivo (0x68 por defecto; 0x69 con AD0 a VCC).
static func address(part: PartInstance) -> int:
	return int(part.estado.get("i2c_dir", part.def.get("i2c_dir", 0x68)))

## Estado de todas las IMU con terminales: uid -> {ok, cableada, motivo, placa, dir}.
static func statuses(main: Node) -> Dictionary:
	var out := {}
	var devices := []
	var boards := []
	for c in main.parts_root.get_children():
		if not (c is PartInstance):
			continue
		var p := c as PartInstance
		if p.def.has("imu") and p.def.has("terminales"):
			devices.append(p)
		if p.def.has("i2c"):
			boards.append(p)
	if devices.is_empty():
		return out
	# Sin una solución del circuito (recién abierto el proyecto) los sensores parecerían
	# sin alimentación justo en el primer paso, cuando el programa los inicializa.
	var rt0 = main.circuit_rt
	if rt0 != null and (rt0.nl == null or rt0.res.is_empty()):
		rt0.solve_once()
	var uf := _connectivity(main)
	var wired := {}
	for w in main.wires:
		for kk in [str(w["a_key"]), str(w["b_key"])]:
			wired[kk.get_slice(":", 0)] = true
	var rt = main.circuit_rt
	for dev in devices:
		var st := {"ok": false, "cableada": wired.has(dev.uid), "motivo": "", "placa": "", "dir": address(dev)}
		out[dev.uid] = st
		if not st["cableada"]:
			st["ok"] = true
			st["motivo"] = "sin cables: conexión directa"
			continue
		var kd := func(t: String) -> String: return main._key(dev.uid, t)
		var v := NAN
		if rt != null:
			v = float(rt.voltage(kd.call("VCC"))) - float(rt.voltage(kd.call("GND")))
		if is_nan(v) or v < V_MIN:
			st["motivo"] = "sin alimentación: VCC–GND = %.2f V (necesita 3.3–5 V)" % (0.0 if is_nan(v) else v)
			continue
		if v > V_MAX:
			st["motivo"] = "tensión excesiva: VCC–GND = %.2f V (máx. 5 V)" % v
			continue
		var sda: String = uf.call(kd.call("SDA"))
		var scl: String = uf.call(kd.call("SCL"))
		var found: PartInstance = null
		var crossed := ""
		var partial := ""
		for b in boards:
			var pins: Dictionary = b.def["i2c"]
			var bsda: String = uf.call(main._key(b.uid, str(pins["sda"])))
			var bscl: String = uf.call(main._key(b.uid, str(pins["scl"])))
			if sda == bsda and scl == bscl:
				found = b
				break
			if sda == bscl and scl == bsda:
				crossed = "SDA y SCL cruzados: SDA debe ir a %s y SCL a %s de %s" % [pins["sda"], pins["scl"], b.def.get("nombre", "la placa")]
			elif sda == bsda:
				partial = "SCL sin conectar a %s (SCL) de %s" % [pins["scl"], b.def.get("nombre", "la placa")]
			elif scl == bscl:
				partial = "SDA sin conectar a %s (SDA) de %s" % [pins["sda"], b.def.get("nombre", "la placa")]
		if found == null:
			if crossed != "":
				st["motivo"] = crossed
			elif partial != "":
				st["motivo"] = partial
			elif boards.is_empty():
				st["motivo"] = "no hay ninguna placa con I²C (ESP32 o Arduino Nano)"
			else:
				var pins0: Dictionary = boards[0].def["i2c"]
				st["motivo"] = "SDA y SCL sin conectar a la placa (SDA = %s, SCL = %s)" % [pins0["sda"], pins0["scl"]]
			continue
		if uf.call(kd.call("GND")) != uf.call(main._key(found.uid, "GND")):
			st["motivo"] = "GND sin conexión común con %s" % found.def.get("nombre", "la placa")
			continue
		st["ok"] = true
		st["placa"] = found.uid
		st["motivo"] = "conectada a %s, dirección 0x%X" % [found.def.get("nombre", "la placa"), int(st["dir"])]
	# Dos dispositivos con la misma dirección en el mismo bus: ninguno responde bien.
	var seen := {}
	for uid in out:
		var st: Dictionary = out[uid]
		if st["ok"] and st["placa"] != "":
			var key := "%s@%d" % [st["placa"], int(st["dir"])]
			if seen.has(key):
				for u2 in [uid, seen[key]]:
					out[u2]["ok"] = false
					out[u2]["motivo"] = "dirección 0x%X repetida en el bus: pon AD0 de una IMU a VCC (0x69)" % int(st["dir"])
			else:
				seen[key] = uid
	return out

## Conectividad eléctrica: clave de terminal -> representante del nodo. Une lo que
## une la netlist del circuito (tiras de la protoboard, patas insertadas, pines
## internos) y los cables.
static func _connectivity(main: Node) -> Callable:
	var parent := {}
	var nl = main.circuit_rt.nl if main.circuit_rt else null
	var base := func(k: String) -> String:
		return str(nl.find(k)) if nl != null and nl.has_point(k) else k
	var find := func(k: String) -> String:
		var r := k
		while parent.has(r) and parent[r] != r:
			r = parent[r]
		return r
	for w in main.wires:
		var a: String = find.call(base.call(str(w["a_key"])))
		var b: String = find.call(base.call(str(w["b_key"])))
		if a != b:
			parent[a] = b
	return func(k: String) -> String: return find.call(base.call(k))
