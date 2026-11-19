extends GutTest
## v0.4.68：独立闯关 9 关、3 店后首领、开局三选一、死亡守卫；走路开火叠层；rush/沙盒不受影响。


const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	CampaignRules.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func after_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func test_version_is_at_least_0_4_68() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.68") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.68" in log)
	assert_true("闯关" in log)


func _boot_cs(seed: int = 4242) -> CombatState:
	var cs := CombatState.new()
	cs.start_campaign(seed)
	cs.campaign_instant_transitions = true
	return cs


func _count_id(arr: Array, ammo_id: int) -> int:
	var n := 0
	for x in arr:
		if int(x) == ammo_id:
			n += 1
	return n


func _pick_opening(cs: CombatState, index: int = 0) -> int:
	assert_true(cs.campaign_offer_pending)
	assert_eq(cs.campaign_offer_choices.size(), 3)
	var picked: int = int(cs.campaign_offer_choices[index])
	assert_true(cs.campaign_pick_opening(index))
	return picked


func test_opening_bag_is_six_whites_then_one_offer() -> void:
	var cs := _boot_cs(7)
	assert_true(cs.campaign_mode)
	assert_false(cs.sandbox_mode)
	assert_true(cs.spawn_paused)
	assert_true(cs.map_shop_disabled)
	assert_eq(cs.bag.size(), 6)
	assert_eq(_count_id(cs.bag, WHITE), 6)
	assert_eq(cs.hand.size(), 0)
	assert_true(cs.campaign_offer_pending)
	assert_eq(cs.campaign_offer_choices.size(), 3)
	var seen := {}
	for aid in cs.campaign_offer_choices:
		assert_ne(int(aid), WHITE)
		assert_true(DataRegistry.is_ammo_reward_eligible(int(aid)))
		assert_false(seen.has(int(aid)), "opening offers must be unique")
		seen[int(aid)] = true
	var picked := _pick_opening(cs, 1)
	assert_false(cs.campaign_offer_pending)
	assert_eq(cs.bag.size(), 7)
	assert_eq(_count_id(cs.bag, WHITE), 6)
	assert_eq(_count_id(cs.bag, picked), 1)
	assert_eq(cs.campaign_offer_picked_id, picked)
	# 不能再领一次
	assert_false(cs.campaign_pick_opening(0))
	assert_eq(cs.bag.size(), 7)


func test_exactly_three_shops_then_boss_per_floor() -> void:
	var cs := _boot_cs(11)
	_pick_opening(cs, 0)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_floor, 1)
	assert_eq(cs.campaign_segment, 1)
	assert_gt(cs.alive_enemies().size(), 0)
	var shops := 0
	var guard := 40
	while shops < 3 and guard > 0:
		guard -= 1
		assert_ne(cs.campaign_phase, CampaignRules.PHASE_BOSS, "boss must not appear before 3 shops")
		assert_true(cs.shop_touch_pending == false or cs.campaign_phase == CampaignRules.PHASE_SHOP)
		if cs.reward_pending:
			assert_true(cs.pick_reward_ammo(0) or cs.skip_reward_for_gold())
			continue
		if cs.alive_enemies().size() > 0:
			# 有活怪时不得开店
			assert_false(cs._shop_field_safe_to_open())
			cs.dev_kill_all_enemies()
		if cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.campaign_phase == CampaignRules.PHASE_SHOP or cs.shop_touch_pending:
			assert_eq(cs.alive_enemies().size(), 0)
			assert_true(cs.campaign_simulate_shop_cycle())
			shops += 1
	assert_eq(shops, 3)
	assert_eq(cs.campaign_shops_this_floor, 3)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_gt(cs.alive_enemies().size(), 0)
	# 第四次不得再开店，而应打首领
	var before_gold: int = cs.gold
	var before_xp: int = cs.xp
	var before_bag: int = cs.bag.size()
	cs.dev_kill_all_enemies()
	# 可能进入首领奖励
	assert_true(cs.campaign_phase == CampaignRules.PHASE_BOSS_REWARD or cs.reward_pending or cs.campaign_await_boss_reward)
	assert_false(cs.shop_touch_pending)
	# 持久：清怪不重置袋/金币（经验可以增加）
	assert_eq(cs.bag.size(), before_bag)
	assert_eq(cs.gold, before_gold)
	assert_gte(cs.xp, before_xp)


