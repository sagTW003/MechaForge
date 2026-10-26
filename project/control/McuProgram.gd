class_name McuProgram
extends RefCounted
## McuProgram — Intérprete del programa del microcontrolador: cada línea
## 'nombre = expr' define una variable y la última línea evaluada del bucle es la
## salida (consigna). Como en un microcontrolador real, las variables conservan su
## valor entre pasos (empiezan en 0): "yaw = yaw + imu1_gz * dt" integra. Las líneas
## bajo «inicio:» se ejecutan solo en el primer paso y las de «bucle:» (o sin
## etiqueta) en todos.
##
## Seguridad: un proyecto compartido trae su programa y se valida ejecutándolo al
## abrirse, así que cada expresión pasa antes por McuIo.unsafe_part().

## Lo que el filtro rechazó en el último paso ("" si no falló por eso).
static var rejected := ""
static var _parse_key := ""
static var _parse_cache: Dictionary = {}
static var _assign_re: RegEx

## Separa el programa en «inicio:» y «bucle:» y reúne los nombres asignados.
static func parse(lines: Array) -> Dictionary:
	var key := "\n".join(PackedStringArray(lines))
	if key == _parse_key:
		return _parse_cache
	if _assign_re == null:
		_assign_re = RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_]*)\\s*=(?!=)\\s*(.*)$")
	var prog := {"inicio": [], "bucle": [], "nombres": []}
	var sec := "bucle"
	for raw in lines:
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var low := line.to_lower()
		if low in ["inicio:", "setup:"]:
			sec = "inicio"
			continue
		if low in ["bucle:", "loop:"]:
			sec = "bucle"
			continue
		var m := _assign_re.search(line)
		if m:
			prog[sec].append({"var": m.get_string(1), "expr": m.get_string(2)})
			if not prog["nombres"].has(m.get_string(1)):
				prog["nombres"].append(m.get_string(1))
		else:
			prog[sec].append({"var": "", "expr": line})
	_parse_key = key
	_parse_cache = prog
	return prog

## Un paso del programa con las entradas de «vars». «st» guarda la memoria entre
## pasos (las variables del programa y si ya corrió «inicio»). Devuelve la salida
## o NAN si alguna línea falla.
static func step(prog: Dictionary, vars: Dictionary, st: Dictionary, io: McuIo) -> float:
	rejected = ""
	if not st.get("_iniciado", false):
		if is_nan(exec(prog["inicio"], vars, io)):
			return NAN
		st["_iniciado"] = true
	var result := exec(prog["bucle"], vars, io)
	if is_nan(result):
		return NAN
	for n in prog["nombres"]:
		st[n] = vars[n]
	return result

## Ejecuta líneas ya analizadas ({var, expr}); devuelve la última o NAN si falla.
static func exec(prog_lines: Array, vars: Dictionary, io: McuIo) -> float:
	var result := 0.0
	for ln in prog_lines:
		var v := evaluate(ln["expr"], vars, io)
		if is_nan(v):
			return NAN
		if ln["var"] != "":
			vars[ln["var"]] = v
		result = v
	return result

## Evalúa una expresión con las variables dadas (Expression de Godot, sin objeto
## base). NAN si no es válida o si McuIo.unsafe_part() rechaza algo (queda en «rejected»).
static func evaluate(expr_str: String, vars: Dictionary, io: McuIo) -> float:
	if expr_str.contains("i2c"):
		expr_str = io.expand(expr_str, vars, func(e: String, v: Dictionary) -> float: return evaluate(e, v, io))
		if expr_str == "":
			return NAN
	var bad := McuIo.unsafe_part(expr_str)
	if bad != "":
		rejected = bad
		return NAN
	var e := Expression.new()
	if e.parse(expr_str, PackedStringArray(vars.keys())) != OK:
		return NAN
	var r = e.execute(vars.values(), null, false)
	if e.has_execute_failed():
		return NAN
	return float(r)
