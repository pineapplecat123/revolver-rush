extends GutTest
## v0.4.61：沙盒保存/还原袋中配置；手动/自动开火分键；实时伤害修正。


const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const HUIWEI := CombatConstants.HUIWEI_AMMO_ID
const CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const EMPTY := Magazine.EMPTY
const FIRE_ONCE := CombatConstants.FIRE_ONCE_TEMP
const PRESET_PATH := "user://sandbox_bag_preset_test_0461.json"


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.sandbox_bag_preset_path = PRESET_PATH
	_wipe_preset()


func after_each() -> void:
	_wipe_preset()
	CombatState.sandbox_bag_preset_path = "user://sandbox_bag_preset.json"
	CombatState.boot_sandbox = false


func _wipe_preset() -> void:
	if FileAccess.file_exists(PRESET_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PRESET_PATH))


func test_version_is_at_least_0_4_61() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.61") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.61" in log)
	assert_true("伤害修正" in log)
	assert_true("手动开火" in log)
	assert_true("袋中配置" in log)


func _sandbox_fight(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH, true)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	cs.player_fire_gate_remaining = 0.0
	if not cs.enemies.is_empty():
		cs.enemies[0].hp = 999
		cs.enemies[0].max_hp = 999
		cs.enemies[0].atk = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs


func _load_mag(cs: CombatState, ids: Array) -> void:
	cs.magazine.clear()
	cs.magazine.start_index = 0
	for i in ids.size():
		var aid: int = int(ids[i])
		if aid != EMPTY:
			cs.magazine.set_slot(i, aid)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.player_fire_gate_remaining = 0.0


func _manual(cs: CombatState) -> Dictionary:
	cs.player_fire_gate_remaining = 0.0
	return cs.fire_manual_tap()


func test_save_modify_restore_bag_and_leave_hand_chamber() -> void:
	var cs := _sandbox_fight(46101)
	cs.sandbox_add_ammo(BAIBAN, 2)
	cs._bag_append(QISHI, FIRE_ONCE, true)
	cs.sandbox_add_ammo(CHUANDI, 1)
	# 手和弹仓放不同的弹，还原时必须原样保留
	cs.hand = [XULI] as Array[int]
	cs.hand_temp = [0.0]
	cs.hand_envy_copy = [false]
	cs.hand_uid = [4242] as Array[int]
	cs.magazine.set_slot(2, HUIWEI)
	cs.discard = [BAIBAN] as Array[int]
	var saved: Array = cs.sandbox_bag_preset_snapshot()
	assert_eq(saved.size(), 4)
	var r: Dictionary = cs.save_sandbox_bag_preset()
	assert_true(bool(r.get("ok", false)))
	assert_false(bool(r.get("empty", true)))
	cs.dev_clear_bag()
	cs.sandbox_add_ammo(XULI, 2)
	assert_eq(cs.bag.size(), 2)
	var back: Dictionary = cs.restore_sandbox_bag_preset()
	assert_true(bool(back.get("ok", false)))
	assert_eq(cs.bag.size(), 4)
	assert_eq(int(cs.bag[0]), BAIBAN)
	assert_eq(int(cs.bag[1]), BAIBAN)
	assert_eq(int(cs.bag[2]), QISHI)
	assert_true(cs.is_bag_index_temporary(2))
	assert_true(bool(cs.bag_envy_copy[2]))
	assert_eq(int(cs.bag[3]), CHUANDI)
	assert_eq(cs.hand, [XULI] as Array[int])
	assert_eq(cs.hand_uid, [4242] as Array[int])
	assert_eq(cs.magazine.slots[2], HUIWEI)
	assert_eq(cs.discard, [BAIBAN] as Array[int])
	assert_false(cs.sandbox_hold_bag_empty)


func test_empty_bag_preset_is_valid_and_distinct_from_missing() -> void:
	var cs := _sandbox_fight(46102)
	assert_false(cs.has_sandbox_bag_preset())
	cs.sandbox_add_ammo(BAIBAN, 2)
	var miss: Dictionary = cs.restore_sandbox_bag_preset()
	assert_false(bool(miss.get("ok", false)))
	assert_eq(str(miss.get("reason", "")), "no_preset")
	assert_eq(cs.bag.size(), 2, "没有存档时不得偷偷改袋")
	cs.dev_clear_bag()
	assert_eq(cs.bag.size(), 0)
	var saved: Dictionary = cs.save_sandbox_bag_preset()
	assert_true(bool(saved.get("ok", false)))
	assert_true(bool(saved.get("empty", false)))
	assert_true(cs.has_sandbox_bag_preset())
	cs.sandbox_add_ammo(BAIBAN, 2)
	assert_eq(cs.bag.size(), 2)
	var back: Dictionary = cs.restore_sandbox_bag_preset()
	assert_true(bool(back.get("ok", false)))
	assert_true(bool(back.get("empty", false)))
	assert_eq(cs.bag.size(), 0)
	assert_true(cs.sandbox_hold_bag_empty)


