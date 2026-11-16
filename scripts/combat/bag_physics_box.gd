class_name BagPhysicsBox
extends Control
## 弹药袋物理盒：袋内每发按子弹外形凸包做碰撞和点选（利于嵌 UI / Web）；绘制为圆钝弹头、台阶肩、单色子弹外形。

signal ball_hover(ammo_id: int)
signal ball_hover_exit(ammo_id: int)
signal ball_press(ammo_id: int)
signal ball_long_press_tick(ammo_id: int)  ## 按下持续时由外部计时；本控件发 press/release

const GRAVITY := 1400.0
## v0.4.49：默认视觉高度（720 视口像素）。碰撞与点选跟外形走（凸包 SAT + 多边形点选）。
const DEFAULT_HEIGHT := 48.0
const MIN_HEIGHT := 28.0
const LABEL_FONT_MIN := 16
const DEFAULT_RADIUS := 9.7344  ## 1.04*0.39*DEFAULT_HEIGHT/2，外形半宽近似；扫掠用半高
const ANG_DRAG := 0.985
const ANG_IMPULSE := 0.05
const MIN_RADIUS := 5.0
const MAX_BALLS_SOFT := 64
const RESTITUTION := 0.28
const WALL_FRICTION := 0.82
const AIR_DRAG := 0.995
const SLEEP_SPEED := 12.0
const WALL_PAD := 5.0
const SPAWN_JITTER := 18.0
## v0.4.49 袋内子弹外形（相对高度 1，尖朝 -Y）：宽 0.39；弹头 0.30（底部宽 0.90w）后横出台阶接到弹身；
## 弹身直到 0.89；抽壳槽收到 0.88w @ 0.925；底缘 1.04w 从 0.925 到 1。单色填充 + 一条外轮廓。
const BULLET_NOSE_FRAC := 0.30
const BULLET_BODY_W := 0.39
const BULLET_NOSE_W := 0.39 * 0.90
const BULLET_BODY_END := 0.89
const BULLET_GROOVE_Y := 0.925
const BULLET_GROOVE_W := 0.39 * 0.88
const BULLET_RIM_W := 0.39 * 1.04
const BULLET_RIM_FRAC := 0.075
const BULLET_OUTLINE := Color(0.086, 0.086, 0.102, 0.92)
const BULLET_OUTLINE_W := 1.7
const BULLET_OGIVE_STEPS := 12
const BULLET_OGIVE_EXP := 0.55

var _bullet_unit: PackedVector2Array = PackedVector2Array()
var _bullet_hull: PackedVector2Array = PackedVector2Array()
var _bullet_tris: PackedInt32Array = PackedInt32Array()

var color_lookup: Callable = Callable()  ## (ammo_id) -> {bg, fg}
var name_lookup: Callable = Callable()  ## (ammo_id) -> short glyph

var _balls: Array = []  # each: {id, pos:Vector2, vel:Vector2, r:float, asleep:bool, freeze:int}
var _hover_ammo: int = -1
var _pressed_ammo: int = -1
var _wall_color := Color(0.55, 0.38, 0.18, 1.0)
var _floor_color := Color(0.42, 0.28, 0.12, 1.0)
var _bg_color := Color(0.08, 0.07, 0.06, 0.92)
var _rim_color := Color(0.92, 0.72, 0.35, 0.85)
## v0.3.8 临时罪孽寿命：满寿命（画倒计时环用）；消失时的「啵」特效
var temp_full_life: float = 18.0
## v0.4.20：按弹药 id 覆盖寿命环满格（幽灵/小石头 18s，临时罪孽 10s）
var temp_full_life_by_id: Dictionary = {}
var _pops: Array = []  # {pos, r, t, color}
const POP_SEC := 0.45
## v0.4.29 性能基准用：累计 _draw / _physics_process 耗时（微秒），基准脚本读取后清零。
static var prof_draw_usec: int = 0
static var prof_phys_usec: int = 0
static var prof_draw_calls: int = 0
## v0.4.29 性能：每种弹的颜色/字/稀有度缓存（不再每帧每球调 Callable / 查表）；字形尺寸缓存；
## 重绘只在 _process 里每帧最多一次，且只有「有球在动 / 有动态稀有度特效 / 有啵圈」时才重绘。
var _style_cache: Dictionary = {}  # aid -> {bg, fg, tier, glyph}
var _text_off_cache: Dictionary = {}  # "glyph|fsize" -> Vector2(半宽, 基线偏移)
var _dirty: bool = true
var _animated_balls: int = 0  # 有动态特效（稀有度/罪孽）的球数；>0 则每帧重绘
## 布袋：外形+袋口束带；子弹在袋内轮廓里。sack_tilt 为绕袋身下部的倾角（倒出时口朝下）。
var _sack_tilt: float = 0.0
var sack_tilt: float:
	get:
		return _sack_tilt
	set(v):
		_sack_tilt = v
		_dirty = true
		queue_redraw()
var mouth_open: bool = false
var _pour_marks: Dictionary = {}  # ball index or id-key -> true
var _order_keys := PackedInt64Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(200, 200)


func ball_local_positions(ammo_id: int) -> Array:
	## v0.4.20：某种弹当前在袋里的球心（本地坐标），给「幽灵飞向手枪」动画取起点。
	var out: Array = []
	for b in _balls:
		if int(b.get("id", -1)) == ammo_id:
			out.append(b["pos"])
	return out


func ball_count() -> int:
	return _balls.size()


func clear_balls() -> void:
	_balls.clear()
	_animated_balls = 0
	_dirty = true
	_hover_ammo = -1
	_pressed_ammo = -1
	queue_redraw()


