class_name CampaignBackdrop
extends Node2D
## 多层视差巷景：近处走道与地上碎块同速左移，中景较慢，远楼最慢。无缝平铺。
## 天空和下方托底不滚。店铺房屋不画在这里，避免把门带走。

const DEPTH_FAR := 0.22
const DEPTH_MID := 0.48
const DEPTH_NEAR := 1.0
const TILE := 360.0
const PLANK := 18.0

var view_size: Vector2 = Vector2(720, 1280)
var ground_y: float = 520.0
var board_left: float = 20.0
var board_right: float = 700.0
## 近景层位移（像素）。drift 为负时减小，表示世界向左退。
var scroll: float = 0.0


func configure(vs: Vector2, gy: float, bleft: float, bright: float) -> void:
	view_size = vs
	ground_y = gy
	board_left = bleft
	board_right = bright
	queue_redraw()


func advance(dt: float, drift_px_per_sec: float) -> void:
	if dt == 0.0 or drift_px_per_sec == 0.0:
		return
	scroll += drift_px_per_sec * dt
	queue_redraw()


func shift_for(depth: float) -> float:
	return scroll * depth


func _draw() -> void:
	var w: float = maxf(view_size.x, 8.0)
	var h: float = maxf(view_size.y, 8.0)
	var gy: float = ground_y if ground_y > 40.0 else h * 0.38
	_fill_sky(w, h, gy)
	_each_tile(DEPTH_FAR, func(ox: float): _far_buildings_tile(ox, gy))
	_each_tile(DEPTH_MID, func(ox: float): _mid_tile(ox, w, h, gy))
	_fog_veils(w, gy)
	_walkway(w, gy)
	# 压住走道以下，避免楼体画进转轮区（不参与滚动）
	if h > gy + 80.0:
		draw_rect(Rect2(0.0, gy + 28.0, w, h - gy), Color(0.05, 0.06, 0.08, 1.0))


func _each_tile(depth: float, cb: Callable) -> void:
	var sh: float = shift_for(depth)
	var x: float = fposmod(sh, TILE)
	if x > 0.0:
		x -= TILE
	var limit: float = view_size.x + 1.0
	while x < limit:
		cb.call(x)
		x += TILE


func _fill_sky(w: float, h: float, gy: float) -> void:
	var top := Color(0.045, 0.055, 0.075, 1.0)
	var mid := Color(0.32, 0.40, 0.48, 1.0)
	var low := Color(0.12, 0.16, 0.20, 1.0)
	var sky_h: float = maxf(gy + 40.0, 80.0)
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, sky_h * 0.55), Vector2(0, sky_h * 0.55)])
	draw_polygon(pts, PackedColorArray([top, top, mid, mid]))
	pts = PackedVector2Array([Vector2(0, sky_h * 0.55), Vector2(w, sky_h * 0.55), Vector2(w, sky_h), Vector2(0, sky_h)])
	draw_polygon(pts, PackedColorArray([mid, mid, low, low]))
	draw_rect(Rect2(0.0, sky_h, w, h - sky_h + 2.0), Color(0.05, 0.06, 0.08, 1.0))


func _far_buildings_tile(ox: float, gy: float) -> void:
	var far := Color(0.16, 0.22, 0.27, 0.35)
	var base := Color(0.10, 0.14, 0.18, 0.85)
	_building_block(ox + 40.0, gy * 0.28, 48.0, gy - gy * 0.28, base, 0.22)
	_building_block(ox + 110.0, gy * 0.22, 54.0, gy - gy * 0.22, far, 0.35)
	_building_block(ox + 180.0, gy * 0.16, 70.0, gy - gy * 0.16, far.darkened(0.1), 0.3)
	_building_block(ox + 270.0, gy * 0.24, 52.0, gy - gy * 0.24, far.darkened(0.05), 0.28)


func _mid_tile(ox: float, _w: float, _h: float, gy: float) -> void:
	var left := Color(0.055, 0.07, 0.09, 1.0)
	var right := Color(0.07, 0.09, 0.12, 1.0)
	_building_block(ox - 10.0, 0.0, 86.0, gy + 8.0, left, 0.55)
	_building_block(ox + 48.0, gy * 0.08, 36.0, gy * 0.55, left.lightened(0.04), 0.4)
	_building_block(ox + 210.0, gy * 0.05, 130.0, gy + 16.0, right, 0.42)
	_building_block(ox + 250.0, gy * 0.22, 90.0, gy * 0.5, right.lightened(0.05), 0.28)