func _finish_floor(cs: CombatState) -> void:
	## 从当前战斗/进场推进到打完本关首领并领完奖励（进入下一关或胜利）。
	var start_floor: int = cs.campaign_floor
	if cs.campaign_phase == CampaignRules.PHASE_ENTER:
		cs.campaign_skip_walk()
	var guard := 80
	while guard > 0:
		guard -= 1
		if cs.phase == CombatState.Phase.WON:
			return
		if cs.campaign_floor > start_floor:
			return
		if cs.campaign_offer_pending:
			_pick_opening(cs, 0)
			continue
		if cs.reward_pending:
			assert_true(cs.pick_reward_ammo(0) or cs.skip_reward_for_gold())
			continue
		if cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.shop_touch_pending or cs.campaign_phase == CampaignRules.PHASE_SHOP:
			cs.campaign_simulate_shop_cycle()
			continue
		if cs.campaign_phase == CampaignRules.PHASE_WALK_FLOOR or cs.campaign_phase == CampaignRules.PHASE_ENTER:
			cs.campaign_skip_walk()
			continue
		if cs.alive_enemies().size() > 0:
			cs.dev_kill_all_enemies()
			continue
		cs.campaign_try_advance()
	assert_true(cs.phase == CombatState.Phase.WON or cs.campaign_floor > start_floor, "floor %d did not finish (phase=%d)" % [start_floor, cs.campaign_phase])


func test_nine_floors_end_in_victory_not_floor_ten() -> void:
	var cs := _boot_cs(99)
	_pick_opening(cs, 0)
	var start_hp: int = cs.player_hp
	var start_bag: int = cs.bag.size()
	for floor_i in range(1, 10):
		assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
		assert_lte(cs.campaign_floor, 9)
		_finish_floor(cs)
		if floor_i < 9:
			assert_eq(cs.campaign_floor, floor_i + 1)
			assert_ne(cs.phase, CombatState.Phase.WON)
			assert_eq(cs.player_hp, start_hp, "HP persists unless a chosen reward changes it; no auto heal")
			assert_gte(cs.bag.size(), start_bag)
		else:
			assert_eq(cs.phase, CombatState.Phase.WON)
			assert_eq(cs.campaign_phase, CampaignRules.PHASE_VICTORY)
			assert_eq(cs.campaign_floor, 9)
	# 没有第 10 关
	assert_eq(cs.campaign_floor, 9)
	assert_eq(CampaignRules.floor_count(), 9)


