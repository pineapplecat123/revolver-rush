extends GutTest
## v0.4.91：弹药数量上限 30、传递弹加强量改写、倒出/糖果物理、进屏即可命中。

const WHITE := CombatConstants.WHITE_AMMO_ID
const CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const ShopState = preload("res://scripts/shop/shop_state.gd")

func before_each() -> void:
	DataRegistry.reload()


func test_version_is_0_4_91() -> void:
	assert_eq(GameVersion.STRING, "0.4.91")


func _fill_to_cap(cs: CombatState) -> void:
	while cs.owned_live_ammo_count() < CombatConstants.OWNED_AMMO_CAP:
		assert_true(cs.try_gain_to_bag(WHITE, false))


func test_owned_ammo_cap_refuses_new_grants_but_allows_moves() -> void:
	var cs := CombatState.new(49101)
	cs.start_rush(49101)
	assert_false(cs.sandbox_mode)
	assert_true(cs.ammo_cap_applies())
	assert_eq(cs.owned_live_ammo_count(), cs.bag.size())
	_fill_to_cap(cs)
	assert_eq(cs.owned_live_ammo_count(), 30)
	assert_false(cs.can_gain_ammo(1))
	var bag_before: int = cs.bag.size()
	assert_false(cs.try_gain_to_bag(WHITE, false))
	assert_eq(cs.bag.size(), bag_before, "满时拒收，不删已有弹药")
	# 搬运：倒出、退回、装填都不创造新弹，满时仍可用。
	var moved: int = cs.dump_to_hand()
	assert_gt(moved, 0)
	assert_eq(cs.owned_live_ammo_count(), 30)
	assert_eq(cs.bag.size() + cs.hand.size(), 30)
	var back: int = cs.return_hand_to_bag()
	assert_eq(back, moved)
	assert_eq(cs.owned_live_ammo_count(), 30)
	assert_eq(cs.hand.size(), 0)


func test_shop_and_reward_and_candy_do_not_charge_when_full() -> void:
	var cs := CombatState.new(49102)
	cs.start_rush(49102)
	cs.gold = 99
	_fill_to_cap(cs)
	var shop := ShopState.new()
	var held: int = cs.owned_live_ammo_count() - cs.bag.size()
	shop.begin(cs.gold, cs.bag.duplicate(), 1, 49102, [], held, CombatConstants.OWNED_AMMO_CAP)
	assert_false(shop.can_buy(0))
	var gold_before: int = shop.gold
	var bag_before: int = shop.bag.size()
	assert_false(shop.buy(0))
	assert_eq(shop.gold, gold_before)
	assert_eq(shop.bag.size(), bag_before)
	assert_true(shop.last_message.contains("弹药已满"))
	# 奖励：拒收且不结束三选一。
	cs.reward_pending = true
	cs.reward_resolved = false
	cs.reward_choices = [WHITE, WHITE, WHITE]
	assert_true(cs.can_pick_reward())
	assert_false(cs.pick_reward_ammo(0))
	assert_true(cs.reward_pending)
	assert_eq(cs.owned_live_ammo_count(), 30)
	# 糖果机：拉杆前就拒绝，不扣金币。
	cs.alley_seq = cs.ALLEY_HOLD
	cs.alley_kind = CampaignRules.ALLEY_GUMBALL
	cs.alley_hold = true
	cs.alley_used = false
	assert_false(cs.alley_can_buy())
	assert_false(cs.alley_commit_pull())
	assert_eq(cs.gold, 99)
	assert_false(cs.alley_used)


func test_sandbox_stays_uncapped() -> void:
	var cs := CombatState.new(49103)
	cs.start_sandbox(49103)
	assert_true(cs.sandbox_mode)
	assert_false(cs.ammo_cap_applies())
	for _i in 40:
		cs.sandbox_add_ammo(WHITE, 1)
	assert_gt(cs.owned_live_ammo_count(), CombatConstants.OWNED_AMMO_CAP)
	assert_true(cs.can_gain_ammo(1))


