class_name CampaignBackdrop
extends Node2D
## 静止巷景/屋面：雾蓝、远处楼层、晾衣绳、前景走道。不滚动。

var view_size: Vector2 = Vector2(720, 1280)
var ground_y: float = 520.0
var board_left: float = 20.0
var board_right: float = 700.0


func configure(vs: Vector2, gy: float, bleft: float, bright: float) -> void:
	view_size = vs
	ground_y = gy
	board_left = bleft
	board_right = bright
	queue_redraw()


func _draw() -> void:
	var w: float = maxf(view_size.x, 8.0)
	var h: float = maxf(view_size.y, 8.0)
	var gy: float = ground_y if ground_y > 40.0 else h * 0.38
	# 天空：上暗下雾亮，中间略青
	_fill_sky(w, h, gy)
	# 远景楼群（中景发亮的雾窗）
	_far_buildings(w, gy)
	# 左右近处建筑体块
	_side_masses(w, h, gy)
	# 雾纱
	_fog_veils(w, gy)
	# 电线与衣物（静止）
	_wires_and_laundry(w, gy)
	# 前景走道与栏杆
	_walkway(w, gy)


func _fill_sky(w: float, h: float, gy: float) -> void:
	var top := Color(0.045, 0.055, 0.075, 1.0)
	var mid := Color(0.32, 0.40, 0.48, 1.0)
	var low := Color(0.12, 0.16, 0.20, 1.0)
	var steps := 16
	var sky_h: float = maxf(gy + 40.0, 80.0)
	for i in steps:
		var t: float = float(i) / float(steps)
		var y0: float = sky_h * t
		var y1: float = sky_h * (t + 1.0 / float(steps)) + 1.0
		var col: Color
		if t < 0.55:
			col = top.lerp(mid, t / 0.55)
		else:
			col = mid.lerp(low, (t - 0.55) / 0.45)
		draw_rect(Rect2(0.0, y0, w, y1 - y0), col)
	# 下半屏保持深底，给中/下 UI 托底
	draw_rect(Rect2(0.0, sky_h, w, h - sky_h + 2.0), Color(0.05, 0.06, 0.08, 1.0))
	# 中央一道更亮的雾窗
	var mist := Color(0.45, 0.54, 0.62, 0.28)
	draw_rect(Rect2(w * 0.22, gy * 0.12, w * 0.56, gy * 0.7), mist)
	# 远处一抹天光
	draw_rect(Rect2(w * 0.28, gy * 0.16, w * 0.44, 14.0), Color(0.62, 0.70, 0.76, 0.16))


func _far_buildings(w: float, gy: float) -> void:
	var base := Color(0.10, 0.14, 0.18, 0.85)
	var far := Color(0.16, 0.22, 0.27, 0.35)
	# 中央远处两栋瘦楼
	_building_block(w * 0.38, gy * 0.22, 54.0, gy - gy * 0.22, far, 0.35)
	_building_block(w * 0.52, gy * 0.16, 70.0, gy - gy * 0.16, far.darkened(0.1), 0.3)
	_building_block(w * 0.30, gy * 0.28, 48.0, gy - gy * 0.28, base, 0.22)


func _side_masses(w: float, h: float, gy: float) -> void:
	# 左侧近景：几乎剪影的楼墙
	var left := Color(0.055, 0.07, 0.09, 1.0)
	_building_block(-30.0, 0.0, w * 0.22, gy + 8.0, left, 0.55)
	_building_block(w * 0.08, gy * 0.08, 36.0, gy * 0.55, left.lightened(0.04), 0.4)
	# 右侧远处楼与屋面体块（商店到来前的巷口结构，不代替商店）
	var right := Color(0.07, 0.09, 0.12, 1.0)
	_building_block(w * 0.72, gy * 0.05, w * 0.36, gy + 16.0, right, 0.42)
	_building_block(w * 0.80, gy * 0.22, 90.0, gy * 0.5, right.lightened(0.05), 0.28)
	# 右下一点棚架暗示
	draw_rect(Rect2(w * 0.78, gy - 70.0, 86.0, 70.0), Color(0.09, 0.11, 0.14, 0.7))
	# 暖色路灯（克制）
	var lx: float = w * 0.835
	var ly: float = gy * 0.42
	draw_rect(Rect2(lx, ly, 3.0, gy - ly - 8.0), Color(0.08, 0.09, 0.10, 0.9))
	draw_circle(Vector2(lx + 1.5, ly), 5.0, Color(0.85, 0.78, 0.58, 0.35))
	draw_circle(Vector2(lx + 1.5, ly), 18.0, Color(0.7, 0.62, 0.4, 0.07))
	# 压住下半屏，避免楼体画进转轮区
	if h > gy + 80.0:
		draw_rect(Rect2(0.0, gy + 28.0, w, h - gy), Color(0.05, 0.06, 0.08, 1.0))


