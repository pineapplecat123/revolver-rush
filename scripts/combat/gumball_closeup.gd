class_name GumballCloseup
extends Control
## 糖果机特写：罩内是与弹药袋相同的物理圆球；玩家下拉拉杆到头才扣费，
## 计量闸放行罩里已有的一发，经颈部/滑道/出球口落到托盘。奖励就是那一发。

signal lever_commit_requested
signal ball_dispensed(ammo_id: int)
signal leave_pressed
signal use_pressed  ## 保留但不用于购买；购买只能拉拉杆。

const REF := Vector2(720.0, 1280.0)
const MACHINE_SCALE := 2.55
const BALL_HEIGHT := 48.0
const GRAVITY := 2100.0
const RESTITUTION := 0.28
const TRAY_RESTITUTION := 0.62  # 出球口落到托盘时更明显的弹跳；不改罩内常数。
const AIR_DRAG := 0.995
const WALL_FRICTION := 0.82
const SLEEP_SPEED := 12.0
const PHYS_SUBSTEPS := 4
const MIN_WATCH := 1.05
const TRAY_HALF_W := 210.0
const RAIL_H := 22.0
const HOPPER_COUNT := 12
const COMMIT_PULL := 0.88
const LEVER_TRAVEL := 120.0
const GATE_CLEAR := 0.22
const METER_EXIT_SPEED := 120.0  # Physical throat brake, released once the whole ball clears the lip.

var machine: GumballMachine = null
var color_lookup: Callable = Callable()
var name_lookup: Callable = Callable()

var _title: Label = null
var _gold: Label = null
var _hint: Label = null
var _result: Label = null
var _use_btn: Button = null
var _leave_btn: Button = null
var _chrome: Control = null
var _actions: Control = null
var _ball_view: Control = null
var _hopper_ball_clip: Control = null
var _outlet_ball_clip: Control = null

var _session: bool = false
var _balls: Array = []  # {id, pos, vel, asleep, freeze, payload, in_tray, floor_hits, bounce, fill, fg, glyph}
var _pull: float = 0.0
var _pull_target: float = 0.0
var _dragging: bool = false
var _drag_index: int = -1
var _commit_ok: bool = false
var _commit_emitted: bool = false
var _commit_enabled: bool = false
var _gate_open: float = 0.0
var _gate_want: float = 0.0
var _pending_open: bool = false
var _agitating: bool = false
var _agitate_age: float = 0.0
var _payload_idx: int = -1
var _dispensed_id: int = 0
var _released_at: float = -1.0
var _anim_age: float = 0.0
var _layout_size: Vector2 = Vector2.ZERO
var _can_afford: bool = true
var _already_used: bool = false
var _frame_dt: float = 1.0 / 30.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_as_relative = false
	z_index = 92
	clip_contents = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_ensure_children()


func _ensure_children() -> void:
	if machine == null or not is_instance_valid(machine):
		machine = GumballMachine.new()
		machine.name = "CloseupMachine"
		machine.physics_drop = true
		machine.hide_interior_balls = true
		machine.hide_knob = true
		machine.hide_glass = true
		add_child(machine)
		machine.z_as_relative = true
		machine.z_index = 3
	if _ball_view == null or not is_instance_valid(_ball_view):
		_ball_view = Control.new()
		_ball_view.name = "DropBallView"
		_ball_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ball_view.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ball_view.offset_left = 0.0
		_ball_view.offset_top = 0.0
		_ball_view.offset_right = 0.0
		_ball_view.offset_bottom = 0.0
		_ball_view.z_as_relative = true
		_ball_view.z_index = 6
		_ball_view.draw.connect(_on_ball_view_draw)
		add_child(_ball_view)
	if _hopper_ball_clip == null:
		_hopper_ball_clip = _make_ball_clip("HopperBallClip")
		_outlet_ball_clip = _make_ball_clip("OutletBallClip")

	if _chrome == null or not is_instance_valid(_chrome):
		_chrome = Control.new()
		_chrome.name = "CloseupChrome"
		_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chrome.z_index = 8
		add_child(_chrome)
		_title = _make_label(22, Color(0.88, 0.91, 0.94), true)
		_chrome.add_child(_title)
		_gold = _make_label(18, Color(0.93, 0.82, 0.38), false)
		_chrome.add_child(_gold)
		_hint = _make_label(16, Color(0.78, 0.82, 0.86), false)
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_chrome.add_child(_hint)
		_result = _make_label(18, Color(0.86, 0.90, 0.93), false)
		_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_chrome.add_child(_result)
	if _actions == null or not is_instance_valid(_actions):
		_actions = HBoxContainer.new()
		_actions.name = "CloseupActions"
		_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		_actions.add_theme_constant_override("separation", 16)
		_actions.z_index = 8
		add_child(_actions)
		_use_btn = Button.new()
		_use_btn.visible = false
		_use_btn.custom_minimum_size = Vector2(200, 52)
		_use_btn.pressed.connect(func() -> void: use_pressed.emit())
		_actions.add_child(_use_btn)
		_leave_btn = Button.new()
		_leave_btn.custom_minimum_size = Vector2(180, 52)
		_leave_btn.pressed.connect(func() -> void: leave_pressed.emit())
		_actions.add_child(_leave_btn)
		UiStyle.apply_text_button(_use_btn)
		UiStyle.apply_text_button(_leave_btn)
	_apply_layout()