func test_chuandi_grants_one_flame_with_potency_equal_to_actual_minus_base() -> void:
	# 预计 5，基础 3 → 一个加强量 2 的火焰，不是 2 层 +1。
	var planned := FireResolver.compute_volley_details(
		[CHUANDI, WHITE], [], [],
		[{"id": "m", "effect_kind": "damage_mult", "remaining": 1, "effect_per_stack": 1.5}]
	)
	assert_eq(FireResolver.round_damage(float(planned["damages"][0])), 5)
	var f0: Dictionary = planned["after"][0][0]
	assert_eq(str(f0.get("id", "")), "chuandi")
	assert_eq(int(f0["remaining"]), 1)
	assert_eq(float(f0["amount"]), 2.0)
	assert_eq(float(planned["damages"][1]), 5.0)  # 3+2
	# 有实际伤害时用实际：12−3=9，仍只一层。
	var settled := FireResolver.compute_volley_details(
		[CHUANDI, WHITE], [], [12],
		[{"id": "m", "effect_kind": "damage_mult", "remaining": 1, "effect_per_stack": 1.5}]
	)
	assert_eq(int(settled["after"][0][0]["remaining"]), 1)
	assert_eq(float(settled["after"][0][0]["amount"]), 9.0)
	# 没消耗火焰就不生成。
	var plain := FireResolver.compute_volley_details([CHUANDI, WHITE])
	assert_true(plain["after"][0].filter(func(f): return str(f.get("id", "")) == "chuandi").is_empty())
	assert_eq(int(plain["damages"][1]), 3)
	# 巨大加强量不被 99 层上限截成层数；加强量就是差值本身。
	var huge := FireResolver.compute_volley_details(
		[CHUANDI], [], [8748],
		[{"id": "m", "effect_kind": "damage_mult", "remaining": 3, "effect_per_stack": 1.5}]
	)
	var granted: Array = huge["after"][0].filter(func(f): return str(f.get("id", "")) == "chuandi")
	assert_eq(granted.size(), 1)
	assert_eq(int(granted[0]["remaining"]), 1)
	assert_eq(float(granted[0]["amount"]), 8745.0)
	# 文案与枪口说明跟新规则一致。
	var def: Dictionary = DataRegistry.get_ammo(CHUANDI)
	assert_true(str(def.get("special", "")).contains("只生成一个"))
	assert_true(str(def.get("special", "")).contains("枪口"))
	assert_true(str(def.get("game_description", "")).contains("加强量"))
	assert_eq(DataRegistry.format_muzzle_status_effect(granted[0]), "加强量 +8745")


func test_second_pour_catch_bodies_keep_position_and_collide() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	box.sync_ammo_ids([WHITE, WHITE])
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.pour_cap = 2
	box.mark_pour_balls(2)
	box.mouth_open = true
	box.impulse_pour_balls()
	for _j in 300:
		box._physics_process(1.0 / 60.0)
		if box.fallen_count() >= 2:
			box.mouth_open = false
	box.mouth_open = false
	for _k in 60:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 2)
	assert_eq(box.promote_exited_to_catch_bodies(), 2)
	var first_pos: Array = []
	for rec in box.catch_body_records():
		first_pos.append(rec["pos"])
	# 补第二批进仍倒扣的袋子，已入手的球必须还在手区原位。
	box.sync_ammo_ids([WHITE, WHITE, WHITE, WHITE])
	assert_eq(box.catch_body_count(), 2)
	assert_eq(box.bag_body_count(), 4)
	var after_sync: Array = []
	for rec2 in box.catch_body_records():
		after_sync.append(rec2["pos"])
	for i in first_pos.size():
		assert_lt(first_pos[i].distance_to(after_sync[i]), 2.0, "sync must not teleport the first pile")
		assert_false(box._point_in_sack_interior(after_sync[i]), "first pile stays in the catcher, not reset into the sack")
	box.pour_cap = 4
	box.mark_pour_balls(4)
	assert_eq(box.catch_body_count(), 2, "mark_pour_balls must not demote catch bodies")
	box.mouth_open = true
	box.impulse_pour_balls()
	for _m in 360:
		box._physics_process(1.0 / 60.0)
		if box.fallen_count() >= 4:
			box.mouth_open = false
	box.mouth_open = false
	for _n in 90:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 4)
	assert_eq(box.catch_body_count(), 2)
	var final_catch: Array = box.catch_body_records()
	for rec3 in final_catch:
		var p: Vector2 = rec3["pos"]
		assert_false(box._point_in_sack_interior(p), "first pile must keep its catcher position after the second pour")
		assert_true(box.hand_catch_rect.grow(16.0).has_point(p))
	# 第二批落地后应与第一堆分离（碰撞把重叠弹开），且两批都在手区。
	box.promote_exited_to_catch_bodies()
	assert_eq(box.catch_body_count(), 6)
	var recs: Array = box.catch_body_records()
	for a in recs.size():
		assert_true(box.hand_catch_rect.grow(16.0).has_point(recs[a]["pos"]))
		for b in range(a + 1, recs.size()):
			var ra: float = float(recs[a].get("r", 8.0))
			var rb: float = float(recs[b].get("r", 8.0))
			assert_gt(
				Vector2(recs[a]["pos"]).distance_to(recs[b]["pos"]) + 0.5,
				ra + rb - 3.0,
				"poured piles must collide instead of occupying the same point"
			)


