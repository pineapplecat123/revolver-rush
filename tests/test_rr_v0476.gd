extends GutTest
## v0.4.76：糖果机特写，出球口与掉落区不被挡住；袋内同款圆球从出球口物理下落弹跳。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func _boot_campaign(seed_v: int = 47601, instant: bool = true) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_campaign(seed_v)
	cs.campaign_instant_transitions = instant
	if cs.campaign_offer_pending:
		assert_true(cs.campaign_pick_opening(0))
	if cs.campaign_phase == CampaignRules.PHASE_ENTER:
		cs.campaign_skip_walk()
	return cs


func _kill_wave(cs: CombatState) -> void:
	# Reach one event/shop node (three cleared combat waves as of v0.4.88).
	for i in CombatState.COMBAT_WAVES_PER_NODE:
		cs.enemies.clear()
		cs.reward_pending = false
		cs.pending_levelups = 0
		cs.campaign_try_advance()


func _make_closeup() -> GumballCloseup:
	var cu := GumballCloseup.new()
	cu.custom_minimum_size = Vector2(720, 1280)
	cu.size = Vector2(720, 1280)
	add_child_autofree(cu)
	cu.present()
	cu._apply_layout()
	return cu


func test_version_is_at_least_0_4_76() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.76") >= 0)
	assert_true("0.4.76" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_closeup_layout_outlet_and_drop_unobstructed() -> void:
	var cu := _make_closeup()
	assert_eq(cu.size, Vector2(720, 1280))
	var outlet: Vector2 = cu.outlet_point()
	var drop: Rect2 = cu.drop_bounds()
	var floor_y: float = cu.floor_y()
	assert_almost_eq(outlet.x, cu.machine_rect().get_center().x, 3.0)
	assert_almost_eq(outlet.x, 360.0, 8.0)
	assert_gt(outlet.x, 200.0)
	assert_lt(outlet.x, 520.0)
	assert_gt(outlet.y, 400.0)
	assert_lt(outlet.y, floor_y - 160.0)
	assert_gt(drop.size.y, 160.0)
	assert_true(drop.has_point(Vector2(outlet.x, outlet.y + 8.0)))
	assert_almost_eq(drop.end.y, floor_y + cu.ball_radius() + 8.0, 2.0)
	assert_true(cu.is_outlet_unobstructed(), "出球口不能被标题或按钮挡住")
	assert_true(cu.is_drop_region_unobstructed(), "掉落区不能被面板或按钮挡住")
	for b in cu.ui_block_rects():
		var r: Rect2 = b
		assert_false(r.has_point(outlet), "交互块碰到了出球口")
		# 掉落区内任取中线若干点都不应落在按钮/标题里
		for k in 8:
			var y: float = drop.position.y + drop.size.y * (0.1 + 0.1 * float(k))
			assert_false(r.has_point(Vector2(outlet.x, y)), "交互块切到掉落路径")
	# 按钮在托盘下方
	var actions: Rect2 = cu.actions_rect()
	assert_gt(actions.position.y, floor_y + 80.0)
	# 标题在机器顶上方或机器顶附近，但不盖出球口
	var chrome: Rect2 = cu.chrome_rect()
	assert_lt(chrome.end.y, outlet.y - 80.0)


func test_drop_physics_shares_bag_constants() -> void:
	assert_eq(GumballCloseup.GRAVITY, BagPhysicsBox.GRAVITY)
	assert_eq(GumballCloseup.RESTITUTION, BagPhysicsBox.RESTITUTION)
	# 出球口物理下落/弹跳的完整路径改由 v0.4.77 用罩内真实球覆盖。


func test_one_grant_one_charge_doubletap_and_collect() -> void:
	var cs := _boot_campaign(47610, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 20
	var bag0: int = cs.bag.size()
	var gold0: int = cs.gold
	assert_true(cs.alley_try_buy())
	assert_eq(cs.gold, gold0 - 5)
	assert_eq(cs.bag.size(), bag0)
	assert_eq(cs.alley_awarded_id, 0)
	assert_false(cs.alley_has_pending_grant())
	var aid: int = CampaignRules.roll_alley_ammo(cs.rng)
	assert_true(cs.alley_note_dispensed(aid))
	assert_true(cs.alley_has_pending_grant())
	assert_false(cs.alley_try_buy())
	assert_eq(cs.gold, gold0 - 5)
	assert_eq(cs.bag.size(), bag0)
	assert_true(cs.alley_collect_award())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.bag.count(aid), 1)
	assert_true(aid in cs._combat_bag_baseline)
	assert_false(cs.alley_has_pending_grant())
	assert_false(cs.alley_collect_award())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.gold, gold0 - 5)
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	assert_eq(cs.campaign_wave, 2)
	assert_gt(cs.alive_enemies().size(), 0)


