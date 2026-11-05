extends Control
## 主菜单（竖屏）：rush!（唯一模式）/ 更新日志 / 清理缓存 / 退出；底部版本号。

const CHANGELOG_PATH := "res://data/changelog.json"

var _changelog_open := false


## v0.4.32/33 图鉴惯性滑动（方格上也能拖；轻点开详情）
var _codex_dragging: bool = false
var _codex_moved: bool = false
var _codex_last_y: float = 0.0
var _codex_vel: float = 0.0
var _codex_detail_ammo: int = -1
var _codex_press_ammo: int = -1
var _codex_press_pos := Vector2.ZERO
var _codex_press_ms: int = 0
const CODEX_TAP_MAX_PX := 14.0
const CODEX_TAP_MAX_MS := 450


func _ready() -> void:
	RrAa.apply_project_defaults()
	RrAa.apply_to_viewport(get_viewport())
	%VersionLabel.text = "v%s" % GameVersion.STRING
	_style_menu()
	_style_changelog_panel()
	_populate_changelog()
	_set_changelog_open(false)
	_style_codex_panel()
	_populate_codex()
	_set_codex_open(false)


func _style_menu() -> void:
	%BtnStart.custom_minimum_size = Vector2(420, 110)
	%BtnSandbox.custom_minimum_size = Vector2(420, 72)
	%BtnChangelog.custom_minimum_size = Vector2(420, 72)
	%BtnCodex.custom_minimum_size = Vector2(420, 72)
	%BtnClearCache.custom_minimum_size = Vector2(420, 64)
	%BtnQuit.custom_minimum_size = Vector2(420, 64)
	%TitleLabel.add_theme_font_size_override("font_size", 64)
	%Subtitle.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	%HintLabel.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	%VersionLabel.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))


func _style_changelog_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.55, 0.75, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	%ChangelogPanel.add_theme_stylebox_override("panel", style)


func _load_changelog_entries() -> Array:
	var text := FileAccess.get_file_as_string(CHANGELOG_PATH)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var entries: Variant = parsed.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return []
	return entries


func _populate_changelog() -> void:
	var list: VBoxContainer = %ChangelogList
	for c in list.get_children():
		c.queue_free()
	var entries := _load_changelog_entries()
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ver := str(entry.get("version", ""))
		var date := str(entry.get("date", ""))
		var items: Variant = entry.get("items", [])
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		if date.is_empty():
			title.text = "v%s" % ver
		else:
			title.text = "v%s  ·  %s" % [ver, date]
		block.add_child(title)
		if typeof(items) == TYPE_ARRAY:
			for it in items:
				var line := Label.new()
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.add_theme_font_size_override("font_size", 19)
				line.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
				line.text = "· %s" % str(it)
				block.add_child(line)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		block.add_child(spacer)
		list.add_child(block)


func _set_changelog_open(open: bool) -> void:
	_changelog_open = open
	%ChangelogDimmer.visible = open
	%ChangelogPanel.visible = open
	%BtnStart.disabled = open
	%BtnSandbox.disabled = open
	%BtnChangelog.disabled = open
	if has_node("%BtnCodex"):
		%BtnCodex.disabled = open
	%BtnClearCache.disabled = open
	%BtnQuit.disabled = open
	if open and has_node("%CodexPanel"):
		%CodexDimmer.visible = false
		%CodexPanel.visible = false


func _style_codex_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.92, 0.72, 0.35, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	%CodexPanel.add_theme_stylebox_override("panel", style)
	if has_node("%CodexDetailPanel"):
		var ds := style.duplicate() as StyleBoxFlat
		ds.bg_color = Color(0.09, 0.1, 0.14, 0.98)
		%CodexDetailPanel.add_theme_stylebox_override("panel", ds)
	_setup_codex_kinetic_scroll()


func _setup_codex_kinetic_scroll() -> void:
	## 触摸/鼠标拖拽 + 惯性。事件挂在 Scroll 与每个方格上（方格不再用 Button 吞触摸）。
	var scroll: ScrollContainer = %CodexScroll
	if scroll == null:
		return
	if not scroll.gui_input.is_connected(_on_codex_scroll_gui_input):
		scroll.gui_input.connect(_on_codex_scroll_gui_input)
	set_process(true)


func _codex_begin_press(ammo_id: int, local_pos: Vector2) -> void:
	_codex_dragging = true
	_codex_moved = false
	_codex_press_ammo = ammo_id
	_codex_press_pos = local_pos
	_codex_press_ms = Time.get_ticks_msec()
	_codex_vel = 0.0
	_codex_last_y = local_pos.y


