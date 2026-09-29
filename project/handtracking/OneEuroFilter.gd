class_name OneEuroFilter
extends RefCounted
## Filtro One Euro (Casiez, Roussel y Vogel, CHI 2012) para señales ruidosas en
## tiempo real. Es un paso bajo exponencial cuya frecuencia de corte crece con la
## velocidad de la señal:
##     corte = min_cutoff + beta·|dx/dt|
## En reposo el corte es bajo (mucho suavizado: sin temblor al sostener una
## gráfica). En un movimiento rápido el corte sube y el retardo casi desaparece.
##   · min_cutoff (Hz): menos = más estable en reposo.
##   · beta: más = menos retardo en movimientos rápidos.
##   · d_cutoff (Hz): corte con el que se suaviza la propia velocidad.
## Filtra escalares, Vector2 o Vector3 (componente a componente, en doble
## precisión).

var min_cutoff: float = 1.0
var beta: float = 10.0
var d_cutoff: float = 1.0
var _x: Array = []
var _dx: Array = []
var _t: float = -1.0

func _init(p_min_cutoff: float = 1.0, p_beta: float = 10.0, p_d_cutoff: float = 1.0) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	d_cutoff = p_d_cutoff

static func alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)

func reset() -> void:
	_x.clear()
	_dx.clear()
	_t = -1.0

## Filtra el valor v (float, Vector2 o Vector3) medido en el instante t (s).
func filter(v, t: float):
	var comps := _to_array(v)
	if _x.size() != comps.size() or _t < 0.0:
		_x = comps.duplicate()
		_dx = []
		_dx.resize(comps.size())
		_dx.fill(0.0)
		_t = t
		return v
	var dt := t - _t
	if dt <= 1e-6:
		dt = 1.0 / 60.0
	_t = t
	var ad := alpha(d_cutoff, dt)
	for i in range(comps.size()):
		var dx: float = (float(comps[i]) - float(_x[i])) / dt
		_dx[i] = lerpf(_dx[i], dx, ad)
		var a := alpha(min_cutoff + beta * absf(_dx[i]), dt)
		_x[i] = lerpf(_x[i], float(comps[i]), a)
	return _from_array(_x, v)

static func _to_array(v) -> Array:
	match typeof(v):
		TYPE_VECTOR2: return [v.x, v.y]
		TYPE_VECTOR3: return [v.x, v.y, v.z]
	return [float(v)]

static func _from_array(a: Array, like):
	match typeof(like):
		TYPE_VECTOR2: return Vector2(a[0], a[1])
		TYPE_VECTOR3: return Vector3(a[0], a[1], a[2])
	return a[0]
