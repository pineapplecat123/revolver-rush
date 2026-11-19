class_name ShopHouse
extends Node2D
## 右侧巷边店铺：嵌入式门洞，不是独立卡通小屋。分前后层，小猫可从门洞走进/走出。
## 前后墙是 Node2D，挂到 UnitBody 里与骨骼做兄弟，才能真正挡住猫（Control 墙挡不住 Node2D 骨骼）。

const WIDTH := 360.0
const HEIGHT := 236.0
const ENTRANCE_X := 62.0
const EXIT_X := 304.0
const ENTRANCE_W := 46.0
const EXIT_W := 40.0
const DOOR_H := 118.0
const EXIT_DOOR_H := 108.0
## 控件左上角相对「左下角贴地原点」的偏移，给屋顶和檐留空。
const DRAW_OX := 10.0
const DRAW_OY := HEIGHT + 40.0

var lit_inside: bool = false
var _back: _Layer = null
var _front: _Layer = null


func _ready() -> void:
	if _back == null:
		_back = _Layer.new()
		_back.name = "HouseBack"
		_back.z_as_relative = true
		_back.z_index = 0
		_back.is_front = false
		_back.house = self
		add_child(_back)
	if _front == null:
		_front = _Layer.new()
		_front.name = "HouseFront"
		_front.z_as_relative = true
		_front.z_index = 20
		_front.is_front = true
		_front.house = self
		add_child(_front)
	visible = false


func attach_layers(unit: Node) -> void:
	## 把前后墙挂进 UnitBody，与骨骼小人成为 Node2D 兄弟，靠同级 z 挡住身体。
	if unit == null or _back == null or _front == null:
		return
	if unit is Control:
		(unit as Control).clip_contents = false
	if _back.get_parent() != unit:
		if _back.get_parent() != null:
			_back.get_parent().remove_child(_back)
		unit.add_child(_back)
		unit.move_child(_back, 0)
	if _front.get_parent() != unit:
		if _front.get_parent() != null:
			_front.get_parent().remove_child(_front)
		unit.add_child(_front)
	_back.z_as_relative = true
	_back.z_index = 0
	_front.z_as_relative = true
	_front.z_index = 20


func set_house_visible(v: bool) -> void:
	visible = v
	if _back:
		_back.visible = v
	if _front:
		_front.visible = v


func house_origin_global() -> Vector2:
	if _back != null and _back.is_inside_tree():
		return _back.global_position
	return Vector2.ZERO


func set_grounded(left_x: float, ground_y: float) -> void:
	# 传入的是墙层父节点（UnitBody）坐标系里，左下角贴走道顶边的坐标。
	var pos := Vector2(floorf(left_x) + 0.5, floorf(ground_y) + 0.5)
	for layer in [_back, _front]:
		if layer == null:
			continue
		layer.position = pos
		layer.queue_redraw()


func set_lit(v: bool) -> void:
	if lit_inside == v:
		return
	lit_inside = v
	if _back:
		_back.queue_redraw()
	if _front:
		_front.queue_redraw()


func entrance_center_x() -> float:
	return house_origin_global().x + ENTRANCE_X


func exit_center_x() -> float:
	return house_origin_global().x + EXIT_X


func occlusion_at(cat_x: float) -> String:
	## outside / door_in / inside / door_out
	if _front == null or not _front.visible:
		return "outside"
	var lx: float = cat_x - house_origin_global().x
	var in_l: float = ENTRANCE_X - ENTRANCE_W * 0.5
	var in_r: float = ENTRANCE_X + ENTRANCE_W * 0.5
	var out_l: float = EXIT_X - EXIT_W * 0.5
	var out_r: float = EXIT_X + EXIT_W * 0.5
	if lx >= in_l and lx <= in_r:
		return "door_in"
	if lx >= out_l and lx <= out_r:
		return "door_out"
	if lx > in_r and lx < out_l:
		return "inside"
	return "outside"


