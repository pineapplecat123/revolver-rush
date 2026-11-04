extends Control
class_name RarityFx
## v0.4.27 弹药稀有度特效（弹仓 / 弹药袋 / 商店 / 三选一 / 沙盒 统一）：
##   普通 common   = 无
##   稀有 uncommon = 表面一道斜向流光扫过 + 两颗小星闪
##   更稀有 rare   = 四周同色辉光（轻呼吸）
##   最稀有 epic   = 四周更亮七彩辉光（沿边流动） + 字体发亮（七彩描边）
## 用法：RarityFx.attach(任意 Control, ammo_id)；画圆形弹球用 RarityFx.draw_ball_back / draw_ball_front。

const TIER_COMMON := 0
const TIER_UNCOMMON := 1
const TIER_RARE := 2
const TIER_EPIC := 3
const NODE_NAME := "RarityFx"

var tier: int = 0
var base_col: Color = Color.WHITE
var corner: float = 6.0
var seed_f: float = 0.0
var _text_targets: Array = []


static func tier_for_ammo(ammo_id: int) -> int:
	if ammo_id <= 0:
		return TIER_COMMON
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	if def.is_empty():
		return TIER_COMMON
	match DataRegistry.get_ammo_rarity(ammo_id):
		"epic":
			return TIER_EPIC
		"rare":
			return TIER_RARE
		"uncommon":
			return TIER_UNCOMMON
	return TIER_COMMON


static func attach(host: Control, ammo_id: int, col: Color = Color(-1, -1, -1), p_corner: float = 6.0) -> RarityFx:
	## 幂等：同一 host 只挂一个；普通/空 → 摘掉。
	var t: int = tier_for_ammo(ammo_id)
	var fx: RarityFx = host.get_node_or_null(NODE_NAME) as RarityFx
	if t == TIER_COMMON:
		if fx != null:
			fx.clear_text_glow()
			host.remove_child(fx)
			fx.queue_free()
		return null
	if fx == null:
		fx = RarityFx.new()
		fx.name = NODE_NAME
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(fx)
	if col.r < 0.0:
		col = Color(0.9, 0.9, 0.9)
	var changed: bool = fx.tier != t
	fx.tier = t
	fx.base_col = col
	fx.corner = p_corner
	fx.seed_f = float(ammo_id) * 0.37 + float(host.get_index()) * 0.21
	if changed:
		fx.clear_text_glow()
	fx._collect_text_targets(host)
	fx.queue_redraw()
	return fx


func _collect_text_targets(host: Control) -> void:
	_text_targets.clear()
	if tier != TIER_EPIC:
		return
	if host is Button or host is Label:
		_text_targets.append(host)
	for c in host.get_children():
		if c is Label or c is Button:
			_text_targets.append(c)


func clear_text_glow() -> void:
	for n in _text_targets:
		if is_instance_valid(n):
			(n as Control).remove_theme_color_override("font_outline_color")
			(n as Control).remove_theme_constant_override("outline_size")
	_text_targets.clear()


func _process(_delta: float) -> void:
	if tier == TIER_COMMON or not is_visible_in_tree():
		return
	queue_redraw()
	if tier == TIER_EPIC:
		var tt: float = Time.get_ticks_msec() * 0.001
		var hc := Color.from_hsv(fposmod(tt * 0.35 + seed_f, 1.0), 0.55, 1.0, 0.95)
		for n in _text_targets:
			if is_instance_valid(n):
				(n as Control).add_theme_color_override("font_outline_color", hc)
				(n as Control).add_theme_constant_override("outline_size", 5)


func _draw() -> void:
	draw_rect_fx(self, Rect2(Vector2.ZERO, size), base_col, tier, Time.get_ticks_msec() * 0.001, seed_f, corner)


# ------------------------------------------------------------------ 共用绘制

static func rounded_rect_points(r: Rect2, rad: float, seg: int = 4) -> PackedVector2Array:
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var cs := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI]]
	for c in cs:
		for k in seg + 1:
			var a: float = float(c[1]) + PI * 0.5 * float(k) / float(seg)
			pts.append(Vector2(c[0]) + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	return pts


static func _shimmer_band(center_x: float, h_top: float, h_bot: float, w: float) -> PackedVector2Array:
	var slant: float = (h_bot - h_top) * 0.45
	return PackedVector2Array([
		Vector2(center_x - w + slant, h_top), Vector2(center_x + w + slant, h_top),
		Vector2(center_x + w - slant, h_bot), Vector2(center_x - w - slant, h_bot)])


static func _draw_star(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -s), p + Vector2(s * 0.28, -s * 0.28), p + Vector2(s, 0), p + Vector2(s * 0.28, s * 0.28),
		p + Vector2(0, s), p + Vector2(-s * 0.28, s * 0.28), p + Vector2(-s, 0), p + Vector2(-s * 0.28, -s * 0.28)]), col)