## 与袋内弹药同步。ammo_ids 可含重复；temps/envies 与之等长。
## v0.4.30：envies 标记嫉妒一次性复制（绿菱角标）。
func sync_ammo_ids(ammo_ids: Array, temps: Array = [], envies: Array = []) -> void:
	var want: Dictionary = {}  # key "id:t:e" -> count
	for i in ammo_ids.size():
		var aid: int = int(ammo_ids[i])
		var is_temp: bool = bool(temps[i]) if i < temps.size() else false
		var is_envy: bool = bool(envies[i]) if i < envies.size() else false
		var key: String = "%d:%d:%d" % [aid, 1 if is_temp else 0, 1 if is_envy else 0]
		want[key] = int(want.get(key, 0)) + 1
	var have: Dictionary = {}
	for b in _balls:
		var key2: String = "%d:%d:%d" % [int(b["id"]), 1 if bool(b.get("temp", false)) else 0, 1 if bool(b.get("envy", false)) else 0]
		have[key2] = int(have.get(key2, 0)) + 1
	for key3 in have.keys():
		var extra: int = int(have[key3]) - int(want.get(key3, 0))
		while extra > 0:
			var parts: PackedStringArray = str(key3).split(":")
			_remove_one_ball(int(parts[0]), parts.size() > 1 and parts[1] == "1", parts.size() > 2 and parts[2] == "1")
			extra -= 1
	for key4 in want.keys():
		var miss: int = int(want[key4]) - int(have.get(key4, 0))
		var parts2: PackedStringArray = str(key4).split(":")
		var aid4: int = int(parts2[0])
		var t4: bool = parts2.size() > 1 and parts2[1] == "1"
		var e4: bool = parts2.size() > 2 and parts2[2] == "1"
		for _i in miss:
			_spawn_ball(aid4, t4, e4)
	_update_radii_for_count()
	_recount_animated()
	_dirty = true
	queue_redraw()


func _style_for(aid: int) -> Dictionary:
	var st = _style_cache.get(aid)
	if st != null:
		return st
	var colors: Dictionary = {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}
	if color_lookup.is_valid():
		var looked = color_lookup.call(aid)
		if typeof(looked) == TYPE_DICTIONARY:
			colors = looked
	var glyph := "?"
	if name_lookup.is_valid():
		glyph = str(name_lookup.call(aid))
	st = {
		"bg": colors.get("bg", Color(0.85, 0.85, 0.88)),
		"fg": colors.get("fg", Color(0.1, 0.1, 0.1)),
		"tier": RarityFx.tier_for_ammo(aid),
		"glyph": glyph,
	}
	_style_cache[aid] = st
	return st


func invalidate_style_cache() -> void:
	_style_cache.clear()
	_text_off_cache.clear()
	_recount_animated()
	_dirty = true


func _recount_animated() -> void:
	_animated_balls = 0
	for b in _balls:
		if int(_style_for(int(b["id"]))["tier"]) != RarityFx.TIER_COMMON:
			_animated_balls += 1


func needs_redraw_every_frame() -> bool:
	return _animated_balls > 0 or not _pops.is_empty()


func _update_radii_for_count() -> void:
	var n: int = _balls.size()
	var sz := size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = custom_minimum_size
	var h: float = DEFAULT_HEIGHT
	if n > 0 and sz.x >= 8.0 and sz.y >= 8.0:
		var aabb := _sack_interior_aabb()
		var inner_w: float = maxf(aabb.size.x, 8.0)
		var inner_h: float = maxf(aabb.size.y, 8.0)
		h = _fit_bullet_height(n, inner_w, inner_h)
	var cr: float = h * BULLET_RIM_W * 0.5
	var r: float = h * 0.5
	var changed := false
	for b in _balls:
		if absf(float(b.get("h", 0.0)) - h) > 0.05:
			changed = true
		b["h"] = h
		b["cr"] = cr
		b["r"] = r
	if changed:
		for b2 in _balls:
			b2["asleep"] = false
			b2["freeze"] = 0
		_clamp_balls_inside()
		_dirty = true


func _fit_bullet_height(n: int, inner_w: float, inner_h: float) -> float:
	var h: float = DEFAULT_HEIGHT
	var guard := 0
	while h > MIN_HEIGHT and guard < 40:
		guard += 1
		if _pack_capacity(inner_w, inner_h, h) >= n:
			return h
		h -= 1.0
	return maxf(MIN_HEIGHT, h)


func _pack_capacity(inner_w: float, inner_h: float, h: float) -> int:
	## 自由旋转时按外形外接圆排，保证横躺的弹也能装进盒内。
	# 各种朝向时比外接圆网格更吃得下，容量略收紧以免把字缩到 16 以下。
	var cell: float = _bullet_circ_radius(h) * 1.76 + 2.0
	if cell < 4.0:
		return 0
	var cols: int = maxi(1, int(floor(inner_w / cell)))
	var rows: int = maxi(1, int(floor(inner_h / (cell * 0.8660254))))
	return cols * rows


static func _bullet_aabb_half(h: float, tilt: float) -> Vector2:
	## 最大倾角下凸包的轴对齐半宽半高，用来排位置。
	var hull: PackedVector2Array = build_bag_bullet_hull_unit()
	var cs := cos(tilt)
	var sn := sin(tilt)
	var mx := 0.0
	var my := 0.0
	for q0 in hull:
		var q: Vector2 = q0 * h
		var p := Vector2(q.x * cs - q.y * sn, q.x * sn + q.y * cs)
		mx = maxf(mx, absf(p.x))
		my = maxf(my, absf(p.y))
	return Vector2(mx, my)


static func _bullet_circ_radius(h: float) -> float:
	## 外形中心到凸包最远点，自由旋转时的包围半径。
	var hull: PackedVector2Array = build_bag_bullet_hull_unit()
	var m := 0.0
	for q in hull:
		m = maxf(m, (q as Vector2).length())
	return m * h


func _refresh_world_hull(b: Dictionary) -> PackedVector2Array:
	_ensure_bullet_unit()
	var pos: Vector2 = b["pos"]
	var pts: PackedVector2Array = _xform_unit_poly(_bullet_hull, pos, float(b.get("h", DEFAULT_HEIGHT)), float(b.get("ang", 0.0)))
	b["hull"] = pts
	var mx := 0.0
	var my := 0.0
	for p in pts:
		mx = maxf(mx, absf(p.x - pos.x))
		my = maxf(my, absf(p.y - pos.y))
	b["ext"] = Vector2(mx, my)
	return pts


func _world_hull(b: Dictionary) -> PackedVector2Array:
	var hull = b.get("hull", null)
	if hull is PackedVector2Array and (hull as PackedVector2Array).size() >= 3:
		return hull
	return _refresh_world_hull(b)


func _ball_ext(b: Dictionary) -> Vector2:
	var e = b.get("ext", null)
	if e is Vector2:
		return e
	var hull: PackedVector2Array = _world_hull(b)
	var pos: Vector2 = b["pos"]
	var mx := 0.0
	var my := 0.0
	for p in hull:
		mx = maxf(mx, absf(p.x - pos.x))
		my = maxf(my, absf(p.y - pos.y))
	var ext := Vector2(mx, my)
	b["ext"] = ext
	return ext