class _Layer extends Node2D:
	var is_front: bool = false
	var house: ShopHouse = null

	func _draw() -> void:
		if house == null:
			return
		if is_front:
			house._draw_front(self)
		else:
			house._draw_back(self)


func _draw_back(ci: CanvasItem) -> void:
	# 背墙与门洞内暗室，小猫在此层之上、前墙之下
	var wall := Color(0.09, 0.11, 0.14, 1.0)
	ci.draw_rect(Rect2(0, -HEIGHT, WIDTH, HEIGHT), wall)
	# 室内比外墙更暗，购物时略暖
	var room := Color(0.05, 0.045, 0.04, 1.0) if lit_inside else Color(0.03, 0.035, 0.04, 1.0)
	ci.draw_rect(Rect2(18, -HEIGHT + 20, WIDTH - 36, HEIGHT - 28), room)
	if lit_inside:
		ci.draw_rect(Rect2(80, -90, 200, 70), Color(0.45, 0.38, 0.24, 0.07))
	# 门洞凹槽（比门口更黑，有深度）
	_draw_door_recess(ci, ENTRANCE_X, ENTRANCE_W, DOOR_H, true)
	_draw_door_recess(ci, EXIT_X, EXIT_W, EXIT_DOOR_H, false)


func _draw_door_recess(ci: CanvasItem, cx: float, dw: float, dh: float, is_entry: bool) -> void:
	var x: float = cx - dw * 0.5
	var y: float = -dh
	ci.draw_rect(Rect2(x, y, dw, dh), Color(0.015, 0.018, 0.02, 1.0))
	# 内侧一点门框阴影
	var lip := Color(0.06, 0.05, 0.04, 0.9) if is_entry else Color(0.07, 0.08, 0.09, 0.9)
	ci.draw_rect(Rect2(x + 3, y + 4, 3, dh - 6), lip)
	ci.draw_rect(Rect2(x + dw - 6, y + 4, 3, dh - 6), lip)