func _make_label(size_px: int, col: Color, bold: bool) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", size_px)
	lb.add_theme_color_override("font_color", col)
	if bold:
		lb.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.07, 0.7))
		lb.add_theme_constant_override("outline_size", 2)
	return lb


func _ref_size() -> Vector2:
	var sz: Vector2 = size
	if sz.x < 8.0 or sz.y < 8.0:
		return REF
	return sz


func _sx() -> float:
	return _ref_size().x / REF.x


func _sy() -> float:
	return _ref_size().y / REF.y


func chrome_rect() -> Rect2:
	return Rect2(16.0 * _sx(), 8.0 * _sy(), _ref_size().x - 32.0 * _sx(), 110.0 * _sy())


func actions_rect() -> Rect2:
	return Rect2(40.0 * _sx(), 1010.0 * _sy(), _ref_size().x - 80.0 * _sx(), 70.0 * _sy())


func machine_foot() -> Vector2:
	return Vector2(_ref_size().x * 0.5, 650.0 * _sy())


func machine_scale() -> float:
	return MACHINE_SCALE * minf(_sx(), _sy())


func outlet_point() -> Vector2:
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	return Vector2(foot.x, foot.y + GumballMachine.outlet_local().y * sc)


func floor_y() -> float:
	return 800.0 * _sy()


func globe_center() -> Vector2:
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	return Vector2(foot.x, foot.y + GumballMachine.globe_center_local().y * sc)


func globe_radius() -> float:
	return maxf(GumballMachine.GLOBE_R * machine_scale() - 8.0, ball_radius() * 4.0)


func ball_radius() -> float:
	return BagPhysicsBox.circle_radius_for_height(BALL_HEIGHT)


func neck_half() -> float:
	# 壁到壁约 2r+6，槽里只能过一发。
	return ball_radius() + 3.0 * minf(_sx(), _sy())


func neck_y() -> float:
	## 球心能进入颈部的高度：按内径 R-r 与槽半宽计算，避免玻璃开口在球够不到的地方。
	var c: Vector2 = globe_center()
	var R: float = globe_radius()
	var r: float = ball_radius()
	var h: float = neck_half()
	var inner: float = maxf(R - r, r)
	var half_c: float = maxf(h - r, 1.0)
	var dy: float = sqrt(maxf(inner * inner - half_c * half_c, 1.0))
	return c.y + dy


func gate_y() -> float:
	return neck_y() + ball_radius() * 2.15


func drop_bounds() -> Rect2:
	var out: Vector2 = outlet_point()
	var fy: float = floor_y()
	var r: float = ball_radius()
	var x0: float = _ref_size().x * 0.5 - TRAY_HALF_W * _sx()
	var w: float = TRAY_HALF_W * 2.0 * _sx()
	var y0: float = out.y - r
	return Rect2(x0, y0, w, fy + r + 8.0 - y0)


func machine_rect() -> Rect2:
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	var w: float = GumballMachine.WIDTH * sc
	var h: float = GumballMachine.HEIGHT * sc
	return Rect2(foot.x - w * 0.5, foot.y - h, w, h)


func ui_block_rects() -> Array:
	return [chrome_rect(), actions_rect()]


func is_outlet_unobstructed() -> bool:
	var p: Vector2 = outlet_point()
	var r: float = 18.0 * machine_scale() / MACHINE_SCALE
	var mouth := Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0)
	for b in ui_block_rects():
		if (b as Rect2).intersects(mouth):
			return false
	return drop_bounds().grow(12.0).has_point(p)


func is_drop_region_unobstructed() -> bool:
	var area: Rect2 = drop_bounds()
	for b in ui_block_rects():
		if (b as Rect2).intersects(area):
			return false
	return area.size.y >= 160.0 * _sy()


func lever_pivot() -> Vector2:
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	return Vector2(foot.x + 36.0 * sc, foot.y - 58.0 * sc)


func lever_rest_pos() -> Vector2:
	return lever_pivot() + Vector2(18.0 * _sx(), -36.0 * _sy())


func lever_pulled_pos() -> Vector2:
	return lever_pivot() + Vector2(22.0 * _sx(), LEVER_TRAVEL * _sy())


func lever_handle_pos() -> Vector2:
	return lever_rest_pos().lerp(lever_pulled_pos(), clampf(_pull, 0.0, 1.0))