func test_skip_and_poor_stay_valid() -> void:
	var poor := _boot_campaign(47620, true)
	poor.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(poor)
	poor.gold = 3
	var bag0: int = poor.bag.size()
	assert_false(poor.alley_can_buy())
	assert_false(poor.alley_try_buy())
	assert_eq(poor.gold, 3)
	assert_eq(poor.bag.size(), bag0)
	assert_false(poor.alley_used)
	assert_false(poor.alley_has_pending_grant())
	assert_true(poor.campaign_simulate_alley_skip())
	assert_eq(poor.gold, 3)
	assert_eq(poor.bag.size(), bag0)
	assert_eq(poor.campaign_phase, CampaignRules.PHASE_COMBAT)

	var skip := _boot_campaign(47621, true)
	skip.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(skip)
	skip.gold = 20
	var b1: int = skip.bag.size()
	assert_true(skip.campaign_simulate_alley_skip())
	assert_eq(skip.gold, 20)
	assert_eq(skip.bag.size(), b1)
	assert_eq(skip.campaign_wave, 2)


func test_skip_after_buy_grants_once_and_does_not_stall() -> void:
	var cs := _boot_campaign(47622, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 15
	var bag0: int = cs.bag.size()
	assert_true(cs.alley_try_buy())
	assert_eq(cs.bag.size(), bag0)
	assert_false(cs.alley_can_leave(), "球还没出来不能离开")
	var aid: int = CampaignRules.roll_alley_ammo(cs.rng)
	assert_true(cs.alley_note_dispensed(aid))
	# 模拟离开会先发奖再进下一波，不会卡死或连进两波
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.campaign_wave, 2)
	assert_false(cs.campaign_simulate_alley_skip())
	assert_eq(cs.campaign_wave, 2)
	assert_eq(cs.bag.size(), bag0 + 1)


func test_cleanup_restart_and_next_wave() -> void:
	var cs := _boot_campaign(47630, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 20
	assert_true(cs.alley_try_buy())
	assert_true(cs.alley_used)
	assert_eq(cs.alley_awarded_id, 0)
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_false(cs.alley_active())
	assert_false(cs.alley_hold)
	assert_false(cs.alley_has_pending_grant())
	cs.start_campaign(47631)
	assert_eq(cs.bag.size(), CampaignRules.opening_white_count())
	assert_eq(cs.bag.count(CombatConstants.WHITE_AMMO_ID), 5)
	assert_false(cs.alley_active())
	assert_eq(cs.gold, 0)
	# 特写节点在关闭后不应留下活动球
	var cu := _make_closeup()
	cu.begin_session_with_ids([CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID])
	assert_gt(cu.ball_count(), 0)
	cu.close()
	assert_false(cu.visible)
	assert_false(cu.is_ball_active())
	assert_eq(cu.ball_count(), 0)
	assert_eq(cu.bounce_count(), 0)


func test_cadence_and_event_pool_unchanged() -> void:
	assert_eq(CampaignRules.floor_count(), 9)
	assert_eq(CampaignRules.gumball_price(), 5)
	assert_eq(CampaignRules.trash_gold_amount(), 8)
	assert_eq(CampaignRules.trash_outcome_at(0.05), "bullet")
	assert_eq(CampaignRules.trash_outcome_at(0.20), "gold")
	assert_eq(CampaignRules.trash_outcome_at(0.70), "xp")
	var cs := _boot_campaign(47640, true)
	var events := 0
	var shops := 0
	var guard := 40
	while shops < 3 and guard > 0:
		guard -= 1
		if cs.campaign_phase == CampaignRules.PHASE_BOSS:
			break
		if cs.alive_enemies().size() > 0:
			_kill_wave(cs)
		if cs.alley_active() or cs.campaign_phase in [CampaignRules.PHASE_WALK_ALLEY, CampaignRules.PHASE_ALLEY, CampaignRules.PHASE_LEAVE_ALLEY]:
			assert_true(cs.campaign_simulate_alley_skip())
			events += 1
			continue
		if cs.campaign_phase == CampaignRules.PHASE_WALK_SHOP or cs.campaign_phase == CampaignRules.PHASE_SHOP or cs.shop_touch_pending:
			assert_true(cs.campaign_simulate_shop_cycle())
			shops += 1
			continue
		cs.campaign_try_advance()
	assert_eq(events, 3)
	assert_eq(shops, 3)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_false(cs.alley_active())
