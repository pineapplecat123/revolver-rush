extends GutTest
## v0.4.75：波间随机事件（糖果机/垃圾桶）与商店轮流；袋内浅灰底、深灰球、外套冷灰无高光。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func _boot_campaign(seed_v: int = 47501, instant: bool = true) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_campaign(seed_v)
	cs.campaign_instant_transitions = instant
	if cs.campaign_offer_pending:
		assert_true(cs.campaign_pick_opening(0))
	if cs.campaign_phase == CampaignRules.PHASE_ENTER:
		cs.campaign_skip_walk()
	return cs


func _kill_wave(cs: CombatState) -> void:
	cs.enemies.clear()
	cs.reward_pending = false
	cs.pending_levelups = 0
	cs.campaign_try_advance()


func test_version_is_0_4_75() -> void:
	assert_eq(GameVersion.STRING, "0.4.75")
	assert_true("0.4.75" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_all_segments_have_two_waves_for_event_shop_cadence() -> void:
	assert_eq(CampaignRules.floor_count(), 9)
	assert_eq(CampaignRules.SEGMENTS_PER_FLOOR, 3)
	for f in range(1, 10):
		assert_eq(CampaignRules.floor_def(f).get("segments", []).size(), 3)
		for s in range(1, 4):
			assert_eq(CampaignRules.wave_count(f, s), 2, "floor %d seg %d should have 2 waves" % [f, s])


func test_event_shop_event_shop_event_shop_then_boss() -> void:
	var cs := _boot_campaign(47510, true)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_wave, 1)
	assert_eq(cs.campaign_shops_this_floor, 0)
	var events := 0
	var shops := 0
	var kinds: Array[String] = []
	var guard := 40
	while shops < 3 and guard > 0:
		guard -= 1
		if cs.campaign_phase == CampaignRules.PHASE_BOSS:
			break
		if cs.alive_enemies().size() > 0:
			_kill_wave(cs)
		if cs.alley_active() or cs.campaign_phase in [CampaignRules.PHASE_WALK_ALLEY, CampaignRules.PHASE_ALLEY, CampaignRules.PHASE_LEAVE_ALLEY]:
			assert_eq(cs.alive_enemies().size(), 0, "事件途中不刷下一波")
			assert_eq(cs.campaign_shops_this_floor, shops)
			kinds.append(cs.alley_kind)
			assert_true(cs.campaign_simulate_alley_skip())
			events += 1
			assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
			continue
		if cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.campaign_phase == CampaignRules.PHASE_SHOP or cs.shop_touch_pending:
			assert_eq(cs.alive_enemies().size(), 0)
			assert_true(cs.campaign_simulate_shop_cycle())
			shops += 1
			continue
		cs.campaign_try_advance()
	assert_eq(events, 3)
	assert_eq(shops, 3)
	assert_eq(cs.campaign_shops_this_floor, 3)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_gt(cs.alive_enemies().size(), 0)
	assert_false(cs.alley_active(), "第三店和首领之间不能再插随机事件")


func test_pool_selects_both_event_kinds_across_seeds() -> void:
	var seen := {}
	for s in range(47520, 47520 + 40):
		var kind: String = CampaignRules.roll_alley_event(RandomNumberGenerator.new())
		# use a seeded rng
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		kind = CampaignRules.roll_alley_event(rng)
		seen[kind] = true
	assert_true(seen.has(CampaignRules.ALLEY_GUMBALL), "池里应能随到糖果机")
	assert_true(seen.has(CampaignRules.ALLEY_TRASH), "池里应能随到垃圾桶")
	var w = CampaignRules.trash_outcome_weights()
	assert_almost_eq(w.x, 0.10, 0.0001)
	assert_almost_eq(w.y, 0.35, 0.0001)
	assert_almost_eq(w.z, 0.55, 0.0001)
	assert_eq(CampaignRules.trash_outcome_at(0.00), "bullet")
	assert_eq(CampaignRules.trash_outcome_at(0.05), "bullet")
	assert_eq(CampaignRules.trash_outcome_at(0.20), "gold")
	assert_eq(CampaignRules.trash_outcome_at(0.40), "gold")
	assert_eq(CampaignRules.trash_outcome_at(0.70), "xp")
	assert_eq(CampaignRules.gumball_price(), 5)
	assert_eq(CampaignRules.trash_gold_amount(), 8)


