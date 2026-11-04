extends Node2D
class_name GoreLayer
## v0.4.27 死亡肢体乱飞：碎块抛出 → 重力 + 旋转 → 落地弹两下 → 躺一会儿 → 淡出。
## 纯 Polygon2D，_process 自己积分；全场上限 MAX_PIECES，超了先回收最老的。

const MAX_PIECES := 60
const GRAVITY := 1500.0
const BOUNCE := 0.38
const FRICTION := 0.62
const REST_SEC := 0.9
const FADE_SEC := 0.45
const MAX_AIR_SEC := 2.5

var ground_y: float = 0.0
var _pieces: Array = []  # {node, vel, spin, rest_t, bounces}


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
		var ang: float = randf_range(-PI * 0.92, -PI * 0.08)  # 向上半圆
		var v := Vector2(cos(ang), sin(ang)) * randf_range(260.0, 620.0)
		if bias_dir.length_squared() > 0.01:
			v += bias_dir.normalized() * 160.0
		_pieces.append({"node": node, "vel": v, "spin": randf_range(-16.0, 16.0), "rest_t": -1.0, "bounces": 0, "age": 0.0})
		n += 1
	return n


func _process(delta: float) -> void:
	if _pieces.is_empty():
		return
	var dt: float = minf(delta, 0.05)
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
		v.y += GRAVITY * dt
		var pos: Vector2 = node.global_position + v * dt
		node.rotation += float(p["spin"]) * dt
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