func test_preset_persists_to_new_state() -> void:
	var cs := _sandbox_fight(46103)
	cs.sandbox_add_ammo(BAIBAN, 2)
	cs._bag_append(QISHI, FIRE_ONCE, true)
	assert_true(bool(cs.save_sandbox_bag_preset().get("ok", false)))
	var cs2 := CombatState.new(46113)
	cs2.start_sandbox(46113, FireResolver.ID_WRATH, false)
	assert_true(cs2.has_sandbox_bag_preset())
	assert_eq(cs2.bag.size(), 0)
	var back: Dictionary = cs2.restore_sandbox_bag_preset()
	assert_true(bool(back.get("ok", false)))
	assert_eq(cs2.bag.size(), 3)
	assert_eq(int(cs2.bag[2]), QISHI)
	assert_true(cs2.is_bag_index_temporary(2))
	assert_true(bool(cs2.bag_envy_copy[2]))


func test_manual_one_tap_one_shot_and_buff_continues() -> void:
	var cs := _sandbox_fight(46110)
	_load_mag(cs, [QISHI, BAIBAN, BAIBAN])
	var first: Dictionary = _manual(cs)
	assert_true(bool(first.get("ok", false)))
	assert_true(bool(first.get("started", false)))
	assert_false(bool(first.get("finished", true)))
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_true(cs.is_sandbox_sequence_active())
	assert_false(cs.is_volley_pending())
	var mid: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(int(mid.get("qishi_pct", 0)), 125)
	assert_true("%s×2.25" % DataRegistry.ammo_display_name(QISHI) in str(mid.get("text", "")))
	assert_true("白板弹" in str(mid.get("text", "")))
	var second: Dictionary = _manual(cs)
	assert_true(bool(second.get("ok", false)))
	assert_false(bool(second.get("finished", true)))
	var shots: Array = second.get("shots", [])
	assert_gt(shots.size(), 0)
	var dealt: int = int(shots[0].get("planned_damage", 0))
	# 白板基础 3，吃一层起势 → 4.5，计划值至少是 4
	assert_gte(dealt, 4)
	assert_true(cs.is_sandbox_sequence_active())
	var third: Dictionary = _manual(cs)
	assert_true(bool(third.get("ok", false)))
	assert_true(bool(third.get("finished", false)))
	assert_false(cs.is_sandbox_sequence_active())
	assert_false(cs.is_volley_session())
	assert_eq(str(cs.sandbox_damage_modifiers_text()), "伤害修正：无")


