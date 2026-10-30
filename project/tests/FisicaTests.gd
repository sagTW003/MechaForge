extends Node
## FisicaTests — Núcleo compartido de «Física moderna» (Fase 2, docs/FISICA_MODERNA.md).
## Ejecutar:  Godot --headless --path project -- mffisica
##   Sin --headless se prueba además la GPU (Coulomb frente a la referencia en C#);
##   «-- mffisica bench» mide Coulomb con 10 000 cargas en la GPU.

var lab: MathLab
var ok: int = 0
var fail: int = 0

func check(cond: bool, nombre: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % nombre)
	else:
		fail += 1
		print("  [FALLO] %s" % nombre)

## Módulo mínimo para probar los contratos del laboratorio.
class ModPrueba extends LabModule:
	var n := 0
	var pasos := 0
	var roto := false
	var liberado := false
	var primero := 0.0
	func uses_time() -> bool: return true
	func fixed_dt() -> float: return 0.01
	func step(_dt: float) -> void: pasos += 1
	func reset() -> void: primero = rng.randf()
	func finito() -> bool: return not roto
	func estado() -> Dictionary: return {"n": n}
	func cargar(d: Dictionary) -> String:
		if not typeof(d.get("n")) in [TYPE_INT, TYPE_FLOAT]:
			return "falta «n»"
		n = int(d["n"])
		return ""
	func metricas() -> Dictionary: return {"entidades": 3}
	func liberar() -> void: liberado = true
	func fidelidad() -> Array:
		return [{"subsistema": "Prueba", "nivel": "exacto", "modelo": "x = 1", "unidades": "u.a."}]

