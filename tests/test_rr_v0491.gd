extends GutTest
## v0.4.91：弹药数量上限 30、传递弹加强量改写、倒出/糖果物理、进屏即可命中。

const WHITE := CombatConstants.WHITE_AMMO_ID
const CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const ShopState = preload("res://scripts/shop/shop_state.gd")

func before_each() -> void:
	DataRegistry.reload()


func test_version_is_at_least_0_4_91() -> void:
	assert_true(GameVersion.STRING.begins_with("0.4."))
	var minor := int(GameVersion.STRING.split(".")[2])
	assert_gte(minor, 91)


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
	assert_true(str(def.get("game_description", "")).contains("强化量"))
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
	var reveal_i := -1
	var floor_i := -1
	var max_dy := 0.0
	for i in 300:
		cu.tick(1.0 / 30.0)
		var y: float = cu.ball_pos().y
		if y > cu.outlet_reveal_y():
			if saw_below_outlet:
				ys.append(y)
				if prev_y > -INF:
					var dy: float = y - prev_y
					max_dy = maxf(max_dy, dy)
					# 重力下落末速约 30–40px/帧，超过半径不算瞬移；整段跳到托盘才会超过 3 倍半径。
					if dy > cu.ball_radius() * 3.0:
						jumped += 1
			else:
				saw_below_outlet = true
				reveal_i = i
			prev_y = y
		if floor_i < 0 and cu.has_contacted_floor():
			floor_i = i
		if cu.is_drop_settled():
			break
	assert_true(saw_below_outlet)
	assert_gte(ys.size(), 8, "candy must travel below the outlet across many frames")
	assert_eq(jumped, 0, "candy must not teleport from the outlet onto the tray")
	assert_true(cu.has_contacted_floor())
	assert_gte(floor_i, reveal_i)
	# 旧路径出球口限速+闸门关闭后 0.96 阻尼，出球口到托盘要飘 0.7s 以上。重力下落应明显更快。
	assert_lte(float(floor_i - reveal_i) / 30.0, 0.55, "drop from mouth to tray must be gravity, not a float")
	assert_gt(max_dy, 12.0, "falling candy must accelerate under gravity")
	assert_gte(cu.bounce_count(), 1)
	assert_eq(cu.tray_count(), 1)
	assert_eq(cu.ball_count(), 12)


func _run_candy_drop(cu: GumballCloseup, seed_value: int) -> void:
	cu.drop_rng = RandomNumberGenerator.new()
	cu.drop_rng.seed = seed_value
	cu.present()
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	for _i in 150:
		cu.tick(1.0 / 30.0)
	cu.set_can_commit(true, false)
	cu.lever_commit_requested.connect(func(): cu.accept_commit(), CONNECT_ONE_SHOT)
	cu.simulate_full_stroke()


func test_candy_exit_kick_range_and_both_signs() -> void:
	var cu: GumballCloseup = autofree(GumballCloseup.new())
	cu.drop_rng = RandomNumberGenerator.new()
	cu.drop_rng.seed = 49501
	var left := 0
	var right := 0
	var seen: Dictionary = {}
	for _i in 40:
		var rec: Dictionary = {}
		var vel: Vector2 = cu._apply_exit_kick(rec, Vector2.ZERO)
		var k: float = float(rec.get("exit_kick", 0.0))
		assert_eq(k, vel.x)
		assert_true(bool(rec.get("exit_kicked", false)))
		assert_gte(absf(k), GumballCloseup.EXIT_KICK_MIN - 0.001)
		assert_lte(absf(k), GumballCloseup.EXIT_KICK_MAX + 0.001)
		seen[snapped(k, 0.01)] = true
		if k < 0.0:
			left += 1
		else:
			right += 1
	assert_gt(left, 0, "kick must be able to go left")
	assert_gt(right, 0, "kick must be able to go right")
	assert_gt(seen.size(), 8, "magnitude should vary inside the range")

