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
	_t_hidrogeno()
	await _t_modulo_hidrogeno()
	await _t_modulo_particulas()
	await _t_pilar()
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
	check(absf(f2[3] + 1.0 / sqrt(1.0 + eps2)) < 1e-6, "Coulomb (C#): energía potencial de cada carga en w (U = −1/√(1 + ε²) para el par)")
	var p3 := _cargas(300, 4)
	var v3 := _cargas(300, 5)
	for i in 300:
		v3[4 * i + 3] = 1.0 if i % 2 == 0 else 1.0 / 1836.152673426
	var ex: PackedFloat64Array = Fisica.CoulombEnergy(p3, v3, 1e-4)
	var ef: PackedFloat64Array = Fisica.CoulombEnergyFromForces(v3, Fisica.CoulombForces(p3, 1e-4))
	check(absf(ef[1] / ex[1] - 1.0) < 1e-5 and absf(ef[0] - ex[0]) < 1e-9 * absf(ex[0]),
		"Coulomb (C#): la energía a partir de las fuerzas (½ Σ U_i, O(N)) coincide con la suma por pares")

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

# --- Fase 3: átomo de hidrógeno -------------------------------------------------------

## Comprueba que el módulo pedido es el abierto: si su script no compila, el
## laboratorio se queda con el anterior y las pruebas mirarían otro módulo.
func _abierto(id: String) -> bool:
	check(lab.module_id == id, "El módulo «%s» se abre (su script compila)" % id)
	return lab.module_id == id

func _t_hidrogeno() -> void:
	var c: Dictionary = Fisica.Constantes()
	check(absf(Fisica.HydrogenEnergyEv(1, false) + c["hartree_eV"] / 2.0) < 1e-12 and absf(Fisica.HydrogenEnergyEv(1, false) + 13.605693122990) < 1e-9,
		"Hidrógeno: E₁ = −Eₕ/2 = −13,605693 eV (núcleo infinitamente pesado)")
	check(absf(Fisica.HydrogenEnergyEv(3, false) * 9.0 - Fisica.HydrogenEnergyEv(1, false)) < 1e-12
		and absf(Fisica.HydrogenEnergyEv(1, true) / Fisica.HydrogenEnergyEv(1, false) - c["mp_me"] / (c["mp_me"] + 1.0)) < 1e-14,
		"Hidrógeno: Eₙ ∝ 1/n², y con masa reducida Eₙ·mₚ/(mₚ + mₑ) = %.6f eV" % Fisica.HydrogenEnergyEv(1, true))
	var worst_norm := 0.0
	var worst_r := 0.0
	for nl in [[1, 0], [2, 0], [2, 1], [3, 2], [4, 1], [6, 5]]:
		worst_norm = maxf(worst_norm, absf(Fisica.HydrogenRadialMoment(nl[0], nl[1], 0) - 1.0))
		worst_r = maxf(worst_r, absf(Fisica.HydrogenRadialMoment(nl[0], nl[1], 1) / Fisica.HydrogenMeanR(nl[0], nl[1]) - 1.0))
	check(worst_norm < 1e-8, "Hidrógeno: ∫R²r²dr = 1 para 1s, 2s, 2p, 3d, 4p y 6h (error máx. %s)" % LabUI.sci(worst_norm, 1))
	check(worst_r < 1e-8, "Hidrógeno: ⟨r⟩ numérico = a₀(3n² − l(l+1))/2 (error relativo máx. %s)" % LabUI.sci(worst_r, 1))
	var worst_y := 0.0
	for lm in [[0, 0], [1, 1], [2, -1], [3, 3], [4, -2], [5, 0]]:
		worst_y = maxf(worst_y, absf(Fisica.HydrogenYlmNorm(lm[0], lm[1]) - 1.0))
	check(worst_y < 1e-8, "Hidrógeno: ∫|Yₗᵐ|²dΩ = 1 (error máx. %s)" % LabUI.sci(worst_y, 1))
	var psi0: PackedFloat64Array = Fisica.HydrogenPsi(1, 0, 0, 0.0, 0.0, 0.0)
	check(absf(psi0[0] * psi0[0] - 1.0 / PI) < 1e-12, "Hidrógeno: |ψ₁₀₀(0)|² = 1/(πa₀³)")
	# La muestra reproduce ⟨r⟩ dentro del error estadístico (4σ/√N).
	var n_s := 40000
	var ok_all := true
	var detalle := ""
	for nl in [[1, 0], [3, 1], [4, 3]]:
		var pts: PackedFloat32Array = Fisica.HydrogenSample(nl[0], nl[1], 0, n_s, 17)
		var acc := 0.0
		for i in n_s:
			acc += sqrt(pts[4 * i] ** 2 + pts[4 * i + 1] ** 2 + pts[4 * i + 2] ** 2)
		var mr: float = Fisica.HydrogenMeanR(nl[0], nl[1])
		var sd := sqrt(Fisica.HydrogenMeanR2(nl[0], nl[1]) - mr * mr)
		var z := absf(acc / n_s - mr) / (sd / sqrt(n_s))
		ok_all = ok_all and z < 4.0
		detalle += " %d%s: %.1fσ" % [nl[0], "spdfgh"[nl[1]], z]
	check(ok_all, "Hidrógeno: el ⟨r⟩ de 40 000 puntos muestreados coincide con el exacto (%s)" % detalle.strip_edges())
	check(Fisica.HydrogenSample(2, 2, 0, 10, 1).is_empty(), "Hidrógeno: números cuánticos no válidos (l ≥ n) no dan puntos")

