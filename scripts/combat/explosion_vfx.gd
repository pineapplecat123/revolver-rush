extends Control
## 炸药爆炸（Compatibility / Web）：自绘闪光、冲击波、火花、烟和余烬。不用 GPUParticles2D。
## 挂在战斗 UI 上，z 高于伤害飘字。

var span_px: float = 280.0
var duration: float = 1.35
var _age: float = 0.0
var _sparks: Array = []
var _smokes: Array = []
var _embers: Array = []
var _rings: Array = []
var _rng := RandomNumberGenerator.new()


func setup(world_span: float) -> void:
	_rng.randomize()
	span_px = world_span * _rng.randf_range(0.92, 1.18)
	duration = _rng.randf_range(1.2, 1.5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := span_px * 2.2
	size = Vector2(side, side)
	pivot_offset = size * 0.5
	var spark_n: int = _rng.randi_range(36, 54)
	for i in spark_n:
		var ang := _rng.randf() * TAU
		var spd := _rng.randf_range(140.0, 620.0) * _rng.randf_range(0.75, 1.25)
		var col_roll := _rng.randf()
		var col := Color(1.0, 0.95, 0.75)
		if col_roll < 0.45:
			col = Color(1.0, _rng.randf_range(0.55, 0.82), _rng.randf_range(0.05, 0.22))
		elif col_roll < 0.75:
			col = Color(1.0, _rng.randf_range(0.82, 0.95), _rng.randf_range(0.35, 0.6))
		_sparks.append({
			"p": Vector2.ZERO,
			"v": Vector2.from_angle(ang) * spd + Vector2(0, _rng.randf_range(-80.0, 40.0)),
			"g": _rng.randf_range(420.0, 980.0),
			"life": _rng.randf_range(0.45, 1.15),
			"w": _rng.randf_range(2.2, 6.5),
			"col": col,
			"trail": [],
			"smoke": _rng.randf() < 0.55,
		})
	for _s in _rng.randi_range(10, 16):
		_smokes.append({
			"p": Vector2(_rng.randf_range(-18, 18), _rng.randf_range(-8, 12)),
			"v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-50, -18)),
			"r": _rng.randf_range(16.0, 38.0),
			"grow": _rng.randf_range(22.0, 48.0),
			"life": _rng.randf_range(0.9, 1.45),
		})
	for _e in _rng.randi_range(12, 20):
		_embers.append({
			"p": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-6, 20)),
			"v": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-90, -20)),
			"life": _rng.randf_range(0.8, 1.45),
			"w": _rng.randf_range(1.6, 3.4),
		})
	var ring_n: int = _rng.randi_range(3, 5)
	for r in ring_n:
		_rings.append({
			"delay": float(r) * _rng.randf_range(0.03, 0.07),
			"dur": _rng.randf_range(0.38, 0.62),
			"max_r": span_px * _rng.randf_range(0.72, 1.15),
			"width": _rng.randf_range(4.0, 9.0),
			"overshoot": _rng.randf_range(1.08, 1.28),
		})


func _process(delta: float) -> void:
	_age += delta
	var origin := size * 0.5
	for s in _sparks:
		var life: float = float(s["life"])
		if _age > life:
			continue
		var v: Vector2 = s["v"]
		v.y += float(s["g"]) * delta
		s["v"] = v
		var p: Vector2 = s["p"] + v * delta
		s["p"] = p
		var trail: Array = s["trail"]
		trail.append(origin + p)
		while trail.size() > 5:
			trail.pop_front()
		s["trail"] = trail
	for sm in _smokes:
		sm["p"] = sm["p"] + sm["v"] * delta
		sm["r"] = float(sm["r"]) + float(sm["grow"]) * delta
	for em in _embers:
		var v2: Vector2 = em["v"]
		v2.y += 80.0 * delta
		em["v"] = v2
		em["p"] = em["p"] + v2 * delta
	queue_redraw()
	if _age >= duration:
		queue_free()


func _draw() -> void:
	var origin := size * 0.5
	var u: float = clampf(_age / duration, 0.0, 1.0)
	# 白-黄-橙大光晕，盖过好几格
	var bloom_a: float = maxf(0.0, 1.0 - u * 2.4)
	if bloom_a > 0.01:
		var bloom_r: float = span_px * (0.28 + u * 0.85)
		draw_circle(origin, bloom_r, Color(1.0, 0.72, 0.18, 0.22 * bloom_a))
		draw_circle(origin, bloom_r * 0.62, Color(1.0, 0.9, 0.45, 0.38 * bloom_a))
		draw_circle(origin, bloom_r * 0.28, Color(1.0, 0.98, 0.9, 0.7 * bloom_a))
	for ring in _rings:
		var delay: float = float(ring["delay"])
		var dur: float = float(ring["dur"])
		var local_t: float = (_age - delay) / dur
		if local_t <= 0.0 or local_t >= 1.15:
			continue
		var over: float = float(ring["overshoot"])
		var grow: float = local_t * over
		if local_t > 0.72:
			grow = lerpf(over, 1.0, clampf((local_t - 0.72) / 0.28, 0.0, 1.0))
		var rad: float = float(ring["max_r"]) * grow
		var a: float = maxf(0.0, 1.0 - local_t)
		draw_arc(origin, rad, 0.0, TAU, 48, Color(1.0, 0.78, 0.25, 0.85 * a), float(ring["width"]), true)
		draw_arc(origin, rad * 0.92, 0.0, TAU, 40, Color(1.0, 0.95, 0.7, 0.45 * a), 2.0, true)
	for sm in _smokes:
		var life_s: float = float(sm["life"])
		var a_s: float = clampf(1.0 - _age / life_s, 0.0, 1.0)
		if a_s <= 0.02:
			continue
		var c: Vector2 = origin + (sm["p"] as Vector2)
		draw_circle(c, float(sm["r"]), Color(0.45, 0.4, 0.36, 0.22 * a_s))
		draw_circle(c, float(sm["r"]) * 0.55, Color(0.75, 0.7, 0.62, 0.18 * a_s))
	for s in _sparks:
		var life: float = float(s["life"])
		if _age > life:
			continue
		var a2: float = clampf(1.0 - _age / life, 0.0, 1.0)
		var col: Color = s["col"]
		col.a = a2
		var trail: Array = s["trail"]
		for ti in range(1, trail.size()):
			var tc: Color = col
			tc.a = a2 * float(ti) / float(trail.size()) * 0.85
			draw_line(trail[ti - 1], trail[ti], tc, maxf(1.2, float(s["w"]) * 0.45), true)
		draw_circle(origin + (s["p"] as Vector2), float(s["w"]) * (0.7 + 0.5 * a2), col)
	for em in _embers:
		var life_e: float = float(em["life"])
		if _age > life_e:
			continue
		var ember_p: Vector2 = em["p"]
		var flick: float = 0.45 + 0.55 * absf(sin(_age * 28.0 + ember_p.x))
		var ae: float = clampf(1.0 - _age / life_e, 0.0, 1.0) * flick
		draw_circle(origin + ember_p, float(em["w"]), Color(1.0, 0.62, 0.15, ae))
		draw_circle(origin + ember_p, float(em["w"]) * 0.45, Color(1.0, 0.95, 0.7, ae))