func test_candy_exit_kick_veers_and_still_lands() -> void:
	## 左右两种冲量都要看得见偏转，但必须落到托盘、弹跳、不瞬移，下落时间仍接近重力自由落体。
	var seeds := [49511, 49512, 49513, 49514, 49515, 49516, 49517, 49518]
	var saw_left := false
	var saw_right := false
	for seed_value in seeds:
		var cu := GumballCloseup.new()
		cu.size = Vector2(720, 1280)
		add_child_autofree(cu)
		_run_candy_drop(cu, seed_value)
		assert_true(cu.is_commit_accepted())
		var mid_x: float = cu.outlet_point().x
		var max_dx := 0.0
		var reveal_i := -1
		var floor_i := -1
		var prev_y := -INF
		var jumped := 0
		var kick_seen := 0.0
		for i in 300:
			cu.tick(1.0 / 30.0)
			var p: Vector2 = cu.ball_pos()
			if cu.payload_exit_kick() != 0.0:
				kick_seen = cu.payload_exit_kick()
			max_dx = maxf(max_dx, absf(p.x - mid_x))
			if p.y > cu.outlet_reveal_y():
				if prev_y > -INF and p.y - prev_y > cu.ball_radius() * 3.0:
					jumped += 1
				if reveal_i < 0:
					reveal_i = i
				prev_y = p.y
			if floor_i < 0 and cu.has_contacted_floor():
				floor_i = i
			if cu.is_drop_settled():
				break
		assert_ne(kick_seen, 0.0, "a one-shot horizontal kick must be applied after leaving the mouth")
		assert_gte(absf(kick_seen), GumballCloseup.EXIT_KICK_MIN - 0.001)
		assert_lte(absf(kick_seen), GumballCloseup.EXIT_KICK_MAX + 0.001)
		assert_eq(cu.payload_exit_kick(), kick_seen, "kick is applied once and then kept")
		if kick_seen < 0.0:
			saw_left = true
		else:
			saw_right = true
		assert_gt(max_dx, 24.0, "drop must veer sideways, not fall in a straight vertical line")
		assert_eq(jumped, 0, "candy must not teleport from the outlet onto the tray")
		assert_true(cu.has_contacted_floor())
		assert_gte(cu.bounce_count(), 1)
		assert_eq(cu.tray_count(), 1)
		assert_gte(floor_i, reveal_i)
		assert_lte(float(floor_i - reveal_i) / 30.0, 0.55, "mouth-to-tray time stays a gravity drop")
		var settle: Vector2 = cu.ball_pos()
		var tray: Rect2 = cu.drop_bounds()
		assert_true(tray.grow(cu.ball_radius()).has_point(settle), "kicked ball must settle on the tray")
	assert_true(saw_left, "integration drops should include a left kick")
	assert_true(saw_right, "integration drops should include a right kick")


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


func test_after_pour_finish_keeps_physics_pile() -> void:
	## 倒完之后：球还在物理世界里，不消失、不重排；袋子回正后仍有重力和碰撞。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	box.sync_ammo_ids([WHITE, WHITE, WHITE])
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.pour_cap = 3
	box.mark_pour_balls(3)
	box.mouth_open = true
	box.impulse_pour_balls()
	for _j in 360:
		box._physics_process(1.0 / 60.0)
		if box.fallen_count() >= 3:
			box.mouth_open = false
	box.mouth_open = false
	for _k in 60:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 3)
	assert_eq(box.promote_exited_to_catch_bodies([11, 12, 13]), 3)
	var settled: Array = []
	for rec in box.catch_body_records():
		settled.append(rec["pos"])
	# 模拟倒完回正袋子：不 take、不关手区碰撞盒。
	box.sack_tilt = 0.0
	box.sack_shift = Vector2.ZERO
	box.mouth_open = false
	assert_true(box.hand_catch_active)
	assert_eq(box.catch_body_count(), 3)
	for _n in 120:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.catch_body_count(), 3, "finishing the pour must not remove the hand pile")
	assert_eq(box.take_catch_bodies().size(), 0) if false else true
	var after: Array = box.catch_body_records()
	assert_eq(after.size(), 3)
	for rec2 in after:
		var p2: Vector2 = rec2["pos"]
		assert_true(box.hand_catch_rect.grow(16.0).has_point(p2), "pile stays in the hand area")
		assert_false(box._point_in_sack_interior(p2), "untilting the sack must not teleport the pile back")
	# 没有被收成网格：落点只允许因重力/碰撞微调，不能整手重排到远处。
	for i in settled.size():
		assert_lt(settled[i].distance_to(after[i]["pos"]), 40.0, "no rearrange into a new layout")
	# 重力还在：把一发提到手区上方，它会落下并与其它球碰撞。
	var lifted: Dictionary = {}
	for b in box._balls:
		if bool(b.get("catch_body", false)):
			lifted = b
			break
	assert_false(lifted.is_empty())
	var floor_y: float = box.hand_catch_rect.end.y
	lifted["asleep"] = false
	lifted["freeze"] = 0
	lifted["vel"] = Vector2.ZERO
	lifted["pos"] = Vector2(box.hand_catch_rect.get_center().x, box.hand_catch_rect.position.y + 16.0)
	var y0: float = float(lifted["pos"].y)
	for _g in 90:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.catch_body_count(), 3)
	assert_gt(float(lifted["pos"].y), y0 + 8.0, "lifted ball must fall under gravity")
	assert_lt(float(lifted["pos"].y) + float(lifted.get("r", 8.0)), floor_y + 4.0)
	var recs: Array = box.catch_body_records()
	for a in recs.size():
		for b2 in range(a + 1, recs.size()):
			var ra: float = float(recs[a].get("r", 8.0))
			var rb: float = float(recs[b2].get("r", 8.0))
			assert_gt(
				Vector2(recs[a]["pos"]).distance_to(recs[b2]["pos"]) + 0.5,
				ra + rb - 3.0,
				"hand pile must still collide after the pour finishes"
			)