static func _xform_unit_poly(unit: PackedVector2Array, pos: Vector2, h: float, ang: float) -> PackedVector2Array:
	var cs := cos(ang)
	var sn := sin(ang)
	var pts := PackedVector2Array()
	pts.resize(unit.size())
	for i in unit.size():
		var q: Vector2 = unit[i] * h
		pts[i] = pos + Vector2(q.x * cs - q.y * sn, q.x * sn + q.y * cs)
	return pts


static func _sat_mtv(pa: PackedVector2Array, pb: PackedVector2Array) -> Vector2:
	## 若重叠，返回把 A 推出 B 的最小平移；不重叠则 ZERO。
	if pa.size() < 3 or pb.size() < 3:
		return Vector2.ZERO
	var min_overlap := INF
	var mtv := Vector2.ZERO
	for side in 2:
		var poly: PackedVector2Array = pa if side == 0 else pb
		var nvert: int = poly.size()
		for i in nvert:
			var e: Vector2 = poly[(i + 1) % nvert] - poly[i]
			var axis := Vector2(-e.y, e.x)
			var alen: float = axis.length()
			if alen <= 0.0000001:
				continue
			axis /= alen
			var mina := INF
			var maxa := -INF
			for p in pa:
				var d: float = p.dot(axis)
				mina = minf(mina, d)
				maxa = maxf(maxa, d)
			var minb := INF
			var maxb := -INF
			for p2 in pb:
				var d2: float = p2.dot(axis)
				minb = minf(minb, d2)
				maxb = maxf(maxb, d2)
			var overlap: float = minf(maxa, maxb) - maxf(mina, minb)
			if overlap <= 0.0:
				return Vector2.ZERO
			if overlap < min_overlap:
				min_overlap = overlap
				mtv = axis * overlap
	var ca := Vector2.ZERO
	var cb := Vector2.ZERO
	for p3 in pa:
		ca += p3
	for p4 in pb:
		cb += p4
	ca /= float(pa.size())
	cb /= float(pb.size())
	if mtv.dot(cb - ca) > 0.0:
		mtv = -mtv
	return mtv


static func _point_in_poly(p: Vector2, pts: PackedVector2Array) -> bool:
	var inside := false
	var n: int = pts.size()
	if n < 3:
		return false
	var j: int = n - 1
	for i in n:
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[j]
		if ((a.y > p.y) != (c.y > p.y)) and (p.x < (c.x - a.x) * (p.y - a.y) / (c.y - a.y + 0.0000001) + a.x):
			inside = not inside
		j = i
	return inside


static func label_font_size_for_height(h: float) -> int:
	var body_w: float = BULLET_BODY_W * h
	return int(clampf(round(body_w * 0.88), 11.0, 22.0))


func _clamp_balls_inside() -> void:
	if size.x < 8.0 and custom_minimum_size.x < 8.0:
		return
	for b in _balls:
		if bool(b.get("exited", false)):
			continue
		var ext: Vector2 = _ball_ext(b)
		var pos: Vector2 = b["pos"]
		var c: float = maxf(ext.x, ext.y)
		var np: Vector2 = _contain_point_in_sack(pos, c)
		if np.distance_squared_to(pos) > 0.0001:
			b["pos"] = np
			_refresh_world_hull(b)


func _spawn_ball(ammo_id: int, temporary: bool = false, envy_copy: bool = false) -> void:
	var sz := size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = custom_minimum_size
	var h: float = DEFAULT_HEIGHT
	var cr: float = h * BULLET_RIM_W * 0.5
	var r: float = h * 0.5
	var aabb := _sack_interior_aabb()
	var x: float = aabb.get_center().x + randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	x = clampf(x, aabb.position.x + cr, maxf(aabb.position.x + cr, aabb.end.x - cr))
	var y: float = aabb.position.y + r + randf_range(4.0, 16.0)
	_balls.append({
		"id": ammo_id,
		"temp": temporary or envy_copy,
		"envy": envy_copy,
		"pos": Vector2(x, y),
		"vel": Vector2(randf_range(-40.0, 40.0), randf_range(0.0, 30.0)),
		"r": r,
		"h": h,
		"cr": cr,
		"ang": randf_range(-PI, PI),
		"omega": randf_range(-3.5, 3.5),
		"asleep": false,
		"freeze": 0,
	})


func set_temp_lifetimes(by_id: Dictionary) -> void:
	## by_id: ammo_id -> [剩余秒…]。临时球同 id 互相等价：按顺序把寿命分给各球（升序）。
	var buckets: Dictionary = {}
	for k in by_id.keys():
		var arr: Array = (by_id[k] as Array).duplicate()
		arr.sort()
		buckets[int(k)] = arr
	var used: Dictionary = {}
	for b in _balls:
		if not bool(b.get("temp", false)):
			continue
		var aid: int = int(b["id"])
		var arr2: Array = buckets.get(aid, [])
		var idx: int = int(used.get(aid, 0))
		b["life"] = float(arr2[idx]) if idx < arr2.size() else 0.0
		used[aid] = idx + 1
	_dirty = true


func has_animation() -> bool:
	return not _pops.is_empty()


func _process(delta: float) -> void:
	if not _pops.is_empty():
		var i := _pops.size() - 1
		while i >= 0:
			_pops[i]["t"] = float(_pops[i]["t"]) + delta
			if float(_pops[i]["t"]) >= POP_SEC:
				_pops.remove_at(i)
			i -= 1
		_dirty = true
	if not is_visible_in_tree():
		return
	# 每个渲染帧最多重绘一次（物理步里不再 queue_redraw：低帧率时一帧跑多步物理会重复画 N 次）
	if _dirty or _animated_balls > 0:
		_dirty = false
		queue_redraw()


func _remove_one_ball(ammo_id: int, temporary: bool = false, envy_copy: bool = false) -> void:
	# 优先移除靠上的同 id+temp+envy 球，看起来像被「抓走」
	var best_i := -1
	var best_top := INF
	for i in _balls.size():
		var b: Dictionary = _balls[i]
		if int(b["id"]) != ammo_id:
			continue
		if bool(b.get("temp", false)) != temporary:
			continue
		if bool(b.get("envy", false)) != envy_copy:
			continue
		if float(b["pos"].y) < best_top:
			best_top = float(b["pos"].y)
			best_i = i
	if best_i >= 0:
		var gone: Dictionary = _balls[best_i]
		if temporary:
			# 临时罪孽消失：原地「啵」一下
			var col: Color = Color(1, 0.4, 0.3)
			if color_lookup.is_valid():
				var looked = color_lookup.call(ammo_id)
				if typeof(looked) == TYPE_DICTIONARY:
					col = looked.get("bg", col)
			_pops.append({"pos": gone["pos"], "r": float(gone["r"]), "t": 0.0, "color": col})
		_balls.remove_at(best_i)
		_dirty = true


