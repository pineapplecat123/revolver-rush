extends Control
## 燃烧：目标身上往上窜的火苗和余烬。自绘，Compatibility 友好。

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var base_y: float = size.y * 0.72
	var n := 6
	for i in n:
		var phase: float = _t * (7.5 + float(i) * 1.3) + float(i) * 1.7
		var flick: float = 0.45 + 0.55 * absf(sin(phase))
		var x: float = size.x * (0.22 + 0.56 * float(i) / float(n - 1))
		x += sin(phase * 0.8) * 3.5
		var rise: float = fmod(_t * (26.0 + float(i) * 9.0) + float(i) * 11.0, 34.0)
		var h: float = (12.0 + float(i % 3) * 4.0) * flick
		var tip := Vector2(x + sin(phase) * 2.0, base_y - rise - h)
		var foot := Vector2(x, base_y - rise * 0.25)
		var col := Color(1.0, 0.42 + 0.2 * flick, 0.05, 0.35 + 0.45 * flick)
		draw_line(foot, tip, col, 2.2 + flick * 2.4, true)
		draw_circle(tip, 2.4 + flick * 2.2, Color(1.0, 0.9, 0.45, 0.55 + 0.4 * flick))
		# 余烬点
		var ey: float = fmod(_t * (40.0 + float(i) * 6.0) + float(i) * 8.0, 46.0)
		draw_circle(Vector2(x + sin(phase * 1.4) * 6.0, base_y - ey), 1.5, Color(1.0, 0.75, 0.25, 0.7 * flick))