func test_candy_exit_falls_and_bounces_on_the_tray() -> void:
	var cu := GumballCloseup.new()
	cu.size = Vector2(720, 1280)
	add_child_autofree(cu)
	cu.present()
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	for i in 150:
		cu.tick(1.0 / 30.0)
	cu.set_can_commit(true, false)
	cu.lever_commit_requested.connect(func(): cu.accept_commit(), CONNECT_ONE_SHOT)
	cu.simulate_full_stroke()
	assert_true(cu.is_commit_accepted())
	var ys: Array[float] = []
	var saw_below_outlet := false
	var prev_y := -INF
	var jumped := 0
	for i in 300:
		cu.tick(1.0 / 30.0)
		var y: float = cu.ball_pos().y
		if y > cu.outlet_reveal_y():
			if saw_below_outlet:
				ys.append(y)
				if prev_y > -INF and y - prev_y > cu.ball_radius():
					jumped += 1
			else:
				saw_below_outlet = true
			prev_y = y
		if cu.is_drop_settled():
			break
	assert_true(saw_below_outlet)
	assert_gte(ys.size(), 8, "candy must travel below the outlet across many frames")
	assert_eq(jumped, 0, "candy must not teleport from the outlet onto the tray")
	assert_true(cu.has_contacted_floor())
	assert_gte(cu.bounce_count(), 1)
	assert_eq(cu.tray_count(), 1)
	assert_eq(cu.ball_count(), 12)


func test_visible_on_screen_enemies_are_hittable_but_offscreen_spawns_are_not() -> void:
	assert_eq(CombatConstants.WALK_IN_TARGETABLE_SLACK, 1.0)
	var cs := CombatState.new(49104)
	cs.free_walk = true
	cs.start_rush(49104, FireResolver.ID_WRATH)
	cs.spawn_paused = true
	cs.enemies.clear()
	# 刚进屏幕：中心约 9.6–9.8，旧松弛 0.45 会判定还在走进、打不中。
	var visible := EnemyInstance.new(DataRegistry.get_enemy(1), 9)
	visible.pos_x = 9.7
	cs.enemies.append(visible)
	assert_false(cs.is_entering(visible))
	assert_eq(cs.enemies_sorted_by_cell().size(), 1)
	# 刷点仍在屏外，打不到。
	var spawn := EnemyInstance.new(DataRegistry.get_enemy(1), 9)
	spawn.pos_x = float(CombatConstants.BOARD_SIZE - 1) + CombatConstants.WALK_IN_SPAWN_OFFSET_CELLS
	cs.enemies.append(spawn)
	assert_gt(spawn.pos_x, 10.5)
	assert_true(cs.is_entering(spawn))
	# 刚过屏幕右沿一点：10.2 仍视为未进屏。
	var edge := EnemyInstance.new(DataRegistry.get_enemy(1), 9)
	edge.pos_x = 10.2
	cs.enemies.append(edge)
	assert_true(cs.is_entering(edge))
	assert_eq(cs.enemies_sorted_by_cell().size(), 1)