func lever_grab_rect() -> Rect2:
	var a: Vector2 = lever_rest_pos()
	var b: Vector2 = lever_pulled_pos()
	var pad := 36.0 * minf(_sx(), _sy())
	var x0: float = minf(a.x, b.x) - pad
	var y0: float = minf(a.y, b.y) - pad
	var x1: float = maxf(a.x, b.x) + pad
	var y1: float = maxf(a.y, b.y) + pad
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func _apply_layout() -> void:
	var new_sz: Vector2 = _ref_size()
	if _layout_size.x > 8.0 and _session and not _balls.is_empty():
		if not new_sz.is_equal_approx(_layout_size):
			var sx: float = new_sz.x / _layout_size.x
			var sy: float = new_sz.y / _layout_size.y
			for b in _balls:
				b["pos"] = Vector2(float(b["pos"].x) * sx, float(b["pos"].y) * sy)
				b["vel"] = Vector2(float(b["vel"].x) * sx, float(b["vel"].y) * sy)
			if _dragging and not _commit_ok:
				_cancel_pull()
	_layout_size = new_sz
	if _chrome != null:
		var cr: Rect2 = chrome_rect()
		_chrome.position = cr.position
		_chrome.size = cr.size
		if _title != null:
			_title.position = Vector2(8, 0)
			_title.size = Vector2(cr.size.x - 16.0, 28.0)
		if _gold != null:
			_gold.position = Vector2(8, 28)
			_gold.size = Vector2(cr.size.x - 16.0, 22.0)
		if _hint != null:
			_hint.position = Vector2(8, 50)
			_hint.size = Vector2(cr.size.x - 16.0, 28.0)
		if _result != null:
			_result.position = Vector2(8, 78)
			_result.size = Vector2(cr.size.x - 16.0, 30.0)
	if _actions != null:
		var ar: Rect2 = actions_rect()
		_actions.position = ar.position
		_actions.size = ar.size
	if machine != null:
		var foot: Vector2 = machine_foot()
		var sc: float = machine_scale()
		machine.hide_interior_balls = true
		machine.hide_knob = true
		machine.hide_glass = true
		machine.physics_drop = true
		machine.scale = Vector2(sc, sc)
		machine.position = Vector2(foot.x - GumballMachine.WIDTH * 0.5 * sc, foot.y)
		machine.set_prop_visible(visible)
		machine.queue_redraw()
	if _ball_view != null:
		_ball_view.queue_redraw()
	queue_redraw()


func present() -> void:
	_ensure_children()
	visible = true
	_apply_layout()
	if machine != null:
		machine.set_prop_visible(true)
	queue_redraw()


func has_session() -> bool:
	return _session


func set_copy(title: String, gold_text: String, hint: String, result: String, use_text: String, use_visible: bool, use_enabled: bool, leave_text: String, leave_enabled: bool) -> void:
	_ensure_children()
	if _title != null:
		_title.text = title
	if _gold != null:
		_gold.text = gold_text
	if _hint != null:
		_hint.text = hint
	if _result != null:
		_result.text = result
	if _use_btn != null:
		_use_btn.text = use_text
		_use_btn.visible = false  # 购买只能拉拉杆
		_use_btn.disabled = true
	if _leave_btn != null:
		_leave_btn.text = leave_text
		_leave_btn.disabled = not leave_enabled
	# use_visible=还没用过；use_enabled=付得起。
	_already_used = not use_visible
	_can_afford = use_enabled and not _already_used
	_commit_enabled = _can_afford


func set_can_commit(can: bool, already_used: bool) -> void:
	_can_afford = can
	_already_used = already_used


func begin_session(rng: RandomNumberGenerator, count: int = HOPPER_COUNT) -> void:
	var ids: Array[int] = []
	var n: int = maxi(count, 1)
	for _i in n:
		ids.append(CampaignRules.roll_alley_ammo(rng))
	begin_session_with_ids(ids)


func begin_session_with_ids(ids: Array) -> void:
	_ensure_children()
	present()
	_clear_balls()
	_session = true
	_pull = 0.0
	_pull_target = 0.0
	_commit_ok = false
	_commit_emitted = false
	_gate_open = 0.0
	_gate_want = 0.0
	_pending_open = false
	_agitating = false
	_payload_idx = -1
	_dispensed_id = 0
	_released_at = -1.0
	_anim_age = 0.0
	_apply_layout()
	var c: Vector2 = globe_center()
	var R: float = globe_radius()
	var r: float = ball_radius()
	var i: int = 0
	for raw in ids:
		var aid: int = int(raw)
		var style: Dictionary = _style_for(aid)
		# 从罩子上半部落下，看得见挤堆。格子位置稳定，速度带一点随机。
		var ring: int = i / 5
		var slot: int = i % 5
		var ang: float = -PI * 0.55 + float(slot) * 0.42 + float(ring) * 0.11
		var rad: float = minf(R - r - 10.0, r * 0.4 + float(ring) * (r * 1.85))
		var pos := c + Vector2(cos(ang), sin(ang)) * rad
		pos.y = minf(pos.y, neck_y() - r - 4.0)
		_balls.append({
			"id": aid,
			"pos": pos,
			"vel": Vector2(float((i % 3) - 1) * 14.0, 28.0 + float(i) * 3.0),
			"asleep": false,
			"freeze": 0,
			"payload": false,
			"in_tray": false,
			"floor_hits": 0,
			"bounce": 0,
			"fill": style.get("bg", Color(0.85, 0.85, 0.88)),
			"fg": style.get("fg", Color(0.1, 0.1, 0.1)),
			"glyph": style.get("glyph", ""),
		})
		i += 1
	_wake_all()
	queue_redraw()


func _style_for(aid: int) -> Dictionary:
	var fill := Color(0.85, 0.85, 0.88)
	var fg := Color(0.1, 0.1, 0.1)
	if color_lookup.is_valid():
		var looked = color_lookup.call(aid)
		if typeof(looked) == TYPE_DICTIONARY:
			fill = looked.get("bg", fill)
			fg = looked.get("fg", fg)
	else:
		var cols: Dictionary = AmmoColors.colors_for(aid)
		fill = cols.get("bg", fill)
		fg = cols.get("fg", fg)
	var glyph := "?"
	if name_lookup.is_valid():
		glyph = str(name_lookup.call(aid))
	return {"bg": fill, "fg": fg, "glyph": glyph}


func _clear_balls() -> void:
	_balls.clear()
	_session = false
	_payload_idx = -1
	_dispensed_id = 0
	_released_at = -1.0
	_gate_open = 0.0
	_gate_want = 0.0
	_pending_open = false
	_agitating = false
	_commit_ok = false
	_commit_emitted = false
	_pull = 0.0
	_pull_target = 0.0
	_dragging = false
	_drag_index = -1