func _building_block(x: float, y: float, bw: float, bh: float, col: Color, window_lit: float) -> void:
	draw_rect(Rect2(x, y, bw, bh), col)
	# 窗点：稀疏、冷光
	var wy: float = y + 16.0
	while wy < y + bh - 20.0:
		var wx: float = x + 8.0
		while wx < x + bw - 10.0:
			var lit: bool = ((int(wx) * 13 + int(wy) * 7) % 11) > 7
			var wc := Color(0.55, 0.62, 0.68, window_lit) if lit else Color(0.04, 0.05, 0.06, 0.5)
			draw_rect(Rect2(wx, wy, 5.0, 8.0), wc)
			wx += 12.0
		wy += 16.0


func _fog_veils(w: float, gy: float) -> void:
	draw_rect(Rect2(w * 0.18, gy * 0.30, w * 0.64, gy * 0.45), Color(0.48, 0.56, 0.64, 0.14))
	draw_rect(Rect2(0.0, gy - 36.0, w, 48.0), Color(0.10, 0.13, 0.16, 0.28))


func _wires_and_laundry(w: float, gy: float) -> void:
	var y0: float = gy * 0.28
	var pts_a := PackedVector2Array([Vector2(w * 0.16, y0 + 8.0), Vector2(w * 0.38, y0 + 28.0), Vector2(w * 0.62, y0 + 22.0), Vector2(w * 0.84, y0 + 6.0)])
	var pts_b := PackedVector2Array([Vector2(w * 0.18, y0 + 36.0), Vector2(w * 0.40, y0 + 58.0), Vector2(w * 0.66, y0 + 50.0), Vector2(w * 0.86, y0 + 30.0)])
	var pts_c := PackedVector2Array([Vector2(w * 0.20, y0 + 62.0), Vector2(w * 0.44, y0 + 82.0), Vector2(w * 0.68, y0 + 74.0), Vector2(w * 0.86, y0 + 54.0)])
	var wire := Color(0.08, 0.09, 0.11, 0.7)
	_polyline(pts_a, wire)
	_polyline(pts_b, wire)
	_polyline(pts_c, wire)
	# 几件静衣
	var clothes: Array = [
		[0.34, y0 + 28.0, 10.0, 22.0, Color(0.12, 0.14, 0.18, 0.7)],
		[0.46, y0 + 26.0, 8.0, 18.0, Color(0.16, 0.18, 0.22, 0.55)],
		[0.58, y0 + 24.0, 11.0, 26.0, Color(0.10, 0.11, 0.14, 0.75)],
		[0.41, y0 + 58.0, 9.0, 20.0, Color(0.14, 0.16, 0.2, 0.6)],
		[0.63, y0 + 52.0, 8.0, 16.0, Color(0.11, 0.13, 0.16, 0.65)],
	]
	for c in clothes:
		draw_rect(Rect2(w * float(c[0]), float(c[1]), float(c[2]), float(c[3])), c[4])


func _polyline(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, 1.2, true)


func _walkway(w: float, gy: float) -> void:
	var left: float = minf(board_left, 8.0)
	var right: float = maxf(board_right, w - 8.0)
	# 厚实走道，湿冷木板/屋面感
	var deck := Color(0.18, 0.19, 0.21, 1.0)
	var seam := Color(0.10, 0.11, 0.13, 0.7)
	var deck_h := 22.0
	draw_rect(Rect2(0.0, gy, w, deck_h), deck)
	draw_rect(Rect2(0.0, gy, w, 2.0), Color(0.28, 0.30, 0.32, 0.7))
	var x: float = left
	while x < right:
		draw_line(Vector2(x, gy + 1.0), Vector2(x, gy + deck_h - 1.0), seam, 1.0)
		x += 18.0
	# 栏杆：左右各一段，中间留战斗位
	var rail := Color(0.08, 0.09, 0.10, 0.85)
	draw_line(Vector2(4.0, gy - 26.0), Vector2(maxf(board_left - 4.0, 40.0), gy - 26.0), rail, 2.0, true)
	draw_line(Vector2(minf(board_right + 4.0, w - 80.0), gy - 26.0), Vector2(w - 4.0, gy - 26.0), rail, 2.0, true)
	# 柱
	for px in [10.0, 40.0, w - 48.0, w - 16.0]:
		draw_line(Vector2(px, gy - 26.0), Vector2(px, gy), rail, 2.0, true)
	# 走道上一点碎屑（静止，不是会漂移的战斗碎块）
	draw_rect(Rect2(w * 0.42, gy + 6.0, 10.0, 3.0), Color(0.12, 0.12, 0.13, 0.8))
	draw_rect(Rect2(w * 0.61, gy + 9.0, 7.0, 2.0), Color(0.13, 0.13, 0.14, 0.7))
