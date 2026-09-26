class_name LiveGraph
extends Control
## LiveGraph — Osciloscopio/gráfica en vivo dibujada con _draw().
##
## Muestra una o varias series (t, valores) con autoescala, rejilla y leyenda.
## Uso: set_series(tiempos, [{"nombre","color","valores"}, ...]).

var _t: Array = []
var _series: Array = []
var _title: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)

func set_title(t: String) -> void:
	_title = t

func set_series(tiempos: Array, series: Array) -> void:
	_t = tiempos
	_series = series
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Fondo.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, 0.9))
	var m := 6.0
	var plot := Rect2(m, m, w - 2 * m, h - 2 * m)
	# Rejilla.
	var grid := Color(0.2, 0.22, 0.26)
	for i in range(5):
		var y := plot.position.y + plot.size.y * i / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y), grid, 1.0)

	var font := ThemeDB.fallback_font
	if _title != "":
		draw_string(font, Vector2(m + 2, m + 12), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.73, 0.78))

	if _t.size() < 2 or _series.is_empty():
		draw_string(font, plot.position + Vector2(4, plot.size.y * 0.5), "Sin datos…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.53, 0.58))
		return

	# Rango de valores (autoescala) sobre todas las series.
	var vmin := INF
	var vmax := -INF
	for s in _series:
		for v in s["valores"]:
			vmin = minf(vmin, float(v))
			vmax = maxf(vmax, float(v))
	if vmin == vmax:
		vmin -= 1.0; vmax += 1.0
	var pad := (vmax - vmin) * 0.1
	vmin -= pad; vmax += pad

	var t0: float = float(_t[0])
	var t1: float = float(_t[_t.size() - 1])
	var tspan := maxf(0.0001, t1 - t0)

	# Línea del cero si está en rango.
	if vmin < 0.0 and vmax > 0.0:
		var yz := plot.position.y + plot.size.y * (1.0 - (0.0 - vmin) / (vmax - vmin))
		draw_line(Vector2(plot.position.x, yz), Vector2(plot.position.x + plot.size.x, yz), Color(0.35, 0.38, 0.42), 1.0)

	# Series.
	var legend_x := plot.position.x + 6
	for s in _series:
		var vals: Array = s["valores"]
		var col: Color = s["color"]
		var pts := PackedVector2Array()
		var n := mini(vals.size(), _t.size())
		for i in range(n):
			var x := plot.position.x + plot.size.x * (float(_t[i]) - t0) / tspan
			var y := plot.position.y + plot.size.y * (1.0 - (float(vals[i]) - vmin) / (vmax - vmin))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, col, 1.8, true)
		draw_string(font, Vector2(legend_x, plot.position.y + plot.size.y - 6), s["nombre"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		legend_x += 90

	# Etiquetas de rango.
	draw_string(font, Vector2(plot.position.x + plot.size.x - 60, m + 12), "%.2f" % vmax, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.58, 0.62))
	draw_string(font, Vector2(plot.position.x + plot.size.x - 60, h - 8), "%.2f" % vmin, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.58, 0.62))
