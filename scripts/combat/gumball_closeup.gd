class_name GumballCloseup
extends Control
## 糖果机购买特写：放大整机，出球口和掉落区不被面板挡住。
## 摇出的球用与弹药袋相同的圆形外观和重力/碰撞/弹跳，从真实出球口落下。

signal use_pressed
signal leave_pressed

const REF := Vector2(720.0, 1280.0)
const MACHINE_SCALE := 2.55
const BALL_HEIGHT := 48.0  ## 与袋内默认高度一致
const GRAVITY := 2100.0  ## BagPhysicsBox.GRAVITY
const RESTITUTION := 0.28  ## BagPhysicsBox.RESTITUTION
const AIR_DRAG := 0.995
const WALL_FRICTION := 0.82
const SLEEP_SPEED := 12.0
const PHYS_SUBSTEPS := 4
const RELEASE_AGE := 0.95
const MIN_WATCH := 1.25  ## 出球后至少看这么久才允许继续
const TRAY_HALF_W := 210.0
const RAIL_H := 22.0

var machine: GumballMachine = null
var _title: Label = null
var _gold: Label = null
var _hint: Label = null
var _result: Label = null
var _use_btn: Button = null
var _leave_btn: Button = null
var _chrome: Control = null
var _actions: Control = null
var _ball_view: Control = null

var _dispensing: bool = false
var _anim_age: float = 0.0
var _ball_alive: bool = false
var _ball_pos: Vector2 = Vector2.ZERO
var _ball_vel: Vector2 = Vector2.ZERO
var _ball_asleep: bool = false
var _ball_freeze: int = 0
var _ball_id: int = 0
var _ball_fill: Color = Color(0.85, 0.85, 0.88)
var _ball_fg: Color = Color(0.1, 0.1, 0.1)
var _ball_glyph: String = ""
var _floor_hits: int = 0
var _bounce_count: int = 0
var _released_at: float = -1.0
var _released: bool = false

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
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
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
	var y: float = 1010.0 * _sy()
	return Rect2(40.0 * _sx(), y, _ref_size().x - 80.0 * _sx(), 70.0 * _sy())


func machine_foot() -> Vector2:
	return Vector2(_ref_size().x * 0.5, 650.0 * _sy())


func machine_scale() -> float:
	return MACHINE_SCALE * minf(_sx(), _sy())


func outlet_point() -> Vector2:
	## 特写坐标系下出球口中心。机器原点在左下角，脚点是底边中心。
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	return Vector2(foot.x, foot.y + GumballMachine.outlet_local().y * sc)


func floor_y() -> float:
	return 800.0 * _sy()


func drop_bounds() -> Rect2:
	## 出球口到托盘的掉落区（含左右护栏内侧）。
	var out: Vector2 = outlet_point()
	var fy: float = floor_y()
	var r: float = BagPhysicsBox.circle_radius_for_height(BALL_HEIGHT)
	var x0: float = _ref_size().x * 0.5 - TRAY_HALF_W * _sx()
	var w: float = TRAY_HALF_W * 2.0 * _sx()
	var y0: float = out.y - r
	var h: float = fy + r + 8.0 - y0
	return Rect2(x0, y0, w, h)


func machine_rect() -> Rect2:
	var foot: Vector2 = machine_foot()
	var sc: float = machine_scale()
	var w: float = GumballMachine.WIDTH * sc
	var h: float = GumballMachine.HEIGHT * sc
	return Rect2(foot.x - w * 0.5, foot.y - h, w, h)


func ui_block_rects() -> Array:
	## 标题栏和底部按钮（结果也写在标题栏里，不挡掉落区）。
	return [chrome_rect(), actions_rect()]


func is_outlet_unobstructed() -> bool:
	var p: Vector2 = outlet_point()
	var r: float = 18.0 * machine_scale() / MACHINE_SCALE
	var mouth := Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0)
	for b in ui_block_rects():
		if (b as Rect2).intersects(mouth):
			return false
	return drop_bounds().has_point(p) or drop_bounds().grow(12.0).has_point(p)


func is_drop_region_unobstructed() -> bool:
	var area: Rect2 = drop_bounds()
	for b in ui_block_rects():
		if (b as Rect2).intersects(area):
			return false
	return area.size.y >= 160.0 * _sy()