func run() -> void:
	print("[TEST] Física moderna (núcleo)...")
	await get_tree().process_frame
	_t_constantes()
	_t_coulomb_cpu()
	_t_gpu()
	await _t_contratos()
	_t_guardado()
	print("[TEST] Física moderna: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

func _t_constantes() -> void:
	var c: Dictionary = Fisica.Constantes()
	var eh: float = c["alpha"] ** 2 * c["mec2_MeV"] * 1e6
	check(absf(eh / c["hartree_eV"] - 1.0) < 1e-9, "Constantes (CODATA 2022): Eₕ = α²·mₑc² = %.9f eV" % eh)
	var a0: float = c["hbarc_MeV_fm"] / (c["alpha"] * c["mec2_MeV"]) * 1e-15
	check(absf(a0 / c["bohr_m"] - 1.0) < 1e-9, "Constantes: a₀ = ħc / (α·mₑc²)")
	check(absf(c["hbarc_MeV_fm"] - 197.3269804) < 1e-7, "Constantes: ħc = 197.3269804 MeV·fm, derivada de h, c y e exactas")

## n cargas ±1 al azar en el cubo [−1, 1]³: [x, y, z, q] por carga.
func _cargas(n: int, semilla: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var p := PackedFloat32Array()
	p.resize(n * 4)
	for i in n:
		p[4 * i] = rng.randf_range(-1, 1)
		p[4 * i + 1] = rng.randf_range(-1, 1)
		p[4 * i + 2] = rng.randf_range(-1, 1)
		p[4 * i + 3] = 1.0 if i % 2 == 0 else -1.0
	return p

func _t_coulomb_cpu() -> void:
	var eps2 := 1e-6
	var f2: PackedFloat32Array = Fisica.CoulombForces(PackedFloat32Array([0, 0, 0, 1, 1, 0, 0, -1]), eps2)
	var expect := 1.0 / pow(1.0 + eps2, 1.5)
	check(absf(f2[0] - expect) < 1e-6 and absf(f2[4] + expect) < 1e-6,
		"Coulomb (C#): dos cargas opuestas a distancia 1 se atraen con |F| = 1/(1 + ε²)^{3/2}")
	var f: PackedFloat32Array = Fisica.CoulombForces(_cargas(300, 3), 1e-4)
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var total := 0.0
	for i in 300:
		sx += f[4 * i]
		sy += f[4 * i + 1]
		sz += f[4 * i + 2]
		total += sqrt(f[4 * i] ** 2 + f[4 * i + 1] ** 2 + f[4 * i + 2] ** 2)
	check(sqrt(sx * sx + sy * sy + sz * sz) / total < 1e-5, "Coulomb (C#): la suma de fuerzas de 300 cargas es nula (acción y reacción)")

func _t_gpu() -> void:
	var g := GpuCompute.create()
	if g == null:
		print("  [OMITIDO] GPU: sin RenderingDevice (ejecuta sin --headless para probarla)")
		return
	var n := 4096
	var p := _cargas(n, 11)
	var fc: PackedFloat32Array = Fisica.CoulombForces(p, 1e-4)
	var fg := g.coulomb(p, 1e-4)
	var worst := 0.0
	var rms := 0.0
	for i in n:
		rms += fc[4 * i] ** 2 + fc[4 * i + 1] ** 2 + fc[4 * i + 2] ** 2
		worst = maxf(worst, sqrt((fg[4 * i] - fc[4 * i]) ** 2 + (fg[4 * i + 1] - fc[4 * i + 1]) ** 2 + (fg[4 * i + 2] - fc[4 * i + 2]) ** 2))
	var rel := worst / sqrt(rms / n)
	check(rel < 1e-4, "GPU (%s): Coulomb con %d cargas coincide con la referencia en C# (error máx. %s de la fuerza típica)" % [g.device_name(), n, str(snappedf(rel, 1e-9))])
	if "bench" in OS.get_cmdline_user_args():
		var pb := _cargas(10000, 5)
		var best := INF
		for k in 10:
			var t0 := Time.get_ticks_usec()
			g.coulomb(pb, 1e-4)
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		check(best < 2.0, "Rendimiento: Coulomb con 10 000 cargas en la GPU (subida, cálculo y lectura) en %.2f ms (objetivo < 2 ms)" % best)
	g.liberar()
	check(g.rd == null, "GPU: liberar() suelta el RenderingDevice y sus recursos")
	# Sin liberar(): se libera solo al soltarlo (un fallo saldría como SCRIPT ERROR o
	# como fuga al cerrar).
	var g2 := GpuCompute.create()
	g2.coulomb(_cargas(64, 1), 1e-4)
	g2 = null

func _t_contratos() -> void:
	var m := ModPrueba.new()
	lab.open_instance(m, {"id": "prueba", "nombre": "Prueba"})
	await get_tree().process_frame
	if lab.playing:
		lab.toggle_play()
	check(not lab.model_button.disabled and lab.model_label.text.contains("EXACTO") and lab.model_label.text.contains("u.a."),
		"Modelo y límites: el nivel de cada subsistema en palabras, con modelo y unidades")
	m.pasos = 0
	lab._acc = 0.0
	lab.advance(0.035)
	check(m.pasos == 3, "Paso fijo: 0,035 s con pasos de 0,01 s son 3 pasos (el resto pasa al siguiente)")
	lab.advance(10.0)
	check(m.pasos == 3 + MathLab.MAX_SUBSTEPS, "Paso fijo: como mucho %d subpasos por fotograma (sin acumular retraso)" % MathLab.MAX_SUBSTEPS)
	lab.seed_value = 42
	lab.reset_module()
	var a := m.primero
	lab.reset_module()
	var b := m.primero
	lab.seed_value = 43
	lab.reset_module()
	check(a == b and m.primero != a, "Semilla: la misma semilla repite los números aleatorios al reiniciar; otra, no")
	m.n = 0
	m.remember()
	m.n = 5
	lab.undo()
	var tras_deshacer := m.n
	lab.redo()
	check(tras_deshacer == 0 and m.n == 5, "Deshacer (Ctrl+Z) y rehacer (Ctrl+Y) del estado del módulo")
	lab.toggle_play()
	m.roto = true
	lab.advance(0.01)
	check(not lab.playing and lab.status_label.text.contains("NaN"), "NaN o ∞ en la simulación: el laboratorio pausa y avisa")
	m.roto = false
	var snap := lab.snapshot()
	check(snap["version"] == MathLab.STATE_VERSION and snap["modulo"] == "prueba" and snap["estado"] == {"n": 5},
		"El estado del laboratorio para el proyecto: versión, módulo y estado del módulo")
	check(m.cargar({"x": 1}) != "", "cargar() rechaza un estado que no tiene el formato del módulo")
	lab.metrics_panel.visible = true
	lab._update_metrics()
	check(lab.metrics_label.text.contains("FPS") and lab.metrics_label.text.contains("Física") and lab.metrics_label.text.contains("Entidades: 3"),
		"Métricas: FPS, tiempo de física, render, memoria y las entidades del módulo")
	lab.open_module("onda")
	check(m.liberado, "Al cambiar de módulo se llama a liberar() (recursos de GPU)")
	await get_tree().process_frame
	check(lab.model_button.disabled, "Modelo y límites: desactivado en los módulos que no declaran modelo")

func _t_guardado() -> void:
	check(MathLab.validate_snapshot({"version": 1, "modulo": "onda", "estado": {}}) == "", "Guardado: un estado válido del laboratorio se acepta")
	check(MathLab.validate_snapshot({"version": 99, "modulo": "onda", "estado": {}}).contains("versión"), "Guardado: una versión desconocida se rechaza")
	check(MathLab.validate_snapshot({"version": 1, "modulo": "no_existe", "estado": {}}).contains("desconocido"), "Guardado: un módulo desconocido se rechaza")
	check(MathLab.validate_snapshot({"version": 1, "modulo": "onda", "estado": [1]}) != "" and MathLab.validate_snapshot("texto") != "",
		"Guardado: tipos incorrectos se rechazan")
	var main: Node = lab.main_scene
	main.lab_state = {"version": 1, "modulo": "onda", "estado": {}}
	check(str(main._project_extra().get("laboratorio", {}).get("modulo", "")) == "onda", "El proyecto guarda el módulo del laboratorio («laboratorio»)")
	main._apply_project_extra({"laboratorio": {"version": 99, "modulo": "onda"}})
	var rechazado: bool = main.lab_state.is_empty()
	main._apply_project_extra({"laboratorio": {"version": 1, "modulo": "calor", "estado": {}}})
	check(rechazado and str(main.lab_state.get("modulo", "")) == "calor", "Al cargar un proyecto, un estado del laboratorio no válido se ignora y uno válido se recupera")
	main.lab_state = {}
