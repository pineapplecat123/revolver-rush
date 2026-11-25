extends GutTest
## v0.4.72：巷边店铺进门才购物、从另一扇门离开；静止巷景；rush/沙盒分界。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()


func _boot_campaign(seed_v: int = 47201) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_campaign(seed_v)
	cs.campaign_instant_transitions = false
	if cs.campaign_offer_pending:
		assert_true(cs.campaign_pick_opening(0))
	return cs


func _force_walk_to_shop(cs: CombatState) -> void:
	## 把本段剩余波次视为打完，清场后走向商店（不走完整战斗）。
	if cs.campaign_phase == CampaignRules.PHASE_ENTER or cs.campaign_walk_left > 0.0:
		cs.campaign_skip_walk()
	cs.campaign_wave = maxi(1, CampaignRules.wave_count(cs.campaign_floor, cs.campaign_segment))
	cs.campaign_node_clears = 2
	cs.enemies.clear()
	cs.reward_pending = false
	cs.pending_levelups = 0
	cs.campaign_try_advance()


func test_version_is_at_least_0_4_72() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.72") >= 0)


func test_campaign_shop_opens_only_after_entering_door() -> void:
	var cs := _boot_campaign(47210)
	cs.campaign_instant_transitions = false
	_force_walk_to_shop(cs)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_WALK_SHOP)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	assert_false(cs.shop_touch_pending, "还在走向入口时不能开店")
	assert_eq(cs.shop_house_occlusion_at(0.0), "outside")
	# 走到门口
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_SHOP)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_INSIDE)
	assert_true(cs.shop_touch_pending)
	assert_eq(cs.shop_house_occlusion_at(0.0), "door_in")
	assert_eq(cs.campaign_shops_this_floor, 1)


func test_leave_uses_other_door_then_continues_no_spawn_during_exit() -> void:
	var cs := _boot_campaign(47211)
	_force_walk_to_shop(cs)
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(cs.shop_touch_pending)
	cs.shop_hold = true
	cs.campaign_on_shop_left()
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_LEAVE_SHOP)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	assert_false(cs.shop_touch_pending)
	assert_eq(cs.alive_enemies().size(), 0, "出门途中不刷下一段")
	assert_ne(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_eq(cs.campaign_segment, 1)
	# 出门走到另一扇门附近
	var mid: float = CampaignRules.walk_from_shop_sec() * 0.45
	cs.tick_shop_house(mid)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	var occ: String = cs.shop_house_occlusion_at(0.0)
	assert_true(occ == "inside" or occ == "door_out" or occ == "outside")
	cs.tick_shop_house(CampaignRules.walk_from_shop_sec())
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_segment, 2)
	assert_gt(cs.alive_enemies().size(), 0, "出完门才继续下一段")


func test_third_shop_exit_starts_boss_not_during_exit() -> void:
	var cs := _boot_campaign(47212)
	cs.campaign_instant_transitions = true
	# 前两次店用即时循环
	var shops := 0
	var guard := 80
	while shops < 2 and guard > 0:
		guard -= 1
		if cs.campaign_offer_pending:
			cs.campaign_pick_opening(0)
			continue
		cs.campaign_skip_walk()
		cs.enemies.clear()
		cs.campaign_try_advance()
		if cs.alley_active() or cs.campaign_phase in [CampaignRules.PHASE_WALK_ALLEY, CampaignRules.PHASE_ALLEY, CampaignRules.PHASE_LEAVE_ALLEY]:
			assert_true(cs.campaign_simulate_alley_skip())
			continue
		if cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.shop_touch_pending or cs.campaign_phase == CampaignRules.PHASE_SHOP:
			assert_true(cs.campaign_simulate_shop_cycle())
			shops += 1
	assert_eq(shops, 2)
	# 第三次：不用即时，确认出门阶段还没有首领
	cs.campaign_instant_transitions = false
	cs.enemies.clear()
	cs.campaign_try_advance()
	var guard2 := 8
	while guard2 > 0 and not (cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.shop_house_seq == CombatState.SHOP_HOUSE_APPROACH):
		guard2 -= 1
		if cs.alley_active() or cs.campaign_phase in [CampaignRules.PHASE_WALK_ALLEY, CampaignRules.PHASE_ALLEY, CampaignRules.PHASE_LEAVE_ALLEY]:
			cs.campaign_simulate_alley_skip()
		if cs.campaign_phase == CampaignRules.PHASE_COMBAT:
			cs.enemies.clear()
			cs.campaign_try_advance()
	assert_true(cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.shop_house_seq == CombatState.SHOP_HOUSE_APPROACH)
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_eq(cs.campaign_shops_this_floor, 3)
	cs.campaign_on_shop_left()
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_LEAVE_SHOP)
	assert_ne(cs.campaign_phase, CampaignRules.PHASE_BOSS, "第三店出门途中不能出首领")
	assert_eq(cs.alive_enemies().size(), 0)
	cs.tick_shop_house(CampaignRules.walk_from_shop_sec() + 0.05)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_gt(cs.alive_enemies().size(), 0)


