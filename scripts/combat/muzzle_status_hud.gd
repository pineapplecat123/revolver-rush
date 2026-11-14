extends Control
## 枪口旁的状态图标、信息弹层、循环火焰，以及零伤害时的短喷火。

const ICON_SIZE := 28.0
const ICON_GAP := 4.0
const RING_WIDTH := 3.0
const MUZZLE_OFFSET := Vector2(16, -30)
const FONT := preload("res://assets/fonts/NotoSansSC-UI.ttf")

var state: CombatState
var muzzle_provider: Callable
var icon_host: Control = null  ## 放在「枪口：」后面；空则回退到本层（枪口旁）

var _icons: Array = []
var _popup: PanelContainer
var _popup_name: Label
var _popup_dur: Label
var _popup_eff: Label
var _open_id: String = ""
var _catcher: Control
var _flame: _Flame


func setup(cs: CombatState, provider: Callable) -> void:
	state = cs
	muzzle_provider = provider


func set_icon_host(host: Control) -> void:
	if icon_host == host:
		return
	icon_host = host
	for ic in _icons:
		if is_instance_valid(ic) and ic.get_parent() != host and host != null:
			ic.reparent(host)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80
	_build_popup()
	_flame = _Flame.new()
	_flame.name = "MuzzleFlame"
	_flame.z_index = 1
	add_child(_flame)
	set_process(true)


func play_puff(color: Color) -> void:
	var puff := _Puff.new()
	puff.color = color
	puff.z_index = 2
	add_child(puff)
	var pos := _muzzle_local()
	if pos != Vector2.ZERO:
		puff.position = pos + Vector2(6, 0)


func _muzzle_local() -> Vector2:
	if muzzle_provider.is_null():
		return Vector2.ZERO
	var g: Variant = muzzle_provider.call()
	if g is Vector2:
		var v: Vector2 = g
		if v != Vector2.ZERO:
			return get_global_transform_with_canvas().affine_inverse() * v
	return Vector2.ZERO


func _buffs() -> Array:
	if state == null:
		return []
	return state.volley_muzzle_buffs()


func _process(delta: float) -> void:
	var entries: Array = _buffs()
	_sync_icons(entries)
	var muzzle := _muzzle_local()
	var hosted := icon_host != null and is_instance_valid(icon_host)
	if not hosted:
		var origin := muzzle + MUZZLE_OFFSET if muzzle != Vector2.ZERO else Vector2(-9999, -9999)
		for i in _icons.size():
			var ic: Control = _icons[i]
			ic.position = origin + Vector2(float(i) * (ICON_SIZE + ICON_GAP), 0.0)
	if entries.is_empty():
		_flame.visible = false
		_hide_popup()
	else:
		_flame.visible = muzzle != Vector2.ZERO
		_flame.position = muzzle + Vector2(4, 0)
		_flame.color = _flame_color(entries)
		_flame.tick(delta)
	if _open_id != "":
		_place_popup()


func _flame_color(entries: Array) -> Color:
	if entries.is_empty():
		return Color(0.32, 0.78, 0.42)
	var latest: Color = entries[entries.size() - 1].get("color", Color(0.32, 0.78, 0.42))
	if entries.size() == 1:
		return latest
	var mix := Color(0, 0, 0, 1)
	for e in entries:
		mix += e.get("color", latest)
	mix /= float(entries.size())
	return latest.lerp(mix, 0.35)


func _sync_icons(entries: Array) -> void:
	var parent: Node = icon_host if icon_host != null and is_instance_valid(icon_host) else self
	while _icons.size() < entries.size():
		var ic := _Icon.new()
		ic.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		ic.size = Vector2(ICON_SIZE, ICON_SIZE)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		ic.gui_input.connect(_on_icon_input.bind(ic))
		parent.add_child(ic)
		_icons.append(ic)
	while _icons.size() > entries.size():
		var extra: Control = _icons.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
		if _open_id != "" and entries.filter(func(e): return str(e.get("id", "")) == _open_id).is_empty():
			_hide_popup()
	for i in entries.size():
		var ic: _Icon = _icons[i]
		ic.entry = entries[i]
		ic.queue_redraw()


func _on_icon_input(event: InputEvent, ic: _Icon) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_toggle_popup(ic)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_toggle_popup(ic)
			accept_event()


func _toggle_popup(ic: _Icon) -> void:
	var eid := str(ic.entry.get("id", ""))
	if _open_id == eid:
		_hide_popup()
		return
	_open_id = eid
	_popup_name.text = str(ic.entry.get("name", ic.entry.get("label", "")))
	_popup_dur.text = DataRegistry.format_muzzle_status_duration(ic.entry)
	_popup_eff.text = DataRegistry.format_muzzle_status_effect(ic.entry)
	_popup.visible = true
	_catcher.visible = true
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_place_popup()


func _place_popup() -> void:
	if not _popup.visible:
		return
	var target: Control = null
	for ic in _icons:
		if str((ic as _Icon).entry.get("id", "")) == _open_id:
			target = ic
			break
	if target == null:
		_hide_popup()
		return
	_popup.reset_size()
	var inv := get_global_transform_with_canvas().affine_inverse()
	var gr := target.get_global_rect()
	var top_left: Vector2 = inv * gr.position
	var bot_left: Vector2 = inv * Vector2(gr.position.x, gr.end.y)
	# 图标已在「枪口：」行时优先弹在上方，避免挡住转轮
	var pos := Vector2(top_left.x, top_left.y - _popup.size.y - 6.0)
	if pos.y < 8.0:
		pos.y = bot_left.y + 6.0
	var max_x: float = size.x - _popup.size.x - 8.0
	pos.x = clampf(pos.x, 8.0, maxf(max_x, 8.0))
	if pos.y + _popup.size.y > size.y - 8.0:
		pos.y = top_left.y - _popup.size.y - 6.0
	_popup.position = pos
	move_child(_catcher, get_child_count() - 2)
	move_child(_popup, get_child_count() - 1)