func _codex_apply_drag(dy: float) -> void:
	var scroll: ScrollContainer = %CodexScroll
	if scroll == null:
		return
	_codex_dragging = true
	if absf(dy) >= 1.0:
		_codex_moved = true
	scroll.scroll_vertical = int(scroll.scroll_vertical - dy)
	_codex_vel = dy


func _codex_end_press() -> void:
	var ammo: int = _codex_press_ammo
	var moved: bool = _codex_moved
	var held_ms: int = Time.get_ticks_msec() - _codex_press_ms
	var dist: float = 0.0
	# dist already reflected in _codex_moved; keep threshold gate for safety
	_codex_dragging = false
	_codex_press_ammo = -1
	if ammo < 0:
		return
	if (not moved) and held_ms <= CODEX_TAP_MAX_MS:
		_on_codex_cell_pressed(ammo)


func _on_codex_scroll_gui_input(event: InputEvent) -> void:
	## 缝隙/空白处的拖拽（无 ammo）；仍走同一套惯性。
	if not %CodexPanel.visible:
		return
	_codex_handle_pointer_event(event, -1)


func _on_codex_cell_gui_input(event: InputEvent, ammo_id: int) -> void:
	if not %CodexPanel.visible:
		return
	_codex_handle_pointer_event(event, ammo_id)


func _codex_handle_pointer_event(event: InputEvent, ammo_id: int) -> void:
	var scroll: ScrollContainer = %CodexScroll
	if scroll == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_codex_begin_press(ammo_id, st.position)
		else:
			_codex_end_press()
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if absf(sd.position.distance_to(_codex_press_pos)) >= CODEX_TAP_MAX_PX:
			_codex_moved = true
		_codex_apply_drag(sd.relative.y)
		_codex_last_y = sd.position.y
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_vertical = int(scroll.scroll_vertical - 48)
			_codex_vel = 0.0
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_vertical = int(scroll.scroll_vertical + 48)
			_codex_vel = 0.0
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_codex_begin_press(ammo_id, mb.position)
			else:
				_codex_end_press()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _codex_dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if absf(mm.position.distance_to(_codex_press_pos)) >= CODEX_TAP_MAX_PX:
				_codex_moved = true
			_codex_apply_drag(mm.relative.y)
			_codex_last_y = mm.position.y
			accept_event()


func _process(delta: float) -> void:
	if not has_node("%CodexPanel") or not %CodexPanel.visible:
		return
	if _codex_dragging:
		return
	if absf(_codex_vel) < 0.4:
		_codex_vel = 0.0
		return
	var scroll: ScrollContainer = %CodexScroll
	if scroll == null:
		return
	scroll.scroll_vertical = int(scroll.scroll_vertical - _codex_vel)
	_codex_vel = lerpf(_codex_vel, 0.0, clampf(delta * 8.0, 0.0, 1.0))


func _populate_codex() -> void:
	## 方格网格：每格只显示弹球 + 名称 + 稀有度；点开看详情。
	var list: GridContainer = %CodexList
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	var view_w: float = size.x if size.x > 1.0 else 720.0
	var cols: int = 3 if view_w >= 520.0 else 2
	list.columns = cols
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 10)
	var cell: float = floorf((mini(view_w, 640.0) - 48.0 - float(cols - 1) * 10.0) / float(cols))
	cell = clampf(cell, 96.0, 150.0)
	var items: Array = DataRegistry.all_ammo()
	items = items.duplicate()
	items.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var aid: int = int(item.get("id", 0))
		if aid <= 0 or not DataRegistry.is_ammo_enabled(aid):
			continue
		list.add_child(_make_codex_cell(aid, item, cell))
	_codex_vel = 0.0
	if has_node("%CodexScroll"):
		%CodexScroll.scroll_vertical = 0


func _make_codex_cell(ammo_id: int, def: Dictionary, cell: float) -> Control:
	## v0.4.33：不用 Button（会吞触摸）；Panel 接 gui_input，拖=滚、点=详情。
	var card := PanelContainer.new()
	card.name = "CodexCell_%d" % ammo_id
	card.custom_minimum_size = Vector2(cell, cell)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.17, 0.22, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.5, 0.6, 0.85)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var chip := _codex_chip(ammo_id, mini(cell * 0.48, 64.0))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(chip)
	var nm := Label.new()
	nm.text = str(def.get("name", ammo_id))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var rarity: String = DataRegistry.get_ammo_rarity(ammo_id)
	var rl := Label.new()
	rl.text = ShopConstants.rarity_label(rarity)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 13)
	rl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rl)
	card.gui_input.connect(_on_codex_cell_gui_input.bind(ammo_id))
	return card