func _building_block(x: float, y: float, bw: float, bh: float, col: Color, _window_lit: float) -> void:
	draw_rect(Rect2(x, y, bw, bh), col)


func _fog_veils(w: float, gy: float) -> void:
	# A soft horizon fade, no opaque rectangular mist patches.
	for i in 16:
		var t := float(i) / 16.0
		draw_rect(Rect2(0.0, gy - 48.0 + t * 48.0, w, 4.0), Color(0.10, 0.14, 0.18, t * 0.22))


func _wires_tile(ox: float, gy: float) -> void:
	var y0: float = gy * 0.28
	var pts_a := PackedVector2Array([
		Vector2(ox + 10.0, y0 + 8.0), Vector2(ox + 110.0, y0 + 28.0),
		Vector2(ox + 230.0, y0 + 22.0), Vector2(ox + 350.0, y0 + 6.0)
	])
	var pts_b := PackedVector2Array([
		Vector2(ox + 16.0, y0 + 36.0), Vector2(ox + 120.0, y0 + 58.0),
		Vector2(ox + 250.0, y0 + 50.0), Vector2(ox + 352.0, y0 + 30.0)
	])
	var pts_c := PackedVector2Array([
		Vector2(ox + 22.0, y0 + 62.0), Vector2(ox + 140.0, y0 + 82.0),
		Vector2(ox + 260.0, y0 + 74.0), Vector2(ox + 352.0, y0 + 54.0)
	])
	var wire := Color(0.08, 0.09, 0.11, 0.7)
	_polyline(pts_a, wire)
	_polyline(pts_b, wire)
	_polyline(pts_c, wire)
	var clothes: Array = [
		[78.0, y0 + 28.0, 10.0, 22.0, Color(0.12, 0.14, 0.18, 0.7)],
		[150.0, y0 + 26.0, 8.0, 18.0, Color(0.16, 0.18, 0.22, 0.55)],
		[220.0, y0 + 24.0, 11.0, 26.0, Color(0.10, 0.11, 0.14, 0.75)],
		[120.0, y0 + 58.0, 9.0, 20.0, Color(0.14, 0.16, 0.2, 0.6)],
		[248.0, y0 + 52.0, 8.0, 16.0, Color(0.11, 0.13, 0.16, 0.65)],
	]
	for c in clothes:
		draw_rect(Rect2(ox + float(c[0]), float(c[1]), float(c[2]), float(c[3])), c[4])


func _polyline(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, 1.2, true)


func _walkway(w: float, gy: float) -> void:
	var deck := Color(0.18, 0.19, 0.21, 1.0)
	var seam := Color(0.10, 0.11, 0.13, 0.7)
	var deck_h := 22.0
	draw_rect(Rect2(0.0, gy, w, deck_h), deck)
	draw_rect(Rect2(0.0, gy, w, 2.0), Color(0.28, 0.30, 0.32, 0.7))
	# 板缝随近景滚动，周期 18px，与 TILE 对齐
	var sh: float = shift_for(DEPTH_NEAR)
	var x: float = fposmod(sh, PLANK)
	if x > 0.0:
		x -= PLANK
	while x < w:
		draw_line(Vector2(x, gy + 1.0), Vector2(x, gy + deck_h - 1.0), seam, 1.0)
		x += PLANK
	# 栏杆留在战斗位两侧，不随走道滚，避免把小猫的站位框走掉
	var rail := Color(0.08, 0.09, 0.10, 0.85)
	draw_line(Vector2(4.0, gy - 26.0), Vector2(maxf(board_left - 4.0, 40.0), gy - 26.0), rail, 2.0, true)
	draw_line(Vector2(minf(board_right + 4.0, w - 80.0), gy - 26.0), Vector2(w - 4.0, gy - 26.0), rail, 2.0, true)
	for px in [10.0, 40.0, w - 48.0, w - 16.0]:
		draw_line(Vector2(px, gy - 26.0), Vector2(px, gy), rail, 2.0, true)
	# 走道碎屑随近景滚
	var near0: float = fposmod(sh, TILE)
	if near0 > 0.0:
		near0 -= TILE
	var tx: float = near0
	while tx < w + TILE:
		draw_rect(Rect2(tx + 150.0, gy + 6.0, 10.0, 3.0), Color(0.12, 0.12, 0.13, 0.8))
		draw_rect(Rect2(tx + 220.0, gy + 9.0, 7.0, 2.0), Color(0.13, 0.13, 0.14, 0.7))
		tx += TILE
