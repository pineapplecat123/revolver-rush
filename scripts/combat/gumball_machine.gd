class_name GumballMachine
extends Node2D
## 巷边糖果机：透明圆罩、冷灰座、投币板和出球口。原点在左下角贴走道顶边。

const WIDTH := 118.0
const HEIGHT := 208.0
const USE_X := 59.0
const PAD := 12.0
const GLOBE_R := 50.0
const CAP_H := 16.0

var coin_t: float = 0.0
var knob_t: float = 0.0
var ball_t: float = 0.0
var awarded_id: int = 0
var awarded_color: Color = Color(0.75, 0.55, 0.7, 1.0)
var physics_drop: bool = false  ## 特写里用物理出球，不再画补间球
var _anim: String = ""
var _anim_age: float = 0.0


func _ready() -> void:
	visible = false
	# z_index / z_as_relative 由放置方决定（街上机器 / 特写）。


func set_grounded(left_x: float, ground_y: float) -> void:
	position = Vector2(floorf(left_x) + 0.5, ground_y)
	queue_redraw()


func set_prop_visible(v: bool) -> void:
	visible = v
	if v:
		queue_redraw()


func origin_global() -> Vector2:
	return global_position if is_inside_tree() else position


static func outlet_local() -> Vector2:
	## 出球口开口中心（本地，原点在左下角，Y 向上为负）。
	return Vector2(WIDTH * 0.5, -36.0 + 8.0)


static func globe_center_local() -> Vector2:
	return Vector2(WIDTH * 0.5, -78.0 - GLOBE_R + 4.0)


func reset_anim() -> void:
	coin_t = 0.0
	knob_t = 0.0
	ball_t = 0.0
	_anim = ""
	_anim_age = 0.0
	queue_redraw()


func play_dispense(ammo_id: int, fill: Color) -> void:
	awarded_id = ammo_id
	awarded_color = fill
	_anim = "dispense"
	_anim_age = 0.0
	coin_t = 0.0
	knob_t = 0.0
	ball_t = 0.0
	queue_redraw()


func tick_anim(dt: float) -> void:
	if _anim != "dispense":
		return
	_anim_age += maxf(0.0, dt)
	# 投币 0–0.45s，摇把 0.25–0.95s，出球 0.7–1.55s
	coin_t = clampf(_anim_age / 0.45, 0.0, 1.0)
	knob_t = clampf((_anim_age - 0.25) / 0.70, 0.0, 1.0)
	ball_t = clampf((_anim_age - 0.70) / 0.85, 0.0, 1.0)
	queue_redraw()


func is_dispense_done() -> bool:
	return _anim == "dispense" and _anim_age >= 1.7


