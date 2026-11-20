class_name TrashCan
extends Node2D
## 巷边旧锌铁垃圾桶：竖楞圆筒、外撇口沿、侧耳、克制锈迹，口上堆着杂物。原点在左下角贴走道。

const WIDTH := 100.0
const HEIGHT := 156.0
const USE_X := 50.0
const PAD := 12.0
const BODY_H := 108.0
const BODY_RX := 36.0


var rummage_t: float = 0.0
var _anim: String = ""
var _anim_age: float = 0.0
var result_kind: String = ""


func _ready() -> void:
	visible = false
	z_as_relative = false
	z_index = 8


func set_grounded(left_x: float, ground_y: float) -> void:
	position = Vector2(floorf(left_x) + 0.5, ground_y)
	queue_redraw()


func set_prop_visible(v: bool) -> void:
	visible = v
	if v:
		queue_redraw()


func origin_global() -> Vector2:
	return global_position if is_inside_tree() else position


func reset_anim() -> void:
	rummage_t = 0.0
	_anim = ""
	_anim_age = 0.0
	result_kind = ""
	queue_redraw()


func play_rummage(kind: String = "") -> void:
	result_kind = kind
	_anim = "rummage"
	_anim_age = 0.0
	rummage_t = 0.0
	queue_redraw()


func tick_anim(dt: float) -> void:
	if _anim != "rummage":
		return
	_anim_age += maxf(0.0, dt)
	rummage_t = clampf(_anim_age / 1.15, 0.0, 1.0)
	queue_redraw()


func is_rummage_done() -> bool:
	return _anim == "rummage" and _anim_age >= 1.25


func _draw() -> void:
	var foot := Vector2(WIDTH * 0.5, 0.0)
	var shake := Vector2.ZERO
	var jostle := 0.0
	if rummage_t > 0.0 and rummage_t < 1.0:
		var w: float = (1.0 - rummage_t) * 3.4
		shake = Vector2(sin(rummage_t * 42.0) * w, cos(rummage_t * 33.0) * w * 0.25)
		jostle = sin(rummage_t * 38.0) * (1.0 - rummage_t) * 5.0
	var steel := Color(0.46, 0.50, 0.54, 1.0)
	var steel_d := Color(0.32, 0.36, 0.39, 1.0)
	var steel_l := Color(0.58, 0.62, 0.66, 1.0)
	var rust := Color(0.46, 0.28, 0.22, 0.55)
	var rust_d := Color(0.38, 0.22, 0.18, 0.40)
	# 筒身：略外撇的竖楞圆筒（用多层扁椭圆叠出体积，不加高光体块）
	var mid_y := -BODY_H * 0.52
	var rings := 9
	for i in rings:
		var k: float = float(i) / float(rings - 1)
		var y: float = -8.0 - k * (BODY_H - 10.0)
		var flare: float = 1.0 + (1.0 - k) * 0.08
		var rx: float = BODY_RX * flare
		var col := steel.lerp(steel_d, 0.35 if i % 2 == 0 else 0.0)
		_draw_ellipse(foot + Vector2(shake.x, y + shake.y), rx, 7.5, col)
	# 竖楞
	for i in 8:
		var a: float = -0.95 + 1.9 * float(i) / 7.0
		var x0: float = sin(a) * (BODY_RX * 0.92)
		var pts := PackedVector2Array()
		for k in 8:
			var t: float = float(k) / 7.0
			var y: float = -10.0 - t * (BODY_H - 14.0)
			var flare: float = 1.0 + (1.0 - t) * 0.08
			pts.append(foot + Vector2(x0 * flare, y) + shake)
		draw_polyline(pts, Color(0.28, 0.32, 0.35, 0.7), 1.4, true)
	# 克制锈斑/锈痕
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-18, -30) + shake, foot + Vector2(-10, -28) + shake,
		foot + Vector2(-12, -70) + shake, foot + Vector2(-20, -68) + shake,
	]), rust_d)
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(14, -24) + shake, foot + Vector2(20, -22) + shake,
		foot + Vector2(16, -54) + shake, foot + Vector2(10, -52) + shake,
	]), rust)
	# 底圈
	_draw_ellipse(foot + Vector2(shake.x, -6.0 + shake.y), BODY_RX * 1.08, 8.0, steel_d)
	# 外撇口沿
	var rim_y := -BODY_H + 2.0
	_draw_ellipse(foot + Vector2(shake.x, rim_y + 5.0 + shake.y), BODY_RX * 1.16, 8.5, steel_d)
	_draw_ellipse(foot + Vector2(shake.x, rim_y + shake.y), BODY_RX * 1.20, 8.0, steel_l)
	_draw_ellipse(foot + Vector2(shake.x, rim_y - 3.0 + shake.y), BODY_RX * 1.08, 6.5, Color(0.22, 0.24, 0.26, 1.0))
	# 侧耳
	_draw_handle(foot + Vector2(-BODY_RX * 1.12, -BODY_H * 0.62) + shake, -1.0)
	_draw_handle(foot + Vector2(BODY_RX * 1.12, -BODY_H * 0.62) + shake, 1.0)
	# 口上杂物（袋子/纸/瓶/盒），翻找时轻轻晃
	var pile := foot + Vector2(shake.x, rim_y - 4.0 + shake.y)
	_draw_clutter(pile, jostle)


