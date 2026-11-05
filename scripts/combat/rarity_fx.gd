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
## v0.4.28 罪孽弹统一「危险」特效（盖过稀有度）：暗红/黑色锯齿光环抽动、红色警示描边忽闪、黑红余烬往上飘、字体暗红描边。
const TIER_SIN := 10
const SIN_RED := Color(0.86, 0.06, 0.1)
const SIN_DARK := Color(0.16, 0.0, 0.02)
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
	if DataRegistry.is_sin_ammo(ammo_id):
		return TIER_SIN
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
	if tier != TIER_EPIC and tier != TIER_SIN:
		return
	if host is Button or host is Label:
		_text_targets.append(host)
	for c in host.get_children():
		if c is Label or c is Button:
			_text_targets.append(c)



func _is_roughly_on_screen() -> bool:
	var gr := get_global_rect()
	if gr.size.x <= 1.0 or gr.size.y <= 1.0:
		return false
	var parent_scroll: ScrollContainer = null
	var n: Node = get_parent()
	while n != null:
		if n is ScrollContainer:
			parent_scroll = n as ScrollContainer
			break
		n = n.get_parent()
	if parent_scroll == null:
		return true
	var vr := parent_scroll.get_global_rect()
	# 稍扩一圈，避免刚入镜时空白一帧
	vr = vr.grow(48.0)
	return gr.intersects(vr)


func clear_text_glow() -> void:
	for n in _text_targets:
		if is_instance_valid(n):
			(n as Control).remove_theme_color_override("font_outline_color")
			(n as Control).remove_theme_constant_override("outline_size")
	_text_targets.clear()


func _process(_delta: float) -> void:
	if tier == TIER_COMMON or not is_visible_in_tree() or not visible:
		return
	# v0.4.32：滚动容器外的格子不 redraw，减轻图鉴滑动卡顿
	if not _is_roughly_on_screen():
		return
	queue_redraw()
	if tier == TIER_EPIC or tier == TIER_SIN:
		var tt: float = Time.get_ticks_msec() * 0.001
		var hc := Color.from_hsv(fposmod(tt * 0.35 + seed_f, 1.0), 0.55, 1.0, 0.95)
		if tier == TIER_SIN:
			hc = sin_text_outline(tt, seed_f)
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


static func _shimmer_ops(shape: PackedVector2Array, bounds: Rect2, t: float, seed: float) -> Array:
	## 与 _surface_shimmer 同几何，只返回 [多边形, 颜色] 列表（星星也是多边形）。
	var out: Array = []
	var period := 1.8
	var ph: float = fposmod(t + seed * 1.7, period) / period
	var span: float = bounds.size.x + bounds.size.y
	var cx: float = bounds.position.x - bounds.size.y * 0.5 + span * ph
	var band := _shimmer_band(cx, bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.09, 2.5))
	for poly in Geometry2D.intersect_polygons(shape, band):
		out.append([poly, Color(1, 1, 1, 0.5)])
	var band2 := _shimmer_band(cx - maxf(bounds.size.x * 0.2, 6.0), bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.035, 1.2))
	for poly2 in Geometry2D.intersect_polygons(shape, band2):
		out.append([poly2, Color(1, 1, 1, 0.3)])
	for k in 2:
		var tw: float = sin(t * 4.2 + seed * 3.0 + float(k) * 2.4)
		if tw <= 0.2:
			continue
		var fx: float = fposmod(seed * 0.618 + float(k) * 0.53, 1.0)
		var fy: float = fposmod(seed * 0.414 + float(k) * 0.37 + 0.2, 1.0)
		var p := bounds.position + Vector2(bounds.size.x * (0.18 + 0.64 * fx), bounds.size.y * (0.18 + 0.64 * fy))
		var s: float = minf(bounds.size.x, bounds.size.y) * 0.16 * tw
		out.append([PackedVector2Array([
			p + Vector2(0, -s), p + Vector2(s * 0.28, -s * 0.28), p + Vector2(s, 0), p + Vector2(s * 0.28, s * 0.28),
			p + Vector2(0, s), p + Vector2(-s * 0.28, s * 0.28), p + Vector2(-s, 0), p + Vector2(-s * 0.28, -s * 0.28)]),
			Color(1, 1, 0.92, 0.85 * tw)])
	return out