func _apply_layout() -> void:
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
		machine.scale = Vector2(sc, sc)
		# 机器原点在左下角
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
		machine.physics_drop = true
	queue_redraw()


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
		_use_btn.visible = use_visible
		_use_btn.disabled = not use_enabled
	if _leave_btn != null:
		_leave_btn.text = leave_text
		_leave_btn.disabled = not leave_enabled


func play_dispense(ammo_id: int, fill: Color, fg: Color = Color(0.1, 0.1, 0.1), glyph: String = "") -> void:
	_ensure_children()
	present()
	_dispensing = true
	_anim_age = 0.0
	_released = false
	_released_at = -1.0
	_clear_ball_state()
	_ball_id = ammo_id
	_ball_fill = fill
	_ball_fg = fg
	_ball_glyph = glyph
	if machine != null:
		machine.physics_drop = true
		machine.play_dispense(ammo_id, fill)
	queue_redraw()


func release_ball_now() -> void:
	## 测试/演示：跳过投币摇把，立刻从出球口放出物理球。
	_ensure_children()
	present()
	_dispensing = true
	_anim_age = RELEASE_AGE
	if machine != null:
		machine.physics_drop = true
		machine.tick_anim(0.0)
		machine._anim = "dispense"
		machine._anim_age = RELEASE_AGE
		machine.coin_t = 1.0
		machine.knob_t = 1.0
		machine.ball_t = 0.0
	_spawn_ball()


func tick(dt: float) -> void:
	if not visible:
		return
	_apply_layout()
	var step: float = maxf(0.0, dt)
	if machine != null and machine.visible:
		machine.tick_anim(step)
	if _dispensing:
		_anim_age += step
		if not _released and _anim_age >= RELEASE_AGE:
			_spawn_ball()
	if _ball_alive and not _ball_asleep:
		var sub: float = step / float(PHYS_SUBSTEPS)
		for _i in PHYS_SUBSTEPS:
			_physics_step(sub)
	queue_redraw()


func _spawn_ball() -> void:
	if _released and _ball_alive:
		return
	_apply_layout()
	var r: float = BagPhysicsBox.circle_radius_for_height(BALL_HEIGHT)
	var mouth: Vector2 = outlet_point()
	_ball_pos = Vector2(mouth.x, mouth.y + r + 1.0)
	# 轻微水平初速，避免完全垂直得像补间；测试里可用 0。
	_ball_vel = Vector2(0.0, 40.0)
	_ball_asleep = false
	_ball_freeze = 0
	_ball_alive = true
	_released = true
	_released_at = _anim_age
	_floor_hits = 0
	_bounce_count = 0
	queue_redraw()


func _physics_step(dt: float) -> void:
	if not _ball_alive or _ball_asleep:
		return
	var r: float = BagPhysicsBox.circle_radius_for_height(BALL_HEIGHT)
	var vel: Vector2 = _ball_vel
	vel += Vector2(0.0, GRAVITY) * dt
	vel *= AIR_DRAG
	var pos: Vector2 = _ball_pos + vel * dt
	var fy: float = floor_y()
	var tray_l: float = _ref_size().x * 0.5 - TRAY_HALF_W * _sx() + r
	var tray_r: float = _ref_size().x * 0.5 + TRAY_HALF_W * _sx() - r
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
	# 托盘底面
	if pos.y + r > fy:
		pos.y = fy - r
		if vel.y > 0.0:
			_floor_hits += 1
			var incoming: float = vel.y
			vel.y *= -RESTITUTION
			vel.x *= WALL_FRICTION
			if incoming >= 80.0 and vel.y < -8.0:
				_bounce_count += 1
			if absf(vel.y) < SLEEP_SPEED:
				vel.y = 0.0
	_ball_pos = pos
	_ball_vel = vel
	var settle: float = GRAVITY * dt + SLEEP_SPEED
	if absf(vel.x) < SLEEP_SPEED and absf(vel.y) < settle:
		_ball_freeze += 1
		if _ball_freeze > 8:
			_ball_vel = Vector2.ZERO
			_ball_asleep = true
	else:
		_ball_freeze = 0


func is_ball_active() -> bool:
	return _ball_alive


func is_drop_settled() -> bool:
	if not _released or not _ball_alive:
		return false
	if not _ball_asleep:
		return false
	if _released_at < 0.0:
		return false
	return (_anim_age - _released_at) >= MIN_WATCH


func can_collect() -> bool:
	return is_drop_settled()