func _physics_process(delta: float) -> void:
	var _pt0: int = Time.get_ticks_usec()
	_physics_step(delta)
	prof_phys_usec += Time.get_ticks_usec() - _pt0


func _physics_step(delta: float) -> void:
	if not visible or _balls.is_empty():
		return
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# 重力在袋局部坐标：袋子一倾斜，子弹就往袋口落。
	var gvec := Vector2(0.0, GRAVITY).rotated(-_sack_tilt)
	# integrate
	# 墓碑锚点：幽灵尽量围着漂
	var tomb_anchors: Array[Vector2] = []
	for tb in _balls:
		if int(tb.get("id", -1)) == FireResolver.ID_TOMBSTONE:
			tomb_anchors.append(tb["pos"])
	var any_awake := false
	for b in _balls:
		if bool(b["asleep"]):
			# 幽灵不睡死在底：轻推回漂浮
			if int(b.get("id", -1)) == FireResolver.ID_GHOST:
				b["asleep"] = false
				b["freeze"] = 0
			else:
				continue
		any_awake = true
		var vel: Vector2 = b["vel"]
		var aid: int = int(b.get("id", -1))
		if aid == FireResolver.ID_GHOST:
			# 低重力 + 轻正弦漂浮
			vel += gvec * 0.12 * delta
			vel.y += sin(Time.get_ticks_msec() * 0.004 + float(b["pos"].x) * 0.05) * 18.0 * delta
			if not tomb_anchors.is_empty():
				var nearest: Vector2 = tomb_anchors[0] as Vector2
				var best_d: float = float(b["pos"].distance_squared_to(nearest))
				for apos in tomb_anchors:
					var d2: float = b["pos"].distance_squared_to(apos)
					if d2 < best_d:
						best_d = d2
						nearest = apos
				var pull: Vector2 = nearest - b["pos"]
				var pd: float = pull.length()
				if pd > 1.0:
					# 围着墓碑：径向拉力 + 切向环绕
					var nrm: Vector2 = pull / pd
					var tangent := Vector2(-nrm.y, nrm.x)
					var orbit_r := 28.0
					vel += nrm * clampf(orbit_r - pd, -40.0, 40.0) * 0.9 * delta
					vel += tangent * 26.0 * delta
			vel *= 0.985
		else:
			vel += gvec * delta
			vel *= AIR_DRAG
		var pos: Vector2 = b["pos"]
		pos += vel * delta
		var ang: float = float(b.get("ang", 0.0))
		var omega: float = float(b.get("omega", 0.0))
		ang = wrapf(ang + omega * delta, -PI, PI)
		omega *= ANG_DRAG
		b["ang"] = ang
		b["omega"] = omega
		b["pos"] = pos
		# 转角变了，清掉缓存的凸包
		b.erase("hull")
		b.erase("ext")
		var ext: Vector2 = _ball_ext(b)
		var rad: float = maxf(ext.x, ext.y)
		var can_exit: bool = mouth_open and bool(b.get("pouring", false))
		var hit: Dictionary = _sack_wall_resolve(pos, rad, vel, can_exit)
		pos = hit["pos"]
		vel = hit["vel"]
		if bool(hit.get("exited", false)):
			b["exited"] = true
			b["asleep"] = false
		b["pos"] = pos
		b["vel"] = vel
		_refresh_world_hull(b)
	# ball-ball：外形凸包 SAT；按 x 扫掠，超过两倍半高就停；两颗都睡着的跳过。
	# 重力每帧会给 awake 的弹 ~GRAVITY*delta 的向下速度，入睡阈值必须把这计入，否则堆里的弹永远睡不着。
	var settle: float = GRAVITY * delta + SLEEP_SPEED
	var n: int = _balls.size()
	if any_awake:
		_dirty = true
	else:
		return
	var max_r: float = 0.0
	_order_keys.resize(n)
	for k in n:
		var bk: Dictionary = _balls[k]
		_world_hull(bk)
		max_r = maxf(max_r, float(bk.get("h", DEFAULT_HEIGHT)) * 0.56)
		_order_keys[k] = (int(floor(float(bk["pos"].x) * 16.0)) + 1048576) * 4096 + k
	_order_keys.sort()
	for oi in n:
		var i: int = int(_order_keys[oi] % 4096)
		var a: Dictionary = _balls[i]
		var ax: float = float(a["pos"].x)
		for oj in range(oi + 1, n):
			var j: int = int(_order_keys[oj] % 4096)
			var c: Dictionary = _balls[j]
			if float(c["pos"].x) - ax > max_r * 2.0 + 1.0:
				break
			if bool(a["asleep"]) and bool(c["asleep"]):
				continue
			if bool(a.get("exited", false)) or bool(c.get("exited", false)):
				continue
			# 轴对齐包围盒先剔除，避免细长弹在同一 x 窗口里对整列做 SAT
			var ea: Vector2 = a["ext"] if a.get("ext") is Vector2 else _ball_ext(a)
			var ec: Vector2 = c["ext"] if c.get("ext") is Vector2 else _ball_ext(c)
			if absf(float(c["pos"].x) - ax) > ea.x + ec.x + 0.5:
				continue
			if absf(float(c["pos"].y) - float(a["pos"].y)) > ea.y + ec.y + 0.5:
				continue
			var ha: PackedVector2Array = _world_hull(a)
			var hc: PackedVector2Array = _world_hull(c)
			var mtv: Vector2 = _sat_mtv(ha, hc)
			if mtv == Vector2.ZERO:
				continue
			var push: Vector2 = mtv * 0.5
			a["pos"] = a["pos"] + push
			c["pos"] = c["pos"] - push
			_refresh_world_hull(a)
			_refresh_world_hull(c)
			var va: Vector2 = a["vel"]
			var vc: Vector2 = c["vel"]
			# 被往上推的一方视为有支撑，清掉向下的重力速度，堆才能入睡。
			if push.y < -0.001 and va.y > 0.0:
				va.y = 0.0
			if push.y > 0.001 and vc.y > 0.0:
				vc.y = 0.0
			if va.length() >= settle or vc.length() >= settle:
				var nrm: Vector2 = mtv.normalized()
				var rel: float = (vc - va).dot(nrm)
				if rel > 0.0:
					var impulse: float = (1.0 + RESTITUTION) * rel * 0.5
					va = va + nrm * impulse
					vc = vc - nrm * impulse
					var tangent := Vector2(-nrm.y, nrm.x)
					var rel_t: float = (vc - va).dot(tangent)
					var spin: float = rel_t * ANG_IMPULSE
					a["omega"] = float(a.get("omega", 0.0)) + spin
					c["omega"] = float(c.get("omega", 0.0)) - spin
				a["asleep"] = false
				c["asleep"] = false
				a["freeze"] = 0
				c["freeze"] = 0
			a["vel"] = va
			c["vel"] = vc
	# 互撞可能把弹挤出墙外；睡着的弹下一帧不再做墙约束，所以这里再夹一次。
	_clamp_balls_inside()
	# 不靠底的弹在堆里速度也很低时同样入睡，避免 150 发时整袋每帧 SAT
	for b2 in _balls:
		if bool(b2["asleep"]):
			continue
		var v2: Vector2 = b2["vel"]
		if absf(v2.x) < SLEEP_SPEED and absf(v2.y) < settle:
			b2["freeze"] = int(b2["freeze"]) + 1
			if int(b2["freeze"]) > 8:
				b2["vel"] = Vector2.ZERO
				b2["omega"] = 0.0
				b2["asleep"] = true
		else:
			b2["freeze"] = 0