static func _surface_shimmer(ci: CanvasItem, shape: PackedVector2Array, bounds: Rect2, t: float, seed: float) -> void:
	var period := 1.8
	var ph: float = fposmod(t + seed * 1.7, period) / period
	var span: float = bounds.size.x + bounds.size.y
	var cx: float = bounds.position.x - bounds.size.y * 0.5 + span * ph
	var band := _shimmer_band(cx, bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.09, 2.5))
	for poly in Geometry2D.intersect_polygons(shape, band):
		_fill_convex(ci, poly, Color(1, 1, 1, 0.5))
	var band2 := _shimmer_band(cx - maxf(bounds.size.x * 0.2, 6.0), bounds.position.y, bounds.end.y, maxf(bounds.size.x * 0.035, 1.2))
	for poly2 in Geometry2D.intersect_polygons(shape, band2):
		_fill_convex(ci, poly2, Color(1, 1, 1, 0.3))
	# 两颗小星闪
	for k in 2:
		var tw: float = sin(t * 4.2 + seed * 3.0 + float(k) * 2.4)
		if tw <= 0.2:
			continue
		var fx: float = fposmod(seed * 0.618 + float(k) * 0.53, 1.0)
		var fy: float = fposmod(seed * 0.414 + float(k) * 0.37 + 0.2, 1.0)
		var p := bounds.position + Vector2(bounds.size.x * (0.18 + 0.64 * fx), bounds.size.y * (0.18 + 0.64 * fy))
		_draw_star(ci, p, minf(bounds.size.x, bounds.size.y) * 0.16 * tw, Color(1, 1, 0.92, 0.85 * tw))


## v0.4.29 帧内几何缓存：同一帧里同种弹（同 seed、同半径）的特效几何完全一样，只算一次，其余球平移复用。
static var _fc_t: float = -1.0
static var _fc: Dictionary = {}


static func _frame_cache(t: float) -> Dictionary:
	if t != _fc_t:
		_fc_t = t
		_fc.clear()
	return _fc


static func sin_flicker(t: float, seed: float) -> float:
	## 不规则忽闪：大部分时间亮，偶尔猛地暗一下。
	var a: float = 0.78 + 0.22 * sin(t * 9.0 + seed * 5.0)
	var h: float = fposmod(sin(floor(t * 14.0) * 12.9898 + seed * 78.233) * 43758.5453, 1.0)
	if h < 0.12:
		a *= 0.35
	return a


static func sin_text_outline(t: float, seed: float) -> Color:
	var f: float = sin_flicker(t, seed)
	return Color(0.75 * f + 0.1, 0.02, 0.05, 0.95)


static func _jagged_ring(center: Vector2, rx: float, ry: float, t: float, seed: float, n: int = 28, amp: float = 0.22) -> PackedVector2Array:
	## 锯齿光环：每个顶点半径跟时间乱跳（像噼啪的电/火舌）。形状只随 floor(t*18) 变：按原点缓存后平移。
	var step: float = floor(t * 18.0)
	var key := Vector4(step, seed, rx * 1000.0 + ry, float(n) * 1000.0 + amp)
	var cached = _jag_cache.get(key)
	if cached == null:
		cached = _jagged_ring_raw(Vector2.ZERO, rx, ry, step, seed, n, amp)
		if _jag_cache.size() > 512:
			_jag_cache.clear()
		_jag_cache[key] = cached
	return Transform2D(0.0, center) * (cached as PackedVector2Array)


static var _jag_cache: Dictionary = {}


static func _jagged_ring_raw(center: Vector2, rx: float, ry: float, step: float, seed: float, n: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a: float = TAU * float(k) / float(n)
		var hsh: float = fposmod(sin(float(k) * 91.7 + step * 13.1 + seed * 7.3) * 43758.5453, 1.0)
		var spike: float = (1.0 + amp * (hsh * 2.0 - 0.4)) if k % 2 == 0 else (1.0 - amp * 0.3 * hsh)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry) * spike)
	return pts