func _hide_popup() -> void:
	_open_id = ""
	if _popup != null:
		_popup.visible = false
	if _catcher != null:
		_catcher.visible = false
		_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_popup() -> void:
	_catcher = Control.new()
	_catcher.name = "PopupCatcher"
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.visible = false
	_catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_hide_popup()
			accept_event()
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_hide_popup()
			accept_event()
	)
	add_child(_catcher)
	_popup = PanelContainer.new()
	_popup.name = "BuffPopup"
	_popup.visible = false
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.z_index = 3
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.75, 0.8, 0.7, 0.7)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_popup.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_popup_name = _popup_label(16, Color(0.96, 0.97, 0.92), true)
	_popup_dur = _popup_label(13, Color(0.78, 0.82, 0.7), false)
	_popup_eff = _popup_label(14, Color(0.85, 1.0, 0.8), false)
	col.add_child(_popup_name)
	col.add_child(_popup_dur)
	col.add_child(_popup_eff)
	_popup.add_child(col)
	add_child(_popup)


func _popup_label(size_px: int, col: Color, bold: bool) -> Label:
	var lab := Label.new()
	lab.add_theme_font_override("font", FONT)
	lab.add_theme_font_size_override("font_size", size_px)
	lab.add_theme_color_override("font_color", col)
	if bold:
		lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		lab.add_theme_constant_override("shadow_offset_x", 1)
		lab.add_theme_constant_override("shadow_offset_y", 1)
	return lab


class _Icon extends Control:
	const FONT := preload("res://assets/fonts/NotoSansSC-UI.ttf")
	var entry: Dictionary = {}

	func _ready() -> void:
		custom_minimum_size = Vector2(28, 28)

	func _draw() -> void:
		var c: Color = entry.get("color", Color(0.32, 0.78, 0.42))
		var cx := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 1.5
		draw_circle(cx, r - 1.0, Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.92))
		draw_circle(cx, r - 4.0, Color(c.r * 0.35, c.g * 0.38, c.b * 0.32, 0.96))
		var label := str(entry.get("label", ""))
		var font: Font = FONT
		var fs := 11 if label.length() >= 2 else 13
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var fg := Color(0.07, 0.12, 0.07) if (c.r * 0.3 + c.g * 0.6 + c.b * 0.1) > 0.55 else Color(0.95, 0.98, 0.92)
		draw_string(font, cx - ts * 0.5 + Vector2(0, ts.y * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
		var rem: int = maxi(int(entry.get("remaining", 0)), 0)
		var total: int = maxi(int(entry.get("total", rem)), 1)
		var frac: float = clampf(float(rem) / float(total), 0.0, 1.0)
		if frac > 0.0:
			draw_arc(cx, r - 0.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, c.lightened(0.15), 3.0, true)
		draw_arc(cx, r - 0.5, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 1.0, true)


class _Flame extends Node2D:
	var color := Color(0.32, 0.78, 0.42)
	var _t := 0.0

	func tick(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var t := _t
		# 底部光晕，让火焰在棋盘上更容易看见
		var glow := color
		glow.a = 0.42 + sin(t * 10.0) * 0.08
		draw_circle(Vector2(0, -4), 14.0 + sin(t * 8.0) * 1.6, glow)
		var glow2 := color.lerp(Color(1, 0.85, 0.4), 0.35)
		glow2.a = 0.28
		draw_circle(Vector2(0, -10), 10.0, glow2)
		for i in 11:
			var u := float(i) / 10.0
			var wob := sin(t * 14.0 + float(i) * 0.9) * (3.2 + u * 2.4)
			var h := 10.0 + (1.0 - u) * 28.0 + sin(t * 18.0 + float(i) * 0.5) * 3.4
			var w := (1.0 - u) * 7.2 + 2.2
			var col := color.lerp(Color(1, 1, 0.85), 0.55 * (1.0 - u))
			col.a = 0.98 - u * 0.32
			var p := Vector2(wob, -h)
			draw_rect(Rect2(p.snapped(Vector2(1, 1)) - Vector2(w, w) * 0.5, Vector2(w, w).ceil()), col)


class _Puff extends Node2D:
	var color := Color(1.0, 0.72, 0.28)
	var _age := 0.0
	const LIFE := 0.32

	func _process(delta: float) -> void:
		_age += delta
		queue_redraw()
		if _age >= LIFE:
			queue_free()

	func _draw() -> void:
		var k := clampf(_age / LIFE, 0.0, 1.0)
		var grow := 1.0 + k * 2.1
		for i in 8:
			var u := float(i) / 7.0
			var ang := -0.45 + u * 0.9 + sin(_age * 20.0 + float(i)) * 0.08
			var dist := (10.0 + u * 14.0) * grow
			var p := Vector2.RIGHT.rotated(ang) * dist + Vector2(0, -u * 7.0 * grow)
			var col := color.lerp(Color(1, 0.95, 0.7), 0.4 * (1.0 - u))
			col.a = (1.0 - k) * (0.95 - u * 0.3)
			var s := (5.6 - u * 2.2) * (1.15 - k * 0.3)
			draw_rect(Rect2((p - Vector2(s, s) * 0.5).snapped(Vector2(1, 1)), Vector2(s, s).ceil()), col)