func _t_modulo_hidrogeno() -> void:
	lab.open_module("hidrogeno")
	await get_tree().process_frame
	if not _abierto("hidrogeno"):
		return
	var hm = lab.module
	check(hm.cloud.multimesh.instance_count == hm.puntos and lab.info_label.text.contains("eV"),
		"Módulo «Átomo de hidrógeno»: %d puntos en la GPU y la energía en la información" % hm.puntos)
	check(hm.cargar({"n": 3, "l": 2, "m": -1, "puntos": 20000}) == "" and hm.n == 3 and hm.l == 2 and hm.m == -1 and hm.cloud.multimesh.instance_count == 20000,
		"Hidrógeno: cargar un estado (3d, m = −1, 20 000 puntos) cambia la nube")
	check(hm.cargar({"n": 2, "l": 2, "m": 0, "puntos": 1000}) != "" and hm.n == 3, "Hidrógeno: un estado con l ≥ n se rechaza y no cambia nada")
	hm.remember()
	hm.cargar({"n": 1, "l": 0, "m": 0, "puntos": 20000})
	lab.undo()
	check(hm.n == 3 and hm.l == 2, "Hidrógeno: deshacer vuelve al orbital anterior")

# --- Fase 3: partículas y Coulomb ------------------------------------------------------