static func _sin_embers(ci: CanvasItem, center: Vector2, rx: float, ry: float, t: float, seed: float, n: int = 6) -> void:
	## 黑红余烬：从边缘往上飘、变暗消失。
	for k in n:
		var life: float = 1.1
		var ph: float = fposmod(t / life + float(k) / float(n) + seed * 0.37, 1.0)
		var ang: float = TAU * fposmod(float(k) * 0.618 + seed * 0.21 + floor(t / life + float(k) / float(n)) * 0.37, 1.0)
		var start: Vector2 = center + Vector2(cos(ang) * rx, sin(ang) * ry)
		var p: Vector2 = start + Vector2(sin(ph * 6.0 + float(k)) * 3.0, -ph * ry * 1.2)
		var c: Color = SIN_RED.lerp(Color(0.05, 0.0, 0.0), ph)
		c.a = (1.0 - ph) * 0.9
		var sz: float = 2.6 * (1.0 - 0.5 * ph)
		ci.draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c, true)


static func draw_sin_aura(ci: CanvasItem, center: Vector2, rx: float, ry: float, t: float, seed: float) -> void:
	## 外层：黑红锯齿光环（两层，抽动）+ 余烬。
	var f: float = sin_flicker(t, seed)
	var outer := _jagged_ring(center, rx + 9.0, ry + 9.0, t, seed, 30, 0.2)
	var inner := _jagged_ring(center, rx + 4.5, ry + 4.5, t + 0.37, seed + 1.0, 30, 0.16)
	_fill_star(ci, center, outer, Color(SIN_DARK.r, SIN_DARK.g, SIN_DARK.b, 0.55 * f))
	_fill_star(ci, center, inner, Color(0.55, 0.0, 0.05, 0.6 * f))
	var ol := outer.duplicate()
	ol.append(outer[0])
	ci.draw_polyline(ol, Color(SIN_RED.r, SIN_RED.g, SIN_RED.b, 0.85 * f), 1.6, true)
	_sin_embers(ci, center, rx + 4.0, ry + 4.0, t, seed)


static func draw_sin_front(ci: CanvasItem, shape: PackedVector2Array, t: float, seed: float) -> void:
	## 内沿：红色警示描边忽闪。
	var f: float = sin_flicker(t, seed)
	var pts := shape.duplicate()
	if pts.size() > 0 and pts[0] != pts[pts.size() - 1]:
		pts.append(pts[0])
	ci.draw_polyline(pts, Color(1.0, 0.12, 0.12, 0.95 * f), 2.0, true)


static func draw_rect_fx(ci: CanvasItem, rect: Rect2, col: Color, tier: int, t: float, seed: float, corner: float = 6.0) -> void:
	if tier == TIER_SIN:
		# 外层光环在宿主背后画不了（覆盖层在前），所以只画在宿主外沿以外：光环中心镂空用宿主本身遮住大半
		var c: Vector2 = rect.get_center()
		var hx: float = rect.size.x * 0.5
		var hy: float = rect.size.y * 0.5
		if corner >= minf(hx, hy):
			draw_sin_ring_only(ci, c, hx, hy, t, seed)
		else:
			draw_sin_rect_ring(ci, rect, corner, t, seed)
		draw_sin_front(ci, rounded_rect_points(rect.grow(-1.0), corner), t, seed)
		return
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


static var _unit_circle_cache: Dictionary = {}


static func _circle_pts(pos: Vector2, r: float, n: int = 24) -> PackedVector2Array:
	## v0.4.29：单位圆点缓存，按需缩放平移（原生变换，不再每球每帧 sin/cos）。
	var unit = _unit_circle_cache.get(n)
	if unit == null:
		var u := PackedVector2Array()
		for k in n:
			var a: float = TAU * float(k) / float(n)
			u.append(Vector2(cos(a), sin(a)))
		_unit_circle_cache[n] = u
		unit = u
	return Transform2D(0.0, Vector2(r, r), 0.0, pos) * (unit as PackedVector2Array)