func test_manual_empty_chamber_is_one_blank_beat() -> void:
	var cs := _sandbox_fight(46111)
	_load_mag(cs, [EMPTY, BAIBAN, BAIBAN])
	# start_index=0 且槽 0 空，火门口为空
	assert_true(cs.volley_port_empty())
	var first: Dictionary = _manual(cs)
	assert_true(bool(first.get("blank", false)))
	assert_true(bool(first.get("ok", false)))
	assert_false(bool(first.get("finished", true)))
	assert_eq(cs.magazine.loaded_count(), 2, "空仓一拍不得把后面的实弹一起跳掉")
	assert_eq(cs.magazine.slots[1], BAIBAN)
	assert_true(cs.is_sandbox_sequence_active())
	var second: Dictionary = _manual(cs)
	assert_false(bool(second.get("blank", true)))
	assert_true(bool(second.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 1)


func test_auto_volley_still_fires_whole_magazine() -> void:
	var cs := _sandbox_fight(46112)
	_load_mag(cs, [BAIBAN, BAIBAN, BAIBAN])
	var shots: Array = cs.fire_tap(true)
	assert_gte(shots.size(), 3)
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_false(cs.is_volley_pending())
	assert_false(cs.is_volley_session())


func test_manual_then_auto_continues_without_reset_or_duplicate() -> void:
	var cs := _sandbox_fight(46113)
	_load_mag(cs, [QISHI, BAIBAN, BAIBAN])
	var first: Dictionary = _manual(cs)
	assert_eq((first.get("shots", []) as Array).size(), 1)
	assert_true(cs.is_sandbox_sequence_active())
	var remain_before: int = cs.magazine.loaded_count()
	assert_eq(remain_before, 2)
	assert_true(cs.begin_auto_continue_from_manual())
	assert_true(cs.is_volley_pending())
	var rest: Array = []
	var guard := 8
	while guard > 0 and cs.is_volley_pending():
		guard -= 1
		cs.player_fire_gate_remaining = 0.0
		if cs.volley_port_empty():
			cs.take_volley_blank_beat()
		else:
			for rec in cs.take_volley_shot():
				rest.append(rec)
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_eq(rest.size(), 2, "自动应只打剩余两发，不得重打已打出的加伤弹")
	assert_false(cs.is_sandbox_sequence_active())


func test_damage_modifiers_baseline_and_active_kinds() -> void:
	var cs := _sandbox_fight(46120)
	_load_mag(cs, [BAIBAN, BAIBAN])
	var none: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(str(none.get("text", "")), "伤害修正：无")
	assert_eq(int(none.get("qishi_pct", 1)), 0)
	assert_eq(float(none.get("xuli_mult", 0.0)), 1.0)
	assert_eq(int(none.get("huiwei_flat", 1)), 0)
	# 只读预览不得为了展示去挂或消耗状态
	assert_true(cs.volley_muzzle_buffs().is_empty())

	_load_mag(cs, [QISHI, XULI, BAIBAN])
	assert_true(bool(_manual(cs).get("ok", false)))
	var q: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(int(q.get("qishi_pct", 0)), 125)
	assert_true("%s×2.25" % DataRegistry.ammo_display_name(QISHI) in str(q.get("text", "")))
	assert_true("倍伤弹" in str(q.get("text", "")) or "加伤" in str(q.get("text", "")))
	# 下一发是开始弹：起势对它无效
	assert_true("无效" in str(q.get("text", "")))
	var buffs_before: int = cs.volley_muzzle_buffs().size()
	cs.sandbox_damage_modifiers()
	cs.sandbox_damage_modifiers()
	assert_eq(cs.volley_muzzle_buffs().size(), buffs_before)
	assert_eq(cs.magazine.loaded_count(), 2)

	assert_true(bool(_manual(cs).get("ok", false)))
	var x: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(int(x.get("qishi_pct", 0)), 125)
	assert_almost_eq(float(x.get("xuli_mult", 1.0)), 1.5, 0.0001)
	assert_true("%s×1.5" % DataRegistry.ammo_display_name(XULI) in str(x.get("text", "")))
	assert_true("白板弹" in str(x.get("text", "")))
	assert_false("倍率" in str(x.get("text", "")) and "回味" in str(x.get("text", "")))
	# 消费蓄力：打出白板后倍率应掉
	assert_true(bool(_manual(cs).get("ok", false)))
	assert_true(bool(_manual(cs).get("finished", false)) or cs.magazine.is_empty())
	var done: Dictionary = cs.sandbox_damage_modifiers()
	assert_true(str(done.get("text", "")).contains("加伤弹"), "未消耗层跨装填保留")
	assert_eq(float(done.get("xuli_mult", 0.0)), 1.0)


func test_damage_modifiers_flat_aftertaste_and_transfer_and_reset() -> void:
	var cs := _sandbox_fight(46121)
	_load_mag(cs, [HUIWEI, BAIBAN, BAIBAN])
	var first: Dictionary = _manual(cs)
	assert_true(bool(first.get("ok", false)))
	var hw: Dictionary = cs.sandbox_damage_modifiers()
	assert_gt(int(hw.get("huiwei_flat", 0)), 0)
	var hw_name: String = DataRegistry.ammo_display_name(HUIWEI)
	assert_true(hw_name + "+" in str(hw.get("text", "")), str(hw.get("text", "")))
	assert_false(hw_name + "×" in str(hw.get("text", "")), "固定加伤不得写成倍率")
	assert_false("伤害倍率" in str(hw.get("text", "")))
	var flat0: int = int(hw.get("huiwei_flat", 0))
	cs.sandbox_damage_modifiers()
	assert_eq(int(cs.sandbox_damage_modifiers().get("huiwei_flat", 0)), flat0)
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_true(bool(_manual(cs).get("ok", false)))
	var still: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(int(still.get("huiwei_flat", 0)), 2, "回味持续本弹夹剩余，不应打一发就掉")
	assert_true(bool(_manual(cs).get("finished", false)))
	assert_eq(str(cs.sandbox_damage_modifiers_text()), "伤害修正：无")

	_ready_again(cs)
	_load_mag(cs, [QISHI, CHUANDI, BAIBAN])
	assert_true(bool(_manual(cs).get("ok", false)))
	assert_true(bool(_manual(cs).get("ok", false)))
	var tr: Dictionary = cs.sandbox_damage_modifiers()
	assert_gt(int(tr.get("chuandi_flat", 0)), 0)
	assert_true(DataRegistry.ammo_display_name(CHUANDI) + "+" in str(tr.get("text", "")), str(tr.get("text", "")))
	assert_true("白板弹" in str(tr.get("text", "")))
	var carry: int = int(tr.get("chuandi_flat", 0))
	cs.sandbox_damage_modifiers()
	assert_eq(int(cs.sandbox_damage_modifiers().get("chuandi_flat", 0)), carry)
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(bool(_manual(cs).get("finished", false)))
	# 新规则：一个加强量火焰在最后一发白板被消耗完，不再留下逐层递减的余层。
	assert_eq(int(cs.sandbox_damage_modifiers().get("chuandi_flat", 0)), 0)


func test_busy_blocks_preset_and_missing_is_non_destructive() -> void:
	var cs := _sandbox_fight(46122)
	cs.sandbox_add_ammo(BAIBAN, 2)
	_load_mag(cs, [BAIBAN, BAIBAN])
	assert_true(bool(_manual(cs).get("ok", false)))
	assert_true(cs.sandbox_bag_preset_busy())
	var blocked: Dictionary = cs.save_sandbox_bag_preset()
	assert_false(bool(blocked.get("ok", false)))
	assert_eq(str(blocked.get("reason", "")), "busy")
	var blocked_r: Dictionary = cs.restore_sandbox_bag_preset()
	assert_false(bool(blocked_r.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 1)


func test_sandbox_ui_splits_fire_and_shows_modifiers() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_true(ui.state.sandbox_mode)
	ui.state.player_fire_gate_remaining = 0.0
	CombatState.sandbox_bag_preset_path = PRESET_PATH
	assert_false(ui.btn_fire.visible, "沙盒应隐藏原来的整轮射击键")
	assert_not_null(ui._sb_btn_manual_fire)
	assert_not_null(ui._sb_btn_auto_fire)
	assert_eq(ui._sb_btn_manual_fire.text, "手动开火")
	assert_eq(ui._sb_btn_auto_fire.text, "自动开火")
	assert_true(ui._sb_fire_split.visible)
	assert_gte(ui._sb_btn_manual_fire.custom_minimum_size.y, 60.0)
	assert_gte(ui._sb_btn_auto_fire.custom_minimum_size.y, 60.0)
	assert_not_null(ui._sb_btn_save_preset)
	assert_not_null(ui._sb_btn_restore_preset)
	assert_eq(ui._sb_btn_save_preset.text, "保存当前袋中配置")
	assert_eq(ui._sb_btn_restore_preset.text, "一键还原袋中配置")
	assert_true(ui._sb_btn_restore_preset.disabled)
	assert_true("还没有保存过袋中配置" in ui._sb_preset_status.text)
	var stats: Dictionary = ui.sandbox_stats_text()
	assert_eq(str(stats.get("mod", "")), "伤害修正：无")
	assert_not_null(ui._sb_stats_mod)
	assert_eq(ui._sb_stats_mod.text, "伤害修正：无")
	# 装上加伤+白板后手动打一发，暂停期间应看到起势修正
	ui.state.magazine.clear()
	ui.state.magazine.start_index = 0
	ui.state.magazine.set_slot(0, QISHI)
	ui.state.magazine.set_slot(1, BAIBAN)
	ui.state._set_phase(CombatState.Phase.AWAIT_ACTION)
	if not ui.state.enemies.is_empty():
		ui.state.enemies[0].hp = 999
		ui.state.enemies[0].max_hp = 999
	ui.state.player_fire_gate_remaining = 0.0
	assert_true(bool(ui.state.fire_manual_tap().get("ok", false)))
	ui._update_sandbox_stats_hud()
	var live: String = ui.state.sandbox_damage_modifiers_text()
	assert_true("%s×1.5" % DataRegistry.ammo_display_name(QISHI) in live)
	assert_eq(ui._sb_stats_mod.text, live)
	CombatState.boot_sandbox = false


func _ready_again(cs: CombatState) -> void:
	cs._volley_pending = false
	cs._volley_followup_pending = false
	cs._volley_session = false
	cs.player_fire_gate_remaining = 0.0
	cs._reset_volley_plan()
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