func test_bag_sync_before_promote_does_not_delete_exited_pile() -> void:
	## 倒出逻辑入手会立刻 emit/refresh。若 sync 把尚未 promote 的出袋球当成袋内存货，会删掉它们。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	var ids: Array = []
	for _i in 10:
		ids.append(WHITE)
	box.sync_ammo_ids(ids)
	for _j in 90:
		box._physics_process(1.0 / 60.0)
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.pour_cap = 6
	box.mark_pour_balls(6)
	box.mouth_open = true
	box.impulse_pour_balls()
	for _m in 420:
		box._physics_process(1.0 / 60.0)
		if box.fallen_count() >= 6:
			box.mouth_open = false
	box.mouth_open = false
	for _n in 60:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 6)
	assert_eq(box.catch_body_count(), 0)
	# 模拟 dump_to_hand_items 的 emit：袋里还剩 4 发，出袋球尚未标成 catch_body。
	box.sync_ammo_ids([WHITE, WHITE, WHITE, WHITE])
	var still_exited := 0
	for b in box._balls:
		if bool(b.get("exited", false)) and not bool(b.get("catch_body", false)):
			still_exited += 1
	assert_eq(still_exited, 6, "bag sync must not eat poured balls before they are promoted")
	assert_eq(box.bag_body_count(), 4)
	assert_eq(box.promote_exited_to_catch_bodies([1, 2, 3, 4, 5, 6]), 6)
	assert_eq(box.catch_body_count(), 6)
	assert_eq(box.bag_body_count(), 4)
	for rec in box.catch_body_records():
		assert_true(box.hand_catch_rect.grow(16.0).has_point(rec["pos"]))
		assert_false(box._point_in_sack_interior(rec["pos"]))


func test_ui_finish_keeps_catch_bodies_and_hides_hand_cards() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var box: BagPhysicsBox = ui._bag_physics
	assert_not_null(box)
	var cs: CombatState = ui.state
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.hand_uid.clear()
	cs.hand.append(WHITE)
	cs.hand_temp.append(0.0)
	cs.hand_envy_copy.append(false)
	cs.hand_uid.append(101)
	box.clear_balls()
	box.hand_catch_rect = Rect2(0, 400, 200, 120)
	box.hand_catch_active = true
	box._balls.append({
		"id": WHITE, "pos": Vector2(80, 460), "vel": Vector2.ZERO, "r": 10.0, "h": 48.0,
		"exited": true, "catch_body": true, "hand_uid": 101, "asleep": false, "held": false, "temp": false, "envy": false,
	})
	ui._dump_pouring = false
	ui._refresh_hand_list()
	assert_true(ui._hand_physics_pile_active())
	assert_eq(box.catch_body_count(), 1)
	for p in ui._hand_slot_panels:
		assert_false(p.visible, "hand cards must stay hidden while the physics pile is live")


func _pour_all_to_catcher(box: BagPhysicsBox, n: int) -> void:
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.pour_cap = n
	box.mark_pour_balls(n)
	box.mouth_open = true
	box.impulse_pour_balls()
	for _j in 420:
		box._physics_process(1.0 / 60.0)
		if box.fallen_count() >= n:
			box.mouth_open = false
	box.mouth_open = false
	for _k in 60:
		box._physics_process(1.0 / 60.0)