static func draw_sin_ring_only(ci: CanvasItem, center: Vector2, rx: float, ry: float, t: float, seed: float) -> void:
	## 覆盖层用：只画宿主外面那一圈（锯齿环带 + 描边 + 余烬），不盖住弹药本体。
	var f: float = sin_flicker(t, seed)
	var outer := _jagged_ring(center, rx + 9.0, ry + 9.0, t, seed, 30, 0.2)
	var inner_hole := _jagged_ring(center, rx + 0.5, ry + 0.5, 0.0, 0.0, 30, 0.0)
	_draw_band(ci, outer, inner_hole, Color(0.32, 0.0, 0.03, 0.75 * f))
	var mid := _jagged_ring(center, rx + 4.5, ry + 4.5, t + 0.37, seed + 1.0, 30, 0.16)
	mid.append(mid[0])
	ci.draw_polyline(mid, Color(0.6, 0.0, 0.06, 0.8 * f), 2.0, true)
	var ol := outer.duplicate()
	ol.append(outer[0])
	ci.draw_polyline(ol, Color(SIN_RED.r, SIN_RED.g, SIN_RED.b, 0.9 * f), 1.6, true)
	_sin_embers(ci, center, rx + 4.0, ry + 4.0, t, seed)


static func _draw_band(ci: CanvasItem, outer: PackedVector2Array, inner: PackedVector2Array, col: Color) -> void:
	## 两条同点数闭合折线之间填环带（逐段四边形，不会把中间也填上）。
	## v0.4.29：整条环带一次三角形数组提交（原来每段 2 次 draw_primitive）。
	var n: int = mini(outer.size(), inner.size())
	if n < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(n * 2)
	for k in n:
		pts[k] = outer[k]
		pts[n + k] = inner[k]
	var idx := PackedInt32Array()
	idx.resize(n * 6)
	for k in n:
		var k2: int = (k + 1) % n
		var o: int = k * 6
		idx[o] = k
		idx[o + 1] = k2
		idx[o + 2] = n + k2
		idx[o + 3] = k
		idx[o + 4] = n + k2
		idx[o + 5] = n + k
	var cols := PackedColorArray()
	cols.resize(n * 2)
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _fill_convex(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	## 凸多边形（圆∩斜带）：质心扇形。细条退化时不报错。
	var n: int = poly.size()
	if n < 3:
		return
	var c := Vector2.ZERO
	for v in poly:
		c += v
	_fill_star(ci, c / float(n), poly, col)


static func _fill_star(ci: CanvasItem, center: Vector2, ring: PackedVector2Array, col: Color) -> void:
	## 星形（围绕中心单调）多边形：中心扇形三角化，一次提交。
	## 锯齿环会自交/退化，draw_colored_polygon 会三角化失败、每帧刷错误日志且不画——这里不会。
	var n: int = ring.size()
	if n < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	pts[0] = center
	for k in n:
		pts[k + 1] = ring[k]
	var idx := PackedInt32Array()
	idx.resize(n * 3)
	for k in n:
		idx[k * 3] = 0
		idx[k * 3 + 1] = k + 1
		idx[k * 3 + 2] = (k + 1) % n + 1
	var cols := PackedColorArray()
	cols.resize(n + 1)
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _jag_outward(pts: PackedVector2Array, center: Vector2, amp: float, t: float, seed: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step: float = floor(t * 18.0)
	for k in pts.size():
		var v: Vector2 = pts[k]
		var d: Vector2 = (v - center).normalized()
		var hsh: float = fposmod(sin(float(k) * 91.7 + step * 13.1 + seed * 7.3) * 43758.5453, 1.0)
		var push: float = amp * hsh if k % 2 == 0 else amp * 0.15 * hsh
		out.append(v + d * push)
	return out


static func draw_sin_rect_ring(ci: CanvasItem, rect: Rect2, corner: float, t: float, seed: float) -> void:
	## 方形宿主（三选一卡片等）：沿边一圈锯齿暗红环带 + 红描边 + 余烬。
	var f: float = sin_flicker(t, seed)
	var c: Vector2 = rect.get_center()
	var base := rounded_rect_points(rect.grow(4.0), corner + 4.0, 3)
	base.remove_at(base.size() - 1)
	var outer := _jag_outward(base, c, 8.0, t, seed)
	var hole := rounded_rect_points(rect.grow(0.5), corner, 3)
	hole.remove_at(hole.size() - 1)
	_draw_band(ci, outer, hole, Color(0.32, 0.0, 0.03, 0.72 * f))
	var ol := outer.duplicate()
	ol.append(outer[0])
	ci.draw_polyline(ol, Color(SIN_RED.r, SIN_RED.g, SIN_RED.b, 0.9 * f), 1.6, true)
	_sin_embers(ci, c, rect.size.x * 0.5, rect.size.y * 0.5, t, seed, 8)


static func draw_ball_back(ci: CanvasItem, pos: Vector2, r: float, col: Color, tier: int, t: float, seed: float) -> void:
	## 球体之前画（外辉光）。
	if tier == TIER_SIN:
		draw_sin_aura(ci, pos, r, r, t, seed)
		return
	if tier == TIER_RARE:
		var pulse: float = 0.75 + 0.25 * sin(t * 3.2 + seed)
		var gc: Color = col.lightened(0.25)
		ci.draw_circle(pos, r * 1.75, Color(gc.r, gc.g, gc.b, 0.14 * pulse))
		ci.draw_circle(pos, r * 1.42, Color(gc.r, gc.g, gc.b, 0.26 * pulse))
		ci.draw_circle(pos, r * 1.16, Color(gc.r, gc.g, gc.b, 0.4 * pulse))
	elif tier == TIER_EPIC:
		# 三圈同一条色相序列，只是透明度不同：色相每点算一次
		var fc := _frame_cache(t)
		var ckey := Vector3(3.0, seed, 0.0)
		var cols3 = fc.get(ckey)
		if cols3 == null:
			var base_cols := PackedColorArray()
			base_cols.resize(29)
			for k in 29:
				var hue: float = fposmod(float(k) / 29.0 + t * 0.45 + seed, 1.0)
				base_cols[k] = Color.from_hsv(hue, 0.75, 1.0, 1.0)
			cols3 = []
			for i in 3:
				var cols := base_cols.duplicate()
				var al: float = 0.35 + 0.2 * float(i)
				for k in 29:
					cols[k].a = al
				cols3.append(cols)
			fc[ckey] = cols3
		for i in 3:
			var rr: float = r * (1.85 - 0.3 * float(i))
			var pts := _circle_pts(pos, rr, 28)
			pts.append(pts[0])
			ci.draw_polyline_colors(pts, cols3[i], 2.6, true)


static func draw_ball_front(ci: CanvasItem, pos: Vector2, r: float, tier: int, t: float, seed: float) -> void:
	## 球体之后画（表面流光）。
	if tier == TIER_SIN:
		draw_sin_front(ci, _circle_pts(pos, r - 0.5), t, seed)
		return
	if tier == TIER_UNCOMMON:
		# 帧内同种同半径的球：流光几何一样，原点算一次（命令录进临时数组），各球平移重放
		var fc := _frame_cache(t)
		var key := Vector3(1.0, seed, r)
		var ops = fc.get(key)
		if ops == null:
			ops = _shimmer_ops(_circle_pts(Vector2.ZERO, r * 0.96), Rect2(-Vector2(r, r), Vector2(r, r) * 2.0), t, seed)
			fc[key] = ops
		var xf := Transform2D(0.0, pos)
		for op in ops:
			_fill_convex(ci, xf * (op[0] as PackedVector2Array), op[1])
	elif tier == TIER_EPIC:
		ci.draw_arc(pos, r + 0.5, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5, true)


static func epic_text_outline(t: float, seed: float) -> Color:
	return Color.from_hsv(fposmod(t * 0.35 + seed, 1.0), 0.55, 1.0, 0.95)
