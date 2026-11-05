extends Node2D
## v0.4.35：一团篝火式大火焰（软圆/泪滴叠色），盖住全身 + 上升黑烟。
## 自绘 Compatibility 友好；无细线。挂骨骼随走，按体型缩放。

var _t: float = 0.0
var body_w: float = 56.0
var body_h: float = 100.0
var _active: bool = true

## 共享软斑纹理（径向渐变），全场只生成一次
static var _blob_tex: Texture2D = null
static var _tear_tex: Texture2D = null


func _ready() -> void:
	z_index = 8
	set_process(true)
	_ensure_textures()


func configure(w: float, h: float, scale_mul: float = 1.0) -> void:
	var m: float = maxf(0.85, scale_mul)
	body_w = maxf(48.0, w) * m
	body_h = maxf(80.0, h) * m
	queue_redraw()


func set_burn_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if on:
		queue_redraw()


func _process(delta: float) -> void:
	if not _active or not visible:
		return
	_t += delta
	queue_redraw()


static func _ensure_textures() -> void:
	if _blob_tex != null and _tear_tex != null:
		return
	_blob_tex = _make_radial_blob(64)
	_tear_tex = _make_teardrop_blob(48, 72)


static func _make_radial_blob(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(float(sz - 1) * 0.5, float(sz - 1) * 0.5)
	var r_max: float = float(sz) * 0.5
	for y in sz:
		for x in sz:
			var d: float = Vector2(float(x), float(y)).distance_to(c) / r_max
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			# 平滑软边
			a = a * a * (3.0 - 2.0 * a)
			a = pow(a, 1.15)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _make_teardrop_blob(w: int, h: int) -> Texture2D:
	## 上尖下圆的泪滴火舌（仍是软斑，不是线）
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx: float = float(w - 1) * 0.5
	for y in h:
		var v: float = float(y) / float(h - 1)  # 0=顶 1=底
		# 底部更宽，顶部收尖
		var half: float = lerpf(float(w) * 0.12, float(w) * 0.48, pow(v, 0.65))
		for x in w:
			var dx: float = absf(float(x) - cx) / maxf(half, 1.0)
			var a: float = clampf(1.0 - dx, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			# 纵向：中下部更实，尖端稍淡
			var along: float = 1.0 - absf(v - 0.62) * 1.1
			along = clampf(along, 0.0, 1.0)
			a *= along * (0.55 + 0.45 * (1.0 - v * 0.35))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _draw_blob(tex: Texture2D, center: Vector2, size: Vector2, col: Color) -> void:
	if tex == null:
		return
	var rect := Rect2(center - size * 0.5, size)
	draw_texture_rect(tex, rect, false, col)


func _draw() -> void:
	if not _active:
		return
	_ensure_textures()
	var half_w: float = body_w * 0.52
	var base_y: float = 10.0
	var top_y: float = -body_h * 0.95
	var mid_y: float = (base_y + top_y) * 0.5
	var flick_g: float = 0.82 + 0.18 * absf(sin(_t * 9.5))
	var sway: float = sin(_t * 3.2) * half_w * 0.06

	# —— 底层：暗红大罩，把全身糊成一团 ——
	_draw_blob(
		_blob_tex,
		Vector2(sway * 0.3, mid_y + 6.0),
		Vector2(body_w * 1.35, body_h * 1.15),
		Color(0.85, 0.12, 0.02, 0.42 * flick_g)
	)
	_draw_blob(
		_blob_tex,
		Vector2(-sway * 0.2, mid_y - body_h * 0.08),
		Vector2(body_w * 1.15, body_h * 1.05),
		Color(1.0, 0.28, 0.04, 0.38 * flick_g)
	)

	# —— 中层：大块橙黄叠色（少量大斑，不是细线）——
	var lobes := [
		{"x": 0.0, "y": 0.55, "sx": 1.05, "sy": 1.15, "spd": 7.0, "ph": 0.0},
		{"x": -0.28, "y": 0.42, "sx": 0.85, "sy": 1.0, "spd": 8.2, "ph": 1.7},
		{"x": 0.26, "y": 0.40, "sx": 0.88, "sy": 1.02, "spd": 7.6, "ph": 3.1},
		{"x": -0.12, "y": 0.22, "sx": 0.72, "sy": 0.95, "spd": 9.0, "ph": 4.4},
		{"x": 0.14, "y": 0.18, "sx": 0.70, "sy": 0.92, "spd": 8.5, "ph": 5.6},
		{"x": 0.0, "y": 0.05, "sx": 0.78, "sy": 0.88, "spd": 6.8, "ph": 2.2},
	]
	for i in lobes.size():
		var L: Dictionary = lobes[i]
		var ph: float = _t * float(L["spd"]) + float(L["ph"])
		var f: float = 0.75 + 0.25 * absf(sin(ph))
		var rise: float = sin(ph * 0.55) * body_h * 0.04
		var cx: float = float(L["x"]) * half_w + sin(ph * 0.4) * half_w * 0.05 + sway * 0.4
		var cy: float = lerpf(base_y, top_y, float(L["y"])) + rise
		var sx: float = body_w * float(L["sx"]) * (0.92 + 0.1 * f)
		var sy: float = body_h * float(L["sy"]) * (0.88 + 0.14 * f)
		# 外橙红
		_draw_blob(_blob_tex, Vector2(cx, cy), Vector2(sx, sy), Color(1.0, 0.32, 0.05, 0.36 * f))
		# 泪滴叠一层（向上拉长）
		_draw_blob(
			_tear_tex,
			Vector2(cx, cy - sy * 0.08),
			Vector2(sx * 0.72, sy * 1.15),
			Color(1.0, 0.55, 0.08, 0.40 * f)
		)

	# —— 内核：白黄亮心（篝火中心）——
	var core_f: float = 0.7 + 0.3 * absf(sin(_t * 11.0))
	_draw_blob(
		_blob_tex,
		Vector2(sway * 0.5, mid_y + body_h * 0.08),
		Vector2(body_w * 0.72, body_h * 0.7),
		Color(1.0, 0.78, 0.2, 0.45 * core_f)
	)
	_draw_blob(
		_blob_tex,
		Vector2(sway * 0.35, mid_y + body_h * 0.12),
		Vector2(body_w * 0.42, body_h * 0.48),
		Color(1.0, 0.95, 0.7, 0.55 * core_f)
	)
	_draw_blob(
		_blob_tex,
		Vector2(sway * 0.25, mid_y + body_h * 0.16),
		Vector2(body_w * 0.22, body_h * 0.28),
		Color(1.0, 1.0, 0.92, 0.62 * core_f)
	)

	# —— 顶部几块向上窜的大火舌（仍是软斑）——
	for i in 4:
		var ph2: float = _t * (5.5 + float(i) * 0.9) + float(i) * 1.9
		var f2: float = 0.65 + 0.35 * absf(sin(ph2))
		var x2: float = lerpf(-half_w * 0.45, half_w * 0.45, float(i) / 3.0) + sin(ph2) * 4.0
		var y2: float = top_y + 8.0 + sin(ph2 * 0.7) * 10.0 - fmod(_t * (18.0 + float(i) * 4.0), 22.0)
		_draw_blob(
			_tear_tex,
			Vector2(x2, y2),
			Vector2(body_w * (0.38 + 0.08 * float(i % 2)), body_h * 0.55 * f2),
			Color(1.0, 0.45 + 0.2 * f2, 0.06, 0.34 * f2)
		)

	# —— 上升黑烟（保留）——
	var smoke_n := 6
	for i in smoke_n:
		var phase: float = _t * (1.5 + float(i) * 0.22) + float(i) * 2.0
		var x: float = sin(phase) * half_w * 0.5 + float(i - 2) * 5.0
		var travel: float = fmod(_t * (20.0 + float(i) * 4.5) + float(i) * 12.0, body_h * 1.25)
		var y: float = top_y - 4.0 - travel * 0.55
		var life: float = 1.0 - travel / (body_h * 1.25)
		var rad: float = (body_w * 0.12) + float(i % 3) * 3.0 + (1.0 - life) * body_w * 0.14
		var a: float = 0.16 + 0.26 * life
		_draw_blob(
			_blob_tex,
			Vector2(x, y),
			Vector2(rad * 2.2, rad * 2.0),
			Color(0.1, 0.1, 0.12, a)
		)
		_draw_blob(
			_blob_tex,
			Vector2(x + rad * 0.35, y - rad * 0.4),
			Vector2(rad * 1.5, rad * 1.4),
			Color(0.18, 0.16, 0.14, a * 0.65)
		)
