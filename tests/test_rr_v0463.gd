extends GutTest
## v0.4.63：回味弹在 CombatUI 延后命中路径里，按实际伤害给本弹夹剩余子弹加固定伤害。


const HUIWEI := CombatConstants.HUIWEI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_63() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.63") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.63" in log)
	assert_true("回味" in log)


func _huiwei_amount(cs: CombatState) -> int:
	for b in cs.volley_muzzle_buffs():
		if str(b.get("id", "")) == "huiwei":
			return int(b.get("amount", 0))
	return 0


func _front_hp(cs: CombatState) -> int:
	var e: EnemyInstance = cs.front_enemy()
	return e.hp if e != null else -1


func _load_mag(cs: CombatState, ids: Array) -> void:
	cs.magazine.clear()
	cs.magazine.start_index = 0
	for i in ids.size():
		var aid: int = int(ids[i])
		if aid != Magazine.EMPTY:
			cs.magazine.set_slot(i, aid)
	cs.player_fire_gate_remaining = 0.0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)


func _paced_cs(seed_v: int) -> CombatState:
	## 与实战 CombatUI 一致：pace + 延后落地，不能走同步 fire_next_shot 扣血。
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH, true)
	cs.pace_after_fire = true
	cs.defer_impacts = true
	cs.auto_enemy_advance = false
	cs.player_fire_gate_remaining = 0.0
	if not cs.enemies.is_empty():
		cs.enemies[0].hp = 999
		cs.enemies[0].max_hp = 999
		cs.enemies[0].atk = 0
	_load_mag(cs, [])
	return cs


func _land_all_impacts(cs: CombatState, shots: Array) -> void:
	for rec in shots:
		var iid: int = int(rec.get("impact_id", -1))
		if iid >= 0:
			cs.finalize_pending_impact(iid)


func test_deferred_huiwei_does_not_mount_until_actual_hit() -> void:
	var cs := _paced_cs(46301)
	_load_mag(cs, [HUIWEI, BAIBAN, BAIBAN])
	var hp0: int = _front_hp(cs)
	var first: Dictionary = cs.fire_manual_tap()
	assert_true(bool(first.get("ok", false)))
	assert_eq(_huiwei_amount(cs), 0, "延后落地前不得按预计伤害提前挂回味")
	assert_eq(_front_hp(cs), hp0, "延后落地前不应先扣血")
	assert_eq(str(cs.sandbox_damage_modifiers().get("huiwei_flat", 0)), "0")
	_land_all_impacts(cs, first.get("shots", []))
	assert_eq(_front_hp(cs), hp0 - 2, "回味本身应打出基础 2")
	assert_eq(_huiwei_amount(cs), 2)
	var mod: Dictionary = cs.sandbox_damage_modifiers()
	assert_eq(int(mod.get("huiwei_flat", 0)), 4)
	assert_true(DataRegistry.ammo_display_name(HUIWEI) + "+4" in str(mod.get("text", "")), str(mod.get("text", "")))
	assert_false(DataRegistry.ammo_display_name(HUIWEI) + "×" in str(mod.get("text", "")))


func test_deferred_huiwei_boosts_next_shot_hp_and_plan() -> void:
	var cs := _paced_cs(46302)
	_load_mag(cs, [HUIWEI, BAIBAN, BAIBAN])
	var first: Dictionary = cs.fire_manual_tap()
	_land_all_impacts(cs, first.get("shots", []))
	assert_eq(_huiwei_amount(cs), 2)
	var hp1: int = _front_hp(cs)
	cs.player_fire_gate_remaining = 0.0
	var second: Dictionary = cs.fire_manual_tap()
	assert_true(bool(second.get("ok", false)))
	var shots: Array = second.get("shots", [])
	assert_gt(shots.size(), 0)
	assert_eq(int(shots[0].get("planned_damage", 0)), 7, "下一发白板计划伤应是 3+2")
	_land_all_impacts(cs, shots)
	assert_eq(_front_hp(cs), hp1 - 7, "下一发实际扣血也应吃到回味+2")
	assert_eq(_huiwei_amount(cs), 2, "回味持续本弹夹，不应打一发就掉")
	cs.player_fire_gate_remaining = 0.0
	var third: Dictionary = cs.fire_manual_tap()
	_land_all_impacts(cs, third.get("shots", []))
	assert_true(bool(third.get("finished", false)))
	assert_eq(_huiwei_amount(cs), 0, "弹夹打完才清除回味")
	assert_eq(str(cs.sandbox_damage_modifiers_text()), "伤害修正：无")