func _draw() -> void:
	# 本地：原点在左下角，Y 向上为负（与店铺房屋一致，贴地后往上画）。
	var foot := Vector2(WIDTH * 0.5, 0.0)
	var steel := Color(0.42, 0.48, 0.54, 1.0)
	var steel_d := Color(0.30, 0.35, 0.40, 1.0)
	var steel_l := Color(0.55, 0.61, 0.66, 1.0)
	var accent := Color(0.38, 0.52, 0.56, 1.0)
	var plate := Color(0.48, 0.52, 0.56, 1.0)
	var slot := Color(0.12, 0.13, 0.15, 1.0)
	# 底座外撇
	var foot_w := 58.0
	var foot_pts := PackedVector2Array([
		foot + Vector2(-foot_w, 0.0),
		foot + Vector2(foot_w, 0.0),
		foot + Vector2(44.0, -10.0),
		foot + Vector2(-44.0, -10.0),
	])
	draw_colored_polygon(foot_pts, steel_d)
	# 锥形支柱
	var ped := PackedVector2Array([
		foot + Vector2(-28.0, -10.0),
		foot + Vector2(28.0, -10.0),
		foot + Vector2(22.0, -78.0),
		foot + Vector2(-22.0, -78.0),
	])
	draw_colored_polygon(ped, steel)
	draw_polyline(PackedVector2Array(ped) + PackedVector2Array([ped[0]]), Color(0.22, 0.26, 0.30, 0.9), 1.6, true)
	# 出球口（支柱上部下方，开口要能看清球出来）
	var out_c := foot + Vector2(0.0, -36.0)
	draw_rect(Rect2(out_c.x - 16.0, out_c.y - 9.0, 32.0, 18.0), steel_d)
	draw_rect(Rect2(out_c.x - 16.0, out_c.y - 9.0, 32.0, 18.0), Color(0.20, 0.24, 0.28, 1.0), false, 1.4)
	draw_arc(out_c + Vector2(0.0, 7.0), 12.0, PI, TAU, 18, Color(0.08, 0.09, 0.10, 1.0), 7.0, true)
	draw_arc(out_c + Vector2(0.0, 7.0), 7.0, PI, TAU, 14, Color(0.05, 0.05, 0.06, 1.0), 3.0, true)
	# 前面金属板：投币口 + 摇把
	var plate_r := Rect2(foot.x - 22.0, foot.y - 78.0, 44.0, 34.0)
	draw_rect(plate_r, plate)
	draw_rect(plate_r, Color(0.28, 0.32, 0.36, 1.0), false, 1.4)
	# 投币口
	var slot_r := Rect2(plate_r.position.x + 7.0, plate_r.position.y + 8.0, 12.0, 4.0)
	draw_rect(slot_r, slot)
	# 摇把
	var knob_c := Vector2(plate_r.position.x + 32.0, plate_r.position.y + 18.0)
	var knob_a: float = -0.35 - knob_t * 4.2
	var knob_end: Vector2 = knob_c + Vector2(cos(knob_a), sin(knob_a)) * 13.0
	draw_circle(knob_c, 5.5, accent)
	draw_line(knob_c, knob_end, Color(0.22, 0.26, 0.28, 1.0), 3.0, true)
	draw_circle(knob_end, 4.2, Color(0.62, 0.66, 0.70, 1.0))
	# 圆罩中心
	var globe_c := Vector2(foot.x, foot.y - 78.0 - GLOBE_R + 4.0)
	# 玻璃圆罩（半透明，里面有彩色小球）
	draw_circle(globe_c, GLOBE_R, Color(0.62, 0.72, 0.78, 0.28))
	_draw_globe_balls(globe_c)
	# 玻璃边和反光弧（单线，不做厚高光体）
	draw_arc(globe_c, GLOBE_R, 0.0, TAU, 40, Color(0.70, 0.78, 0.84, 0.85), 2.0, true)
	draw_arc(globe_c, GLOBE_R * 0.82, -2.4, -1.15, 12, Color(0.85, 0.90, 0.93, 0.28), 2.2, true)
	# 穹顶盖
	var cap_pts := PackedVector2Array()
	var cap_n := 14
	for i in cap_n:
		var a: float = PI + PI * float(i) / float(cap_n - 1)
		cap_pts.append(globe_c + Vector2(cos(a) * (GLOBE_R + 2.0), sin(a) * (GLOBE_R + 2.0)) + Vector2(0.0, -2.0))
	# 盖顶稍平
	var cap_top := globe_c + Vector2(0.0, -GLOBE_R - CAP_H)
	cap_pts.insert(cap_n / 2, cap_top)
	if cap_pts.size() >= 3:
		draw_colored_polygon(cap_pts, steel_l)
	draw_circle(cap_top + Vector2(0.0, 4.0), 7.0, accent)
	# 出球动画：仅在非物理特写时画补间球（特写由 GumballCloseup 做真实掉落）。
	if (not physics_drop) and ball_t > 0.0:
		var start: Vector2 = globe_c + Vector2(0.0, 10.0)
		var mid: Vector2 = Vector2(foot.x, foot.y - 78.0)
		var end: Vector2 = out_c + Vector2(0.0, 2.0)
		var t: float = ball_t
		var p: Vector2
		if t < 0.55:
			var k: float = t / 0.55
			p = start.lerp(mid, k)
		else:
			var k2: float = (t - 0.55) / 0.45
			p = mid.lerp(end, k2)
		draw_circle(p, 8.5, awarded_color)
		draw_arc(p, 8.5, 0.0, TAU, 20, Color(0.12, 0.12, 0.14, 0.9), 1.4, true)
	# 投币：金币飞向投币口
	if coin_t > 0.0 and coin_t < 1.0:
		var c0 := Vector2(plate_r.position.x - 22.0, plate_r.position.y - 18.0)
		var c1 := Vector2(slot_r.position.x + 6.0, slot_r.position.y + 2.0)
		var cp: Vector2 = c0.lerp(c1, coin_t)
		var ca: float = 1.0 - coin_t * 0.3
		draw_circle(cp, 5.5, Color(0.82, 0.70, 0.32, ca))
		draw_arc(cp, 5.5, 0.0, TAU, 14, Color(0.55, 0.44, 0.16, ca), 1.2, true)


func _draw_globe_balls(c: Vector2) -> void:
	## 罩内小球跟弹药袋一样是圆球+描边，用克制的弹药色，不是另外一套糖果画法。
	var fills := [
		Color(0.85, 0.85, 0.88),
		Color(0.32, 0.78, 0.42),
		Color(0.95, 0.80, 0.22),
		Color(0.86, 0.24, 0.22),
		Color(0.70, 0.80, 0.72),
		Color(0.68, 0.70, 0.84),
		Color(0.86, 0.72, 0.62),
	]
	var pts := [
		Vector2(0, 8), Vector2(-16, 0), Vector2(15, 2), Vector2(-8, 18),
		Vector2(10, 18), Vector2(-22, 14), Vector2(22, 14), Vector2(0, -10),
		Vector2(-14, -18), Vector2(14, -16), Vector2(-6, -28), Vector2(8, -26),
		Vector2(-20, -8), Vector2(20, -6), Vector2(0, 26), Vector2(-10, 30),
		Vector2(12, 28), Vector2(-18, 24),
	]
	var j: float = 0.0
	if ball_t > 0.0 and ball_t < 0.6:
		j = sin(ball_t * 18.0) * (1.0 - ball_t) * 2.0
	var h: float = 14.0
	for i in pts.size():
		var off: Vector2 = pts[i] + Vector2(j * (1.0 if i % 2 == 0 else -1.0), j * 0.4)
		var p: Vector2 = c + off
		if p.distance_to(c) > GLOBE_R - 8.0:
			continue
		BagPhysicsBox.stamp_bag_bullet(self, p, h, 0.0, fills[i % fills.size()])
