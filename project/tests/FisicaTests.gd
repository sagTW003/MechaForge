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
	_t_modelo_estandar()
	_t_desintegraciones()
	_t_lorentz()
	await _t_modulo_desintegraciones()
	_t_bateria()
	await _t_modulo_bateria()
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

# --- Fase 4a: Modelo Estándar, conservación, desintegraciones y Lorentz ------------------

func _t_modelo_estandar() -> void:
	var ids := Array(Fisica.ParticleIds())
	var basicas := 0
	for k in ["u", "d", "s", "c", "b", "t", "e-", "nu_e", "mu-", "nu_mu", "tau-", "nu_tau", "gamma", "g", "W+", "Z", "H"]:
		if k in ids:
			basicas += 1
	check(basicas == 17, "Modelo Estándar: 6 quarks, 6 leptones, γ, g, W, Z y H en la tabla (%d partículas con las antipartículas)" % ids.size())
	var ep: Dictionary = Fisica.ParticleInfo("e+")
	var pim: Dictionary = Fisica.ParticleInfo("pi-")
	var km: Dictionary = Fisica.ParticleInfo("K-")
	check(ep["carga3"] == 3 and ep["Le"] == -1 and str(pim["canales"][0]["texto"]) == "π⁻ → μ⁻ ν̄_μ" and str(km["quarks"]) == "u~s",
		"Antipartículas: e⁺ con q = +1 y Lₑ = −1; π⁻ → μ⁻ ν̄_μ (canales conjugados); K⁻ = ūs")
	var u: Dictionary = Fisica.ParticleInfo("u")
	check(u["carga"] == "+2/3" and u["B"] == "+1/3" and u["espin"] == "1/2" and u["color"] == "triplete",
		"Quark u: q = +2/3, B = 1/3, espín 1/2, triplete de color")
	# Cada canal de la tabla cumple todas las leyes: comprueba lo copiado del PDG.
	var malos := []
	var n_canales := 0
	for id in ids:
		for c in Fisica.ParticleInfo(id)["canales"]:
			n_canales += 1
			var v: PackedStringArray = Fisica.Conservation(PackedStringArray([id]), PackedStringArray(c["productos"]), true)
			if not v.is_empty():
				malos.append("%s: %s" % [c["texto"], ", ".join(v)])
	check(malos.is_empty(), "Los %d canales de la tabla conservan carga, B, Lₑ, L_μ, L_τ, energía y paridad de fermiones%s" % [
		n_canales, "" if malos.is_empty() else ": " + "; ".join(malos)])
	# Y las leyes detectan lo prohibido, diciendo cuál.
	var casos := [
		[["n"], ["p", "e-"], "leptónico electrónico"],
		[["p"], ["e+", "gamma"], "bariónico"],
		[["pi+"], ["mu+", "nu_mu~"], "leptónico muónico"],
		[["mu-"], ["e-", "gamma"], "leptónico muónico"],
		[["pi0"], ["p", "p~"], "energía"],
		[["pi+"], ["e+", "gamma"], "momento angular"],
		[["e-"], ["nu_e", "gamma"], "carga eléctrica"],
	]
	var detectados := 0
	for cs in casos:
		var v2: PackedStringArray = Fisica.Conservation(PackedStringArray(cs[0]), PackedStringArray(cs[1]), true)
		if ", ".join(v2).contains(cs[2]):
			detectados += 1
	check(detectados == casos.size(), "Las leyes detectan lo prohibido y dicen cuál (n → p e⁻, p → e⁺γ, π⁺ → μ⁺ν̄_μ, μ⁻ → e⁻γ, π⁰ → pp̄, π⁺ → e⁺γ, e⁻ → νₑγ): %d/%d" % [detectados, casos.size()])
	var pip: Dictionary = Fisica.ParticleInfo("pi+")
	var eta: Dictionary = Fisica.ParticleInfo("eta")
	var hbar := 6.62607015e-34 / TAU / 1.602176634e-19 / 1e9
	check(absf(float(pip["vida_s"]) / 2.6033e-8 - 1.0) < 1e-12 and absf(float(eta["vida_s"]) * 1.31e-6 / hbar - 1.0) < 1e-12,
		"Vidas medias: τ(π⁺) = 2,6033·10⁻⁸ s del PDG; τ(η) = ħ/Γ con Γ = 1,31 keV")

static func _circumradius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area2 := absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
	return ab * bc * ca / (2.0 * area2)