func _codex_chip(ammo_id: int, size_px: float = 48.0) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(size_px, size_px)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colors := _codex_ammo_color(ammo_id)
	var st := StyleBoxFlat.new()
	st.bg_color = colors.get("bg", Color(0.8, 0.8, 0.8))
	st.set_corner_radius_all(999)
	st.set_border_width_all(2)
	st.border_color = Color(0.12, 0.12, 0.14)
	chip.add_theme_stylebox_override("panel", st)
	var lb := Label.new()
	var nm := str(DataRegistry.get_ammo(ammo_id).get("name", "?"))
	var short := nm.replace("子弹", "").replace("弹药", "")
	lb.text = short.substr(0, 1) if not short.is_empty() else "?"
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", int(size_px * 0.42))
	lb.add_theme_color_override("font_color", colors.get("fg", Color(0.1, 0.1, 0.1)))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lb)
	RarityFx.attach(chip, ammo_id, st.bg_color, 999.0)
	return chip


func _codex_ammo_color(ammo_id: int) -> Dictionary:
	## 与战斗 UI 色板大致对齐（主菜单无 CombatUI，本地一份简表）。
	match ammo_id:
		1: return {"bg": Color(0.92, 0.92, 0.94), "fg": Color(0.08, 0.08, 0.1)}
		8: return {"bg": Color(0.95, 0.75, 0.15), "fg": Color(0.2, 0.12, 0.02)}
		16: return {"bg": Color(0.75, 0.12, 0.12), "fg": Color(1.0, 0.92, 0.9)}
		17: return {"bg": Color(0.55, 0.35, 0.85), "fg": Color(0.98, 0.95, 1.0)}
		18: return {"bg": Color(0.2, 0.65, 0.35), "fg": Color(0.95, 1.0, 0.95)}
		19: return {"bg": Color(0.42, 0.4, 0.38), "fg": Color(0.95, 0.93, 0.88)}
		20: return {"bg": Color(0.72, 0.88, 0.95, 0.85), "fg": Color(0.08, 0.18, 0.28)}
		22: return {"bg": Color(0.55, 0.78, 0.92), "fg": Color(0.04, 0.12, 0.2)}
		24: return {"bg": Color(0.35, 0.85, 0.75), "fg": Color(0.05, 0.2, 0.18)}
		25: return {"bg": Color(0.85, 0.35, 0.45), "fg": Color(1.0, 0.95, 0.95)}
		26: return {"bg": Color(1.0, 0.45, 0.15), "fg": Color(0.15, 0.05, 0.0)}
		27: return {"bg": Color(0.35, 0.32, 0.28), "fg": Color(0.95, 0.9, 0.75)}
		28: return {"bg": Color(0.95, 0.85, 0.35), "fg": Color(0.2, 0.15, 0.05)}
		29: return {"bg": Color(0.7, 0.85, 0.95), "fg": Color(0.1, 0.2, 0.3)}
		30: return {"bg": Color(0.55, 0.45, 0.85), "fg": Color(0.95, 0.95, 1.0)}
		31: return {"bg": Color(0.55, 0.5, 0.45), "fg": Color(0.95, 0.92, 0.88)}
		32: return {"bg": Color(0.65, 0.6, 0.55), "fg": Color(0.15, 0.12, 0.1)}
		33: return {"bg": Color(0.95, 0.9, 0.55), "fg": Color(0.25, 0.2, 0.05)}
		34: return {"bg": Color(0.85, 0.25, 0.55), "fg": Color(1.0, 0.94, 0.97)}
		35: return {"bg": Color(0.25, 0.7, 0.45), "fg": Color(0.94, 1.0, 0.96)}
		36: return {"bg": Color(0.75, 0.45, 0.15), "fg": Color(1.0, 0.96, 0.9)}
		37: return {"bg": Color(0.45, 0.55, 0.75), "fg": Color(0.94, 0.96, 1.0)}
	return {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}


func _set_codex_open(open: bool) -> void:
	%CodexDimmer.visible = open
	%CodexPanel.visible = open
	%BtnStart.disabled = open
	%BtnSandbox.disabled = open
	%BtnChangelog.disabled = open
	%BtnCodex.disabled = open
	%BtnClearCache.disabled = open
	%BtnQuit.disabled = open
	if open:
		_set_changelog_open(false)
	else:
		_set_codex_detail_open(false)
		_codex_vel = 0.0


