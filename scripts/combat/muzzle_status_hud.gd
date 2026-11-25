extends Control
## 枪口旁的状态图标、信息弹层、循环火焰，以及零伤害时的短喷火。

const ICON_SIZE := 13.0
const ICON_GAP := 1.0
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
var _seen_flames: Dictionary = {}
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
	_sync_icons(layer_icon_entries(entries))
	var alive: Dictionary = {}
	for entry in entries:
		var uid := str(entry.get("uid", entry.get("id", "")))
		alive[uid] = true
		if not _seen_flames.has(uid):
			play_puff(entry.get("color", Color(1, 0.7, 0.2)))
	_seen_flames = alive
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
		_flame.layers = entries
		_flame.tick(delta)
	if _open_id != "":
		_place_popup()


static func layer_icon_entries(entries: Array) -> Array:
	# Every actual layer gets its own flame icon; groups are never collapsed ×N.
	var icons: Array = []
	for e in entries:
		for i in maxi(0, int(e.get("remaining", 0))):
			var icon: Dictionary = e.duplicate()
			icon["layer_index"] = i
			icons.append(icon)
	return icons


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
	_popup_name.text = DataRegistry.muzzle_buff_display_label(ic.entry)
	if _popup_name.text.strip_edges().is_empty():
		_popup_name.text = str(ic.entry.get("name", ic.entry.get("label", "")))
	_popup_dur.text = "【火焰层数】%d" % int(ic.entry.get("remaining", 0))
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
		custom_minimum_size = Vector2(13, 20)

	func _draw() -> void:
		var c: Color = entry.get("color", Color(0.32, 0.78, 0.42))
		var cx := size * 0.5
		var pts := PackedVector2Array([Vector2(-5, 6), Vector2(-6, 1), Vector2(-2, -4), Vector2(-1, 0), Vector2(2, -9), Vector2(6, 0), Vector2(5, 6), Vector2(0, 8)])
		for i in pts.size():
			pts[i] += cx
		draw_colored_polygon(pts, c)
		draw_circle(cx + Vector2(0, 4), 2.4, c.lightened(0.6))


class _Flame extends Node2D:
	var layers: Array = []
	var _t := 0.0

	func tick(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		# One batched CanvasItem, capped at eight visual shells (icons still exact).
		# Most recently created group is outermost; layer loss shrinks its shell.
		var count := mini(layers.size(), 8)
		for k in range(count - 1, -1, -1):
			var entry: Dictionary = layers[k]
			var c: Color = entry.get("color", Color(1, 0.7, 0.2))
			var ratio := clampf(float(entry.get("remaining", 1)) / maxf(1.0, float(entry.get("total", 1))), 0.0, 1.0)
			var scale := (0.48 + 0.52 * ratio) * (1.0 + float(k) * 0.24)
			for i in 7:
				var u := float(i) / 6.0
				var p := Vector2(8.0 + u * 46.0, sin(_t * 18.0 + float(i + k)) * (5.0 + u * 7.0) - u * 6.0) * scale
				var col := c.lightened((1.0 - u) * 0.38)
				col.a = 0.9 - u * 0.30
				var side := (13.0 - u * 9.0) * scale
				draw_rect(Rect2(p - Vector2.ONE * side * 0.5, Vector2.ONE * side), col)


class _Puff extends Node2D:
	var color := Color(1.0, 0.72, 0.28)
	var _age := 0.0
	const LIFE := 0.44

	func _process(delta: float) -> void:
		_age += delta
		queue_redraw()
		if _age >= LIFE:
			queue_free()

	func _draw() -> void:
		var k := clampf(_age / LIFE, 0.0, 1.0)
		var grow := 2.8 + k * 3.5
		for i in 8:
			var u := float(i) / 7.0
			var ang := -0.45 + u * 0.9 + sin(_age * 20.0 + float(i)) * 0.08
			var dist := (10.0 + u * 14.0) * grow
			var p := Vector2.RIGHT.rotated(ang) * dist + Vector2(0, -u * 7.0 * grow)
			var col := color.lerp(Color(1, 0.95, 0.7), 0.4 * (1.0 - u))
			col.a = (1.0 - k) * (0.95 - u * 0.3)
			var s := (12.0 - u * 4.0) * (1.15 - k * 0.3)
			draw_rect(Rect2((p - Vector2(s, s) * 0.5).snapped(Vector2(1, 1)), Vector2(s, s).ceil()), col)
