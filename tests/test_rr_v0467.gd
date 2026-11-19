extends GutTest
## v0.4.67：DPS/伤害修正放在转轮下方；修正名与枪口展示跟随图鉴当前名。


const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const HUIWEI := CombatConstants.HUIWEI_AMMO_ID
const CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func after_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_67() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.67") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.67" in log)
	assert_true("图鉴名" in log or "当前图鉴名" in log)


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


func _overlap(a: Control, b: Control) -> bool:
	if a == null or b == null:
		return false
	if not a.is_visible_in_tree() or not b.is_visible_in_tree():
		return false
	var inter := a.get_global_rect().intersection(b.get_global_rect())
	return inter.size.x > 1.0 and inter.size.y > 1.0


func test_current_registry_names_are_jia_shang_and_bei_shang() -> void:
	assert_eq(DataRegistry.ammo_display_name(QISHI), "加伤弹")
	assert_eq(DataRegistry.ammo_display_name(XULI), "倍伤弹")
	var q: Dictionary = DataRegistry.muzzle_status_of(QISHI)
	var x: Dictionary = DataRegistry.muzzle_status_of(XULI)
	assert_eq(str(q.get("id", "")), "qishi")
	assert_eq(str(x.get("id", "")), "xuli")
	assert_eq(DataRegistry.muzzle_buff_display_label(q), "加伤弹")
	assert_eq(DataRegistry.muzzle_buff_display_label(x), "倍伤弹")
	assert_eq(DataRegistry.format_muzzle_status_effect(q), "伤害+50%")
	assert_eq(DataRegistry.format_muzzle_status_effect(x), "下一发×1.5")


func test_modifier_text_uses_current_registry_names_not_legacy() -> void:
	var cs := CombatState.new(46701)
	cs.start_sandbox(46701)
	cs._volley_muzzle_buffs = [
		{"id": "qishi", "effect_kind": "damage_pct", "stacks": 1, "source_ammo_id": QISHI},
		{"id": "xuli", "effect_kind": "damage_mult", "stacks": 1, "source_ammo_id": XULI},
		{"id": "huiwei", "effect_kind": "damage_flat", "amount": 8, "source_ammo_id": HUIWEI},
	]
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, BAIBAN)
	var text: String = cs.sandbox_damage_modifiers_text()
	assert_true("加伤弹+50%" in text, text)
	assert_true("倍伤弹×1.5" in text, text)
	assert_true("回味弹+8" in text or "回味弹+" in text or "回味弹+8" in text, text)
	assert_false("起势" in text, text)
	assert_false("蓄力" in text, text)
	var bn: String = DataRegistry.ammo_display_name(BAIBAN)
	assert_true("「%s」" % bn in text, text)


func test_renamed_registry_name_propagates_to_modifiers_and_muzzle() -> void:
	var def_q: Dictionary = DataRegistry.get_ammo(QISHI)
	var def_x: Dictionary = DataRegistry.get_ammo(XULI)
	var old_q: String = str(def_q.get("name", ""))
	var old_x: String = str(def_x.get("name", ""))
	def_q["name"] = "测试改名弹"
	def_x["name"] = "试验倍伤名"
	assert_eq(DataRegistry.ammo_display_name(QISHI), "测试改名弹")
	assert_eq(DataRegistry.muzzle_buff_display_label(DataRegistry.muzzle_status_of(QISHI)), "测试改名弹")
	assert_eq(DataRegistry.muzzle_buff_display_label(DataRegistry.muzzle_status_of(XULI)), "试验倍伤名")
	var cs := CombatState.new(46702)
	cs.start_sandbox(46702)
	cs._volley_muzzle_buffs = [
		{"id": "qishi", "effect_kind": "damage_pct", "stacks": 1, "source_ammo_id": QISHI},
		{"id": "xuli", "effect_kind": "damage_mult", "stacks": 1, "source_ammo_id": XULI},
	]
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, BAIBAN)
	var text: String = cs.sandbox_damage_modifiers_text()
	assert_true("测试改名弹+50%" in text, text)
	assert_true("试验倍伤名×1.5" in text, text)
	assert_false("加伤弹" in text)
	assert_false("起势" in text)
	# 已挂状态也按稳定 id 现查图鉴名，不沿用挂上时写死的旧字。
	var baked: Dictionary = {"id": "qishi", "effect_kind": "damage_pct", "label": "起势", "name": "起势"}
	assert_eq(DataRegistry.muzzle_buff_display_label(baked), "测试改名弹")
	def_q["name"] = old_q
	def_x["name"] = old_x