func ball_pos() -> Vector2:
	return _ball_pos


func ball_vel() -> Vector2:
	return _ball_vel


func ball_ammo_id() -> int:
	return _ball_id


func ball_radius() -> float:
	return BagPhysicsBox.circle_radius_for_height(BALL_HEIGHT)


func floor_hit_count() -> int:
	return _floor_hits


func bounce_count() -> int:
	return _bounce_count


func has_contacted_floor() -> bool:
	return _floor_hits > 0


func _clear_ball_state() -> void:
	_ball_alive = false
	_ball_pos = Vector2.ZERO
	_ball_vel = Vector2.ZERO
	_ball_asleep = false
	_ball_freeze = 0
	_floor_hits = 0
	_bounce_count = 0
	_released = false
	_released_at = -1.0


func clear_drop() -> void:
	_dispensing = false
	_anim_age = 0.0
	_clear_ball_state()
	if machine != null:
		machine.reset_anim()
	queue_redraw()


func close() -> void:
	clear_drop()
	visible = false
	if machine != null:
		machine.set_prop_visible(false)
		machine.reset_anim()


func _on_ball_view_draw() -> void:
	if _ball_view == null or not _ball_alive:
		return
	BagPhysicsBox.stamp_bag_bullet(_ball_view, _ball_pos, BALL_HEIGHT, 0.0, _ball_fill)
	if _ball_glyph.is_empty():
		return
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var fsize: int = BagPhysicsBox.label_font_size_for_height(BALL_HEIGHT)
	var ts: Vector2 = font.get_string_size(_ball_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var text_pos := Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(fsize))
	_ball_view.draw_set_transform(_ball_pos, 0.0, Vector2.ONE)
	var oc := Color(0.08, 0.08, 0.1, 0.7) if _ball_fg.r + _ball_fg.g + _ball_fg.b > 1.6 else Color(1, 1, 1, 0.35)
	_ball_view.draw_string_outline(font, text_pos, _ball_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 2, oc)
	_ball_view.draw_string(font, text_pos, _ball_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, _ball_fg)
	_ball_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _draw() -> void:

	if not visible:
		return
	var sz: Vector2 = _ref_size()
	# 冷灰特写底，不挡出球口本身（机器和球画在上面）
	# 足够不透明的底，避免转轮和弹药袋透出来抢出球过程。
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.10, 0.12, 0.94))
	var stage := Rect2(20.0 * _sx(), chrome_rect().end.y + 4.0, sz.x - 40.0 * _sx(), actions_rect().position.y - chrome_rect().end.y - 12.0)
	draw_rect(stage, Color(0.10, 0.13, 0.16, 0.98))
	var foot: Vector2 = machine_foot()
	var fy: float = floor_y()
	var mid_x: float = sz.x * 0.5
	var stand_w: float = 70.0 * _sx()
	# 机座到托盘的立柱（画在球后面）
	var stand := PackedVector2Array([
		Vector2(mid_x - stand_w * 0.55, foot.y),
		Vector2(mid_x + stand_w * 0.55, foot.y),
		Vector2(mid_x + stand_w * 0.7, fy),
		Vector2(mid_x - stand_w * 0.7, fy),
	])
	draw_colored_polygon(stand, Color(0.34, 0.39, 0.44, 1.0))
	draw_polyline(PackedVector2Array(stand) + PackedVector2Array([stand[0]]), Color(0.22, 0.26, 0.30, 0.9), 1.6, true)
	# 托盘
	var tw: float = TRAY_HALF_W * _sx()
	var tray := Rect2(mid_x - tw, fy, tw * 2.0, 18.0 * _sy())
	draw_rect(tray, Color(0.40, 0.46, 0.51, 1.0))
	draw_rect(Rect2(tray.position.x, fy - 3.0, tray.size.x, 5.0), Color(0.52, 0.58, 0.62, 1.0))
	# 左右矮栏
	var rail_l := Rect2(tray.position.x - 6.0, fy - RAIL_H * _sy(), 8.0, RAIL_H * _sy() + 18.0 * _sy())
	var rail_r := Rect2(tray.end.x - 2.0, fy - RAIL_H * _sy(), 8.0, RAIL_H * _sy() + 18.0 * _sy())
	draw_rect(rail_l, Color(0.36, 0.41, 0.46, 1.0))
	draw_rect(rail_r, Color(0.36, 0.41, 0.46, 1.0))
