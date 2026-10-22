class_name HeadTracking
extends RefCounted
## HeadTracking — Seguimiento de la cabeza: orientación real del visor frente a la que
## estima el programa con la IMU (alabeo, cabeceo y guiñada en ejes del chip, en °).
##
## HeadsetRig añade una muestra por paso de simulación: el tiempo, la orientación real
## (Sensors.imu_angles de la IMU; la guiñada respecto del arranque), la estimada
## (variables roll, pitch y yaw del programa) y el error angular de la vista que se
## mostraría con esa estimación. De ahí salen:
##   · el error RMS y máximo de cada eje (sin el primer segundo, arranque del filtro);
##   · la deriva de la guiñada: pendiente del error de guiñada (°/min);
##   · la latencia del filtro: el retardo τ con que la real mejor se superpone a la
##     estimada, est(t) ≈ real(t − τ), quitando de cada eje su desvío lineal (sesgo y
##     deriva) para que no cuente como retardo;
##   · el error de la vista (RMS y máximo).

const MAX_SAMPLES := 14400          # 2 min a 120 Hz
const SETTLE_S := 1.0               # se descarta el primer segundo
const LATENCY_MAX_MS := 250.0
const LATENCY_WINDOW_S := 12.0      # la latencia se calcula con los últimos segundos

var t := PackedFloat64Array()
# Por eje, Arrays normales: un PackedFloat64Array dentro de un Array se copiaría al
# añadirle valores.
var real := [[], [], []]
var est := [[], [], []]
var view_err := PackedFloat64Array()

func clear() -> void:
	t = PackedFloat64Array()
	real = [[], [], []]
	est = [[], [], []]
	view_err = PackedFloat64Array()

func size() -> int:
	return t.size()

func add(time: float, r: Vector3, e: Vector3, verr: float) -> void:
	t.append(time)
	for k in range(3):
		(real[k] as Array).append(r[k])
		(est[k] as Array).append(e[k])
	view_err.append(verr)
	if t.size() > MAX_SAMPLES:
		var cut := MAX_SAMPLES / 10
		t = t.slice(cut)
		for k in range(3):
			real[k] = (real[k] as Array).slice(cut)
			est[k] = (est[k] as Array).slice(cut)
		view_err = view_err.slice(cut)

## Orientación estimada en el instante «time» (interpolada; la primera si es anterior).
func est_at(time: float) -> Vector3:
	var n := t.size()
	if n == 0:
		return Vector3.ZERO
	if time <= t[0]:
		return Vector3(est[0][0], est[1][0], est[2][0])
	if time >= t[n - 1]:
		return Vector3(est[0][n - 1], est[1][n - 1], est[2][n - 1])
	var i := t.bsearch(time)            # primer índice con t ≥ time
	var t0 := t[i - 1]
	var u := (time - t0) / maxf(1e-12, t[i] - t0)
	return Vector3(lerpf(est[0][i - 1], est[0][i], u), lerpf(est[1][i - 1], est[1][i], u), lerpf(est[2][i - 1], est[2][i], u))

func _first_settled() -> int:
	if t.is_empty():
		return 0
	var i := t.bsearch(t[0] + SETTLE_S)
	return mini(i, t.size())

## Estadísticas del registro (vacío si aún no hay datos tras el arranque).
func stats() -> Dictionary:
	var i0 := _first_settled()
	var n := t.size() - i0
	if n < 10:
		return {}
	var rms := [0.0, 0.0, 0.0]
	var mx := [0.0, 0.0, 0.0]
	var rng := [0.0, 0.0, 0.0]
	for k in range(3):
		var ss := 0.0
		var lo := INF
		var hi := -INF
		for i in range(i0, t.size()):
			var d: float = est[k][i] - real[k][i]
			ss += d * d
			mx[k] = maxf(mx[k], absf(d))
			lo = minf(lo, real[k][i])
			hi = maxf(hi, real[k][i])
		rms[k] = sqrt(ss / n)
		rng[k] = hi - lo
	# Deriva de la guiñada: recta por mínimos cuadrados del error frente al tiempo, con
	# la real retrasada la latencia del filtro (si no, el retraso de una guiñada que va
	# y viene sesga la pendiente).
	var lat := latency_ms()
	var tau := lat / 1000.0 if not is_nan(lat) else 0.0
	var st := 0.0
	var stt := 0.0
	var sd := 0.0
	var std := 0.0
	var ve := 0.0
	var vmax := 0.0
	for i in range(i0, t.size()):
		var tt: float = t[i] - t[i0]
		var d: float = est[2][i] - _real_at(2, t[i] - tau)
		st += tt
		stt += tt * tt
		sd += d
		std += tt * d
		ve += view_err[i] * view_err[i]
		vmax = maxf(vmax, view_err[i])
	var den := n * stt - st * st
	var slope := (n * std - st * sd) / den if den > 1e-12 else 0.0
	return {
		"muestras": n, "duracion_s": t[t.size() - 1] - t[i0],
		"rms_deg": rms, "max_deg": mx, "recorrido_deg": rng,
		"deriva_guinada_deg_min": slope * 60.0,
		"latencia_ms": lat,
		"error_vista_rms_deg": sqrt(ve / n), "error_vista_max_deg": vmax,
	}