func _draw() -> void:
	var _dt0: int = Time.get_ticks_usec()
	_draw_box()
	prof_draw_usec += Time.get_ticks_usec() - _dt0
	prof_draw_calls += 1


func _draw_box() -> void:
	var sz := size
	var pv: Vector2 = _sack_pivot()
	draw_set_transform(pv, _sack_tilt, Vector2.ONE)
	_draw_sack(-pv, sz)
	# balls
	var tsec: float = Time.get_ticks_msec() * 0.001
	var font := get_theme_default_font()
	for b in _balls:
		if bool(b.get("exited", false)):
			continue
		var aid: int = int(b["id"])
		var pos: Vector2 = b["pos"] - pv
		var r: float = float(b["r"])
		var st: Dictionary = _style_for(aid)
		var bg: Color = st["bg"]
		var fg: Color = st["fg"]
		var is_temp_ball: bool = bool(b.get("temp", false))
		if is_temp_ball:
			bg.a *= 0.45
			fg.a *= 0.55
		# 按稀有度（v0.4.27）：稀有表面流光 / 更稀有同色辉光 / 最稀有七彩辉光
		var tier: int = int(st["tier"])
		var seedv: float = float(aid) * 0.37 + float(b.get("seed", 0.0))
		var h: float = float(b.get("h", r * 2.0))
		var fx_r: float = h * 0.36
		if tier != RarityFx.TIER_COMMON:
			RarityFx.draw_ball_back(self, pos, fx_r, bg, tier, tsec, seedv)
		var ang: float = float(b.get("ang", 0.0))
		_draw_bag_bullet(pos, h, ang, bg)
		if tier != RarityFx.TIER_COMMON:
			RarityFx.draw_ball_front(self, pos, fx_r, tier, tsec, seedv)
		# v0.4.36：仅 TTL>0 画寿命环（幽灵/小石头）；打出即毁临时只有半透明，无环无秒数
		if is_temp_ball:
			var life: float = float(b.get("life", 0.0))
			if life > 0.0:
				var full: float = float(temp_full_life_by_id.get(aid, temp_full_life))
				var frac: float = clampf(life / maxf(full, 0.01), 0.0, 1.0)
				var ring_col: Color = Color(1.0, 0.3, 0.25, 0.95) if frac <= 0.25 else Color(1.0, 0.95, 0.8, 0.9)
				draw_arc(pos, fx_r + 2.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, ring_col, 2.5, false)
		var glyph: String = st["glyph"]
		var fsize := label_font_size_for_height(h)
		if font != null:
			# 字永远正向对着玩家，画在子弹中心，不跟外形一起转
			var tkey: String = "%s|%d" % [glyph, fsize]
			var off = _text_off_cache.get(tkey)
			if off == null:
				var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
				off = Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(fsize))
				_text_off_cache[tkey] = off
			var text_pos: Vector2 = off as Vector2
			draw_set_transform(pos, 0.0, Vector2.ONE)
			if tier == RarityFx.TIER_EPIC:
				draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, RarityFx.epic_text_outline(tsec, seedv))
			elif tier == RarityFx.TIER_SIN:
				draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, RarityFx.sin_text_outline(tsec, seedv))
			else:
				# 细描边，720 视口上单字更清楚
				var oc := Color(fg.r, fg.g, fg.b, fg.a)
				oc = Color(0.08, 0.08, 0.1, 0.7) if fg.r + fg.g + fg.b > 1.6 else Color(1, 1, 1, 0.35)
				draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 2, oc)
			draw_string(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# v0.4.30 嫉妒一次性复制：右上角绿菱
		if bool(b.get("envy", false)):
			var d: float = maxf(3.5, h * 0.12)
			var tip: Vector2 = pos + Vector2(h * 0.18, -h * 0.22)
			draw_colored_polygon(PackedVector2Array([
				tip + Vector2(0, -d), tip + Vector2(d, 0), tip + Vector2(0, d), tip + Vector2(-d, 0)
			]), Color(0.25, 0.95, 0.45, 0.95))
	# 临时罪孽消失特效：扩散淡出圈
	for pp in _pops:
		var k: float = clampf(float(pp["t"]) / POP_SEC, 0.0, 1.0)
		var pc: Color = pp["color"]
		pc.a = 0.85 * (1.0 - k)
		draw_arc(pp["pos"], float(pp["r"]) * (1.0 + 1.6 * k), 0.0, TAU, 28, pc, 3.0 * (1.0 - k) + 1.0, true)
		var pc2: Color = pc
		pc2.a = 0.35 * (1.0 - k)
		draw_circle(pp["pos"], float(pp["r"]) * (1.0 - 0.6 * k), pc2)
	# empty hint
	if _balls.is_empty():
		var font2 := get_theme_default_font()
		if font2 != null:
			var empty := "（空袋）"
			var es := font2.get_string_size(empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var ea := font2.get_ascent(14)
			draw_string(
				font2,
				Vector2(sz.x * 0.5 - es.x * 0.5, sz.y * 0.5 - es.y * 0.5 + ea) - pv,
				empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.6, 0.5)
			)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ball_at_pointer(local_pos: Vector2 = Vector2.INF) -> Variant:
	var p := local_pos
	if p.x == INF:
		p = get_local_mouse_position()
	p = _sack_xform().affine_inverse() * p
	# 点选跟可见外形走（单位多边形，含抽壳槽往里收的部分）
	_ensure_bullet_unit()
	var best = null
	var best_d := INF
	for b in _balls:
		if bool(b.get("exited", false)):
			continue
		var pos: Vector2 = b["pos"]
		var h: float = maxf(float(b.get("h", DEFAULT_HEIGHT)), 0.001)
		var ang: float = float(b.get("ang", 0.0))
		var dp: Vector2 = p - pos
		var cs := cos(-ang)
		var sn := sin(-ang)
		var local := Vector2(dp.x * cs - dp.y * sn, dp.x * sn + dp.y * cs) / h
		if not _point_in_poly(local, _bullet_unit):
			continue
		var d: float = dp.length()
		if d < best_d:
			best_d = d
			best = b
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var b = _ball_at_pointer()
		var aid := int(b["id"]) if b != null else -1
		if aid != _hover_ammo:
			if _hover_ammo >= 0:
				ball_hover_exit.emit(_hover_ammo)
			_hover_ammo = aid
			if aid >= 0:
				ball_hover.emit(aid)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var b2 = _ball_at_pointer(mb.position)
			if mb.pressed:
				if b2 != null:
					_pressed_ammo = int(b2["id"])
					ball_press.emit(_pressed_ammo)
					# wake ball a bit
					b2["asleep"] = false
					b2["vel"] = Vector2(b2["vel"]) + Vector2(randf_range(-30, 30), -40)
			else:
				if _pressed_ammo >= 0:
					_pressed_ammo = -1
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var b3 = _ball_at_pointer(st.position)
		if st.pressed and b3 != null:
			_pressed_ammo = int(b3["id"])
			ball_press.emit(_pressed_ammo)
		elif not st.pressed:
			_pressed_ammo = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_radii_for_count()
		_clamp_balls_inside()
		_dirty = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		if _hover_ammo >= 0:
			ball_hover_exit.emit(_hover_ammo)
			_hover_ammo = -1


func _draw_bag_bullet(pos: Vector2, h: float, ang: float, fill: Color) -> void:
	var pts := _bag_bullet_points(pos, h, ang)
	if pts.size() < 3:
		return
	_ensure_bullet_unit()
	# 按预计算三角形填充，避免带抽壳槽的多边形在某些角度三角化失败。
	if _bullet_tris.size() >= 3:
		var tri := PackedVector2Array()
		tri.resize(3)
		var i := 0
		while i + 2 < _bullet_tris.size():
			var a: int = int(_bullet_tris[i])
			var b: int = int(_bullet_tris[i + 1])
			var c: int = int(_bullet_tris[i + 2])
			if a >= 0 and b >= 0 and c >= 0 and a < pts.size() and b < pts.size() and c < pts.size():
				tri[0] = pts[a]
				tri[1] = pts[b]
				tri[2] = pts[c]
				draw_colored_polygon(tri, fill)
			i += 3
	else:
		draw_colored_polygon(_xform_unit_poly(_bullet_hull, pos, h, ang), fill)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, BULLET_OUTLINE, BULLET_OUTLINE_W, true)