func tick(dt: float) -> void:
	if not visible:
		return
	_apply_layout()
	var step: float = maxf(0.0, dt)
	_anim_age += step
	if not _dragging and not _commit_ok:
		_pull = move_toward(_pull, 0.0, step * 3.6)
		_pull_target = _pull
	elif _commit_ok and not _dragging:
		_pull = move_toward(_pull, 0.0, step * 1.6)
	_gate_open = move_toward(_gate_open, _gate_want, step * 5.0)
	if _agitating:
		_agitate_age += step
		_do_agitate(step)
		if _pending_open and _chamber_index() >= 0:
			_start_gate_for_chamber()
	if _pending_open and not _agitating and _chamber_index() >= 0:
		_start_gate_for_chamber()
	if _payload_idx >= 0 and _payload_idx < _balls.size() and _gate_want > 0.5:
		var pb: Dictionary = _balls[_payload_idx]
		if not bool(pb.get("in_tray", false)) and float(pb["pos"].y) > gate_y() + ball_radius() * 2.0 + 8.0:
			_gate_want = 0.0
	if _session and not _balls.is_empty():
		_frame_dt = step
		var sub: float = step / float(PHYS_SUBSTEPS)
		for _s in PHYS_SUBSTEPS:
			_physics_world(sub)
		if not _agitating and _gate_open < 0.15:
			for b3 in _balls:
				if bool(b3.get("in_tray", false)) or bool(b3.get("payload", false)):
					continue
				var v3: Vector2 = b3["vel"]
				v3 *= 0.78
				if v3.length() < 90.0:
					v3 *= 0.45
				if v3.length() < 28.0:
					v3 = Vector2.ZERO
					b3["asleep"] = true
					b3["freeze"] = 9
				b3["vel"] = v3
		_check_dispense()
	if _ball_view != null:
		_ball_view.queue_redraw()
	queue_redraw()


func _do_agitate(dt: float) -> void:
	# 物理扰动，把一发挤进计量槽，不传送。
	var neck := Vector2(globe_center().x, neck_y() + ball_radius() * 0.5)
	for b in _balls:
		if bool(b.get("in_tray", false)) or bool(b.get("payload", false)):
			continue
		b["asleep"] = false
		b["freeze"] = 0
		var pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		var to: Vector2 = neck - pos
		if to.length() > 1.0:
			vel += to.normalized() * (160.0 * dt)
		vel += Vector2(sin(_agitate_age * 19.0 + pos.x * 0.05) * 420.0, 80.0) * dt
		b["vel"] = vel
	if _agitate_age > 2.8 and _chamber_index() < 0:
		# 继续搅，不强行生成。
		pass


func _start_gate_for_chamber() -> void:
	var idx: int = _chamber_index()
	if idx < 0:
		return
	_payload_idx = idx
	_balls[idx]["payload"] = true
	_balls[idx]["asleep"] = false
	_balls[idx]["vel"] = Vector2(_balls[idx]["vel"].x, maxf(float(_balls[idx]["vel"].y), 80.0))
	_gate_want = 1.0
	_pending_open = false
	_agitating = false
	_wake_all()


func _chamber_index() -> int:
	var mid: float = globe_center().x
	var h: float = neck_half()
	var y0: float = neck_y() - ball_radius() * 0.4
	var y1: float = gate_y() + ball_radius() * 0.4
	var best: int = -1
	var best_y: float = -INF
	for i in _balls.size():
		var b: Dictionary = _balls[i]
		if bool(b.get("in_tray", false)):
			continue
		var p: Vector2 = b["pos"]
		if absf(p.x - mid) <= h + 2.0 and p.y >= y0 and p.y <= y1:
			if p.y > best_y:
				best_y = p.y
				best = i
	return best


func _wake_all() -> void:
	for b in _balls:
		b["asleep"] = false
		b["freeze"] = 0