## Orientación real del eje k en el instante «time» (interpolada).
func _real_at(k: int, time: float) -> float:
	var n := t.size()
	if time <= t[0]:
		return real[k][0]
	if time >= t[n - 1]:
		return real[k][n - 1]
	var i := t.bsearch(time)
	var u := (time - t[i - 1]) / maxf(1e-12, t[i] - t[i - 1])
	return lerpf(real[k][i - 1], real[k][i], u)

## Latencia del filtro (ms) con los últimos LATENCY_WINDOW_S segundos (a ~60 Hz).
func latency_ms() -> float:
	var i0 := maxi(_first_settled(), t.bsearch(t[t.size() - 1] - LATENCY_WINDOW_S) if not t.is_empty() else 0)
	if t.size() - i0 < 20:
		return NAN
	var stride := maxi(1, int(round(1.0 / 60.0 / maxf(1e-6, (t[t.size() - 1] - t[i0]) / (t.size() - i0)))))
	return estimate_latency(t, real, est, i0, stride)

## Retardo τ (ms, 0..LATENCY_MAX_MS) que minimiza Σ_ejes Σ_i r_i² con
## r_i = est(t_i) − real(t_i − τ) menos su recta de mínimos cuadrados (el sesgo y la
## deriva de cada eje no cuentan como retardo). Barrido cada 5 ms, refinado cada
## 0.5 ms y parábola por los tres mejores.
static func estimate_latency(ts: PackedFloat64Array, re: Array, es: Array, i0: int = 0, stride: int = 1) -> float:
	var cost := func(tau: float) -> float:
		var total := 0.0
		for k in range(3):
			var rk: Array = re[k]
			var ek: Array = es[k]
			var n := 0.0
			var st := 0.0
			var stt := 0.0
			var sr := 0.0
			var srr := 0.0
			var str_ := 0.0
			var j := 0
			var i := i0
			while i < ts.size():
				var tq: float = ts[i] - tau
				if tq < ts[0]:
					i += stride
					continue
				while j + 1 < ts.size() and ts[j + 1] < tq:
					j += 1
				if j + 1 >= ts.size():
					break
				var u: float = (tq - ts[j]) / maxf(1e-12, ts[j + 1] - ts[j])
				var r: float = ek[i] - lerpf(rk[j], rk[j + 1], u)
				var tt: float = ts[i] - ts[i0]
				n += 1.0
				st += tt
				stt += tt * tt
				sr += r
				srr += r * r
				str_ += tt * r
				i += stride
			if n < 3.0:
				continue
			var den := n * stt - st * st
			var b := (n * str_ - st * sr) / den if den > 1e-12 else 0.0
			var a := (sr - b * st) / n
			total += srr - a * sr - b * str_
		return total
	var best := 0.0
	var best_c := INF
	var tau := 0.0
	while tau <= LATENCY_MAX_MS + 1e-9:
		var c: float = cost.call(tau / 1000.0)
		if c < best_c:
			best_c = c
			best = tau
		tau += 5.0
	var lo := maxf(0.0, best - 5.0)
	var hi := minf(LATENCY_MAX_MS, best + 5.0)
	var cs := []
	tau = lo
	while tau <= hi + 1e-9:
		cs.append([tau, cost.call(tau / 1000.0)])
		tau += 0.5
	var bi := 0
	for k in range(cs.size()):
		if cs[k][1] < cs[bi][1]:
			bi = k
	best = cs[bi][0]
	if bi > 0 and bi < cs.size() - 1:
		var c0: float = cs[bi - 1][1]
		var c1: float = cs[bi][1]
		var c2: float = cs[bi + 1][1]
		var dd := c0 - 2.0 * c1 + c2
		if dd > 1e-18:
			best += 0.5 * 0.5 * (c0 - c2) / dd
	return best

## Registro en CSV: tiempo y, por eje, real y estimada (°), y el error de la vista.
func csv() -> String:
	var lines := PackedStringArray(["tiempo_s,alabeo_real,alabeo_est,cabeceo_real,cabeceo_est,guinada_real,guinada_est,error_vista_deg"])
	for i in range(t.size()):
		lines.append("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [t[i], real[0][i], est[0][i], real[1][i], est[1][i], real[2][i], est[2][i], view_err[i]])
	return "\n".join(lines) + "\n"