func test_death_blocks_shop_and_advance() -> void:
	var cs := _boot_cs(3)
	_pick_opening(cs, 0)
	assert_gt(cs.alive_enemies().size(), 0)
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_false(cs._shop_field_safe_to_open())
	assert_false(cs.campaign_field_safe())
	cs.campaign_try_advance()
	assert_false(cs.shop_touch_pending)
	assert_eq(cs.campaign_shops_this_floor, 0)
	assert_ne(cs.campaign_phase, CampaignRules.PHASE_SHOP)
	assert_ne(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_false(cs.campaign_simulate_shop_cycle())


func test_rush_and_sandbox_unchanged() -> void:
	var rush := CombatState.new()
	rush.start_rush(21, FireResolver.ID_WRATH)
	assert_false(rush.campaign_mode)
	assert_false(rush.sandbox_mode)
	assert_false(rush.spawn_paused)
	assert_false(rush.map_shop_disabled)
	assert_eq(rush.campaign_phase, CampaignRules.PHASE_INACTIVE)
	assert_gt(rush.bag.size(), 6, "rush keeps legacy starter bag, not 6 whites only")
	assert_gt(rush.alive_enemies().size(), 0)
	var starters := CombatConstants.starter_ammo_ids()
	assert_gt(starters.size(), 6)
	assert_eq(_count_id(rush.bag, WHITE), 6)

	var box := CombatState.new()
	box.start_sandbox(21, FireResolver.ID_WRATH, true)
	assert_true(box.sandbox_mode)
	assert_false(box.campaign_mode)
	assert_true(box.spawn_paused)
	assert_true(box.map_shop_disabled)
	assert_eq(box.bag.size(), 0)
	assert_gt(box.alive_enemies().size(), 0)


func test_walk_legs_keep_moving_during_shoot_and_tempo_changes() -> void:
	var cat = add_child_autofree(load("res://scripts/player/skeleton_player.gd").new())
	await wait_process_frames(2)
	cat.set_walk_tempo(0.72)
	cat.set_walking(true)
	await wait_process_frames(4)
	assert_true(cat.is_walking())
	assert_eq(StringName(cat.anim.current_animation), cat.ANIM_WALK)
	var t0: float = cat.walk_cycle_time()
	cat.play_shoot()
	assert_eq(StringName(cat.anim.current_animation), cat.ANIM_SHOOT)
	assert_true(cat.is_walking())
	var thigh0: float = (cat.bones["ThighF"] as Bone2D).rotation
	# 多推进几帧，腿应随走路时钟变化，不能冻在待机
	for _i in 8:
		cat._process(0.03)
	var thigh1: float = (cat.bones["ThighF"] as Bone2D).rotation
	assert_true(cat.is_walking())
	assert_eq(StringName(cat.anim.current_animation), cat.ANIM_SHOOT)
	assert_ne(thigh1, thigh0, "legs must keep walking while firing")
	assert_gt(cat.walk_cycle_time(), t0)
	# 快走时钟更快
	var mid: float = cat.walk_cycle_time()
	cat.set_walk_tempo(1.85)
	cat._process(0.20)
	var fast_dt: float = cat.walk_cycle_time() - mid
	cat.set_walk_tempo(0.72)
	var mid2: float = cat.walk_cycle_time()
	cat._process(0.20)
	var slow_dt: float = cat.walk_cycle_time() - mid2
	assert_gt(fast_dt, slow_dt)


func test_menu_has_campaign_entry_and_ui_progress() -> void:
	var menu = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_process_frames(2)
	var btn: Button = menu.get_node_or_null("%BtnCampaign")
	assert_not_null(btn)
	assert_eq(btn.text, "闯关")
	var start: Button = menu.get_node_or_null("%BtnStart")
	assert_eq(start.text, "rush!")

	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui._fit_combat_viewport(Vector2(720, 1280))
	await wait_process_frames(4)
	assert_true(ui.state.campaign_mode)
	assert_true(ui.state.campaign_offer_pending)
	assert_true("开局自选" in ui.turn_label.text or "闯关" in ui.turn_label.text)
	assert_eq(ui.state.bag.size(), 6)
	# 选第一发后应进战斗或进场，并开始走路
	assert_true(ui.state.campaign_pick_opening(0))
	ui.state.campaign_instant_transitions = true
	ui.state.campaign_skip_walk()
	ui._refresh()
	await wait_process_frames(3)
	assert_eq(ui.state.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_true("第1关" in ui.turn_label.text or "第 1 关" in ui.state.campaign_progress_text())
	assert_true(ui.get("_skel_player").is_walking())
	# 有活怪时 UI 不得开店
	assert_gt(ui.state.alive_enemies().size(), 0)
	ui.state.shop_touch_pending = true
	# process 守卫：场上有怪则不开
	assert_false(ui.state._shop_field_safe_to_open())
	ui.state.shop_touch_pending = false
	# rush 启动不受 boot_campaign 残留影响（已在 _ready 清掉）
	assert_false(CombatState.boot_campaign)
