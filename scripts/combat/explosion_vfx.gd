extends Control
class_name ExplosionBurst
## 炸药爆炸的纯画面。自己画闪光、冲击波、火星和烟，不碰战斗计时。
## 不用 GPUParticles2D：网页版那个渲染会不稳。播完自己删。

const LIFE_SEC := 1.45
const Z_ABOVE_FLOAT := 55

var particle_count: int = 0

var _age := 0.0
var _center := Vector2.ZERO
var _scale := 1.0
var _sparks: Array = []
var _rings: Array = []
var _bloom_r := 120.0
var _flash_col := Color(1.0, 0.92, 0.55, 0.42)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Z_ABOVE_FLOAT
	clip_contents = false


func setup(center: Vector2, n_side: int, cell_w: float) -> void:
	_center = center
	_rng.randomize()
	_scale = _rng.randf_range(0.88, 1.22) * (1.0 + 0.08 * float(maxi(n_side, 1)))
	_bloom_r = cell_w * _rng.randf_range(1.7, 2.8) * _scale
	var hot := _rng.randf()
	_flash_col = Color(1.0, 0.78 + hot * 0.18, 0.35 + hot * 0.25, _rng.randf_range(0.28, 0.48))
	_build_rings(cell_w)
	_build_bits(cell_w)
	particle_count = _sparks.size()
	queue_redraw()


func _build_rings(cell_w: float) -> void:
	var n: int = _rng.randi_range(3, 5)
	for i in n:
		_rings.append({
			"delay": float(i) * _rng.randf_range(0.02, 0.06),
			"dur": _rng.randf_range(0.42, 0.72),
			"max_r": cell_w * _rng.randf_range(3.2, 5.4) * _scale,
			"width": _rng.randf_range(5.0, 11.0),
			"col": Color(1.0, _rng.randf_range(0.55, 0.95), _rng.randf_range(0.15, 0.45)),
		})


func _build_bits(cell_w: float) -> void:
	var n: int = _rng.randi_range(46, 68)
	for i in n:
		var ang := _rng.randf() * TAU
		var spd := _rng.randf_range(160.0, 780.0) * _scale
		var smoke := i % 7 == 0
		var col := Color(1.0, 0.95, 0.75)
		if smoke:
			col = Color(0.55, 0.48, 0.42, 0.55)
			spd *= 0.35
		elif i % 3 == 0:
			col = Color(1.0, 0.72, 0.18)
		elif i % 3 == 1:
			col = Color(1.0, 0.42, 0.08)
		_sparks.append({
			"p": Vector2(cos(ang), sin(ang)) * _rng.randf_range(0.0, cell_w * 0.25),
			"v": Vector2(cos(ang), sin(ang)) * spd + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-80, 40)),
			"life": 0.0,
			"max_life": _rng.randf_range(1.15, 1.45) if smoke else _rng.randf_range(0.45, 0.95),
			"size": _rng.randf_range(10.0, 22.0) if smoke else _rng.randf_range(3.0, 8.0),
			"col": col,
			"grav": 180.0 if smoke else _rng.randf_range(620.0, 1100.0),
			"smoke": smoke,
			"rot": _rng.randf() * TAU,
			"spin": _rng.randf_range(-8.0, 8.0),
			"trail": Vector2.ZERO,
		})


func _process(delta: float) -> void:
	_age += delta
	for s in _sparks:
		if float(s["life"]) >= float(s["max_life"]):
			continue
		s["trail"] = s["p"]
		s["v"] = s["v"] + Vector2(0.0, float(s["grav"]) * delta)
		s["p"] = s["p"] + s["v"] * delta
		s["rot"] = float(s["rot"]) + float(s["spin"]) * delta
		s["life"] = float(s["life"]) + delta
	if _age >= LIFE_SEC:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var flash_t := 1.0 - clampf(_age / 0.18, 0.0, 1.0)
	if flash_t > 0.02 and size.x > 1.0:
		var tint := _flash_col
		tint.a *= flash_t
		draw_rect(Rect2(Vector2.ZERO, size), tint, true)
	_draw_scorch()
	_draw_bloom(flash_t)
	_draw_rings()
	_draw_bits()


func _draw_scorch() -> void:
	var a := clampf(1.0 - _age / LIFE_SEC, 0.0, 1.0) * 0.72
	if a < 0.02:
		return
	draw_circle(_center + Vector2(0, 18), 34.0 * _scale, Color(0.12, 0.06, 0.03, a * 0.85))
	draw_circle(_center + Vector2(-10, 22), 18.0 * _scale, Color(0.05, 0.03, 0.02, a))
	draw_circle(_center + Vector2(14, 16), 14.0 * _scale, Color(0.2, 0.08, 0.02, a * 0.7))


func _draw_bloom(flash_t: float) -> void:
	if flash_t <= 0.02:
		return
	draw_circle(_center, _bloom_r * 1.15, Color(1.0, 0.45, 0.08, 0.22 * flash_t))
	draw_circle(_center, _bloom_r * 0.62, Color(1.0, 0.82, 0.25, 0.45 * flash_t))
	draw_circle(_center, _bloom_r * 0.28, Color(1.0, 0.97, 0.85, 0.85 * flash_t))


func _draw_rings() -> void:
	for ring in _rings:
		var local := _age - float(ring["delay"])
		if local <= 0.0:
			continue
		var u := clampf(local / float(ring["dur"]), 0.0, 1.0)
		if u >= 1.0:
			continue
		var col: Color = ring["col"]
		col.a = (1.0 - u) * 0.9
		var radius: float = lerpf(12.0, float(ring["max_r"]), u)
		draw_arc(_center, radius, 0.0, TAU, 56, col, float(ring["width"]) * (1.15 - u * 0.5), true)


func _draw_bits() -> void:
	for s in _sparks:
		var life := float(s["life"])
		var max_life := float(s["max_life"])
		if life >= max_life:
			continue
		var u := life / max_life
		var col: Color = s["col"]
		col.a *= 1.0 - u
		var at: Vector2 = _center + s["p"]
		var prev: Vector2 = _center + s["trail"]
		if bool(s["smoke"]):
			draw_circle(at, float(s["size"]) * (1.0 + u), col)
			continue
		if prev.distance_squared_to(at) > 4.0:
			var trail_col := col
			trail_col.a *= 0.45
			draw_line(prev, at, trail_col, maxf(1.5, float(s["size"]) * 0.35), true)
		var sz := float(s["size"])
		draw_set_transform(at, float(s["rot"]), Vector2.ONE)
		draw_rect(Rect2(-sz * 0.5, -sz * 0.2, sz, sz * 0.4), col, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
