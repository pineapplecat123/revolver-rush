extends Node2D
class_name GoreLayer
## v0.4.27 死亡肢体乱飞：碎块抛出 → 重力 + 旋转 → 落地弹两下 → 躺一会儿 → 淡出。
## 纯 Polygon2D，_process 自己积分；全场上限 MAX_PIECES，超了先回收最老的。

const MAX_PIECES := 60
const GRAVITY := 1650.0
const BOUNCE := 0.38
const FRICTION := 0.62
const REST_SEC := 0.9
const FADE_SEC := 0.45
const MAX_AIR_SEC := 3.2

var ground_y: float = 0.0
var _pieces: Array = []  # {node, vel, spin, rest_t, bounces}
## v0.4.28 碎块在空中拖血迹（木桩拖木屑）：小血滴每 TRAIL_EVERY 秒掉一颗，淡出缩小；全场上限。
const TRAIL_EVERY := 0.022
const TRAIL_LIFE := 0.5
const TRAIL_MAX := 220
const BLOOD_TRAIL := Color(0.78, 0.06, 0.1, 0.95)
var _drops: Array = []  # {node, vel, t}


func active_count() -> int:
	return _pieces.size()


func spawn(pieces: Array, at_g: Vector2, p_ground_y: float, bias_dir: Vector2 = Vector2.ZERO) -> int:
	ground_y = p_ground_y if p_ground_y > 0.0 else at_g.y + 60.0
	var n := 0
	for pc in pieces:
		while _pieces.size() >= MAX_PIECES:
			var old: Dictionary = _pieces.pop_front()
			if is_instance_valid(old["node"]):
				old["node"].queue_free()
		var node := Node2D.new()
		for L in pc.get("layers", []):
			var poly := Polygon2D.new()
			poly.polygon = L[0]
			poly.color = L[1]
			poly.antialiased = true
			node.add_child(poly)
		add_child(node)
		node.global_position = at_g + Vector2(randf_range(-10, 10), randf_range(-26, 0))
		node.rotation = randf_range(-PI, PI)
		var ang: float = randf_range(-PI * 0.88, -PI * 0.12)  # 向上半圆
		var v := Vector2(cos(ang), sin(ang)) * randf_range(420.0, 980.0)  # v0.4.28 飞得更高更远（≈1.6–1.8×）
		v.x *= 1.35
		if bias_dir.length_squared() > 0.01:
			v += bias_dir.normalized() * 260.0
		_pieces.append({"node": node, "vel": v, "spin": randf_range(-16.0, 16.0), "rest_t": -1.0, "bounces": 0, "age": 0.0,
			"trail": pc.get("trail", BLOOD_TRAIL), "trail_t": 0.0})
		n += 1
	return n


func trail_count() -> int:
	return _drops.size()


func _emit_drop(at: Vector2, col: Color, vel: Vector2) -> void:
	while _drops.size() >= TRAIL_MAX:
		var old: Dictionary = _drops.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
	var r := ColorRect.new()
	var sz: float = randf_range(2.5, 5.0)
	r.size = Vector2(sz, sz)
	r.pivot_offset = r.size * 0.5
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	move_child(r, 0)  # 血迹在碎块下面
	r.global_position = at - r.size * 0.5
	_drops.append({"node": r, "vel": vel * 0.12 + Vector2(randf_range(-12, 12), randf_range(-6, 10)), "t": 0.0})


func _tick_drops(dt: float) -> void:
	if _drops.is_empty():
		return
	var keep: Array = []
	for d in _drops:
		var n: ColorRect = d["node"]
		if not is_instance_valid(n):
			continue
		d["t"] = float(d["t"]) + dt
		var k: float = float(d["t"]) / TRAIL_LIFE
		if k >= 1.0:
			n.queue_free()
			continue
		var v: Vector2 = d["vel"]
		v.y += 380.0 * dt
		d["vel"] = v
		n.position += v * dt
		n.modulate.a = 1.0 - k
		n.scale = Vector2.ONE * (1.0 - 0.6 * k)
		keep.append(d)
	_drops = keep


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_tick_drops(dt)
	if _pieces.is_empty():
		return
	var keep: Array = []
	for p in _pieces:
		var node: Node2D = p["node"]
		if not is_instance_valid(node):
			continue
		p["age"] = float(p.get("age", 0.0)) + dt
		if float(p["rest_t"]) < 0.0 and float(p["age"]) > MAX_AIR_SEC:
			p["rest_t"] = REST_SEC  # 飞太久（出界等）→ 直接淡出
		if float(p["rest_t"]) >= 0.0:
			p["rest_t"] = float(p["rest_t"]) + dt
			var t: float = float(p["rest_t"])
			if t > REST_SEC:
				node.modulate.a = clampf(1.0 - (t - REST_SEC) / FADE_SEC, 0.0, 1.0)
				if t > REST_SEC + FADE_SEC:
					node.queue_free()
					continue
			keep.append(p)
			continue
		var v: Vector2 = p["vel"]
		# 空中拖血迹
		p["trail_t"] = float(p["trail_t"]) + dt
		if float(p["trail_t"]) >= TRAIL_EVERY:
			p["trail_t"] = 0.0
			_emit_drop(node.global_position, p["trail"], v)
		v.y += GRAVITY * dt
		var pos: Vector2 = node.global_position + v * dt
		node.rotation += float(p["spin"]) * dt
		# 屏幕左右边当墙：飞远了弹回来，保证落在画面里
		var vw: float = get_viewport_rect().size.x
		if pos.x < 10.0 and v.x < 0.0:
			pos.x = 10.0
			v.x = -v.x * 0.5
		elif pos.x > vw - 10.0 and v.x > 0.0:
			pos.x = vw - 10.0
			v.x = -v.x * 0.5
		if pos.y < 14.0 and v.y < 0.0:
			pos.y = 14.0
			v.y = 0.0
		if ground_y > 0.0 and pos.y >= ground_y - 3.0 and v.y > 0.0:
			pos.y = ground_y - 3.0
			p["bounces"] = int(p["bounces"]) + 1
			v.y = -v.y * BOUNCE
			v.x *= FRICTION
			p["spin"] = float(p["spin"]) * 0.5
			if absf(v.y) < 90.0 or int(p["bounces"]) >= 3:
				v = Vector2.ZERO
				p["spin"] = 0.0
				p["rest_t"] = 0.0
		node.global_position = pos
		p["vel"] = v
		keep.append(p)
	_pieces = keep