func _bag_bullet_points(pos: Vector2, h: float, ang: float) -> PackedVector2Array:
	## 单位多边形乘高度后旋转；原点在几何中心。
	_ensure_bullet_unit()
	var cs := cos(ang)
	var sn := sin(ang)
	var pts := PackedVector2Array()
	pts.resize(_bullet_unit.size())
	for i in _bullet_unit.size():
		var q: Vector2 = _bullet_unit[i] * h
		pts[i] = pos + Vector2(q.x * cs - q.y * sn, q.x * sn + q.y * cs)
	return pts


func _ensure_bullet_unit() -> void:
	if not _bullet_unit.is_empty() and not _bullet_hull.is_empty() and not _bullet_tris.is_empty():
		return
	_bullet_unit = build_bag_bullet_unit()
	_bullet_hull = build_bag_bullet_hull_unit()
	_bullet_tris = Geometry2D.triangulate_polygon(_bullet_unit)
	if _bullet_tris.is_empty() and _bullet_unit.size() >= 2:
		# 首尾可能都是弹尖，去掉重复点再三角化
		var dedup := PackedVector2Array()
		for i in _bullet_unit.size():
			var q: Vector2 = _bullet_unit[i]
			if dedup.is_empty() or q.distance_squared_to(dedup[dedup.size() - 1]) > 0.00000001:
				if dedup.size() == 0 or q.distance_squared_to(dedup[0]) > 0.00000001 or i < _bullet_unit.size() - 1:
					dedup.append(q)
		if dedup.size() >= 2 and dedup[0].distance_squared_to(dedup[dedup.size() - 1]) <= 0.00000001:
			dedup.remove_at(dedup.size() - 1)
		_bullet_unit = dedup
		_bullet_tris = Geometry2D.triangulate_polygon(_bullet_unit)