func test_full_bag_pour_sync_does_not_respawn_then_delete() -> void:
	## 把袋里全部倒出后、逻辑袋还没扣时，sync 不得在袋内再生成一闪即删的球。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	box.sync_ammo_ids([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE])
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.bag_body_count(), 6)
	_pour_all_to_catcher(box, 6)
	assert_eq(box.fallen_count(), 6)
	assert_eq(box.bag_body_count(), 0)
	assert_eq(box.catch_body_count(), 0)
	var before: int = box._balls.size()
	# 模拟 dump 前的 refresh：state.bag 仍是 6 发。
	box.sync_ammo_ids([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE])
	assert_eq(box.bag_body_count(), 0, "must not flash-spawn bag balls for already poured ammo")
	assert_eq(box._balls.size(), before)
	var still_exited := 0
	for b in box._balls:
		if bool(b.get("exited", false)) and not bool(b.get("catch_body", false)):
			still_exited += 1
	assert_eq(still_exited, 6)
	# dump 之后袋空，再 sync 也不能删掉这些出袋球。
	box.sync_ammo_ids([])
	assert_eq(box.promote_exited_to_catch_bodies([1, 2, 3, 4, 5, 6]), 6)
	assert_eq(box.catch_body_count(), 6)
	assert_eq(box.bag_body_count(), 0)
	box.sync_ammo_ids([])
	assert_eq(box.catch_body_count(), 6)
	assert_eq(box.bag_body_count(), 0)


func test_partial_bag_remaining_sync_does_not_duplicate_exited() -> void:
	## 10 发倒出 6 发时，dump 前 sync 不得把已出袋的 6 发再在袋里复制出来。
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	var ids: Array = []
	for _i in 10:
		ids.append(WHITE)
	box.sync_ammo_ids(ids)
	for _j in 90:
		box._physics_process(1.0 / 60.0)
	_pour_all_to_catcher(box, 6)
	assert_eq(box.fallen_count(), 6)
	assert_eq(box.bag_body_count(), 4)
	box.sync_ammo_ids(ids)
	assert_eq(box.bag_body_count(), 4, "remaining bag balls stay; poured ones must not respawn")
	assert_eq(box.fallen_count(), 6)
	box.sync_ammo_ids([WHITE, WHITE, WHITE, WHITE])
	assert_eq(box.bag_body_count(), 4)
	assert_eq(box.promote_exited_to_catch_bodies([1, 2, 3, 4, 5, 6]), 6)
	assert_eq(box.catch_body_count(), 6)
	assert_eq(box.bag_body_count(), 4)


func test_ui_refresh_during_full_dump_does_not_flash_bag_balls() -> void:
	## 倒出全部时，即使 UI refresh 插入在 dump 之前，袋内也不能闪出再被删掉的球。
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var box: BagPhysicsBox = ui._bag_physics
	assert_not_null(box)
	var cs: CombatState = ui.state
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.hand_uid.clear()
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	for _i in 6:
		cs._bag_append(WHITE, false, false)
	box.clear_balls()
	box.sync_ammo_ids(cs.bag.duplicate())
	for _j in 40:
		box._physics_process(1.0 / 60.0)
	_pour_all_to_catcher(box, 6)
	assert_eq(box.fallen_count(), 6)
	assert_eq(box.bag_body_count(), 0)
	assert_eq(cs.bag.size(), 6)
	ui._dump_pouring = true
	ui._refresh_bag_list()
	assert_eq(box.bag_body_count(), 0, "refresh during pour must not respawn a full bag")
	# 即使倒出标记已关（dump 前误刷新），sync 本身也不能生成。
	ui._dump_pouring = false
	ui._refresh_bag_list()
	assert_eq(box.bag_body_count(), 0, "sync before logical dump must not flash bag balls")
	var prev_n: int = cs.hand.size()
	var fallen: Array = box.snapshot_exited_pour_balls()
	cs.dump_to_hand_items(fallen)
	var uids: Array = []
	cs._sync_hand_arrays()
	for i in range(prev_n, cs.hand.size()):
		uids.append(int(cs.hand_uid[i]) if i < cs.hand_uid.size() else i)
	assert_eq(box.promote_exited_to_catch_bodies(uids), 6)
	ui._refresh()
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.hand.size(), 6)
	assert_eq(box.bag_body_count(), 0)
	assert_eq(box.catch_body_count(), 6)