func _t_desintegraciones() -> void:
	var mpi := 0.13957039
	var mmu := 0.1056583755
	var pstar: float = Fisica.TwoBodyP(mpi, mmu, 0.0)
	check(absf(pstar - (mpi * mpi - mmu * mmu) / (2.0 * mpi)) < 1e-15, "Dos cuerpos: p* del π⁺ → μ⁺ν = (m_π² − m_μ²)/2m_π = %.4f MeV" % (pstar * 1000.0))
	var n_v := 0
	var malos := 0
	for sd in 120:
		for id in ["K+", "K_L", "tau-", "Lambda", "eta", "K_S"]:
			for tr in Fisica.DecayEvent(id, 0.6, 1.5, 10.0, 4, 1000 + sd):
				if bool(tr["decae"]):
					n_v += 1
					if not (tr["violaciones"] as PackedStringArray).is_empty():
						malos += 1
	check(n_v > 300 and malos == 0, "Sucesos: %d vértices (K⁺, K_L, K_S, τ⁻, Λ, η y sus productos) conservan todas las leyes y el cuadrimomento" % n_v)
	var nk := 200000
	var counts: PackedInt32Array = Fisica.SampleChannels("K+", nk, 7)
	var canales: Array = Fisica.ParticleInfo("K+")["canales"]
	var peor := 0.0
	for i in counts.size():
		var pe: float = canales[i]["br_norm"]
		peor = maxf(peor, absf(counts[i] - nk * pe) / sqrt(nk * pe * (1.0 - pe)))
	check(peor < 4.0, "Fracciones: 200 000 desintegraciones del K⁺ reparten los canales como el PDG (desviación máx. %.1fσ)" % peor)
	var bgct := 1.0 / mpi * 299792458.0 * 2.6033e-8
	var nl := 20000
	var lm: float = Fisica.MeanDecayLength("pi+", 1.0, nl, 3)
	var zl := absf(lm - bgct) / (bgct / sqrt(nl))
	check(zl < 4.0, "Vuelo: longitud media del π⁺ con p = 1 GeV/c = βγcτ = %.2f m (muestra %.2f m, %.1fσ)" % [bgct, lm, zl])
	var ev: Array = Fisica.DecayEvent("e+", 0.1, 1.0, 1.0, 1, 5)
	var pts: PackedVector3Array = ev[0]["puntos"]
	var a := pts[0]
	var b := pts[pts.size() / 7]
	var c := pts[2 * pts.size() / 7]
	var r := _circumradius(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
	var re := 0.1 / 0.299792458
	check(absf(r / re - 1.0) < 1e-4, "Trazas: un positrón de 0,1 GeV/c en 1 T gira con R = p/(0,3qB) = %.4f m (medido %.4f m)" % [re, r])

func _t_lorentz() -> void:
	# Electrón (q = −1, m = 1) en B = 1 u.a. sin otras fuerzas: ciclotrón de radio v/ω = 1.
	var p := PackedFloat32Array([0, 0, 0, -1])
	var v := PackedFloat32Array([1, 0, 0, 1])
	var h := 0.01
	var xmin := INF
	var xmax := -INF
	var vmax_err := 0.0
	for i in int(TAU / h) + 5:
		v = PackedFloat32Array(Fisica.CoulombRotate(p, v, 1.0, h))
		var pv := PackedFloat32Array(Fisica.CoulombDrift(p, v, h, 0.0))
		p = pv.slice(0, 4)
		v = pv.slice(4)
		xmin = minf(xmin, p[0])
		xmax = maxf(xmax, p[0])
		vmax_err = maxf(vmax_err, absf(Vector2(v[0], v[1]).length() - 1.0))
	check(absf((xmax - xmin) / 2.0 - 1.0) < 1e-3 and vmax_err < 1e-6,
		"Lorentz (Boris): ciclotrón de radio v/(qB/m) = 1 a₀ (medido %.5f) y |v| constante (error %s)" % [(xmax - xmin) / 2.0, LabUI.sci(vmax_err, 1)])
	var pd := PackedFloat32Array([-1, 0, 0, 1, 1, 0, 0, -1])
	var pts: PackedFloat32Array = Fisica.FieldLines(pd, 1e-4, 10, 600, 0.02, 6.0)
	var llegan := 0
	for i in range(3, pts.size(), 3):
		if is_nan(pts[i]) and not is_nan(pts[i - 3]):
			if Vector3(pts[i - 3], pts[i - 2], pts[i - 1]).distance_to(Vector3(1, 0, 0)) < 0.05:
				llegan += 1
	check(llegan >= 6, "Líneas de campo de un dipolo: %d de 10 salen de la carga positiva y llegan a la negativa" % llegan)

func _t_modulo_desintegraciones() -> void:
	lab.open_module("desintegraciones")
	await get_tree().process_frame
	if not _abierto("desintegraciones"):
		return
	var dm = lab.module
	check(dm.trazas.size() >= 2 and lab.info_label.text.contains("conserva todo"),
		"Módulo «Desintegraciones»: suceso del K⁺ con su cadena y las conservaciones en la información")
	check(dm.cargar({"particula": "Lambda", "p": 1.0, "B": 2.0, "cadena": true}) == "" and dm.trazas[0]["id"] == "Lambda",
		"Desintegraciones: cargar otro estado (Λ, 1 GeV/c, 2 T)")
	check(dm.cargar({"particula": "p", "p": 1.0, "B": 1.0}) != "", "Desintegraciones: una partícula estable se rechaza")
	check(dm.ficha("mu-").contains("μ⁻ → e⁻ ν̄ₑ ν_μ") and dm.ficha("u").contains("triplete"),
		"Ficha de partícula: canales del μ⁻ y color del quark u")
	lab.open_module("particulas")
	await get_tree().process_frame
	var pm = lab.module
	if lab.playing:
		lab.toggle_play()
	check(pm.cargar({"preset": 0, "n": 300, "eps": 0.1, "dt": 0.002, "caja": 3.0, "B": 1.5, "lineas": true}) == "", "Partículas: plasma con campo B y líneas de campo")
	for i in 50:
		pm.step(0.002)
	pm._refresh_lines()
	check(pm.finito() and (pm.lines_mesh.mesh as ImmediateMesh).get_surface_count() == 1, "Partículas con B: estado finito y líneas de campo dibujadas")
	if pm.gpu != null:
		# Mismo estado, 5 pasos de Boris en la GPU y los mismos 5 con las funciones de C#.
		pm.sync(true)
		var cp: PackedFloat32Array = pm.p.duplicate()
		var cv: PackedFloat32Array = pm.v.duplicate()
		var cf: PackedFloat32Array = pm.f.duplicate()
		var eps2: float = pm.eps * pm.eps
		for i in 5:
			pm.step(0.002)
			cv = PackedFloat32Array(Fisica.CoulombKick(cv, cf, 0.001))
			cv = PackedFloat32Array(Fisica.CoulombRotate(cp, cv, pm.bz, 0.002))
			cv = PackedFloat32Array(Fisica.CoulombKick(cv, cf, 0.001))
			var pv := PackedFloat32Array(Fisica.CoulombDrift(cp, cv, 0.002, pm.caja))
			cp = pv.slice(0, cp.size())
			cv = pv.slice(cp.size())
			cf = PackedFloat32Array(Fisica.CoulombForces(cp, eps2))
		pm.sync(true)
		var dmax := 0.0
		for i in cp.size():
			if i % 4 != 3:
				dmax = maxf(dmax, absf(pm.p[i] - cp[i]))
		check(dmax < 1e-4, "GPU: 5 pasos con campo B (Boris, kernel verlet.glsl modo 2) coinciden con C# (diferencia máx. %s a₀)" % LabUI.sci(dmax, 1))

# --- Fase 4b: batería cuántica ----------------------------------------------------------

## Energía almacenada tras cargar t con g (sin interacción) en una cadena de n espines.
func _carga(n: int, j: float, d: float, g: float, t: float, dt: float) -> PackedFloat64Array:
	var psi := PackedFloat64Array(Fisica.SpinEmpty(n))
	for i in int(round(t / dt)):
		psi = PackedFloat64Array(Fisica.SpinStep(psi, n, j, d, g, dt))
	return psi

func _t_bateria() -> void:
	var peor := 0.0
	for nn in [1, 8]:
		for tt in [0.3, 0.8, PI / 2.0]:
			var psi := _carga(nn, 0.0, 0.0, 1.0, tt, 0.01 if tt != PI / 2.0 else PI / 200.0)
			var o: PackedFloat64Array = Fisica.SpinObservables(psi, nn, 1.0, 0.0, 0.0, 1.0)
			var e: float = o[0] + nn * 0.5
			peor = maxf(peor, absf(e - nn * pow(sin(tt), 2)))
	check(peor < 1e-9, "Batería: sin interacción la energía almacenada es Nω₀·sin²(gt) para N = 1 y 8 (error máx. %s)" % LabUI.sci(peor, 1))
	var psi2 := PackedFloat64Array(Fisica.SpinEmpty(6))
	var o0: PackedFloat64Array = Fisica.SpinObservables(psi2, 6, 1.0, 0.3, 0.5, 0.8)
	for i in 500:
		psi2 = PackedFloat64Array(Fisica.SpinStep(psi2, 6, 0.3, 0.5, 0.8, 0.02))
	var o1: PackedFloat64Array = Fisica.SpinObservables(psi2, 6, 1.0, 0.3, 0.5, 0.8)
	check(absf(o1[2] - 1.0) < 1e-10 and absf(o1[1] - o0[1]) < 1e-9,
		"Batería con J = 0,3, Δ = 0,5: tras 500 pasos la norma (%s) y ⟨H_rot⟩ (Δ = %s) se conservan" % [LabUI.sci(absf(o1[2] - 1.0), 1), LabUI.sci(absf(o1[1] - o0[1]), 1)])
	var a := _carga(6, 0.3, 0.5, 0.8, 1.0, 0.1)
	var b := _carga(6, 0.3, 0.5, 0.8, 1.0, 0.005)
	var dif := 0.0
	for k in a.size():
		dif = maxf(dif, absf(a[k] - b[k]))
	check(dif < 1e-9, "Krylov: 10 pasos de 0,1 y 200 de 0,005 dan el mismo estado (diferencia máx. %s)" % LabUI.sci(dif, 1))
	var pe := _carga(2, 0.4, 0.0, 0.7, 1.3, 0.01)
	var oe: PackedFloat64Array = Fisica.SpinObservables(pe, 2, 1.0, 0.4, 0.0, 0.7)
	var eg: float = oe[0] - Fisica.SpinGroundEnergy(2, 1.0, 0.4, 0.0)
	var pp := _carga(2, 0.0, 0.0, 0.7, 1.3, 0.01)
	var op: PackedFloat64Array = Fisica.SpinObservables(pp, 2, 1.0, 0.0, 0.0, 0.7)
	var egp: float = op[0] - Fisica.SpinGroundEnergy(2, 1.0, 0.0, 0.0)
	check(oe[3] < eg - 1e-3 and absf(op[3] - egp) < 1e-9,
		"Ergotropía: sin interacción la local es la global (%.4f); con J = 0,4 el entrelazamiento la deja por debajo (%.4f < %.4f)" % [egp, oe[3], eg])
	check(absf(Fisica.SpinGroundEnergy(5, 1.0, 0.0, 0.0) + 2.5) < 1e-9,
		"Batería: el mínimo de H_B sin interacción es −Nω₀/2 (Lanczos)")
	var p12 := PackedFloat64Array(Fisica.SpinEmpty(12))
	var t0 := Time.get_ticks_usec()
	for i in 5:
		p12 = PackedFloat64Array(Fisica.SpinStep(p12, 12, 0.2, 0.5, 1.0, 0.02))
	var ms := (Time.get_ticks_usec() - t0) / 5000.0
	check(ms < 10.0, "Rendimiento: un paso con N = 12 (4096 estados) en %.1f ms (a velocidad 1 hacen falta ~50 por segundo)" % ms)

func _t_modulo_bateria() -> void:
	lab.open_module("bateria")
	await get_tree().process_frame
	if not _abierto("bateria"):
		return
	if lab.playing:
		lab.toggle_play()
	var bm = lab.module
	check(bm.cargar({"n": 4, "w0": 1.0, "g": 1.0, "J": 0.0, "delta": 0.0, "auto": true, "t_carga": PI / 2.0, "t_almacen": 0.5}) == "",
		"Módulo «Batería cuántica»: 4 espines, ciclo automático")
	var e_carga := 0.0
	while bm.fase == 0:
		bm.step(0.02)
	e_carga = bm.e_fin_carga
	while bm.fase != 3:
		bm.step(0.02)
	check(absf(e_carga - 4.0) < 0.02 and absf(bm.stored()) < 0.08 and bm.finito(),
		"Batería: la carga llega a ≈ Nω₀ (%.3f) y la descarga la devuelve (quedan %.3f ω₀)" % [e_carga, bm.stored()])
	check(lab.info_label.text.contains("Ergotropía") or bm.info().contains("Ergotropía"), "Batería: energía, potencia y ergotropía en la información")
	check(bm.cargar({"n": 20, "w0": 1.0, "g": 1.0, "J": 0.0, "delta": 0.0}) != "", "Batería: N > 12 se rechaza")