## 单位高度 1、原点在中心、尖朝 -Y。给绘制和测试共用。
static func build_bag_bullet_unit() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw: float = BULLET_BODY_W * 0.5
	var nw: float = BULLET_NOSE_W * 0.5
	var gw: float = BULLET_GROOVE_W * 0.5
	var rw: float = BULLET_RIM_W * 0.5
	var y_tip: float = -0.5
	var y_nose: float = -0.5 + BULLET_NOSE_FRAC
	var y_body: float = -0.5 + BULLET_BODY_END
	var y_gr: float = -0.5 + BULLET_GROOVE_Y
	var y_bot: float = 0.5
	# 弹头左侧：t=0 在尖，t=1 到弹头底部（宽 0.90w）。x=(0.90w/2)*sin(t*pi/2)^0.55
	for i in BULLET_OGIVE_STEPS + 1:
		var t: float = float(i) / float(BULLET_OGIVE_STEPS)
		var x: float = nw * pow(sin(t * PI * 0.5), BULLET_OGIVE_EXP)
		var y: float = y_tip + BULLET_NOSE_FRAC * t
		pts.append(Vector2(-x, y))
	# 肩部横出台阶，接到弹身全宽，再沿弹身向下
	pts.append(Vector2(-hw, y_nose))
	pts.append(Vector2(-hw, 0.0))
	pts.append(Vector2(-hw, y_body))
	# 抽壳槽向内收到 0.88w，再横出到底缘 1.04w
	pts.append(Vector2(-gw, y_gr))
	pts.append(Vector2(-rw, y_gr))
	pts.append(Vector2(-rw, y_bot))
	pts.append(Vector2(rw, y_bot))
	pts.append(Vector2(rw, y_gr))
	pts.append(Vector2(gw, y_gr))
	pts.append(Vector2(hw, y_body))
	pts.append(Vector2(hw, 0.0))
	pts.append(Vector2(hw, y_nose))
	# 弹头右侧，从底回到尖
	for i in range(BULLET_OGIVE_STEPS, -1, -1):
		var t4: float = float(i) / float(BULLET_OGIVE_STEPS)
		var x2: float = nw * pow(sin(t4 * PI * 0.5), BULLET_OGIVE_EXP)
		var y2: float = y_tip + BULLET_NOSE_FRAC * t4
		pts.append(Vector2(x2, y2))
	return pts

## 外形凸包（抽壳槽往里收的部分被填上，避免非凸多边形 SAT）。绘制仍用完整轮廓。
static func build_bag_bullet_hull_unit() -> PackedVector2Array:
	## 碰撞凸包只保留外形极值（尖、弹头样点、肩、身、缘），比完整绘制多边形更少顶点。
	var hw: float = BULLET_BODY_W * 0.5
	var nw: float = BULLET_NOSE_W * 0.5
	var rw: float = BULLET_RIM_W * 0.5
	var y_tip: float = -0.5
	var y_nose: float = -0.5 + BULLET_NOSE_FRAC
	var y_body: float = -0.5 + BULLET_BODY_END
	var y_gr: float = -0.5 + BULLET_GROOVE_Y
	var y_bot: float = 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, y_tip))
	for i in [4, 8, 12]:
		var t: float = float(i) / float(BULLET_OGIVE_STEPS)
		var x: float = nw * pow(sin(t * PI * 0.5), BULLET_OGIVE_EXP)
		var y: float = y_tip + BULLET_NOSE_FRAC * t
		pts.append(Vector2(-x, y))
		pts.append(Vector2(x, y))
	pts.append(Vector2(-hw, y_nose))
	pts.append(Vector2(hw, y_nose))
	pts.append(Vector2(-hw, y_body))
	pts.append(Vector2(hw, y_body))
	pts.append(Vector2(-rw, y_gr))
	pts.append(Vector2(rw, y_gr))
	pts.append(Vector2(-rw, y_bot))
	pts.append(Vector2(rw, y_bot))
	return _convex_hull(pts)


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _convex_hull(src: PackedVector2Array) -> PackedVector2Array:
	var pts: Array = []
	for p in src:
		pts.append(p)
	pts.sort_custom(func(u, v):
		return u.x < v.x - 0.0000001 or (absf(u.x - v.x) <= 0.0000001 and u.y < v.y)
	)
	if pts.size() <= 3:
		return PackedVector2Array(pts)
	var lower: Array = []
	for p in pts:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array = []
	var i: int = pts.size() - 1
	while i >= 0:
		var p2: Vector2 = pts[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], p2) <= 0.0:
			upper.pop_back()
		upper.append(p2)
		i -= 1
	if not lower.is_empty():
		lower.pop_back()
	if not upper.is_empty():
		upper.pop_back()
	var out := PackedVector2Array()
	for q in lower:
		out.append(q)
	for q2 in upper:
		out.append(q2)
	return out

func _sack_pivot() -> Vector2:
	var sz := size if size.x >= 8.0 else custom_minimum_size
	return Vector2(sz.x * 0.5, sz.y * 0.62)


func _sack_xform() -> Transform2D:
	var pv := _sack_pivot()
	return Transform2D(_sack_tilt, pv) * Transform2D(0.0, -pv)


func sack_mouth_local() -> Vector2:
	## 袋口中心（盒内坐标，未乘倾角）。
	var sz := size if size.x >= 8.0 else custom_minimum_size
	return Vector2(sz.x * 0.5, sz.y * 0.08)


func sack_mouth_global() -> Vector2:
	return get_global_transform() * (_sack_xform() * sack_mouth_local())


static func sack_interior_unit() -> PackedVector2Array:
	## 袋内轮廓：口在上，下部较宽。单位盒 0-1，Y 向下。
	return PackedVector2Array([
		Vector2(0.34, 0.06),
		Vector2(0.16, 0.22),
		Vector2(0.06, 0.50),
		Vector2(0.10, 0.86),
		Vector2(0.50, 0.97),
		Vector2(0.90, 0.86),
		Vector2(0.94, 0.50),
		Vector2(0.84, 0.22),
		Vector2(0.66, 0.06),
	])


func _sack_interior_local() -> PackedVector2Array:
	var sz := size if size.x >= 8.0 else custom_minimum_size
	var pts := PackedVector2Array()
	for q in sack_interior_unit():
		pts.append(Vector2(q.x * sz.x, q.y * sz.y))
	return pts


func _sack_interior_aabb() -> Rect2:
	var pts := _sack_interior_local()
	if pts.is_empty():
		return Rect2(Vector2.ZERO, size)
	var mn := pts[0]
	var mx := pts[0]
	for p2 in pts:
		mn = Vector2(minf(mn.x, p2.x), minf(mn.y, p2.y))
		mx = Vector2(maxf(mx.x, p2.x), maxf(mx.y, p2.y))
	return Rect2(mn, mx - mn)


func _contain_point_in_sack(pos: Vector2, rad: float) -> Vector2:
	var hit := _sack_wall_resolve(pos, rad, Vector2.ZERO, false)
	return hit["pos"]