func _physics_world(dt: float) -> void:
	var r: float = ball_radius()
	var gvec := Vector2(0.0, GRAVITY)
	for b in _balls:
		if bool(b["asleep"]) and not _agitating and _gate_open < 0.05:
			continue
		var vel: Vector2 = b["vel"]
		vel += gvec * dt
		vel *= AIR_DRAG
		# The metering throat controls the existing payload's velocity, not its
		# visibility/position. Keep bag gravity/restitution during the free fall.
		if bool(b.get("payload", false)) and not bool(b.get("in_tray", false)) and _commit_ok:
			var py := float(b["pos"].y)
			if py >= gate_y() - r and py < outlet_reveal_y() + r:
				vel.y = minf(vel.y, METER_EXIT_SPEED)
		if not _agitating and _gate_open < 0.15:
			vel *= 0.96
		var pos: Vector2 = b["pos"] + vel * dt
		var hit: Dictionary = _resolve_walls(pos, vel, r, bool(b.get("in_tray", false)), bool(b.get("payload", false)))
		pos = hit["pos"]
		vel = hit["vel"]
		if bool(hit.get("floor", false)):
			b["floor_hits"] = int(b.get("floor_hits", 0)) + 1
			if bool(hit.get("bounce", false)):
				b["bounce"] = int(b.get("bounce", 0)) + 1
			b["in_tray"] = true
		b["pos"] = pos
		b["vel"] = vel
	# 球-球
	var n: int = _balls.size()
	var settle: float = GRAVITY * maxf(_frame_dt, dt) + SLEEP_SPEED
	for i in n:
		var a: Dictionary = _balls[i]
		for j in range(i + 1, n):
			var c: Dictionary = _balls[j]
			var off: Vector2 = c["pos"] - a["pos"]
			var dist: float = off.length()
			var min_d: float = r * 2.0
			if dist >= min_d or dist <= 0.00001:
				continue
			var nrm: Vector2 = off / dist
			var overlap: float = min_d - dist
			a["pos"] = a["pos"] - nrm * overlap * 0.5
			c["pos"] = c["pos"] + nrm * overlap * 0.5
			var va: Vector2 = a["vel"]
			var vc: Vector2 = c["vel"]
			var rel: float = (vc - va).dot(nrm)
			if rel < 0.0:
				var impulse: float = (1.0 + RESTITUTION) * rel * 0.5
				va += nrm * impulse
				vc -= nrm * impulse
			a["vel"] = va
			c["vel"] = vc
			# 只有明显的碰撞才叫醒，避免堆里微重叠永远睡不着
			if overlap > 1.25 or rel < -6.0:
				a["asleep"] = false
				c["asleep"] = false
				a["freeze"] = 0
				c["freeze"] = 0
	# 互挤后再贴墙，并入睡
	for b2 in _balls:
		var hit2: Dictionary = _resolve_walls(b2["pos"], b2["vel"], r, bool(b2.get("in_tray", false)), bool(b2.get("payload", false)))
		b2["pos"] = hit2["pos"]
		b2["vel"] = hit2["vel"]
		if bool(b2["asleep"]):
			continue
		var v2: Vector2 = b2["vel"]
		if absf(v2.x) < SLEEP_SPEED and absf(v2.y) < settle and _gate_open < 0.15 and not _agitating:
			b2["freeze"] = int(b2["freeze"]) + 1
			if int(b2["freeze"]) > 8:
				b2["vel"] = Vector2.ZERO
				b2["asleep"] = true
		else:
			b2["freeze"] = 0


func _resolve_walls(pos: Vector2, vel: Vector2, r: float, in_tray: bool, is_payload: bool) -> Dictionary:
	var c: Vector2 = globe_center()
	var R: float = globe_radius()
	var mid: float = c.x
	var h: float = neck_half()
	var ny: float = neck_y()
	var gy: float = gate_y()
	var out: Vector2 = outlet_point()
	var fy: float = floor_y()
	var floor_hit := false
	var bounced := false
	# 罩内圆壁（颈部开口以下走滑道）
	var in_neck_x: bool = absf(pos.x - mid) <= h + 1.0
	var below_neck: bool = pos.y > ny - 2.0
	if not (below_neck and in_neck_x) and not in_tray and pos.y < gy + r * 3.0:
		var off: Vector2 = pos - c
		var d: float = off.length()
		var maxd: float = R - r
		if d > maxd and d > 0.0001:
			var nrm: Vector2 = off / d
			pos = c + nrm * maxd
			var vn: float = vel.dot(nrm)
			if vn > 0.0:
				vel -= nrm * vn * (1.0 + RESTITUTION)
				vel *= WALL_FRICTION
	# 颈部 / 滑道侧壁：只约束已经进槽或已经离开圆罩的球，不要把罩里的一堆挤进细槽。
	var in_globe: bool = (pos - c).length() <= (R - r) + 4.0 and pos.y <= ny + r
	var shaft_top: float = ny - r * 0.2
	var shaft_bot: float = out.y + r * 1.2
	var in_shaft: bool = (not in_globe) or (pos.y >= ny - 2.0 and absf(pos.x - mid) <= h + 1.0)
	if in_shaft and pos.y >= shaft_top and pos.y <= shaft_bot + r * 2.0 and not in_tray:
		var left: float = mid - h
		var right: float = mid + h
		if pos.x - r < left:
			pos.x = left + r
			if vel.x < 0.0:
				vel.x *= -RESTITUTION
			vel.x *= WALL_FRICTION
		elif pos.x + r > right:
			pos.x = right - r
			if vel.x > 0.0:
				vel.x *= -RESTITUTION
			vel.x *= WALL_FRICTION
	# 计量闸：只有标记为 payload 且闸已开的那一发可以通过，其它球一律挡住。
	if pos.y + r > gy and pos.y < gy + r * 3.0 and absf(pos.x - mid) <= h + r:
		var allow: bool = is_payload and _gate_open > 0.2
		if not allow:
			pos.y = gy - r
			if vel.y > 0.0:
				vel.y *= -RESTITUTION
				vel.x *= WALL_FRICTION
				if absf(vel.y) < SLEEP_SPEED:
					vel.y = 0.0
	# 托盘
	if pos.y > out.y + r * 0.2 or in_tray:
		var tray_l: float = mid - TRAY_HALF_W * _sx() + r
		var tray_r: float = mid + TRAY_HALF_W * _sx() - r
		if pos.x < tray_l:
			pos.x = tray_l
			if vel.x < 0.0:
				vel.x *= -RESTITUTION
			vel.x *= WALL_FRICTION
		elif pos.x > tray_r:
			pos.x = tray_r
			if vel.x > 0.0:
				vel.x *= -RESTITUTION
			vel.x *= WALL_FRICTION
		if pos.y + r > fy:
			pos.y = fy - r
			floor_hit = true
			if vel.y > 0.0:
				var incoming: float = vel.y
				vel.y *= -TRAY_RESTITUTION
				vel.x *= WALL_FRICTION
				if incoming >= 40.0 and vel.y < -8.0:
					bounced = true
				if absf(vel.y) < SLEEP_SPEED:
					vel.y = 0.0
	return {"pos": pos, "vel": vel, "floor": floor_hit, "bounce": bounced}