func test_gumball_affordable_one_use_persistent_and_doubletap() -> void:
	var cs := _boot_campaign(47530, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	assert_eq(cs.alley_kind, CampaignRules.ALLEY_GUMBALL)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_ALLEY)
	cs.gold = 12
	var bag0: int = cs.bag.size()
	var gold0: int = cs.gold
	assert_true(cs.alley_can_buy())
	assert_true(cs.alley_try_buy())
	assert_eq(cs.gold, gold0 - 5)
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.alley_award_kind, "bullet")
	assert_gt(cs.alley_awarded_id, 0)
	assert_true(DataRegistry.is_ammo_reward_eligible(cs.alley_awarded_id))
	assert_true(cs.alley_awarded_id in cs._combat_bag_baseline)
	# 第二次购买无效
	assert_false(cs.alley_try_buy())
	assert_eq(cs.gold, gold0 - 5)
	assert_eq(cs.bag.size(), bag0 + 1)
	# 跳过不会再发一次
	var aid: int = cs.alley_awarded_id
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs._combat_bag_baseline.count(aid), 1)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_wave, 2)
	assert_gt(cs.alive_enemies().size(), 0)


func test_gumball_poor_cannot_buy_skip_free() -> void:
	var cs := _boot_campaign(47531, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 3
	var bag0: int = cs.bag.size()
	assert_false(cs.alley_can_buy())
	assert_false(cs.alley_try_buy())
	assert_eq(cs.gold, 3)
	assert_eq(cs.bag.size(), bag0)
	assert_false(cs.alley_used)
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.gold, 3)
	assert_eq(cs.bag.size(), bag0)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_wave, 2)


func test_trash_branches_free_once_and_no_double_grant() -> void:
	# 子弹
	var cs := _boot_campaign(47540, true)
	cs.alley_force_kind = CampaignRules.ALLEY_TRASH
	cs.alley_force_trash_u = 0.05
	_kill_wave(cs)
	var bag0: int = cs.bag.size()
	var gold0: int = cs.gold
	assert_true(cs.alley_try_rummage())
	assert_eq(cs.gold, gold0, "翻找不扣钱")
	assert_eq(cs.alley_award_kind, "bullet")
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_false(cs.alley_try_rummage())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_true(cs.campaign_simulate_alley_skip())

	# 金币
	var cs2 := _boot_campaign(47541, true)
	cs2.alley_force_kind = CampaignRules.ALLEY_TRASH
	cs2.alley_force_trash_u = 0.20
	_kill_wave(cs2)
	var g0: int = cs2.gold
	var b0: int = cs2.bag.size()
	assert_true(cs2.alley_try_rummage())
	assert_eq(cs2.alley_award_kind, "gold")
	assert_eq(cs2.gold, g0 + CampaignRules.trash_gold_amount())
	assert_eq(cs2.bag.size(), b0)
	assert_false(cs2.alley_try_rummage())
	assert_eq(cs2.gold, g0 + CampaignRules.trash_gold_amount())

	# 经验：按本级门槛，足够排队一次升级
	var cs3 := _boot_campaign(47542, true)
	cs3.alley_force_kind = CampaignRules.ALLEY_TRASH
	cs3.alley_force_trash_u = 0.80
	_kill_wave(cs3)
	cs3.level = 1
	cs3.xp = 0
	var need: int = CampaignRules.trash_xp_amount(cs3.level)
	assert_eq(need, cs3.xp_needed())
	assert_true(cs3.alley_try_rummage())
	assert_eq(cs3.alley_award_kind, "xp")
	assert_eq(cs3.alley_award_amount, need)
	assert_eq(cs3.level, 2)
	assert_true(cs3.reward_pending or cs3.pending_levelups >= 0)
	assert_true(cs3.reward_pending)
	# 事件还不能离开
	assert_false(cs3.alley_skip())
	assert_eq(cs3.campaign_phase, CampaignRules.PHASE_ALLEY)
	assert_true(cs3.pick_reward_ammo(0) or cs3.skip_reward_for_gold())
	# 领完升级后才继续，且经验不会再发一次
	var lv: int = cs3.level
	assert_false(cs3.alley_try_rummage())
	assert_eq(cs3.level, lv)
	assert_true(cs3.campaign_simulate_alley_skip())
	assert_eq(cs3.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs3.campaign_wave, 2)
	assert_gt(cs3.alive_enemies().size(), 0)


func test_skip_does_not_stall_or_advance_twice() -> void:
	var cs := _boot_campaign(47550, true)
	cs.alley_force_kind = CampaignRules.ALLEY_TRASH
	_kill_wave(cs)
	assert_eq(cs.campaign_wave, 1)
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.campaign_wave, 2)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	# 再 skip 不应把波次再加一次
	assert_false(cs.campaign_simulate_alley_skip())
	assert_eq(cs.campaign_wave, 2)