func _sack_wall_resolve(pos: Vector2, rad: float, vel: Vector2, can_exit: bool) -> Dictionary:
	var pts := _sack_interior_local()
	var n: int = pts.size()
	if n < 3:
		return {"pos": pos, "vel": vel, "exited": false}
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= float(n)
	# 口是最上面两点之间的边（单位里第一点和最后一点）
	var exited := false
	if can_exit:
		var mouth_y: float = minf(pts[0].y, pts[n - 1].y)
		if pos.y + rad * 0.15 < mouth_y:
			return {"pos": pos, "vel": vel, "exited": true}
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var is_mouth: bool = (i == n - 1)
		if is_mouth and can_exit:
			continue
		var e: Vector2 = b - a
		if e.length_squared() < 0.0001:
			continue
		var nrm := Vector2(e.y, -e.x).normalized()
		if nrm.dot((a + b) * 0.5 - c) < 0.0:
			nrm = -nrm
		var overlap: float = pos.dot(nrm) + rad - a.dot(nrm)
		if overlap > 0.0:
			pos -= nrm * overlap
			var vn: float = vel.dot(nrm)
			if vn > 0.0:
				vel -= nrm * vn * (1.0 + RESTITUTION)
				var tan := Vector2(-nrm.y, nrm.x)
				vel -= tan * vel.dot(tan) * (1.0 - WALL_FRICTION)
	return {"pos": pos, "vel": vel, "exited": exited}


func mark_pour_balls(count: int) -> int:
	_pour_marks.clear()
	var n: int = 0
	var order: Array = []
	for i in _balls.size():
		order.append(i)
	order.shuffle()
	for i in order:
		if n >= count:
			break
		var b: Dictionary = _balls[i]
		if bool(b.get("exited", false)):
			continue
		b["pouring"] = true
		b["asleep"] = false
		b["freeze"] = 0
		n += 1
	return n


func impulse_pour_balls() -> void:
	var mouth: Vector2 = sack_mouth_local()
	for b in _balls:
		if not bool(b.get("pouring", false)):
			continue
		var pos: Vector2 = b["pos"]
		var to_m: Vector2 = mouth - pos
		if to_m.length() > 1.0:
			b["vel"] = Vector2(b["vel"]) + to_m.normalized() * 260.0
		b["asleep"] = false


func take_exited_pour_balls() -> Array:
	var out: Array = []
	var i := _balls.size() - 1
	while i >= 0:
		var b: Dictionary = _balls[i]
		if bool(b.get("exited", false)) and bool(b.get("pouring", false)):
			var rec: Dictionary = b.duplicate()
			rec["world_pos"] = get_global_transform() * (_sack_xform() * Vector2(b["pos"]))
			out.append(rec)
			_balls.remove_at(i)
			_dirty = true
		i -= 1
	if not out.is_empty():
		_update_radii_for_count()
	return out


func take_remaining_pour_balls() -> Array:
	for b in _balls:
		if bool(b.get("pouring", false)) and not bool(b.get("exited", false)):
			b["exited"] = true
	return take_exited_pour_balls()


func _draw_sack(off: Vector2, sz: Vector2) -> void:
	## off 是 -pivot，因为外层已按 pivot 旋转。
	var cloth := Color(0.55, 0.34, 0.18, 1.0)
	var cloth_d := Color(0.36, 0.20, 0.10, 1.0)
	var stitch := Color(0.22, 0.12, 0.06, 0.95)
	var cord := Color(0.78, 0.64, 0.36, 1.0)
	# 外轮廓比里面略大
	var outer := PackedVector2Array()
	for q in [
		Vector2(0.40, 0.015), Vector2(0.37, 0.10), Vector2(0.22, 0.22),
		Vector2(0.08, 0.46), Vector2(0.10, 0.78), Vector2(0.30, 0.96),
		Vector2(0.50, 0.99), Vector2(0.70, 0.96), Vector2(0.90, 0.78),
		Vector2(0.92, 0.46), Vector2(0.78, 0.22), Vector2(0.63, 0.10),
		Vector2(0.60, 0.015),
	]:
		outer.append(off + Vector2(q.x * sz.x, q.y * sz.y))
	if outer.size() >= 3:
		draw_colored_polygon(outer, cloth)
		# 底部暗一点
		var shadow := PackedVector2Array()
		for q2 in [Vector2(0.16, 0.70), Vector2(0.12, 0.84), Vector2(0.50, 0.98), Vector2(0.88, 0.84), Vector2(0.84, 0.70)]:
			shadow.append(off + Vector2(q2.x * sz.x, q2.y * sz.y))
		draw_colored_polygon(shadow, cloth_d)
		var ol := PackedVector2Array(outer)
		ol.append(outer[0])
		draw_polyline(ol, stitch, 2.4, true)
	# 袋口和束带
	var mx := sz.x
	var my := sz.y
	var mouth_l := off + Vector2(0.33 * mx, 0.04 * my)
	var mouth_r := off + Vector2(0.67 * mx, 0.04 * my)
	var neck_y := off.y + 0.09 * my
	draw_line(mouth_l, mouth_r, stitch, 3.0, true)
	draw_line(off + Vector2(0.34 * mx, 0.09 * my), off + Vector2(0.66 * mx, 0.09 * my), cord, 3.2, true)
	# 两侧落下的带子
	draw_polyline(PackedVector2Array([
		off + Vector2(0.36 * mx, 0.09 * my),
		off + Vector2(0.28 * mx, -0.02 * my),
		off + Vector2(0.24 * mx, 0.12 * my),
	]), cord, 2.2, true)
	draw_polyline(PackedVector2Array([
		off + Vector2(0.64 * mx, 0.09 * my),
		off + Vector2(0.72 * mx, -0.02 * my),
		off + Vector2(0.76 * mx, 0.12 * my),
	]), cord, 2.2, true)
	# 口上小结
	draw_circle(off + Vector2(0.50 * mx, 0.07 * my), maxf(3.5, mx * 0.018), cord)


func _draw_bag_bullet_on(ci: CanvasItem, pos: Vector2, h: float, ang: float, fill: Color) -> void:
	if ci == null:
		return
	var pts := _bag_bullet_points(pos, h, ang)
	if pts.size() < 3:
		return
	_ensure_bullet_unit()
	if _bullet_tris.size() >= 3:
		var tri := PackedVector2Array()
		tri.resize(3)
		var i := 0
		while i + 2 < _bullet_tris.size():
			var a: int = int(_bullet_tris[i])
			var b: int = int(_bullet_tris[i + 1])
			var c: int = int(_bullet_tris[i + 2])
			if a >= 0 and b >= 0 and c >= 0 and a < pts.size() and b < pts.size() and c < pts.size():
				tri[0] = pts[a]
				tri[1] = pts[b]
				tri[2] = pts[c]
				ci.draw_colored_polygon(tri, fill)
			i += 3
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	ci.draw_polyline(outline, BULLET_OUTLINE, BULLET_OUTLINE_W, true)