func _check_dispense() -> void:
	if _dispensed_id != 0:
		return
	if _payload_idx < 0 or _payload_idx >= _balls.size():
		return
	var b: Dictionary = _balls[_payload_idx]
	if float(b["pos"].y) > outlet_point().y + ball_radius() * 0.3:
		b["in_tray"] = true
		_dispensed_id = int(b["id"])
		if _released_at < 0.0:
			_released_at = _anim_age
		ball_dispensed.emit(_dispensed_id)


func hopper_count() -> int:
	var n := 0
	for b in _balls:
		if not bool(b.get("in_tray", false)):
			n += 1
	return n


func tray_count() -> int:
	var n := 0
	for b in _balls:
		if bool(b.get("in_tray", false)):
			n += 1
	return n


func hopper_ids() -> Array:
	var out: Array = []
	for b in _balls:
		if not bool(b.get("in_tray", false)):
			out.append(int(b["id"]))
	return out


func tray_ids() -> Array:
	var out: Array = []
	for b in _balls:
		if bool(b.get("in_tray", false)):
			out.append(int(b["id"]))
	return out


func all_ball_ids() -> Array:
	var out: Array = []
	for b in _balls:
		out.append(int(b["id"]))
	return out


func ball_count() -> int:
	return _balls.size()


func is_hopper_settled() -> bool:
	if _balls.is_empty():
		return false
	if _agitating or _gate_open > 0.2:
		return false
	for b in _balls:
		if bool(b.get("in_tray", false)):
			continue
		var v: Vector2 = b["vel"]
		if v.length() > SLEEP_SPEED * 2.5:
			return false
	return true


func is_ball_active() -> bool:
	return tray_count() > 0 or (_payload_idx >= 0 and _gate_open > 0.05)


func is_drop_settled() -> bool:
	if _dispensed_id == 0:
		return false
	if tray_count() <= 0:
		return false
	var settled := false
	for b in _balls:
		if not bool(b.get("in_tray", false)):
			continue
		var v: Vector2 = b["vel"]
		if bool(b["asleep"]) or v.length() <= SLEEP_SPEED:
			settled = true
	if not settled:
		return false
	if _released_at < 0.0:
		return false
	return (_anim_age - _released_at) >= MIN_WATCH


func can_collect() -> bool:
	return is_drop_settled()


func ball_pos() -> Vector2:
	for b in _balls:
		if bool(b.get("payload", false)) or bool(b.get("in_tray", false)):
			return b["pos"]
	return Vector2.ZERO


func ball_vel() -> Vector2:
	for b in _balls:
		if bool(b.get("payload", false)) or bool(b.get("in_tray", false)):
			return b["vel"]
	return Vector2.ZERO


func ball_ammo_id() -> int:
	return _dispensed_id


func bounce_count() -> int:
	var n := 0
	for b in _balls:
		n = maxi(n, int(b.get("bounce", 0)))
	return n


func has_contacted_floor() -> bool:
	for b in _balls:
		if int(b.get("floor_hits", 0)) > 0:
			return true
	return false


func lever_pull() -> float:
	return _pull


func gate_open_amount() -> float:
	return _gate_open


func is_commit_accepted() -> bool:
	return _commit_ok


func accept_commit() -> void:
	_commit_ok = true
	_already_used = true
	_can_afford = false
	_pending_open = true
	if _chamber_index() >= 0:
		_start_gate_for_chamber()
	else:
		_agitating = true
		_agitate_age = 0.0
		_wake_all()


func reject_commit() -> void:
	_commit_ok = false
	_commit_emitted = false
	_pull_target = 0.0
	_cancel_pull()


func _cancel_pull() -> void:
	_dragging = false
	_drag_index = -1
	_pull_target = 0.0


func _gui_input(event: InputEvent) -> void:
	_handle_pointer(event)


func _input(event: InputEvent) -> void:
	if _dragging:
		_handle_pointer(event)


func handle_pointer(event: InputEvent) -> void:
	_handle_pointer(event)


func _pointer_index(event: InputEvent) -> int:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).index
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).index
	return 0


func _pointer_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return (event as InputEventMouse).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	return Vector2.INF


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _is_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return false


func _is_drag(event: InputEvent) -> bool:
	return event is InputEventMouseMotion or event is InputEventScreenDrag


func _handle_pointer(event: InputEvent) -> void:
	if not visible or not _session:
		return
	# 把事件坐标转到本控件
	var ev_pos: Vector2 = _pointer_pos(event)
	if ev_pos.x < -100000.0:
		return
	# Mouse events in _gui_input are local; _input may be viewport. Normalize.
	if event is InputEventMouse and not (event is InputEventMouseButton and get_global_rect().has_point((event as InputEventMouse).global_position) or _dragging):
		pass
	var local := ev_pos
	if event is InputEventMouse:
		var gm: Vector2 = (event as InputEventMouse).global_position
		if is_inside_tree():
			local = get_global_transform().affine_inverse() * gm
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		if is_inside_tree():
			local = get_global_transform().affine_inverse() * ev_pos
	var idx: int = _pointer_index(event)
	if _is_press(event):
		if _dragging:
			return  # 忽略第二根手指
		if _already_used or _commit_ok:
			return
		if lever_grab_rect().grow(10.0).has_point(local):
			_dragging = true
			_drag_index = idx
			_update_pull_from(local)
	elif _is_drag(event) and _dragging and idx == _drag_index:
		_update_pull_from(local)
		_maybe_request_commit()
	elif _is_release(event) and _dragging and idx == _drag_index:
		# 在控件外松开时沿用最后一次拖动进度，避免把远处的点投影成拉满。
		_maybe_request_commit()
		_dragging = false
		_drag_index = -1
		if not _commit_ok:
			_pull_target = 0.0