func test_pending_impact_and_enemies_block_event() -> void:
	var cs := _boot_campaign(47560, true)
	assert_gt(cs.alive_enemies().size(), 0)
	cs.campaign_try_advance()
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_false(cs.alley_active())
	cs.enemies.clear()
	cs._volley_pending = true
	assert_false(cs.campaign_field_safe())
	cs.campaign_try_advance()
	assert_false(cs.alley_active())
	cs._volley_pending = false
	cs.campaign_try_advance()
	assert_true(cs.alley_active() or cs.campaign_phase == CampaignRules.PHASE_ALLEY or cs.campaign_phase == CampaignRules.PHASE_WALK_ALLEY)


func test_death_and_restart_clear_event_and_bag() -> void:
	var cs := _boot_campaign(47570, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 20
	assert_true(cs.alley_try_buy())
	var awarded: int = cs.alley_awarded_id
	assert_gt(awarded, 0)
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_false(cs.alley_active())
	assert_false(cs.alley_hold)
	cs.start_campaign(47571)
	assert_eq(cs.bag.size(), CampaignRules.opening_white_count())
	assert_eq(cs.bag.count(CombatConstants.WHITE_AMMO_ID), 5)
	assert_false(cs.alley_active())
	assert_eq(cs.gold, 0)


func test_machine_starts_offscreen_and_moves_monotonically() -> void:
	var cs := _boot_campaign(47580, false)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	cs.enemies.clear()
	cs.campaign_try_advance()
	assert_eq(cs.alley_seq, CombatState.ALLEY_APPROACH)
	var cat_x := 80.0
	var left: float = cs.alley_left_at(cat_x)
	var view_r: float = CampaignRules.shop_house_view_width()
	assert_gt(left - CampaignRules.alley_visual_pad(cs.alley_kind), view_r - 0.5)
	var dt := 1.0 / 30.0
	var prev: float = left
	var max_step: float = CampaignRules.shop_walk_speed_px() * dt + 1.5
	var steps := 0
	while cs.alley_seq == CombatState.ALLEY_APPROACH:
		cs.tick_alley(dt)
		var now: float = cs.alley_left_at(cat_x)
		assert_lt(now, prev + 0.001)
		assert_gt(now, prev - max_step)
		prev = now
		steps += 1
		if steps > 400:
			assert_true(false, "gumball approach did not finish")
			return
	assert_gt(steps, 20)
	assert_eq(cs.alley_seq, CombatState.ALLEY_HOLD)
	assert_eq(cs.alive_enemies().size(), 0)
	cs.campaign_simulate_alley_skip()
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_gt(cs.alive_enemies().size(), 0)


func test_bag_flat_cool_gray_and_interior_mask_helpers() -> void:
	assert_lt(BagPhysicsBox.SACK_OUTER.r, 0.55)
	assert_gt(BagPhysicsBox.SACK_OUTER.b, BagPhysicsBox.SACK_OUTER.r)
	assert_gt(BagPhysicsBox.SACK_INTERIOR.r, 0.65)
	assert_lt(BagPhysicsBox.SACK_BALL_MASK.r, 0.40)
	# 浅灰底明显亮于深灰球
	assert_gt(BagPhysicsBox.SACK_INTERIOR.r, BagPhysicsBox.SACK_BALL_MASK.r + 0.25)
	var src := FileAccess.get_file_as_string("res://scripts/combat/bag_physics_box.gd")
	assert_false("0.83, 0.65, 0.43" in src)
	assert_false("leather_l" in src)
	assert_true("SACK_INTERIOR" in src)
	var box := BagPhysicsBox.new()
	box.size = Vector2(240, 240)
	add_child_autofree(box)
	box.reset_pour_pose()
	# 袋心应在碰撞区内，袋口上方应在区外
	var mid: Vector2 = Vector2(120, 140)
	assert_true(box._point_in_sack_interior(mid))
	var above_mouth: Vector2 = Vector2(120, 8)
	assert_false(box._point_in_sack_interior(above_mouth))


func test_rush_and_sandbox_do_not_start_alley() -> void:
	var rush := CombatState.new()
	rush.start_rush(21)
	rush.enemies.clear()
	rush.campaign_try_advance()
	assert_false(rush.alley_active())
	assert_false(rush.campaign_mode)
	var box := CombatState.new()
	box.start_sandbox(21, FireResolver.ID_WRATH, true)
	box.enemies.clear()
	box.campaign_try_advance()
	assert_false(box.alley_active())