func _draw_handle(c: Vector2, side: float) -> void:
	var col := Color(0.40, 0.44, 0.48, 1.0)
	var pts := PackedVector2Array([
		c + Vector2(side * 2.0, -7.0),
		c + Vector2(side * 12.0, -5.0),
		c + Vector2(side * 12.0, 7.0),
		c + Vector2(side * 2.0, 7.0),
	])
	draw_polyline(pts, col, 3.2, true)


func _draw_clutter(pile: Vector2, jostle: float) -> void:
	# 袋子
	var bag_col := Color(0.50, 0.54, 0.50, 1.0)
	var b0 := pile + Vector2(-10.0 + jostle * 0.3, -10.0)
	draw_colored_polygon(PackedVector2Array([
		b0 + Vector2(-16, 6), b0 + Vector2(14, 8), b0 + Vector2(10, -16 + jostle * 0.2),
		b0 + Vector2(-2, -22), b0 + Vector2(-14, -14),
	]), bag_col)
	# 纸团
	var paper := Color(0.70, 0.71, 0.68, 1.0)
	_draw_ellipse(pile + Vector2(14.0 - jostle * 0.2, -8.0), 11.0, 7.0, paper)
	_draw_ellipse(pile + Vector2(-20.0, -4.0 + jostle * 0.15), 8.0, 5.5, Color(0.66, 0.67, 0.64, 1.0))
	# 小纸箱
	var box_p := pile + Vector2(8.0 + jostle * 0.25, -20.0)
	draw_rect(Rect2(box_p.x - 11.0, box_p.y - 9.0, 22.0, 16.0), Color(0.55, 0.50, 0.42, 1.0))
	draw_rect(Rect2(box_p.x - 11.0, box_p.y - 9.0, 22.0, 16.0), Color(0.32, 0.30, 0.26, 1.0), false, 1.1)
	draw_line(box_p + Vector2(-11, -1), box_p + Vector2(11, -1), Color(0.32, 0.30, 0.26, 0.8), 1.0, true)
	# 瓶子
	var bot := pile + Vector2(-6.0 - jostle * 0.35, -26.0)
	draw_rect(Rect2(bot.x - 5.0, bot.y - 4.0, 10.0, 18.0), Color(0.45, 0.58, 0.56, 0.92))
	draw_rect(Rect2(bot.x - 3.0, bot.y - 12.0, 6.0, 9.0), Color(0.50, 0.62, 0.60, 0.92))
	# 再一团袋子压在上面
	var bag2 := pile + Vector2(2.0, -30.0 + jostle * 0.4)
	draw_colored_polygon(PackedVector2Array([
		bag2 + Vector2(-12, 6), bag2 + Vector2(16, 4), bag2 + Vector2(12, -12),
		bag2 + Vector2(-4, -16), bag2 + Vector2(-14, -8),
	]), Color(0.42, 0.46, 0.50, 1.0))


func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var n := 18
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts[i] = c + Vector2(cos(a) * rx, sin(a) * ry)
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)
