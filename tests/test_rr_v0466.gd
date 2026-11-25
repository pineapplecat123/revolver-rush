extends GutTest
## v0.4.66：沙盒 DPS/伤害修正面板移到下方空白处，不再挡住战斗区。


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_66() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.66") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.66" in log)
	assert_true("不再挡住战斗区" in log)


func _boot_sandbox(close_console: bool = true):
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui._fit_combat_viewport(Vector2(720, 1280))
	await wait_process_frames(3)
	assert_true(ui.state.sandbox_mode)
	if close_console and ui.get("_dev_open") == true:
		ui._toggle_dev()
	ui._fit_combat_viewport(Vector2(720, 1280))
	ui._update_sandbox_stats_hud()
	await wait_process_frames(3)
	return ui


func _hud(ui) -> Control:
	var hud: Control = ui.find_child("SandboxStatsHud", true, false)
	assert_not_null(hud)
	return hud


func _overlap(a: Control, b: Control) -> bool:
	if a == null or b == null:
		return false
	if not a.is_visible_in_tree() or not b.is_visible_in_tree():
		return false
	var inter := a.get_global_rect().intersection(b.get_global_rect())
	return inter.size.x > 1.0 and inter.size.y > 1.0


func test_sandbox_dps_hud_sits_in_bottom_not_over_battle() -> void:
	## v0.4.67：统计条改到转轮下方左侧空位，不再占用下方操作区。
	var ui = await _boot_sandbox(true)
	var hud := _hud(ui)
	assert_true(hud.visible)
	var bottom := ui.get_node_or_null("Margin/RootVBox/BottomPanel") as Control
	var top := ui.get_node_or_null("Margin/RootVBox/TopPanel") as Control
	var mid := ui.get_node_or_null("Margin/RootVBox/MidPanel") as Control
	var bag: Control = ui.bag_panel
	var hand: Control = ui.hand_panel
	var mag := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol") as Control
	var wheel := ui.get_node_or_null("%MagWheel") as Control
	if wheel == null:
		wheel = ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel") as Control
	var speed := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/CombatSpeedRow") as Control
	var action := ui.get_node_or_null("%ActionRow") as Control
	assert_not_null(mag)
	assert_eq(hud.get_parent(), mag, "HUD 应放在转轮列下方")
	var hr := hud.get_global_rect()
	var midr := mid.get_global_rect()
	assert_true(midr.grow(2.0).encloses(hr) or midr.intersection(hr).size.y > 8.0,
		"HUD 应落在中段内，实际 HUD=%s mid=%s" % [hr, midr])
	assert_false(_overlap(hud, bottom), "不再占用下方操作区")
	assert_false(_overlap(hud, top), "不得挡住战斗区 TopPanel")
	assert_false(_overlap(hud, bag), "不得挡住弹药袋")
	assert_false(_overlap(hud, hand), "不得挡手区")
	assert_false(_overlap(hud, wheel), "不得挡住转轮本体")
	assert_false(_overlap(hud, speed), "不得挡住速度条")
	assert_false(_overlap(hud, action), "不得挡住倒出/装填/开火")
	if wheel != null:
		assert_gt(hr.position.y, wheel.get_global_rect().end.y - 2.0, "HUD 应在转轮之下")
	assert_gt(action.get_global_rect().size.y, 200.0, "下方操作键应恢复高度")
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var clear: Button = hud.find_child("StatsClear", true, false)
	assert_not_null(clear)
	assert_eq(clear.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(_overlap(hud, ui._sb_btn_manual_fire))
	assert_false(_overlap(hud, ui._sb_btn_auto_fire))
	CombatState.boot_sandbox = false


func test_sandbox_dps_hud_keeps_live_values_and_clear() -> void:
	var ui = await _boot_sandbox(true)
	var hud := _hud(ui)
	assert_eq(ui._sb_stats_main.text, ui.sandbox_stats_text()["main"])
	assert_eq(ui._sb_stats_sub.text, ui.sandbox_stats_text()["sub"])
	assert_eq(ui._sb_stats_mod.text, "伤害修正：无")
	assert_true(ui.state.enemies.size() >= 1)
	ui.state._notify_enemy_damage(ui.state.enemies[0], 12, "")
	ui._update_sandbox_stats_hud()
	await wait_process_frames(1)
	assert_true("单次最大 12" in str(ui._sb_stats_main.text))
	assert_true("总伤害 12" in str(ui._sb_stats_sub.text))
	assert_true("伤害修正" in str(ui._sb_stats_mod.text))
	var clear: Button = hud.find_child("StatsClear", true, false)
	clear.pressed.emit()
	await wait_process_frames(1)
	assert_eq(ui.state.dmg_stats_total, 0)
	assert_true("单次最大 0" in str(ui._sb_stats_main.text))
	CombatState.boot_sandbox = false


func test_long_modifier_wraps_inside_hud_without_covering_controls() -> void:
	var ui = await _boot_sandbox(true)
	var hud := _hud(ui)
	assert_eq(ui._sb_stats_mod.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	var qn := DataRegistry.ammo_display_name(CombatConstants.QISHI_AMMO_ID)
	var xn := DataRegistry.ammo_display_name(CombatConstants.XULI_AMMO_ID)
	var hn := DataRegistry.ammo_display_name(CombatConstants.HUIWEI_AMMO_ID)
	var cn := DataRegistry.ammo_display_name(CombatConstants.CHUANDI_AMMO_ID)
	var bn := DataRegistry.ammo_display_name(CombatConstants.BAIBAN_AMMO_ID)
	var long_mod := "伤害修正：%s+50%%（下一发「%s」）  %s×1.5（下一发「%s」）  %s+12（本弹夹剩余，含「%s」）  %s+8（下一发「%s」）  %s+50%%（下一发「%s」）" % [qn, bn, xn, bn, hn, bn, cn, bn, qn, xn]
	var font: Font = ui._sb_stats_mod.get_theme_font("font")
	var fs: int = ui._sb_stats_mod.get_theme_font_size("font_size")
	var text_w: float = ui._sb_stats_mod.size.x
	if text_w < 32.0:
		var magc := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol") as Control
		text_w = maxf(magc.size.x - 24.0, 160.0) if magc != null else 276.0
	assert_not_null(font)
	var one_h: float = font.get_string_size(long_mod, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).y
	var wrap_h: float = font.get_multiline_string_size(long_mod, HORIZONTAL_ALIGNMENT_LEFT, text_w, fs).y
	assert_gt(wrap_h, one_h, "长修正按面板宽度应换行（单行 %.1f 多行 %.1f 宽 %.1f）" % [one_h, wrap_h, text_w])
	# 用真实枪口状态让刷新后仍是长文案，再检查换行后的布局。
	ui.state._volley_muzzle_buffs = [
		{"effect_kind": "damage_pct", "stacks": 2},
		{"effect_kind": "damage_mult", "stacks": 2},
		{"effect_kind": "damage_flat", "amount": 12},
	]
	ui.state.magazine.clear()
	ui.state.magazine.start_index = 0
	ui.state.magazine.set_slot(0, CombatConstants.BAIBAN_AMMO_ID)
	ui._update_sandbox_stats_hud()
	await wait_process_frames(3)
	assert_true(qn + "×" in str(ui._sb_stats_mod.text))
	assert_true(xn in str(ui._sb_stats_mod.text))
	assert_true(hn in str(ui._sb_stats_mod.text))
	var action := ui.get_node_or_null("%ActionRow") as Control
	var top := ui.get_node_or_null("Margin/RootVBox/TopPanel") as Control
	var bag: Control = ui.bag_panel
	var hand: Control = ui.hand_panel
	var wheel := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel") as Control
	assert_true(hud.get_global_rect().grow(2.0).encloses(ui._sb_stats_mod.get_global_rect()))
	assert_false(_overlap(hud, top))
	assert_false(_overlap(hud, bag))
	assert_false(_overlap(hud, hand))
	assert_false(_overlap(hud, wheel))
	assert_false(_overlap(hud, action), "换行后仍不得盖住操作键")
	assert_gt(action.get_global_rect().size.y, 200.0)
	assert_true(hud.get_global_rect().end.y <= action.get_global_rect().position.y + 1.0)
	CombatState.boot_sandbox = false


func test_portrait_scale_keeps_hud_in_bottom() -> void:
	var ui = await _boot_sandbox(true)
	for avail in [Vector2(720, 1280), Vector2(390, 844)]:
		ui._fit_combat_viewport(avail)
		ui._update_sandbox_stats_hud()
		await wait_process_frames(3)
		var hud := _hud(ui)
		var top := ui.get_node_or_null("Margin/RootVBox/TopPanel") as Control
		var bag: Control = ui.bag_panel
		var hand: Control = ui.hand_panel
		var mag := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol") as Control
		var action := ui.get_node_or_null("%ActionRow") as Control
		var midp := ui.get_node_or_null("Margin/RootVBox/MidPanel") as Control
		var wheel := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel") as Control
		assert_true(hud.visible, "portrait %s" % avail)
		assert_false(_overlap(hud, top), "portrait %s 战斗区" % avail)
		assert_false(_overlap(hud, bag), "portrait %s 袋" % avail)
		assert_false(_overlap(hud, hand), "portrait %s 手" % avail)
		assert_false(_overlap(hud, wheel), "portrait %s 转轮" % avail)
		assert_false(_overlap(hud, action), "portrait %s 操作键" % avail)
		var inter := hud.get_global_rect().intersection(midp.get_global_rect())
		assert_gt(inter.size.x, 10.0)
		assert_gt(inter.size.y, 10.0)
	CombatState.boot_sandbox = false


func test_rush_hides_hud_and_keeps_bottom_layout() -> void:
	CombatState.boot_sandbox = false
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui._fit_combat_viewport(Vector2(720, 1280))
	await wait_process_frames(3)
	assert_false(ui.state.sandbox_mode)
	var hud: Control = ui.find_child("SandboxStatsHud", true, false)
	assert_true(hud == null or not hud.visible, "rush 不得显示沙盒 DPS 面板")
	var action := ui.get_node_or_null("%ActionRow") as Control
	assert_not_null(action)
	assert_gt(action.get_global_rect().size.y, 160.0, "rush 操作区不应被沙盒统计条挤矮")
	assert_true(ui.btn_fire.visible)
	assert_true(ui._sb_fire_split == null or not ui._sb_fire_split.visible)
	CombatState.boot_sandbox = false


func test_sandbox_console_open_hud_stays_in_bottom() -> void:
	var ui = await _boot_sandbox(false)
	if ui.get("_dev_open") != true:
		ui._toggle_dev()
	ui._update_sandbox_stats_hud()
	await wait_process_frames(3)
	var hud := _hud(ui)
	var top := ui.get_node_or_null("Margin/RootVBox/TopPanel") as Control
	var action := ui.get_node_or_null("%ActionRow") as Control
	assert_true(hud.visible)
	assert_eq(hud.get_parent(), ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol"), "打开控制台时统计条仍在转轮下方")
	assert_false(_overlap(hud, top), "打开控制台时也不要把统计条贴到战斗区")
	assert_false(_overlap(hud, action))
	CombatState.boot_sandbox = false