func test_no_duplicate_enter_or_exit() -> void:
	var cs := _boot_campaign(47213)
	_force_walk_to_shop(cs)
	var left0: float = cs.shop_house_walk_left
	cs._begin_walk_to_shop()
	assert_almost_eq(cs.shop_house_walk_left, left0, 0.001, "不能叠两次走向商店")
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	var shops: int = cs.campaign_shops_this_floor
	cs._finish_shop_house_approach()
	assert_eq(cs.campaign_shops_this_floor, shops, "进店只计一次")
	cs.campaign_on_shop_left()
	cs.campaign_on_shop_left()
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	cs.tick_shop_house(CampaignRules.walk_from_shop_sec() + 0.05)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	cs._finish_shop_house_exit()
	assert_eq(cs.campaign_segment, 2)


func test_death_and_restart_clear_house() -> void:
	var cs := _boot_campaign(47214)
	_force_walk_to_shop(cs)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	cs._set_phase(CombatState.Phase.LOST)
	cs.tick_shop_house(0.1)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_false(cs.shop_touch_pending)
	cs.start_campaign(47214)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_eq(cs.campaign_shops_this_floor, 0)
	assert_eq(cs.bag.size(), CampaignRules.opening_white_count())


func test_upgrade_gates_shop_until_safe() -> void:
	var cs := _boot_campaign(47215)
	_force_walk_to_shop(cs)
	cs.reward_pending = true
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	assert_false(cs.shop_touch_pending, "升级选择时停在门口")
	cs.reward_pending = false
	cs.tick_shop_house(0.0)
	assert_true(cs.shop_touch_pending)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_INSIDE)


func test_house_is_not_an_enemy() -> void:
	var cs := _boot_campaign(47216)
	_force_walk_to_shop(cs)
	assert_true(cs.shop_house_active())
	for e in cs.enemies:
		assert_false(e == null)
	assert_eq(cs.alive_enemies().size(), 0)
	# 逻辑上没有商店敌人实体、没有血条或掉落
	assert_eq(cs.shop_cell, -1)


func test_doors_are_distinct() -> void:
	assert_gt(CampaignRules.shop_house_exit_x() - CampaignRules.shop_house_entrance_x(), 80.0)
	assert_ne(CampaignRules.shop_house_entrance_x(), CampaignRules.shop_house_exit_x())
	var cs := CombatState.new(47217)
	cs.shop_house_seq = CombatState.SHOP_HOUSE_INSIDE
	assert_eq(cs.shop_house_occlusion_at(0.0), "door_in")
	# 猫仍在玩家格时，入口在猫处；出口在右侧更远处
	var left: float = cs.shop_house_left_at(0.0)
	assert_almost_eq(left + CampaignRules.shop_house_entrance_x(), 0.0, 0.01)
	assert_gt(left + CampaignRules.shop_house_exit_x(), 100.0)


func test_rush_uses_house_sandbox_does_not() -> void:
	var rush := CombatState.new(47218)
	rush.start_rush(47218)
	rush.spawn_paused = true
	rush.enemies.clear()
	rush.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	rush.tick_map_shop(0.0)
	# 场上已空，到点后应走进店铺而不是立刻 pending
	assert_eq(rush.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	assert_false(rush.shop_touch_pending)
	rush.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(rush.shop_touch_pending)
	rush.acknowledge_shop_touch()
	rush.conclude_shop_visit()
	assert_eq(rush.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	assert_true(rush.encounter_spawns_blocked())
	rush.tick_shop_house(CampaignRules.walk_from_shop_sec() + 0.05)
	assert_eq(rush.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_false(rush.encounter_spawns_blocked())

	var box := CombatState.new(47219)
	box.start_sandbox(47219)
	assert_true(box.map_shop_disabled)
	box.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	box.tick_map_shop(0.0)
	assert_eq(box.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_false(box.shop_touch_pending)


func test_instant_transitions_and_ui_house_visibility() -> void:
	var cs := _boot_campaign(47220)
	cs.campaign_instant_transitions = true
	_force_walk_to_shop(cs)
	# 即时过场应直接进店
	assert_true(cs.shop_touch_pending or cs.campaign_phase == CampaignRules.PHASE_SHOP)
	assert_eq(cs.campaign_shops_this_floor, 1)
	assert_true(cs.campaign_simulate_shop_cycle() or cs.campaign_segment == 2 or cs.campaign_phase == CampaignRules.PHASE_COMBAT)

	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui.state.start_campaign(47221)
	if ui.state.campaign_offer_pending:
		ui.state.campaign_pick_opening(0)
	ui.state.campaign_instant_transitions = false
	_force_walk_to_shop(ui.state)
	ui._refresh()
	ui._ensure_campaign_backdrop()
	ui._ensure_shop_house()
	assert_not_null(ui.get("_campaign_backdrop"))
	ui._sync_shop_house()
	var house = ui.get("_shop_house")
	assert_not_null(house)
	assert_true(house.visible)
	assert_false(ui.state.shop_touch_pending)
	ui._process(0.0)
	# 进门完成
	ui.state.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	ui._sync_shop_house()
	assert_true(ui.state.shop_touch_pending)
	ui.state.campaign_on_shop_left()
	ui._sync_shop_house()
	assert_eq(ui.state.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	ui.state.tick_shop_house(CampaignRules.walk_from_shop_sec() + 0.05)
	ui._sync_shop_house()
	assert_eq(ui.state.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_false(house.visible)
