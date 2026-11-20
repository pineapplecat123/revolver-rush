extends GutTest
## v0.4.77：糖果机特写罩内是真实物理球；玩家拉杆到头才扣费，掉出的是罩里那一发。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func _boot_campaign(seed_v: int = 47701, instant: bool = true) -> CombatState:
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


func _make_closeup() -> GumballCloseup:
	var cu := GumballCloseup.new()
	cu.custom_minimum_size = Vector2(720, 1280)
	cu.size = Vector2(720, 1280)
	add_child_autofree(cu)
	cu.present()
	cu._apply_layout()
	return cu


func _ids() -> Array:
	return [
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.QISHI_AMMO_ID,
		CombatConstants.JIASU_AMMO_ID,
		CombatConstants.DIESHI_AMMO_ID,
		CombatConstants.CHUANDI_AMMO_ID,
		CombatConstants.XULI_AMMO_ID,
		CombatConstants.WEIZHONG_AMMO_ID,
		CombatConstants.BAOCHUAN_AMMO_ID,
		CombatConstants.DIZENG_AMMO_ID,
		CombatConstants.CHETUI_AMMO_ID,
		CombatConstants.MOFANG_AMMO_ID,
		CombatConstants.HUIWEI_AMMO_ID,
	]


func _tick_until(cu: GumballCloseup, pred: Callable, max_sec: float = 6.0) -> int:
	var dt := 1.0 / 30.0
	var steps := 0
	var limit: int = int(max_sec * 30.0)
	while steps < limit and not pred.call():
		cu.tick(dt)
		steps += 1
	return steps


func _settle_hopper(cu: GumballCloseup) -> int:
	return _tick_until(cu, func() -> bool: return cu.is_hopper_settled(), 5.0)


func _commit_stroke(cu: GumballCloseup) -> bool:
	var got := [false]
	if not cu.lever_commit_requested.is_connected(_noop_commit):
		pass
	var cb := func() -> void:
		got[0] = true
		cu.accept_commit()
	cu.lever_commit_requested.connect(cb, CONNECT_ONE_SHOT)
	cu.set_can_commit(true, false)
	cu.simulate_full_stroke()
	return got[0]


func _noop_commit() -> void:
	pass