static func _surface_shimmer(ci: CanvasItem, shape: PackedVector2Array, bounds: Rect2, t: float, seed: float) -> void:
	var period := 1.8
	var ph: float = fposmod(t + seed * 1.7, period) / period
	var span: float = bounds.size.x + bounds.size.y
	var cx: float = bounds.position.x - bounds.size.y * 0.5 + span * ph
	var band := _shimmer_band(cx, bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.09, 2.5))
	for poly in Geometry2D.intersect_polygons(shape, band):
		ci.draw_colored_polygon(poly, Color(1, 1, 1, 0.5))
	var band2 := _shimmer_band(cx - maxf(bounds.size.x * 0.2, 6.0), bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.035, 1.2))
	for poly2 in Geometry2D.intersect_polygons(shape, band2):
		ci.draw_colored_polygon(poly2, Color(1, 1, 1, 0.3))
	# 两颗小星闪
	for k in 2:
		var tw: float = sin(t * 4.2 + seed * 3.0 + float(k) * 2.4)
		if tw <= 0.2:
			continue
		var fx: float = fposmod(seed * 0.618 + float(k) * 0.53, 1.0)
		var fy: float = fposmod(seed * 0.414 + float(k) * 0.37 + 0.2, 1.0)
		var p := bounds.position + Vector2(bounds.size.x * (0.18 + 0.64 * fx), bounds.size.y * (0.18 + 0.64 * fy))
		_draw_star(ci, p, minf(bounds.size.x, bounds.size.y) * 0.16 * tw, Color(1, 1, 0.92, 0.85 * tw))


static func draw_rect_fx(ci: CanvasItem, rect: Rect2, col: Color, tier: int, t: float, seed: float, corner: float = 6.0) -> void:
	if tier == TIER_UNCOMMON:
		_surface_shimmer(ci, rounded_rect_points(rect, corner), rect, t, seed)
	elif tier == TIER_RARE:
		var pulse: float = 0.75 + 0.25 * sin(t * 3.2 + seed)
		var gc: Color = col.lightened(0.25)
		for i in 4:
			var g: float = 2.0 + float(i) * 2.2
			var c := Color(gc.r, gc.g, gc.b, (0.55 - float(i) * 0.12) * pulse)
			ci.draw_polyline(rounded_rect_points(rect.grow(g), corner + g), c, 2.4, true)
	elif tier == TIER_EPIC:
		var pulse2: float = 0.85 + 0.15 * sin(t * 4.0 + seed)
		for i in 5:
			var g2: float = 1.5 + float(i) * 2.4
			var pts := rounded_rect_points(rect.grow(g2), corner + g2, 5)
			var cols := PackedColorArray()
			for k in pts.size():
				var hue: float = fposmod(float(k) / float(pts.size()) + t * 0.45 + seed, 1.0)
				cols.append(Color.from_hsv(hue, 0.75, 1.0, (0.9 - float(i) * 0.17) * pulse2))
			ci.draw_polyline_colors(pts, cols, 2.6, true)
		ci.draw_polyline(rounded_rect_points(rect.grow(0.5), corner), Color(1, 1, 1, 0.75 * pulse2), 1.5, true)


static func _circle_pts(pos: Vector2, r: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a: float = TAU * float(k) / float(n)
		pts.append(pos + Vector2(cos(a), sin(a)) * r)
	return pts


static func draw_ball_back(ci: CanvasItem, pos: Vector2, r: float, col: Color, tier: int, t: float, seed: float) -> void:
	## 球体之前画（外辉光）。
	if tier == TIER_RARE:
		var pulse: float = 0.75 + 0.25 * sin(t * 3.2 + seed)
		var gc: Color = col.lightened(0.25)
		ci.draw_circle(pos, r * 1.75, Color(gc.r, gc.g, gc.b, 0.14 * pulse))
		ci.draw_circle(pos, r * 1.42, Color(gc.r, gc.g, gc.b, 0.26 * pulse))
		ci.draw_circle(pos, r * 1.16, Color(gc.r, gc.g, gc.b, 0.4 * pulse))
	elif tier == TIER_EPIC:
		for i in 3:
			var rr: float = r * (1.85 - 0.3 * float(i))
			var pts := _circle_pts(pos, rr, 28)
			pts.append(pts[0])
			var cols := PackedColorArray()
			for k in pts.size():
				var hue: float = fposmod(float(k) / float(pts.size()) + t * 0.45 + seed, 1.0)
				cols.append(Color.from_hsv(hue, 0.75, 1.0, 0.35 + 0.2 * float(i)))
			ci.draw_polyline_colors(pts, cols, 2.6, true)


static func draw_ball_front(ci: CanvasItem, pos: Vector2, r: float, tier: int, t: float, seed: float) -> void:
	## 球体之后画（表面流光）。
	if tier == TIER_UNCOMMON:
		_surface_shimmer(ci, _circle_pts(pos, r * 0.96), Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), t, seed)
	elif tier == TIER_EPIC:
		ci.draw_arc(pos, r + 0.5, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5, true)


static func epic_text_outline(t: float, seed: float) -> Color:
	return Color.from_hsv(fposmod(t * 0.35 + seed, 1.0), 0.55, 1.0, 0.95)