func _on_codex_pressed() -> void:
	_populate_codex()
	_set_codex_open(true)


func _on_codex_close_pressed() -> void:
	_set_codex_open(false)


func _on_codex_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_codex_open(false)
	elif event is InputEventScreenTouch and event.pressed:
		_set_codex_open(false)


func _on_codex_cell_pressed(ammo_id: int) -> void:
	_show_codex_detail(ammo_id)


func _show_codex_detail(ammo_id: int) -> void:
	_codex_detail_ammo = ammo_id
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	var rarity: String = DataRegistry.get_ammo_rarity(ammo_id)
	var price: int = ShopConstants.price_for_rarity(rarity)
	%CodexDetailTitle.text = str(def.get("name", ammo_id))
	var body: VBoxContainer = %CodexDetailBody
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	var chip := _codex_chip(ammo_id, 72.0)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(chip)
	var meta := Label.new()
	meta.text = "%s · %d 金" % [ShopConstants.rarity_label(rarity), price]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 18)
	meta.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	body.add_child(meta)
	var detail := Label.new()
	detail.text = DataRegistry.format_ammo_detail_text(ammo_id)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	body.add_child(detail)
	_set_codex_detail_open(true)


func _set_codex_detail_open(open: bool) -> void:
	if has_node("%CodexDetailDimmer"):
		%CodexDetailDimmer.visible = open
	if has_node("%CodexDetailPanel"):
		%CodexDetailPanel.visible = open


func _on_codex_detail_close_pressed() -> void:
	_set_codex_detail_open(false)


func _on_codex_detail_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_codex_detail_open(false)
	elif event is InputEventScreenTouch and event.pressed:
		_set_codex_detail_open(false)


func _on_start_pressed() -> void:
	## rush!：直接进战斗（先选罪孽）。
	CombatState.boot_sandbox = false
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


func _on_sandbox_pressed() -> void:
	## 沙盒：进战斗后跳过罪孽三选，开沙盒面板。
	CombatState.boot_sandbox = true
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


func _on_changelog_pressed() -> void:
	_set_changelog_open(true)


func _on_changelog_close_pressed() -> void:
	_set_changelog_open(false)


func _on_changelog_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_changelog_open(false)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_clear_cache_pressed() -> void:
	## Web/Pages：清本站 cookie / storage / Cache Storage / SW / IndexedDB，再带 nocache 强制刷新。
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if (window.project001ClearSiteData) { window.project001ClearSiteData(); } else { " + _web_clear_cache_js() + " }",
			true
		)
		return
	# 桌面端没有 Pages 强缓存问题；给个轻提示
	%HintLabel.text = "清理缓存仅在网页版（GitHub Pages）生效。桌面版已是本地最新。"


func _web_clear_cache_js() -> String:
	## 整段在浏览器执行；不依赖额外 HTML（Pages 壳也会挂同名函数）。
	return """
(async function () {
  var log = function (m) { try { console.log('[revolver-rush clear]', m); } catch (e) {} };
  try {
    (document.cookie || '').split(';').forEach(function (c) {
      var n = c.trim().split('=')[0];
      if (!n) return;
      document.cookie = n + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
      document.cookie = n + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=' + location.hostname;
    });
    log('cookies');
  } catch (e) { log(e); }
  try { localStorage.clear(); log('localStorage'); } catch (e) {}
  try { sessionStorage.clear(); log('sessionStorage'); } catch (e) {}
  try {
    if (window.caches && caches.keys) {
      var keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      log('caches ' + keys.length);
    }
  } catch (e) {}
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      var regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map(function (r) { return r.unregister(); }));
      log('sw ' + regs.length);
    }
  } catch (e) {}
  try {
    if (window.indexedDB && indexedDB.databases) {
      var dbs = await indexedDB.databases();
      await Promise.all((dbs || []).map(function (db) {
        return new Promise(function (resolve) {
          if (!db || !db.name) { resolve(); return; }
          var req = indexedDB.deleteDatabase(db.name);
          req.onsuccess = req.onerror = req.onblocked = function () { resolve(); };
        });
      }));
      log('idb');
    }
  } catch (e) {}
  try {
    var u = new URL(location.href);
    u.searchParams.set('nocache', String(Date.now()));
    location.replace(u.toString());
  } catch (e) {
    location.reload();
  }
})();
"""


func get_title() -> String:
	return "Revolver Rush"