func test_version_is_at_least_0_4_77() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.77") >= 0)
	assert_true("0.4.77" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("拉杆" in FileAccess.get_file_as_string("res://data/changelog.json") or "下拉" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_layout_unobstructed_buy_hidden_lever_ready() -> void:
	var cu := _make_closeup()
	assert_true(cu.is_outlet_unobstructed())
	assert_true(cu.is_drop_region_unobstructed())
	assert_almost_eq(cu.outlet_point().x, 360.0, 8.0)
	assert_eq(GumballCloseup.GRAVITY, BagPhysicsBox.GRAVITY)
	assert_eq(GumballCloseup.RESTITUTION, BagPhysicsBox.RESTITUTION)
	cu.set_copy("糖果机", "金币：20", "向下拉杆", "", "投币购买（5金）", true, true, "离开", true)
	assert_false(cu._use_btn.visible, "购买按钮应隐藏，只能拉拉杆")
	assert_gt(cu.lever_grab_rect().size.x, 40.0)
	assert_gt(cu.lever_grab_rect().size.y, 80.0)
	assert_gt(cu.globe_radius(), cu.ball_radius() * 3.5)


func test_each_hopper_ball_is_simulated_and_settles() -> void:
	var cu := _make_closeup()
	var ids: Array = _ids()
	cu.begin_session_with_ids(ids)
	assert_eq(cu.ball_count(), ids.size())
	assert_eq(cu.hopper_count(), ids.size())
	assert_eq(cu.tray_count(), 0)
	var pos0: Array = []
	for b in cu._balls:
		pos0.append(Vector2(b["pos"]))
		assert_false(bool(b["asleep"]))
	# 第一步就该受重力
	cu.tick(1.0 / 30.0)
	var moved := 0
	for i in cu._balls.size():
		var p: Vector2 = cu._balls[i]["pos"]
		if p.y > pos0[i].y + 0.05:
			moved += 1
		# 还在罩或颈部，没有瞬移到托盘
		assert_lt(p.y, cu.outlet_point().y - 4.0)
	assert_gte(moved, 4, "应有若干球被重力拉动")
	var steps: int = _settle_hopper(cu)
	assert_true(cu.is_hopper_settled(), "罩里的球应在几秒内停住，steps=%d" % steps)
	assert_eq(cu.hopper_count(), ids.size())
	assert_eq(cu.tray_count(), 0)
	# 球与球不再严重重叠
	var r: float = cu.ball_radius()
	for i in cu._balls.size():
		for j in range(i + 1, cu._balls.size()):
			var d: float = (cu._balls[i]["pos"] as Vector2).distance_to(cu._balls[j]["pos"])
			assert_gt(d, r * 1.35, "静置后球不应严重重叠")
		# 种类色，不是袋内深灰遮罩
		var fill: Color = cu._balls[i]["fill"]
		assert_false(fill.is_equal_approx(BagPhysicsBox.SACK_BALL_MASK), "罩外球应保留种类色")


func test_contacts_and_reflow_when_agitated() -> void:
	var cu := _make_closeup()
	cu.begin_session_with_ids(_ids())
	_settle_hopper(cu)
	var pos0: Array = []
	for b in cu._balls:
		pos0.append(Vector2(b["pos"]))
	cu._agitating = true
	cu._agitate_age = 0.0
	cu._wake_all()
	for _i in 12:
		cu.tick(1.0 / 30.0)
	var moved := 0
	for i in cu._balls.size():
		if (cu._balls[i]["pos"] as Vector2).distance_to(pos0[i]) > 0.4:
			moved += 1
	assert_false(cu.is_hopper_settled(), "扰动时应重新活动")
	assert_gte(moved, 2, "扰动后应看见球重新挤动")
	assert_eq(cu.tray_count(), 0, "没开闸时不应掉到托盘")
	cu._agitating = false
	_settle_hopper(cu)
	assert_true(cu.is_hopper_settled())
	assert_eq(cu.tray_count(), 0)


func test_identity_conserved_n_to_n_minus_one_plus_outlet() -> void:
	var cu := _make_closeup()
	var ids: Array = _ids()
	cu.begin_session_with_ids(ids)
	_settle_hopper(cu)
	var start: Array = cu.all_ball_ids()
	start.sort()
	assert_eq(start.size(), ids.size())
	assert_true(_commit_stroke(cu))
	var steps: int = _tick_until(cu, func() -> bool: return cu.ball_ammo_id() != 0 and cu.tray_count() == 1, 8.0)
	assert_eq(cu.ball_ammo_id() != 0, true, "应有一发从出球口出来")
	assert_eq(cu.tray_count(), 1)
	assert_eq(cu.hopper_count(), ids.size() - 1)
	assert_eq(cu.ball_count(), ids.size())
	var after: Array = cu.all_ball_ids()
	after.sort()
	assert_eq(after, start, "球的身份集合不变")
	var tray: Array = cu.tray_ids()
	assert_eq(tray.size(), 1)
	assert_true(int(tray[0]) in ids)
	assert_eq(cu.ball_ammo_id(), int(tray[0]))
	assert_false(int(tray[0]) in cu.hopper_ids())
	assert_gt(steps, 4, "出球应经过可看见的滑道，而不是瞬移")
	# 等它落到托盘停住
	_tick_until(cu, func() -> bool: return cu.is_drop_settled(), 5.0)
	assert_true(cu.has_contacted_floor())
	assert_gte(cu.bounce_count(), 1)
	assert_true(cu.can_collect())
	assert_lte(cu.ball_pos().y + cu.ball_radius(), cu.floor_y() + 0.8)


func test_one_lever_stroke_one_ball_across_seeds() -> void:
	var failures: Array = []
	for s in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = 47700 + s
		var cu := _make_closeup()
		cu.begin_session(rng, GumballCloseup.HOPPER_COUNT)
		_settle_hopper(cu)
		var n0: int = cu.hopper_count()
		assert_eq(n0, GumballCloseup.HOPPER_COUNT)
		assert_true(_commit_stroke(cu))
		_tick_until(cu, func() -> bool: return cu.tray_count() >= 1, 8.0)
		var tray_n: int = cu.tray_count()
		var hop_n: int = cu.hopper_count()
		if tray_n != 1 or hop_n != n0 - 1 or cu.ball_ammo_id() <= 0:
			failures.append("seed=%d tray=%d hopper=%d id=%d" % [s, tray_n, hop_n, cu.ball_ammo_id()])
		# 再拖一次不应再出球（已用过）
		cu.set_can_commit(false, true)
		var extra := [0]
		cu.ball_dispensed.connect(func(_a: int) -> void: extra[0] += 1)
		cu.simulate_full_stroke()
		for _i in 20:
			cu.tick(1.0 / 30.0)
		if extra[0] != 0 or cu.tray_count() != 1:
			failures.append("seed=%d double tray=%d extra=%d" % [s, cu.tray_count(), extra[0]])
		cu.close()
	assert_eq(failures, [], "每种种子都应刚好出一发，不能空或双出：%s" % str(failures))


func test_partial_pull_resets_without_charge_or_dispense() -> void:
	var cu := _make_closeup()
	cu.begin_session_with_ids(_ids())
	_settle_hopper(cu)
	cu.set_can_commit(true, false)
	var requested := [false]
	cu.lever_commit_requested.connect(func() -> void: requested[0] = true)
	cu.simulate_partial_stroke(0.5)
	assert_gte(cu.lever_pull(), 0.3)
	assert_lt(cu.lever_pull(), GumballCloseup.COMMIT_PULL)
	assert_false(requested[0])
	# 松手后弹回
	for _i in 40:
		cu.tick(1.0 / 30.0)
	assert_lt(cu.lever_pull(), 0.08)
	assert_eq(cu.tray_count(), 0)
	assert_eq(cu.hopper_count(), _ids().size())
	assert_false(cu.is_commit_accepted())


func test_poor_and_skip_before_commit_are_free() -> void:
	var poor := _boot_campaign(47720, true)
	poor.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(poor)
	poor.gold = 3
	var bag0: int = poor.bag.size()
	assert_false(poor.alley_can_buy())
	assert_false(poor.alley_commit_pull())
	assert_eq(poor.gold, 3)
	assert_eq(poor.bag.size(), bag0)
	assert_true(poor.campaign_simulate_alley_skip())
	assert_eq(poor.gold, 3)
	assert_eq(poor.bag.size(), bag0)

	var skip := _boot_campaign(47721, true)
	skip.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(skip)
	skip.gold = 20
	var b1: int = skip.bag.size()
	assert_true(skip.campaign_simulate_alley_skip())
	assert_eq(skip.gold, 20)
	assert_eq(skip.bag.size(), b1)
	assert_eq(skip.campaign_wave, 2)

	# 拉杆在付不起时也不应提交
	var cu := _make_closeup()
	cu.begin_session_with_ids(_ids())
	cu.set_can_commit(false, false)
	var got := [false]
	cu.lever_commit_requested.connect(func() -> void: got[0] = true)
	cu.simulate_full_stroke()
	assert_false(got[0])
	assert_false(cu.is_commit_accepted())


func test_commit_then_identity_grant_pending_and_no_leave_until_dispensed() -> void:
	var cs := _boot_campaign(47730, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 20
	var bag0: int = cs.bag.size()
	var gold0: int = cs.gold
	var cu := _make_closeup()
	cu.begin_session_with_ids(_ids())
	_settle_hopper(cu)
	var committed := [false]
	cu.lever_commit_requested.connect(func() -> void:
		committed[0] = true
		assert_true(cs.alley_commit_pull())
		cu.accept_commit()
	)
	cu.set_can_commit(true, false)
	cu.simulate_full_stroke()
	assert_true(committed[0])
	assert_eq(cs.gold, gold0 - 5)
	assert_true(cs.alley_used)
	assert_eq(cs.alley_awarded_id, 0)
	assert_false(cs.alley_has_pending_grant())
	assert_false(cs.alley_can_leave())
	assert_false(cs.campaign_simulate_alley_skip())
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_ALLEY)
	_tick_until(cu, func() -> bool: return cu.ball_ammo_id() != 0, 8.0)
	var aid: int = cu.ball_ammo_id()
	assert_gt(aid, 0)
	assert_true(int(aid) in _ids())
	assert_true(cs.alley_note_dispensed(aid))
	assert_eq(cs.alley_awarded_id, aid)
	assert_true(cs.alley_has_pending_grant())
	assert_eq(cs.bag.size(), bag0)
	# 球还没停稳时收集接口为假；记奖后可以在状态层发奖，但 UI 要等停稳
	_tick_until(cu, func() -> bool: return cu.can_collect(), 5.0)
	assert_true(cu.can_collect())
	assert_true(cs.alley_collect_award())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.bag.count(aid), cs.bag.count(aid))
	assert_true(aid in cs._combat_bag_baseline)
	assert_false(cs.alley_collect_award())
	assert_eq(cs.gold, gold0 - 5)
	assert_true(cs.campaign_simulate_alley_skip())
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.campaign_wave, 2)