func _draw_front(ci: CanvasItem) -> void:
	var facade := Color(0.13, 0.16, 0.19, 1.0)
	var facade_dark := Color(0.08, 0.10, 0.12, 1.0)
	var rust := Color(0.16, 0.14, 0.13, 1.0)
	# 屋顶 / 压檐
	var roof := Color(0.10, 0.11, 0.13, 1.0)
	ci.draw_rect(Rect2(-8, -HEIGHT - 18, WIDTH + 16, 22), roof)
	ci.draw_rect(Rect2(-4, -HEIGHT - 4, WIDTH + 8, 8), Color(0.07, 0.08, 0.09, 1.0))
	# 烟囱/通风管
	ci.draw_rect(Rect2(WIDTH - 54, -HEIGHT - 34, 16, 22), Color(0.11, 0.12, 0.14, 1.0))
	# 左右墙体，中间开两个门洞
	var in_l: float = ENTRANCE_X - ENTRANCE_W * 0.5
	var in_r: float = ENTRANCE_X + ENTRANCE_W * 0.5
	var out_l: float = EXIT_X - EXIT_W * 0.5
	var out_r: float = EXIT_X + EXIT_W * 0.5
	# 左段墙（入口左侧）
	ci.draw_rect(Rect2(0, -HEIGHT, in_l, HEIGHT), facade)
	# 两门之间的墙
	ci.draw_rect(Rect2(in_r, -HEIGHT, out_l - in_r, HEIGHT), facade)
	# 右段墙
	ci.draw_rect(Rect2(out_r, -HEIGHT, WIDTH - out_r, HEIGHT), facade_dark)
	# 入口上方过梁
	ci.draw_rect(Rect2(in_l - 6, -HEIGHT, ENTRANCE_W + 12, HEIGHT - DOOR_H), facade)
	# 出口上方过梁
	ci.draw_rect(Rect2(out_l - 5, -HEIGHT, EXIT_W + 10, HEIGHT - EXIT_DOOR_H), facade_dark)
	# 墙板竖缝
	var sx: float = 12.0
	while sx < WIDTH - 8.0:
		if not _in_door_x(sx, 0.0):
			ci.draw_line(Vector2(sx, -HEIGHT + 8), Vector2(sx, -4), Color(0.07, 0.08, 0.10, 0.55), 1.0)
		sx += 16.0
	# 入口门框：略暖的木色，更像店门
	var frame_in := Color(0.18, 0.14, 0.11, 1.0)
	ci.draw_rect(Rect2(in_l - 5, -DOOR_H - 6, ENTRANCE_W + 10, 6), frame_in)
	ci.draw_rect(Rect2(in_l - 5, -DOOR_H, 5, DOOR_H), frame_in)
	ci.draw_rect(Rect2(in_r, -DOOR_H, 5, DOOR_H), frame_in)
	# 小匾，克制、不描金边
	ci.draw_rect(Rect2(ENTRANCE_X - 16, -DOOR_H - 28, 32, 16), Color(0.12, 0.10, 0.09, 0.95))
	# 入口旁一盏小灯
	ci.draw_rect(Rect2(in_r + 8, -DOOR_H - 10, 3, 10), Color(0.08, 0.08, 0.09, 1.0))
	ci.draw_circle(Vector2(in_r + 9.5, -DOOR_H - 12), 3.5, Color(0.82, 0.72, 0.48, 0.55))
	ci.draw_circle(Vector2(in_r + 9.5, -DOOR_H - 12), 14.0, Color(0.7, 0.58, 0.32, 0.07))
	# 出口门框：更冷、更窄，像侧门/后门
	var frame_out := Color(0.11, 0.13, 0.15, 1.0)
	ci.draw_rect(Rect2(out_l - 4, -EXIT_DOOR_H - 4, EXIT_W + 8, 4), frame_out)
	ci.draw_rect(Rect2(out_l - 4, -EXIT_DOOR_H, 4, EXIT_DOOR_H), frame_out)
	ci.draw_rect(Rect2(out_r, -EXIT_DOOR_H, 4, EXIT_DOOR_H), frame_out)
	# 侧门一根横档，区别于店门
	ci.draw_rect(Rect2(out_l + 6, -EXIT_DOOR_H * 0.45, EXIT_W - 12, 3), Color(0.16, 0.18, 0.20, 0.8))
	# 上层窗户
	_window(ci, 120, -HEIGHT + 36, lit_inside)
	_window(ci, 168, -HEIGHT + 36, lit_inside)
	_window(ci, 216, -HEIGHT + 36, false)
	# 右上一段雨棚/铁皮
	ci.draw_rect(Rect2(WIDTH - 130, -HEIGHT + 8, 118, 10), rust)
	# 勒脚
	ci.draw_rect(Rect2(0, -6, WIDTH, 6), Color(0.07, 0.08, 0.09, 1.0))


func _in_door_x(x: float, _pad: float) -> bool:
	if x > ENTRANCE_X - ENTRANCE_W * 0.5 and x < ENTRANCE_X + ENTRANCE_W * 0.5:
		return true
	if x > EXIT_X - EXIT_W * 0.5 and x < EXIT_X + EXIT_W * 0.5:
		return true
	return false


func _window(ci: CanvasItem, x: float, y: float, lit: bool) -> void:
	ci.draw_rect(Rect2(x, y, 22, 18), Color(0.05, 0.06, 0.07, 1.0))
	var glass := Color(0.42, 0.36, 0.24, 0.35) if lit else Color(0.18, 0.24, 0.28, 0.25)
	ci.draw_rect(Rect2(x + 2, y + 2, 18, 14), glass)
	ci.draw_line(Vector2(x + 11, y + 2), Vector2(x + 11, y + 16), Color(0.06, 0.07, 0.08, 0.8), 1.0)