func _maybe_request_commit() -> void:
	if _commit_emitted or _commit_ok or _already_used:
		return
	if not _can_afford:
		return
	if _pull < COMMIT_PULL:
		return
	_commit_emitted = true
	lever_commit_requested.emit()


func _update_pull_from(local: Vector2) -> void:
	var a: Vector2 = lever_rest_pos()
	var b: Vector2 = lever_pulled_pos()
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 <= 0.0001:
		return
	var t: float = clampf((local - a).dot(ab) / len2, 0.0, 1.0)
	_pull = t
	_pull_target = t


func simulate_pointer_down(local: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local
	ev.global_position = local if not is_inside_tree() else get_global_transform() * local
	_handle_pointer(ev)


func simulate_pointer_move(local: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = local
	ev.global_position = local if not is_inside_tree() else get_global_transform() * local
	_handle_pointer(ev)


func simulate_pointer_up(local: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = local
	ev.global_position = local if not is_inside_tree() else get_global_transform() * local
	_handle_pointer(ev)


func simulate_full_stroke() -> void:
	## 走同一套指针逻辑：从拉杆顶部拖到底。
	var a: Vector2 = lever_rest_pos()
	var b: Vector2 = lever_pulled_pos()
	simulate_pointer_down(a)
	var steps := 10
	for i in steps:
		var t: float = float(i + 1) / float(steps)
		simulate_pointer_move(a.lerp(b, t))
	simulate_pointer_up(b)


func simulate_partial_stroke(amount: float = 0.5) -> void:
	var a: Vector2 = lever_rest_pos()
	var b: Vector2 = lever_rest_pos().lerp(lever_pulled_pos(), clampf(amount, 0.0, 0.8))
	simulate_pointer_down(a)
	var steps := 6
	for i in steps:
		var t: float = float(i + 1) / float(steps)
		simulate_pointer_move(a.lerp(b, t))
	simulate_pointer_up(b)


func apply_simulated_resize(new_sz: Vector2) -> void:
	## 测试用：在不和 Full Rect 锚点打架的情况下，模拟窗口缩放。
	var old: Vector2 = _layout_size
	if old.x > 8.0 and _session and not _balls.is_empty() and not new_sz.is_equal_approx(old):
		var sx: float = new_sz.x / old.x
		var sy: float = new_sz.y / old.y
		for b in _balls:
			b["pos"] = Vector2(float(b["pos"].x) * sx, float(b["pos"].y) * sy)
			b["vel"] = Vector2(float(b["vel"].x) * sx, float(b["vel"].y) * sy)
		if _dragging and not _commit_ok:
			_cancel_pull()
	_layout_size = new_sz
	_apply_layout()


func close() -> void:
	_cancel_pull()
	_clear_balls()
	visible = false
	if machine != null:
		machine.set_prop_visible(false)
		machine.reset_anim()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()
	elif what == NOTIFICATION_EXIT_TREE:
		_cancel_pull()
		_clear_balls()


func casing_top_y() -> float:
	return machine_foot().y - 78.0 * machine_scale()


func outlet_reveal_y() -> float:
	# Fixed spatial aperture, NOT a per-body visible switch. The same circle and
	# glyph are progressively clipped as they enter/leave the opaque front casing.
	return machine_foot().y - 42.0 * machine_scale()


func _make_ball_clip(node_name: String) -> Control:
	var ci := Control.new()
	ci.name = node_name
	ci.clip_contents = true
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ci.show_behind_parent = true
	ci.draw.connect(_draw_clipped_balls.bind(ci))
	_ball_view.add_child(ci)
	return ci


func _draw_clipped_balls(ci: Control) -> void:
	# 球（正常种类色，不加袋内深灰遮罩）
	var font: Font = get_theme_default_font()
	for b in _balls:
		var pos: Vector2 = b["pos"] - ci.position
		var fill: Color = b.get("fill", Color(0.85, 0.85, 0.88))
		BagPhysicsBox.stamp_bag_bullet(ci, pos, BALL_HEIGHT, 0.0, fill)
		var glyph: String = str(b.get("glyph", ""))
		if glyph.is_empty() or font == null:
			continue
		var fg: Color = b.get("fg", Color(0.1, 0.1, 0.1))
		var fsize: int = BagPhysicsBox.label_font_size_for_height(BALL_HEIGHT)
		var ts: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var text_pos := Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(fsize))
		ci.draw_set_transform(pos, 0.0, Vector2.ONE)
		var oc := Color(0.08, 0.08, 0.1, 0.7) if fg.r + fg.g + fg.b > 1.6 else Color(1, 1, 1, 0.35)
		ci.draw_string_outline(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 2, oc)
		ci.draw_string(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_ball_view_draw() -> void:
	if _ball_view == null or not visible:
		return
	_hopper_ball_clip.position = Vector2.ZERO
	_hopper_ball_clip.size = Vector2(_ref_size().x, casing_top_y())
	_outlet_ball_clip.position = Vector2(0, outlet_reveal_y())
	_outlet_ball_clip.size = Vector2(_ref_size().x, maxf(0, _ref_size().y - outlet_reveal_y()))
	_hopper_ball_clip.queue_redraw()
	_outlet_ball_clip.queue_redraw()
	# 玻璃罩画在球上面，半透明，能看见里面在滚
	var gc: Vector2 = globe_center()
	var gR: float = globe_radius() + 8.0
	_ball_view.draw_arc(gc, gR, 0.0, TAU, 48, Color(0.70, 0.78, 0.84, 0.9), 3.0, true)
	_ball_view.draw_arc(gc, gR * 0.82, -2.4, -1.15, 12, Color(0.85, 0.90, 0.93, 0.28), 2.2, true)
	# 穹顶盖
	var cap_pts := PackedVector2Array()
	var cap_n := 14
	var cap_h: float = GumballMachine.CAP_H * machine_scale()
	for i in cap_n:
		var a: float = PI + PI * float(i) / float(cap_n - 1)
		cap_pts.append(gc + Vector2(cos(a) * (gR + 2.0), sin(a) * (gR + 2.0)) + Vector2(0.0, -2.0))
	var cap_top: Vector2 = gc + Vector2(0.0, -gR - cap_h)
	cap_pts.insert(cap_n / 2, cap_top)
	if cap_pts.size() >= 3:
		_ball_view.draw_colored_polygon(cap_pts, Color(0.55, 0.61, 0.66, 1.0))
	_ball_view.draw_circle(cap_top + Vector2(0.0, 6.0), 8.0 * machine_scale() / MACHINE_SCALE, Color(0.38, 0.52, 0.56, 1.0))
	# 拉杆
	_draw_lever(_ball_view)


func _draw_lever(ci: Control) -> void:
	var pivot: Vector2 = lever_pivot()
	var handle: Vector2 = lever_handle_pos()
	var track_a: Vector2 = lever_rest_pos()
	var track_b: Vector2 = lever_pulled_pos()
	ci.draw_line(track_a, track_b, Color(0.22, 0.26, 0.30, 0.7), 8.0, true)
	ci.draw_line(pivot, handle, Color(0.32, 0.38, 0.42, 1.0), 7.0, true)
	var col := Color(0.70, 0.76, 0.80, 1.0)
	if _dragging:
		col = Color(0.86, 0.90, 0.84, 1.0)
	elif not _already_used and _can_afford:
		col = Color(0.78, 0.84, 0.72, 1.0)
	elif _already_used:
		col = Color(0.45, 0.48, 0.50, 1.0)
	ci.draw_circle(handle, 16.0 * minf(_sx(), _sy()), col)
	ci.draw_arc(handle, 16.0 * minf(_sx(), _sy()), 0.0, TAU, 20, Color(0.18, 0.20, 0.22, 0.9), 2.0, true)
	# 方向提示
	if not _already_used and not _commit_ok and _pull < 0.15:
		var tip: Vector2 = handle + Vector2(0.0, 28.0 * _sy())
		ci.draw_colored_polygon(PackedVector2Array([
			tip + Vector2(-8, -10), tip + Vector2(8, -10), tip + Vector2(0, 8)
		]), Color(0.86, 0.90, 0.72, 0.9))


func _draw() -> void:
	if not visible:
		return
	var sz: Vector2 = _ref_size()
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.10, 0.12, 0.94))
	var stage := Rect2(20.0 * _sx(), chrome_rect().end.y + 4.0, sz.x - 40.0 * _sx(), actions_rect().position.y - chrome_rect().end.y - 12.0)
	draw_rect(stage, Color(0.10, 0.13, 0.16, 0.98))
	var foot: Vector2 = machine_foot()
	var fy: float = floor_y()
	var mid_x: float = sz.x * 0.5
	var stand_w: float = 70.0 * _sx()
	var stand := PackedVector2Array([
		Vector2(mid_x - stand_w * 0.55, foot.y),
		Vector2(mid_x + stand_w * 0.55, foot.y),
		Vector2(mid_x + stand_w * 0.7, fy),
		Vector2(mid_x - stand_w * 0.7, fy),
	])
	draw_colored_polygon(stand, Color(0.34, 0.39, 0.44, 1.0))
	draw_polyline(PackedVector2Array(stand) + PackedVector2Array([stand[0]]), Color(0.22, 0.26, 0.30, 0.9), 1.6, true)
	var tw: float = TRAY_HALF_W * _sx()
	var tray := Rect2(mid_x - tw, fy, tw * 2.0, 18.0 * _sy())
	draw_rect(tray, Color(0.40, 0.46, 0.51, 1.0))
	draw_rect(Rect2(tray.position.x, fy - 3.0, tray.size.x, 5.0), Color(0.52, 0.58, 0.62, 1.0))
	var rail_l := Rect2(tray.position.x - 6.0, fy - RAIL_H * _sy(), 8.0, RAIL_H * _sy() + 18.0 * _sy())
	var rail_r := Rect2(tray.end.x - 2.0, fy - RAIL_H * _sy(), 8.0, RAIL_H * _sy() + 18.0 * _sy())
	draw_rect(rail_l, Color(0.36, 0.41, 0.46, 1.0))
	draw_rect(rail_r, Color(0.36, 0.41, 0.46, 1.0))