func test_pointer_release_outside_second_touch_resize_cleanup() -> void:
	var cu := _make_closeup()
	cu.begin_session_with_ids(_ids())
	cu.set_can_commit(true, false)
	var requested := [false]
	cu.lever_commit_requested.connect(func() -> void: requested[0] = true)
	var a: Vector2 = cu.lever_rest_pos()
	cu.simulate_pointer_down(a)
	cu.simulate_pointer_move(a.lerp(cu.lever_pulled_pos(), 0.4))
	# 第二根手指按下应被忽略
	var ev := InputEventScreenTouch.new()
	ev.index = 1
	ev.pressed = true
	ev.position = cu.lever_pulled_pos()
	cu.handle_pointer(ev)
	assert_lt(cu.lever_pull(), GumballCloseup.COMMIT_PULL)
	# 在控件外松开：应取消，不扣费
	cu.simulate_pointer_up(Vector2(-40, 2000))
	assert_false(requested[0])
	assert_false(cu.is_commit_accepted())
	for _i in 30:
		cu.tick(1.0 / 30.0)
	assert_lt(cu.lever_pull(), 0.1)
	# 缩放时未提交的拖动取消
	cu.simulate_pointer_down(cu.lever_rest_pos())
	cu.simulate_pointer_move(cu.lever_rest_pos().lerp(cu.lever_pulled_pos(), 0.3))
	assert_true(cu._dragging)
	cu.apply_simulated_resize(Vector2(540, 960))
	assert_false(cu._dragging)
	cu.apply_simulated_resize(Vector2(720, 1280))
	cu.close()
	assert_false(cu.visible)
	assert_eq(cu.ball_count(), 0)
	assert_false(cu.has_session())