func test_missing_ammo_entry_falls_back_to_unknown_id() -> void:
	var saved = DataRegistry._ammo_by_id.get(QISHI, {})
	DataRegistry._ammo_by_id.erase(QISHI)
	assert_eq(DataRegistry.ammo_display_name(QISHI), "未知#%d" % QISHI)
	var entry := {"id": "qishi", "effect_kind": "damage_pct", "source_ammo_id": QISHI}
	assert_eq(DataRegistry.muzzle_buff_display_label(entry), "未知#%d" % QISHI)
	var cs := CombatState.new(46703)
	cs.start_sandbox(46703)
	cs._volley_muzzle_buffs = [entry]
	var text: String = cs.sandbox_damage_modifiers_text()
	assert_true("未知#%d+" % QISHI in text, text)
	assert_false("起势" in text, text)
	if not saved.is_empty():
		DataRegistry._ammo_by_id[QISHI] = saved
	else:
		DataRegistry.reload()


func test_layout_under_wheel_at_portrait_sizes_with_long_wrap() -> void:
	var ui = await _boot_sandbox(true)
	ui.state._volley_muzzle_buffs = [
		{"id": "qishi", "effect_kind": "damage_pct", "stacks": 2, "source_ammo_id": QISHI},
		{"id": "xuli", "effect_kind": "damage_mult", "stacks": 2, "source_ammo_id": XULI},
		{"id": "huiwei", "effect_kind": "damage_flat", "amount": 12, "source_ammo_id": HUIWEI},
	]
	ui.state.magazine.clear()
	ui.state.magazine.start_index = 0
	ui.state.magazine.set_slot(0, BAIBAN)
	for avail in [Vector2(720, 1280), Vector2(390, 844)]:
		ui._fit_combat_viewport(avail)
		ui._update_sandbox_stats_hud()
		await wait_process_frames(3)
		var hud: Control = ui.find_child("SandboxStatsHud", true, false)
		assert_not_null(hud)
		var top := ui.get_node_or_null("Margin/RootVBox/TopPanel") as Control
		var mid := ui.get_node_or_null("Margin/RootVBox/MidPanel") as Control
		var bag: Control = ui.bag_panel
		var hand: Control = ui.hand_panel
		var wheel := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel") as Control
		var speed := ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/CombatSpeedRow") as Control
		var action := ui.get_node_or_null("%ActionRow") as Control
		var bottom := ui.get_node_or_null("Margin/RootVBox/BottomPanel") as Control
		assert_eq(hud.get_parent(), ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol"))
		assert_true(hud.visible, "portrait %s" % avail)
		assert_true("加伤弹" in str(ui._sb_stats_mod.text), str(ui._sb_stats_mod.text))
		assert_true("倍伤弹" in str(ui._sb_stats_mod.text))
		assert_gt(ui._sb_stats_mod.get_line_count(), 1, "窄列长修正应换行 %s" % avail)
		assert_false(_overlap(hud, top), "portrait %s 战斗区" % avail)
		assert_false(_overlap(hud, bag), "portrait %s 袋" % avail)
		assert_false(_overlap(hud, hand), "portrait %s 手" % avail)
		assert_false(_overlap(hud, wheel), "portrait %s 转轮" % avail)
		assert_false(_overlap(hud, speed), "portrait %s 速度条" % avail)
		assert_false(_overlap(hud, action), "portrait %s 操作键" % avail)
		assert_false(_overlap(hud, bottom), "portrait %s 不应再占用下方操作区" % avail)
		var inter := hud.get_global_rect().intersection(mid.get_global_rect())
		assert_gt(inter.size.x, 10.0)
		assert_gt(inter.size.y, 10.0)
		assert_gt(action.size.y, 200.0, "下方操作区应恢复（设计像素） %s  actual=%s" % [avail, action.size.y])
	CombatState.boot_sandbox = false
