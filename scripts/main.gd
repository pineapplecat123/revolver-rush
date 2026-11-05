extends Control
## 主菜单（竖屏）：rush!（唯一模式）/ 更新日志 / 清理缓存 / 退出；底部版本号。

const CHANGELOG_PATH := "res://data/changelog.json"

var _changelog_open := false


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
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	%CodexPanel.add_theme_stylebox_override("panel", style)


func _populate_codex() -> void:
	## 从 live ammo 数据生成：名称 / 稀有度（带特效）/ 售价 / 数值 / 效果。
	var list: VBoxContainer = %CodexList
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	var items: Array = DataRegistry.all_ammo()
	# 按 id 排序，只列实装（enabled）
	items = items.duplicate()
	items.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var aid: int = int(item.get("id", 0))
		if aid <= 0 or not DataRegistry.is_ammo_enabled(aid):
			continue
		list.add_child(_make_codex_row(aid, item))


func _make_codex_row(ammo_id: int, def: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "CodexRow_%d" % ammo_id
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.17, 0.22, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.4, 0.45, 0.55, 0.8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	# chip with rarity fx
	var chip := _codex_chip(ammo_id)
	h.add_child(chip)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	h.add_child(col)
	var rarity: String = DataRegistry.get_ammo_rarity(ammo_id)
	var price: int = ShopConstants.price_for_rarity(rarity)
	var title := Label.new()
	title.text = "%s · %s · %d 金" % [str(def.get("name", ammo_id)), ShopConstants.rarity_label(rarity), price]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var body := Label.new()
	body.text = DataRegistry.format_ammo_detail_text(ammo_id)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	col.add_child(body)
	# rarity overlay on the whole row card
	var cols := _codex_ammo_color(ammo_id)
	RarityFx.attach(row, ammo_id, cols.get("bg", Color(0.8, 0.8, 0.8)), 8.0)
	return row


func _codex_chip(ammo_id: int) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(48, 48)
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
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", colors.get("fg", Color(0.1, 0.1, 0.1)))
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


func _on_codex_pressed() -> void:
	_populate_codex()
	_set_codex_open(true)


func _on_codex_close_pressed() -> void:
	_set_codex_open(false)


func _on_codex_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_codex_open(false)


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