func test_death_restart_clears_pending_and_bag() -> void:
	var cs := _boot_campaign(47740, true)
	cs.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_kill_wave(cs)
	cs.gold = 20
	assert_true(cs.alley_commit_pull())
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_false(cs.alley_active())
	assert_false(cs.alley_hold)
	assert_false(cs.alley_has_pending_grant())
	cs.start_campaign(47741)
	assert_eq(cs.bag.size(), CampaignRules.opening_white_count())
	assert_eq(cs.bag.count(CombatConstants.WHITE_AMMO_ID), 5)
	assert_false(cs.alley_active())
	assert_eq(cs.gold, 0)


func test_cadence_and_event_pool_unchanged() -> void:
	assert_eq(CampaignRules.floor_count(), 9)
	assert_eq(CampaignRules.gumball_price(), 5)
	assert_eq(CampaignRules.trash_gold_amount(), 8)
	assert_eq(CampaignRules.trash_outcome_at(0.05), "bullet")
	assert_eq(CampaignRules.trash_outcome_at(0.20), "gold")
	assert_eq(CampaignRules.trash_outcome_at(0.70), "xp")
	var pool: Array = CampaignRules.alley_reward_pool()
	assert_gt(pool.size(), 3)
	var cs := _boot_campaign(47750, true)
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
