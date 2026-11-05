class_name BagPhysicsBox
extends Control
## 弹药袋物理盒：袋内每发为带重力/碰撞的小球（Control 内自研圆盘物理，等价 RigidBody2D，利于嵌 UI / Web）。

signal ball_hover(ammo_id: int)
signal ball_hover_exit(ammo_id: int)
signal ball_press(ammo_id: int)
signal ball_long_press_tick(ammo_id: int)  ## 按下持续时由外部计时；本控件发 press/release

const GRAVITY := 1400.0
const DEFAULT_RADIUS := 12.0
const MIN_RADIUS := 8.0
const MAX_BALLS_SOFT := 64
const RESTITUTION := 0.28
const WALL_FRICTION := 0.82
const AIR_DRAG := 0.995
const SLEEP_SPEED := 12.0
const WALL_PAD := 5.0
const SPAWN_JITTER := 18.0

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
	var r: float = DEFAULT_RADIUS
	if n > MAX_BALLS_SOFT:
		r = maxf(MIN_RADIUS, DEFAULT_RADIUS * float(MAX_BALLS_SOFT) / float(n))
	for b in _balls:
		b["r"] = r


func _spawn_ball(ammo_id: int, temporary: bool = false, envy_copy: bool = false) -> void:
	var sz := size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = custom_minimum_size
	var r: float = DEFAULT_RADIUS
	var x: float = sz.x * 0.5 + randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	x = clampf(x, WALL_PAD + r, maxf(WALL_PAD + r, sz.x - WALL_PAD - r))
	var y: float = WALL_PAD + r + randf_range(0.0, 10.0)
	_balls.append({
		"id": ammo_id,
		"temp": temporary or envy_copy,
		"envy": envy_copy,
		"pos": Vector2(x, y),
		"vel": Vector2(randf_range(-40.0, 40.0), randf_range(0.0, 30.0)),
		"r": r,
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
	var left := WALL_PAD
	var right := sz.x - WALL_PAD
	var top := WALL_PAD
	var bottom := sz.y - WALL_PAD
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
			vel.y += GRAVITY * 0.12 * delta
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
			vel.y += GRAVITY * delta
			vel *= AIR_DRAG
		var pos: Vector2 = b["pos"]
		pos += vel * delta
		var r: float = float(b["r"])
		# walls
		if pos.x - r < left:
			pos.x = left + r
			vel.x = -vel.x * RESTITUTION
			vel.y *= WALL_FRICTION
		elif pos.x + r > right:
			pos.x = right - r
			vel.x = -vel.x * RESTITUTION
			vel.y *= WALL_FRICTION
		if pos.y - r < top:
			pos.y = top + r
			vel.y = absf(vel.y) * RESTITUTION
		elif pos.y + r > bottom:
			pos.y = bottom - r
			vel.y = -vel.y * RESTITUTION
			vel.x *= WALL_FRICTION
			if absf(vel.y) < SLEEP_SPEED and absf(vel.x) < SLEEP_SPEED:
				b["freeze"] = int(b["freeze"]) + 1
				if int(b["freeze"]) > 8:
					vel = Vector2.ZERO
					b["asleep"] = true
			else:
				b["freeze"] = 0
		else:
			b["freeze"] = 0
		b["pos"] = pos
		b["vel"] = vel
	# ball-ball (simple positional correction + bounce)
	# v0.4.29：按 x 排序扫掠（原生 PackedInt64Array.sort），x 距离超过两倍最大半径就停；两颗都睡着的跳过。
	var n: int = _balls.size()
	if any_awake:
		_dirty = true
	else:
		return
	var max_r: float = 0.0
	_order_keys.resize(n)
	for k in n:
		var bk: Dictionary = _balls[k]
		max_r = maxf(max_r, float(bk["r"]))
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
			var pa: Vector2 = a["pos"]
			var pc: Vector2 = c["pos"]
			var delta_p: Vector2 = pc - pa
			var dist_sq: float = delta_p.length_squared()
			var ra: float = float(a["r"])
			var rc: float = float(c["r"])
			var min_d: float = ra + rc
			if dist_sq <= 0.0001 or dist_sq >= min_d * min_d:
				continue
			var dist: float = sqrt(dist_sq)
			var nrm: Vector2 = delta_p / dist
			var overlap: float = min_d - dist
			var push: Vector2 = nrm * (overlap * 0.5)
			a["pos"] = pa - push
			c["pos"] = pc + push
			var va: Vector2 = a["vel"]
			var vc: Vector2 = c["vel"]
			var rel: float = (vc - va).dot(nrm)
			if rel < 0.0:
				var impulse: float = -(1.0 + RESTITUTION) * rel * 0.5
				a["vel"] = va - nrm * impulse
				c["vel"] = vc + nrm * impulse
			a["asleep"] = false
			c["asleep"] = false
			a["freeze"] = 0
			c["freeze"] = 0


func _draw() -> void:
	var _dt0: int = Time.get_ticks_usec()
	_draw_box()
	prof_draw_usec += Time.get_ticks_usec() - _dt0
	prof_draw_calls += 1


func _draw_box() -> void:
	var sz := size
	# box interior
	draw_rect(Rect2(Vector2.ZERO, sz), _bg_color, true)
	# wooden rim
	var t := WALL_PAD
	draw_rect(Rect2(0, sz.y - t, sz.x, t), _floor_color, true)
	draw_rect(Rect2(0, 0, t, sz.y), _wall_color, true)
	draw_rect(Rect2(sz.x - t, 0, t, sz.y), _wall_color, true)
	draw_rect(Rect2(0, 0, sz.x, t * 0.6), _wall_color, true)
	draw_rect(Rect2(Vector2.ZERO, sz), _rim_color, false, 2.0)
	# balls
	var tsec: float = Time.get_ticks_msec() * 0.001
	var font := get_theme_default_font()
	for b in _balls:
		var aid: int = int(b["id"])
		var pos: Vector2 = b["pos"]
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
		if tier != RarityFx.TIER_COMMON:
			RarityFx.draw_ball_back(self, pos, r, bg, tier, tsec, seedv)
		draw_circle(pos, r, bg)
		draw_arc(pos, r, 0.0, TAU, 24, Color(0.1, 0.1, 0.12, 0.75), 1.5, true)
		if tier != RarityFx.TIER_COMMON:
			RarityFx.draw_ball_front(self, pos, r, tier, tsec, seedv)
		# v0.3.8 临时罪孽寿命环：从 12 点顺时针缩短；≤25% 变红
		if is_temp_ball:
			var life: float = float(b.get("life", temp_full_life))
			var full: float = float(temp_full_life_by_id.get(aid, temp_full_life))
			var frac: float = clampf(life / maxf(full, 0.01), 0.0, 1.0)
			var ring_col: Color = Color(1.0, 0.3, 0.25, 0.95) if frac <= 0.25 else Color(1.0, 0.95, 0.8, 0.9)
			draw_arc(pos, r + 2.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, ring_col, 2.5, true)
		var glyph: String = st["glyph"]
		var fsize := int(maxi(9, int(r * 0.95)))
		if font != null:
			# draw_string 的 y 是基线：用 ascent 把单字框中心对齐球心（尺寸按 字+字号 缓存）
			var tkey: String = "%s|%d" % [glyph, fsize]
			var off = _text_off_cache.get(tkey)
			if off == null:
				var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
				off = Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(fsize))
				_text_off_cache[tkey] = off
			var text_pos: Vector2 = pos + (off as Vector2)
			if tier == RarityFx.TIER_EPIC:
				draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, RarityFx.epic_text_outline(tsec, seedv))
			elif tier == RarityFx.TIER_SIN:
				draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, RarityFx.sin_text_outline(tsec, seedv))
			draw_string(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
		# v0.4.30 嫉妒一次性复制：右上角绿菱
		if bool(b.get("envy", false)):
			var d: float = maxf(3.5, r * 0.35)
			var tip: Vector2 = pos + Vector2(r * 0.55, -r * 0.55)
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
			var empty := "（空盒）"
			var es := font2.get_string_size(empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var ea := font2.get_ascent(14)
			draw_string(
				font2,
				Vector2(sz.x * 0.5 - es.x * 0.5, sz.y * 0.5 - es.y * 0.5 + ea),
				empty, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.6, 0.5)
			)


func _ball_at_pointer(local_pos: Vector2 = Vector2.INF) -> Variant:
	var p := local_pos
	if p.x == INF:
		p = get_local_mouse_position()
	# 从上往下优先（后画的在上层，近似取最近）
	var best = null
	var best_d := INF
	for b in _balls:
		var d: float = p.distance_to(b["pos"])
		if d <= float(b["r"]) + 1.0 and d < best_d:
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
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover_ammo >= 0:
			ball_hover_exit.emit(_hover_ammo)
			_hover_ammo = -1