func _t_modulo_particulas() -> void:
	lab.open_module("particulas")
	await get_tree().process_frame
	if not _abierto("particulas"):
		return
	if lab.playing:
		lab.toggle_play()
	var pm = lab.module
	check(pm.cargar({"preset": 1, "n": 2, "eps": 0.0, "dt": 0.005, "caja": 0.0}) == "", "Partículas: preset «Átomo clásico»")
	var e_ini: float = pm.e0
	var r_max := 0.0
	var steps := int(round(10.0 * TAU / sqrt((pm.mp + 1.0) / pm.mp) / 0.005))
	for i in steps:
		pm.step(0.005)
		if i % 50 == 0:
			pm.sync(true)
			r_max = maxf(r_max, absf(Vector3(pm.p[4] - pm.p[0], pm.p[5] - pm.p[1], pm.p[6] - pm.p[2]).length() - 1.0))
	pm.sync(true)
	var en: PackedFloat64Array = Fisica.CoulombEnergy(pm.p, pm.v, 0.0)
	var drift := absf(en[0] + en[1] - e_ini) / absf(e_ini)
	check(absf(e_ini + 0.5) < 1e-6 and drift < 1e-4 and r_max < 1e-3,
		"Partículas: 10 órbitas de Kepler con Verlet (Δt = 0,005) conservan E = −Eₕ/2 (deriva %s) y el radio (±%s a₀) [%s]" % [LabUI.sci(drift, 1), LabUI.sci(r_max, 1), pm.device()])
	check(pm.cargar({"preset": 0, "n": 600, "eps": 0.05, "dt": 0.002, "caja": 0.0}) == "", "Partículas: plasma de 600 cargas sin paredes")
	for i in 100:
		pm.step(0.002)
	pm.sync(true)
	var e2: PackedFloat64Array = Fisica.CoulombEnergy(pm.p, pm.v, 0.0025)
	var ptot := Vector3(e2[2], e2[3], e2[4]).length()
	var pscale := 0.0
	for i in 600:
		pscale += Vector3(pm.v[4 * i], pm.v[4 * i + 1], pm.v[4 * i + 2]).length() / pm.v[4 * i + 3]
	check(ptot / pscale < 1e-4, "Partículas: el momento total se conserva (|ΣP| / Σ|p| = %s)" % LabUI.sci(ptot / pscale, 1))
	check(pm.finito(), "Partículas: estado finito tras la simulación")
	pm.p[0] = NAN
	check(not pm.finito(), "Partículas: un NaN en las posiciones se detecta (el laboratorio pausa)")
	check(pm.cargar({"preset": 0, "n": 400, "eps": 0.05, "dt": 0.002, "caja": 2.0}) == "", "Partículas: plasma con paredes")
	for i in 200:
		pm.step(0.002)
	pm.sync(true)
	var dentro := true
	for i in 400:
		for k in 3:
			dentro = dentro and absf(pm.p[4 * i + k]) <= 2.0 + 1e-4
	check(dentro, "Partículas: con caja, ninguna carga sale de las paredes")
	check(pm.cargar({"preset": 7, "n": 2, "eps": 0.0, "dt": 0.005, "caja": 0.0}) != "" and pm.cargar({"preset": 0}) != "",
		"Partículas: estados no válidos se rechazan")
	if "bench" in OS.get_cmdline_user_args() and pm.gpu != null:
		pm.cargar({"preset": 0, "n": 10000, "eps": 0.05, "dt": 0.005, "caja": 4.0})
		lab.toggle_play()
		for i in 60:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in 120:
			await get_tree().process_frame
		var fps := 120.0 / ((Time.get_ticks_usec() - t0) / 1e6)
		check(fps >= 55.0, "Rendimiento: 10 000 cargas en la GPU a %.0f FPS (objetivo 60; física %.2f ms por fotograma)" % [fps, lab.physics_ms])
		lab.toggle_play()

# --- Fase 3: el pilar ------------------------------------------------------------------

func _t_pilar() -> void:
	var niveles := ["exacto", "aproximado", "ilustrativo"]
	for m in MathLab.MODULES:
		if int(m["pilar"]) != 4:
			continue
		lab.open_module(m["id"])
		await get_tree().process_frame
		var f: Array = lab.module.fidelidad() if lab.module_id == m["id"] else []
		var bien := not f.is_empty()
		for s in f:
			bien = bien and str(s.get("nivel", "")) in niveles and str(s.get("modelo", "")) != "" and str(s.get("unidades", "")) != ""
		check(bien and not lab.model_button.disabled, "«%s» declara modelo, nivel de fidelidad y unidades de cada subsistema" % m["nombre"])
	lab.open_module("onda")
	await get_tree().process_frame
	await get_tree().process_frame
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 20:
		for id in ["hidrogeno", "particulas", "onda"]:
			lab.open_module(id)
			await get_tree().process_frame
	await get_tree().process_frame
	var after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	check(absf(after - before) <= 5.0, "Montar y desmontar 20 veces hidrógeno y partículas no deja nodos sueltos (%d → %d)" % [before, after])
