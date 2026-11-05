extends Node2D
## v0.4.34：全身燃烧——火苗覆盖躯干/头/腿区 + 上升黑烟。自绘，Compatibility 友好。
## 挂在 SkeletonEnemy（或 UnitBody）上，随目标移动；按目标 scale 放大。

var _t: float = 0.0
var body_w: float = 56.0
var body_h: float = 100.0
var _active: bool = true


func _ready() -> void:
	z_index = 8
	set_process(true)


func configure(w: float, h: float, scale_mul: float = 1.0) -> void:
	body_w = maxf(40.0, w) * maxf(0.85, scale_mul)
	body_h = maxf(70.0, h) * maxf(0.85, scale_mul)
	queue_redraw()


func set_burn_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if on:
		queue_redraw()


func _process(delta: float) -> void:
	if not _active or not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var aa: bool = RrAa.ENABLED
	var half_w: float = body_w * 0.5
	var base_y: float = 8.0
	var top_y: float = -body_h * 0.92
	# —— 躯干底层橙红晕（全身罩住）——
	var core := Color(1.0, 0.35, 0.05, 0.22)
	draw_circle(Vector2(0, top_y + body_h * 0.38), body_w * 0.42, core)
	draw_circle(Vector2(0, top_y + body_h * 0.62), body_w * 0.36, Color(1.0, 0.45, 0.08, 0.18))
	draw_circle(Vector2(0, top_y + body_h * 0.18), body_w * 0.28, Color(1.0, 0.55, 0.12, 0.16))
	# —— 全身火舌（多列从脚到头）——
	var cols := 9
	for i in cols:
		var u: float = float(i) / float(cols - 1)
		var x: float = lerpf(-half_w * 0.85, half_w * 0.85, u)
		var phase: float = _t * (6.5 + float(i) * 0.7) + float(i) * 1.3
		var flick: float = 0.4 + 0.6 * absf(sin(phase))
		# 每列多段火舌覆盖身高
		for band in 4:
			var band_u: float = float(band) / 3.0
			var foot_y: float = lerpf(base_y, top_y + 18.0, band_u)
			var rise: float = fmod(_t * (38.0 + float(i) * 7.0 + float(band) * 11.0) + float(i + band) * 9.0, 28.0)
			var h: float = (14.0 + float(i % 3) * 5.0 + float(band) * 3.0) * flick
			var tip := Vector2(x + sin(phase + band) * 3.5, foot_y - rise - h)
			var foot := Vector2(x, foot_y - rise * 0.2)
			var col := Color(1.0, 0.38 + 0.25 * flick, 0.04, 0.28 + 0.4 * flick)
			draw_line(foot, tip, col, 2.4 + flick * 2.6, aa)
			draw_circle(tip, 2.2 + flick * 2.0, Color(1.0, 0.92, 0.45, 0.5 + 0.35 * flick))
	# —— 上升黑烟（盖全身宽）——
	var smoke_n := 7
	for i in smoke_n:
		var phase: float = _t * (1.6 + float(i) * 0.25) + float(i) * 2.1
		var x: float = sin(phase) * half_w * 0.55 + float(i - 3) * 4.0
		var travel: float = fmod(_t * (22.0 + float(i) * 5.0) + float(i) * 13.0, body_h * 1.15)
		var y: float = base_y - 10.0 - travel
		var life: float = 1.0 - travel / (body_h * 1.15)
		var rad: float = 4.5 + float(i % 3) * 2.2 + (1.0 - life) * 6.0
		var a: float = 0.18 + 0.28 * life
		draw_circle(Vector2(x, y), rad, Color(0.12, 0.12, 0.14, a))
		draw_circle(Vector2(x + 3.0, y - 4.0), rad * 0.7, Color(0.2, 0.18, 0.16, a * 0.7))
