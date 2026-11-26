class_name GumballMachine
extends Node2D
## 巷边糖果机：透明圆罩、冷灰座、投币板和出球口。原点在左下角贴走道顶边。

const WIDTH := 124.0
const HEIGHT := 208.0
const USE_X := 62.0
const PAD := 12.0
const GLOBE_R := 60.0
const CAP_H := 0.0  ## v0.4.96：不再画半个盖子，整罐透明
# 街上装饰糖：少而稀，堆在罐子底部，不要铺满或悬在半空。
const DECOR_GLOBE_BALL_COUNT := 8

var coin_t: float = 0.0
var knob_t: float = 0.0
var ball_t: float = 0.0
var awarded_id: int = 0
var awarded_color: Color = Color(0.75, 0.55, 0.7, 1.0)
var physics_drop: bool = false  ## 特写里用物理出球，不再画补间球
var hide_interior_balls: bool = false  ## 特写里罩内是真实物理球，街上仍用装饰球
var hide_knob: bool = false  ## 特写用可拉的杆，不再画自动摇把
var hide_glass: bool = false  ## 特写自己画玻璃罩，避免挡住物理球
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


static func pedestal_half_width_at_local_y(ly: float) -> float:
	## 锥形支柱在本地 y（向上为负）处的半宽，用来把拉杆座落在机身侧壁上。
	var t: float = clampf((ly - (-10.0)) / ((-78.0) - (-10.0)), 0.0, 1.0)
	return lerpf(28.0, 22.0, t)


static func lever_mount_local() -> Vector2:
	## 拉杆枢轴：贴在支柱右侧壁，高度约出球口上方、玻璃罐下方。
	var ly := -58.0
	return Vector2(WIDTH * 0.5 + pedestal_half_width_at_local_y(ly), ly)


static func decor_globe_ball_offsets() -> PackedVector2Array:
	## 本地偏移，Y 向下为正（朝机身/底部）。全部在下半球，8 颗成一小堆。
	return PackedVector2Array([
		Vector2(-20.0, 28.0), Vector2(-6.0, 32.0), Vector2(8.0, 32.0), Vector2(22.0, 28.0),
		Vector2(-13.0, 17.0), Vector2(2.0, 19.0), Vector2(16.0, 17.0),
		Vector2(0.0, 7.0),
	])



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
	# v0.4.96：罐子更大、全透明无盖；机身少装饰；拉杆从机身侧壁伸出。
	var foot := Vector2(WIDTH * 0.5, 0.0)
	var steel := Color(0.42, 0.48, 0.54, 1.0)
	var steel_d := Color(0.30, 0.35, 0.40, 1.0)
	# 底座外撇
	var foot_w := 58.0
	var foot_pts := PackedVector2Array([
		foot + Vector2(-foot_w, 0.0),
		foot + Vector2(foot_w, 0.0),
		foot + Vector2(44.0, -10.0),
		foot + Vector2(-44.0, -10.0),
	])
	draw_colored_polygon(foot_pts, steel_d)
	# 锥形支柱（不再描一圈装饰边）
	var ped := PackedVector2Array([
		foot + Vector2(-28.0, -10.0),
		foot + Vector2(28.0, -10.0),
		foot + Vector2(22.0, -78.0),
		foot + Vector2(-22.0, -78.0),
	])
	draw_colored_polygon(ped, steel)
	# 出球口
	var out_c := foot + Vector2(0.0, -36.0)
	draw_rect(Rect2(out_c.x - 16.0, out_c.y - 9.0, 32.0, 18.0), steel_d)
	draw_arc(out_c + Vector2(0.0, 7.0), 12.0, PI, TAU, 18, Color(0.08, 0.09, 0.10, 1.0), 7.0, true)
	draw_arc(out_c + Vector2(0.0, 7.0), 7.0, PI, TAU, 14, Color(0.05, 0.05, 0.06, 1.0), 3.0, true)
	# 简单投币口，不再单独做一块装饰板
	var slot_r := Rect2(foot.x - 16.0, foot.y - 70.0, 12.0, 4.0)
	draw_rect(slot_r, Color(0.12, 0.13, 0.15, 1.0))
	# 街上小机器：侧壁拉杆（特写自己画更大的可拉杆，这里藏掉）
	if not hide_knob:
		var mount: Vector2 = foot + Vector2(lever_mount_local().x - WIDTH * 0.5, lever_mount_local().y)
		var knob_a: float = -0.55 - knob_t * 1.15
		var arm_len := 22.0
		var knob_end: Vector2 = mount + Vector2(cos(knob_a), sin(knob_a)) * arm_len
		draw_circle(mount, 5.0, steel_d)
		draw_line(mount, knob_end, Color(0.28, 0.30, 0.33, 1.0), 4.0, true)
		draw_circle(knob_end, 6.5, Color(1.0, 0.16, 0.10, 1.0))
	# 圆罩中心
	var globe_c := Vector2(foot.x, foot.y - 78.0 - GLOBE_R + 4.0)
	# 全透明玻璃圆罩，不要半个盖子。特写自己画罩和物理球。
	if not hide_glass:
		draw_circle(globe_c, GLOBE_R, Color(0.62, 0.72, 0.78, 0.22))
		if not hide_interior_balls:
			_draw_globe_balls(globe_c)
		draw_arc(globe_c, GLOBE_R, 0.0, TAU, 48, Color(0.70, 0.78, 0.84, 0.85), 2.0, true)
	elif not hide_interior_balls:
		_draw_globe_balls(globe_c)
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
		var c0 := Vector2(slot_r.position.x - 22.0, slot_r.position.y - 18.0)
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
	var pts: PackedVector2Array = decor_globe_ball_offsets()
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