func test_deferred_huiwei_stacks_and_manual_to_auto() -> void:
	var cs := _paced_cs(46303)
	_load_mag(cs, [HUIWEI, HUIWEI, BAIBAN])
	var a: Dictionary = cs.fire_manual_tap()
	_land_all_impacts(cs, a.get("shots", []))
	assert_eq(_huiwei_amount(cs), 2)
	cs.player_fire_gate_remaining = 0.0
	var b: Dictionary = cs.fire_manual_tap()
	_land_all_impacts(cs, b.get("shots", []))
	# 第二发回味自身也吃第一层+2，实际 4，叠成 2+4=6
	assert_eq(_huiwei_amount(cs), 2)
	var hp: int = _front_hp(cs)
	assert_true(cs.begin_auto_continue_from_manual())
	cs.player_fire_gate_remaining = 0.0
	var rest: Array = cs.take_volley_shot()
	assert_gt(rest.size(), 0)
	assert_eq(int(rest[0].get("planned_damage", 0)), 11, "白板 3+6")
	_land_all_impacts(cs, rest)
	assert_eq(_front_hp(cs), hp - 11)
	# 按效果每发只减一层；新授予的六点层仍保留。
	assert_eq(_huiwei_amount(cs), 6)


func test_combat_ui_manual_and_auto_huiwei_actually_boosts() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_true(ui.state.sandbox_mode)
	assert_true(ui.state.defer_impacts)
	assert_true(ui.state.pace_after_fire)
	ui._combat_speed = ui.COMBAT_SPEED_MAX
	ui.state.auto_enemy_advance = false
	ui.state.player_fire_gate_remaining = 0.0
	if not ui.state.enemies.is_empty():
		ui.state.enemies[0].hp = 999
		ui.state.enemies[0].max_hp = 999
		ui.state.enemies[0].atk = 0
	_load_mag(ui.state, [HUIWEI, BAIBAN, BAIBAN])
	ui._refresh()
	var hp0: int = _front_hp(ui.state)
	ui._volley_ui_running = true
	var pack: Dictionary = ui._resolve_manual_fire_logic()
	await ui._present_manual_resolved(pack)
	ui._volley_ui_running = false
	assert_eq(_front_hp(ui.state), hp0 - 2)
	assert_eq(_huiwei_amount(ui.state), 2)
	ui._update_sandbox_stats_hud()
	var live: String = ui.state.sandbox_damage_modifiers_text()
	assert_true(DataRegistry.ammo_display_name(HUIWEI) + "+4" in live, live)
	assert_eq(ui._sb_stats_mod.text, live)
	# 手动再打一发白板
	ui.state.player_fire_gate_remaining = 0.0
	var hp1: int = _front_hp(ui.state)
	ui._volley_ui_running = true
	var pack2: Dictionary = ui._resolve_manual_fire_logic()
	await ui._present_manual_resolved(pack2)
	ui._volley_ui_running = false
	assert_eq(_front_hp(ui.state), hp1 - 7, "沙盒手动开火路径下，白板应吃到回味+2")
	assert_eq(_huiwei_amount(ui.state), 2)
	# 切自动打完最后一发，仍应带+2
	var hp2: int = _front_hp(ui.state)
	assert_true(ui.state.begin_auto_continue_from_manual())
	ui._volley_ui_running = true
	await ui._run_volley_autofire(true)
	ui._volley_ui_running = false
	assert_eq(_front_hp(ui.state), hp2 - 5, "手动切自动的剩余白板也应吃到回味")
	assert_eq(_huiwei_amount(ui.state), 0)
	assert_eq(str(ui.state.sandbox_damage_modifiers_text()), "伤害修正：无")
	CombatState.boot_sandbox = false


func test_combat_ui_auto_volley_huiwei_from_start() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui._combat_speed = ui.COMBAT_SPEED_MAX
	ui.state.auto_enemy_advance = false
	ui.state.player_fire_gate_remaining = 0.0
	if not ui.state.enemies.is_empty():
		ui.state.enemies[0].hp = 999
		ui.state.enemies[0].max_hp = 999
		ui.state.enemies[0].atk = 0
	_load_mag(ui.state, [HUIWEI, BAIBAN])
	ui._refresh()
	var hp0: int = _front_hp(ui.state)
	ui.state.commit_unused_hand_for_fire()
	ui._volley_ui_running = true
	# 不预转：只有两发且我们已对准槽 0
	var pack: Dictionary = ui._resolve_fire_logic()
	await ui._present_resolved_fire_async(pack)
	if ui.state.is_volley_pending():
		await ui._run_volley_autofire(pack.get("shots", []).is_empty())
	ui._volley_ui_running = false
	assert_eq(_front_hp(ui.state), hp0 - 2 - 5, "自动连射里回味落地后，后续白板应打 5")
	assert_eq(_huiwei_amount(ui.state), 0)
	CombatState.boot_sandbox = false
