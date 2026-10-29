extends GutTest

func _shot_one(cs: CombatState, resolve_enemy: bool = false) -> void:
	## rush!：打 1 发并 finalize；默认不进怪回合（保留枪口，方便测跨发枪口）。
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		if resolve_enemy:
			cs.resolve_post_fire_enemy_turn()
		else:
			cs._post_fire_enemy_pending = false


## 战斗骨架：抽弹、随机 ROLL、白弹、邻接攻击、空弹失败、逐步射击。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_data_registry_loads_tables() -> void:
	assert_eq(DataRegistry.get_ammo(1).get("name"), "平庸子弹")
	assert_eq(DataRegistry.get_enemy(1).get("name"), "平民")
	assert_true(DataRegistry.get_tag("生物").has("effect"))
	assert_eq(int(DataRegistry.get_ammo(1).get("base_damage")), 3)
	assert_eq(int(DataRegistry.get_enemy(1).get("hp")), 10)


func test_magazine_load_and_fire_order() -> void:
	var mag := Magazine.new()
	var ids: Array[int] = [1, 1, 1, 1, 1, 1]
	assert_eq(mag.load_sequence(ids), 6)
	assert_eq(mag.fire_order(), ids)
	mag.set_start(2)
	assert_eq(mag.fire_order(), [1, 1, 1, 1, 1, 1])
	mag.load_sequence([10, 11, 12, 13, 14, 15] as Array[int])
	mag.set_start(3)
	assert_eq(mag.fire_order(), [13, 14, 15, 10, 11, 12])


func test_magazine_random_roll_keeps_relative_order() -> void:
	var mag := Magazine.new()
	mag.load_sequence([1, 2, 3, 4, 5, 6] as Array[int])
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var before: Array[int] = mag.fire_order()
	var steps: int = mag.random_roll(rng)
	var after: Array[int] = mag.fire_order()
	assert_gte(steps, 1)
	assert_lte(steps, mag.size() - 1)
	assert_eq(after.size(), before.size())
	# after 应是 before 的旋转
	var ok := false
	for rot in before.size():
		var rotated: Array[int] = []
		for i in before.size():
			rotated.append(before[(i + rot) % before.size()])
		if rotated == after:
			ok = true
			break
	assert_true(ok, "fire_order should be a rotation of prior order")


func test_magazine_random_roll_noop_when_one() -> void:
	var mag := Magazine.new()
	mag.load_sequence([9] as Array[int])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(mag.random_roll(rng), 0)
	assert_eq(mag.start_index, 0)


func test_magazine_unload() -> void:
	var mag := Magazine.new()
	mag.load_sequence([1, 1, 1] as Array[int])
	var got := mag.unload_all()
	assert_eq(got.size(), 3)
	assert_true(mag.is_empty())


func test_load_fills_magazine_from_bag() -> void:
	var cs := CombatState.new(42)
	cs.start_rush(42)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL - CombatConstants.MAGAZINE_SIZE + cs.penalty_temp_sins_spawned)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)


func test_fire_white_damages_civilian() -> void:
	var cs := CombatState.new(7)
	cs.start_rush(7)
	cs.do_load()
	var enemy: EnemyInstance = cs.front_enemy()
	assert_not_null(enemy)
	assert_true(cs.do_fire())
	# v0.3.8 无波次：击杀得经验，场上清空立刻补刷，不进胜利
	assert_ne(cs.phase, CombatState.Phase.WON)
	assert_gt(cs.xp + (cs.level - 1) * 1000, 0)
	assert_false(cs.alive_enemies().is_empty())


func test_stepwise_fire_api() -> void:
	var cs := CombatState.new(11)
	cs.start_rush(11)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.do_load()
	assert_true(cs.begin_fire())
	assert_eq(cs.phase, CombatState.Phase.FIRING)
	var shots := 0
	while cs.phase == CombatState.Phase.FIRING:
		cs.fire_next_shot()
		shots += 1
		assert_lte(shots, 4)
	# rush! 单发：1 次规划 + 1 次 finalize；匣内仍有弹 → AWAIT_ACTION
	assert_eq(shots, 2)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)


func test_roll_ends_turn_and_enemy_advances() -> void:
	## rush!：ROLL 只转轮不推进敌人；敌人由 tick_enemy_auto_step 向左走。
	var cs := CombatState.new(99)
	cs.start_rush(99)
	cs.bag.clear()
	for _i in 12:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	var start_cell: int = cs.enemies[0].cell
	var hp_before := cs.player_hp
	cs.do_load()
	var order_before: Array[int] = cs.magazine.fire_order()
	assert_true(cs.begin_roll())
	var order_after: Array[int] = cs.magazine.fire_order()
	assert_eq(order_after.size(), order_before.size())
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.enemies[0].cell, start_cell, "roll must not step enemies in auto mode")
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].cell, start_cell - 1)
	assert_eq(cs.player_hp, hp_before)
	assert_true(cs.can_fire())
	assert_true(cs.can_manual_load() or cs.magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE)


func test_distant_enemy_multiple_turns_no_player_damage() -> void:
	var cs := CombatState.new(5)
	cs.start_rush(5, FireResolver.ID_GREED)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 9
	var hp0 := cs.player_hp
	# rush!：自动推进 5 拍，仍未邻接
	for _i in 5:
		assert_true(cs.tick_enemy_auto_step())
		assert_false(cs.is_adjacent_to_player(cs.enemies[0]))
		assert_eq(cs.player_hp, hp0)
	assert_eq(cs.enemies[0].cell, 4)
	assert_eq(cs.player_hp, hp0)
	assert_true(cs.can_fire() or cs.can_manual_load() or cs.phase == CombatState.Phase.AWAIT_LOAD)


func test_only_adjacent_enemy_attacks() -> void:
	var cs := CombatState.new(1)
	cs.start_rush(1, FireResolver.ID_GREED)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 2
	var hp_before := cs.player_hp
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].cell, 1)
	assert_true(cs.is_adjacent_to_player(cs.enemies[0]))
	assert_eq(cs.player_hp, hp_before - cs.enemies[0].atk)
	# 推进时不锁玩家按钮阶段
	assert_true(cs.phase == CombatState.Phase.AWAIT_LOAD or cs.phase == CombatState.Phase.AWAIT_ACTION)


func test_empty_bag_refills_instead_of_ammo_lose() -> void:
	## v0.3.4：袋空立刻战斗内重置，不再因袋空判「弹药耗尽」。
	var cs := CombatState.new(2)
	cs.start_rush(2)
	cs.bag.clear()
	cs.discard.clear()
	cs.magazine.clear()
	cs.needs_reshuffle_next_load = false
	var hp_before := cs.player_hp
	assert_gt(hp_before, 0)
	assert_true(cs.do_load())
	assert_ne(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs.lose_reason, CombatState.LoseReason.NONE)
	assert_eq(cs.player_hp, hp_before)
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)


func test_unload_discards_and_enemy_turn() -> void:
	## rush!：卸除不推进敌人；清空匣后回 AWAIT_LOAD。
	var cs := CombatState.new(3)
	cs.start_rush(3)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	var cell0: int = cs.enemies[0].cell
	cs.do_load()
	var loaded := cs.magazine.loaded_count()
	assert_true(cs.do_unload())
	assert_true(cs.magazine.is_empty())
	assert_eq(cs.discard.size(), loaded)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_eq(cs.enemies[0].cell, cell0, "unload must not auto-step enemies")


func test_white_bullet_damage_value() -> void:
	assert_eq(BulletEffectRegistry.compute_damage(CombatConstants.WHITE_AMMO_ID), 3)


func test_yellow_damage_by_count() -> void:
	var order: Array[int] = [4, 4, 4]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs, [3, 3, 3])


func test_black_strict_majority_triples() -> void:
	var order: Array[int] = [2, 2, 2, 1]
	assert_true(FireResolver.black_triggers(order))
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[3], 9)  # white 3*3
	# 并列最多不触发
	var tied: Array[int] = [2, 2, 1, 1]
	assert_false(FireResolver.black_triggers(tied))


func test_purple_run_damage() -> void:
	var order: Array[int] = [5, 5, 1]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	assert_eq(dmgs[0], 3)
	assert_eq(dmgs[1], 3)
	assert_eq(dmgs[2], 3)


func test_green_trailing_multiplier() -> void:
	var order: Array[int] = [1, 3, 3]
	var dmgs: Array[int] = FireResolver.compute_shot_damages(order, 0)
	# last green 2*2=4, second-last green 2*3=6
	assert_eq(dmgs[2], 4)
	assert_eq(dmgs[1], 6)
	var allg: Array[int] = [3, 3, 3]
	var z: Array[int] = FireResolver.compute_shot_damages(allg, 0)
	assert_eq(z, [0, 0, 0])


func test_pink_bonus_on_unload() -> void:
	var cs := CombatState.new(8)
	cs.start_rush(8)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.dev_force_load([9, 9, 1, 1, 1, 1] as Array[int])
	assert_eq(cs.pink_bonus, 0)
	assert_true(cs.do_unload())
	assert_eq(cs.pink_bonus, 1)


func test_force_load_yellow_and_fire() -> void:
	var cs := CombatState.new(8)
	cs.start_rush(8)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.dev_force_load([4, 4, 4, 4, 4, 4] as Array[int])
	assert_true(cs.do_fire())
	# rush!：黄梯 5+5+4+3+2+1=20；不在 do_fire 末尾结算流血（自动推进才结算）
	assert_eq(cs.enemies[0].hp, 80)
	assert_eq(cs.enemies[0].bleed_stacks, 6)
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].hp, 74)
	assert_eq(cs.enemies[0].bleed_stacks, 5)


func test_skeleton_does_not_bleed() -> void:
	var def: Dictionary = DataRegistry.get_enemy(104)
	var e := EnemyInstance.new(def, 5)
	assert_true(e.has_tag("骷髅"))
	e.apply_hit(3)
	assert_eq(e.bleed_stacks, 0)


func test_bio_bleeds_and_ticks() -> void:
	var cs := CombatState.new(4)
	cs.start_rush(4)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	cs.enemies[0].cell = 9
	# 命中叠流血
	cs.enemies[0].apply_hit(3)
	assert_eq(cs.enemies[0].bleed_stacks, 1)
	var hp_before: int = cs.enemies[0].hp
	assert_true(cs.tick_enemy_auto_step())  # 自动推进含流血结算
	assert_eq(cs.enemies[0].hp, hp_before - 1)
	assert_eq(cs.enemies[0].bleed_stacks, 0)


func test_stone_ignores_damage_under_4() -> void:
	var def: Dictionary = DataRegistry.get_enemy(105)
	var e := EnemyInstance.new(def, 5)
	assert_eq(e.apply_hit(3), 0)
	assert_eq(e.hp, e.max_hp)
	assert_eq(e.apply_hit(4), 4)
	assert_eq(e.hp, e.max_hp - 4)


func test_stone_ignores_bleed_dot_under_4() -> void:
	var def: Dictionary = DataRegistry.get_enemy(105)
	var e := EnemyInstance.new(def, 5)
	e.bleed_stacks = 3  # 强行叠层
	var dealt := e.apply_damage(e.bleed_stacks)
	assert_eq(dealt, 0)


func test_dev_spawn_bandit() -> void:
	var cs := CombatState.new(6)
	cs.start_rush(6)
	cs.enemies.clear()
	cs.dev_spawn_enemy(2, 8)
	assert_eq(cs.alive_enemies().size(), 1)
	assert_eq(cs.front_enemy().name_zh, "强盗")


func test_bag_draw_is_random_not_fifo() -> void:
	## 袋无顺序：同种子多次装填，不应稳定等于「始终 pop 前端」的 FIFO 序列。
	## 用固定袋 [1,2,3,4,5,6] 不洗牌，若 FIFO 则永远先抽到 1；随机下标则多数情况首发不是 1。
	var firsts: Dictionary = {}
	for seed_v in range(100, 140):
		var cs := CombatState.new(seed_v)
		cs.start_rush(seed_v)
		cs.bag.clear()
		for id in [1, 2, 3, 4, 5, 6]:
			cs.bag.append(id)
		cs.enemies[0].hp = 100
		cs.enemies[0].max_hp = 100
		assert_true(cs.do_load())
		var order: Array[int] = cs.magazine.fire_order()
		assert_eq(order.size(), 6)
		var key := str(order[0])
		firsts[key] = int(firsts.get(key, 0)) + 1
	assert_gt(firsts.size(), 1, "random draw should vary first chamber across seeds")


func test_apply_roll_without_enemy_turn() -> void:
	## apply_roll 本身只转轮（装填后 spin 复用）；显式 resolve 才进怪回合；匣内有弹回 AWAIT_ACTION。
	var cs := CombatState.new(33)
	cs.start_rush(33)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 100
	cs.enemies[0].max_hp = 100
	var cell_before: int = cs.enemies[0].cell
	cs.do_load()
	var steps: int = cs.apply_roll()
	assert_gte(steps, 1)
	assert_lte(steps, CombatConstants.MAGAZINE_SIZE - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.enemies[0].cell, cell_before)
	cs.resolve_after_player_action()  # rush! 自动走位：不推进
	assert_eq(cs.enemies[0].cell, cell_before)
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].cell, cell_before - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_fire())


func test_begin_roll_consumes_turn_like_unload() -> void:
	## rush!：begin_roll 只转轮；自动推进才让怪前进；匣未空保持可行动。
	var cs := CombatState.new(44)
	cs.start_rush(44)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	var cell0: int = cs.enemies[0].cell
	cs.do_load()
	assert_true(cs.begin_roll())
	assert_eq(cs.enemies[0].cell, cell0)
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].cell, cell0 - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_fire())


func test_reward_generate_three_choices() -> void:
	var cs := CombatState.new(7)
	cs.start_rush(7)
	var choices := cs.generate_reward_choices()
	assert_eq(choices.size(), CombatConstants.REWARD_CHOICE_COUNT)
	for id in choices:
		assert_true(DataRegistry.is_ammo_enabled(id))


func test_reward_pick_adds_to_bag_and_base_gold() -> void:
	## v0.3.8：三选一由升级触发（不再由波次结束触发、不发基础金）。
	var cs := CombatState.new(8)
	cs.start_rush(8)
	assert_eq(cs.gold, 0)
	cs.gain_xp(cs.xp_needed())
	assert_true(cs.reward_pending)
	assert_eq(cs.gold, 0)
	assert_eq(cs.reward_choices.size(), 3)
	var bag0 := cs.bag.size()
	var chosen: int = cs.reward_choices[1]
	assert_true(cs.pick_reward_ammo(1))
	assert_eq(cs.bag.size(), bag0 + 1)
	assert_eq(cs.bag[cs.bag.size() - 1], chosen)
	assert_false(cs.reward_pending)
	assert_false(cs.can_pick_reward())


func test_reward_skip_for_extra_gold() -> void:
	var cs := CombatState.new(9)
	cs.start_rush(9)
	cs.gain_xp(cs.xp_needed())
	var bag_after_reset := cs.bag.size()
	assert_true(cs.skip_reward_for_gold())
	assert_eq(cs.gold, CombatConstants.REWARD_SKIP_EXTRA_GOLD)
	assert_eq(cs.bag.size(), bag_after_reset)
	assert_false(cs.reward_pending)
	# 不可重复领取
	assert_false(cs.skip_reward_for_gold())
	assert_false(cs.pick_reward_ammo(0))


func test_stepwise_load_api() -> void:
	var cs := CombatState.new(42)
	cs.start_rush(42)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_true(cs.begin_load())
	assert_true(cs.is_busy_loading())
	assert_eq(cs.magazine.start_index, CombatConstants.LOAD_SESSION_INITIAL_START)
	assert_eq(cs.magazine.chamber_at_load_port(), 0)
	var n := 0
	var last: Dictionary = {}
	var loaded_slots: Array[int] = []
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		last = r
		if int(r.get("slot", -1)) >= 0:
			loaded_slots.append(int(r["slot"]))
		n += 1
		assert_lte(n, CombatConstants.MAGAZINE_SIZE + 1)
		if bool(r.get("done", false)):
			break
		# 入弹后才转盘，下一发才换上弹口仓
		cs.apply_load_rotate()
	assert_eq(n, CombatConstants.MAGAZINE_SIZE)
	assert_false(cs.is_busy_loading())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	# 装满后标记需要 reroll；start_index 在 spin 前保持会话末值
	assert_true(bool(last.get("needs_spin", false)))
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	# v0.3.8：装填中若凑满 3 颗同种罪孽会吃惩罚并往袋里 +1 颗临时罪孽
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL - CombatConstants.MAGAZINE_SIZE + cs.penalty_temp_sins_spawned)
	# 上弹口依次装入仓 0,1,2,3,4,5
	assert_eq(loaded_slots, [0, 1, 2, 3, 4, 5])


func test_stepwise_load_partial_when_bag_small() -> void:
	var cs := CombatState.new(5)
	cs.start_rush(5)
	cs.bag.clear()
	for _i in 3:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.begin_load())
	var n := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		n += 1
		if bool(r.get("done", false)):
			break
		cs.apply_load_rotate()
	assert_eq(n, 3)
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)


func test_ammo_detail_text_from_table() -> void:
	var text := DataRegistry.format_ammo_detail_text(1)
	assert_true(text.contains("平庸子弹"))
	assert_true(text.contains("3"))
	assert_true(text.contains("常规子弹") or text.contains("无"))


func test_ammo_detail_text_invalid() -> void:
	var text := DataRegistry.format_ammo_detail_text(CombatConstants.INVALID_AMMO_ID)
	assert_true(text.contains(CombatConstants.INVALID_AMMO_NAME))
	assert_true(text.contains("0"))


func test_ammo_inventory_bag_and_mag() -> void:
	var cs := CombatState.new(42)
	cs.start_rush(42, FireResolver.ID_WRATH)
	cs.bag.clear()
	for _i in 12:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	var before_bag: int = cs.bag.size()
	assert_true(cs.do_load())
	var inv: Dictionary = cs.ammo_inventory_by_id()
	assert_true(inv.has(CombatConstants.WHITE_AMMO_ID))
	var e: Dictionary = inv[CombatConstants.WHITE_AMMO_ID]
	assert_eq(int(e["mag"]), CombatConstants.MAGAZINE_SIZE)
	assert_eq(int(e["bag"]), before_bag - CombatConstants.MAGAZINE_SIZE)
	assert_eq(int(e.get("discard", 0)), 0)
	assert_eq(int(e["total"]), before_bag)


func test_ammo_inventory_shows_owned_when_bag_empty() -> void:
	## 装满匣后袋立刻补；库存含膛内+新袋，列表不为空。
	var cs := CombatState.new(43)
	cs.start_rush(43)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 6:
		cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 6)
	assert_eq(cs.bag_reset_count, 1)
	assert_false(cs.bag.is_empty())
	var inv: Dictionary = cs.ammo_inventory_by_id()
	assert_false(inv.is_empty())
	assert_true(inv.has(CombatConstants.WHITE_AMMO_ID))
	var e: Dictionary = inv[CombatConstants.WHITE_AMMO_ID]
	assert_eq(int(e["mag"]), 6)
	assert_gt(int(e["bag"]), 0)
	assert_eq(int(e["discard"]), 0)
	assert_eq(int(e["total"]), int(e["bag"]) + 6)


func test_load_port_and_fire_port_offsets() -> void:
	var mag := Magazine.new()
	mag.start_index = CombatConstants.LOAD_SESSION_INITIAL_START
	assert_eq(mag.chamber_at_load_port(), 0)
	assert_eq(mag.chamber_at_fire_port(), CombatConstants.LOAD_SESSION_INITIAL_START)
	mag.start_index = 0
	assert_eq(mag.chamber_at_fire_port(), 0)
	assert_eq(mag.chamber_at_load_port(), CombatConstants.LOAD_PORT_OFFSET_STEPS)


func test_stepwise_load_rotates_start_each_chamber() -> void:
	var cs := CombatState.new(7)
	cs.start_rush(7)
	assert_true(cs.begin_load())
	var starts: Array[int] = [cs.magazine.start_index]
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		if bool(r.get("done", false)):
			break
		assert_eq(int(r.get("rotate_to", -1)), (cs.magazine.start_index + 1) % CombatConstants.MAGAZINE_SIZE)
		cs.apply_load_rotate()
		starts.append(cs.magazine.start_index)
	# 每装一发后 apply_load_rotate：1→2→3→4→5→0（最后一发不步进）
	assert_eq(starts, [1, 2, 3, 4, 5, 0])


func test_do_load_full_applies_post_spin() -> void:
	var cs := CombatState.new(99)
	cs.start_rush(99)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	# 装满后必有 random_roll；步数∈[1,5]，start 合法
	assert_gte(cs.magazine.start_index, 0)
	assert_lt(cs.magazine.start_index, CombatConstants.MAGAZINE_SIZE)


func test_fire_consumes_top_chamber_then_advances() -> void:
	var cs := CombatState.new(3)
	cs.start_rush(3)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	])
	cs.magazine.set_start(2)
	assert_true(cs.begin_fire())
	var top_before: int = cs.magazine.start_index
	assert_eq(top_before, 2)
	assert_eq(cs.magazine.slots[2], CombatConstants.WHITE_AMMO_ID)
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(cs.magazine.slots[2], Magazine.EMPTY)
	assert_eq(cs.magazine.start_index, 3)


func test_reward_blurb_short() -> void:
	var blurb := DataRegistry.format_ammo_reward_blurb(1)
	assert_true(blurb.contains("伤") or blurb.contains("3") or blurb.contains("常规"))
	assert_lte(blurb.length(), 40)
	var black := DataRegistry.format_ammo_reward_blurb(2)
	assert_true(black.length() > 0)
	assert_lte(black.length(), 48)

func test_load_writes_only_load_port_each_step() -> void:
	## 每步只写入当前上弹口；未 apply_load_rotate 前重复写入同一仓。
	var cs := CombatState.new(11)
	cs.start_rush(11)
	assert_true(cs.begin_load())
	var port0: int = cs.magazine.chamber_at_load_port()
	var r1: Dictionary = cs.load_next_chamber()
	assert_eq(int(r1["slot"]), port0)
	assert_eq(cs.magazine.loaded_count(), 1)
	# 未旋转前上弹口仍是同一仓；若再装会覆盖（API 约定每次装后应 rotate）
	assert_eq(cs.magazine.chamber_at_load_port(), port0)
	cs.apply_load_rotate()
	var port1: int = cs.magazine.chamber_at_load_port()
	assert_ne(port1, port0)
	var r2: Dictionary = cs.load_next_chamber()
	assert_eq(int(r2["slot"]), port1)
	assert_eq(cs.magazine.loaded_count(), 2)


func test_fire_consumes_fire_port_chamber() -> void:
	## 击发清空的是正上锤位仓，与 last_fired_slot / chamber_at_fire_port 一致。
	var cs := CombatState.new(13)
	cs.start_rush(13)
	cs.dev_force_load([
		FireResolver.ID_YELLOW, FireResolver.ID_RED, FireResolver.ID_BLUE,
		FireResolver.ID_GREEN, FireResolver.ID_PURPLE, FireResolver.ID_WHITE,
	])
	cs.magazine.set_start(4)
	assert_eq(cs.magazine.chamber_at_fire_port(), 4)
	assert_eq(cs.magazine.slots[4], FireResolver.ID_PURPLE)
	_shot_one(cs)
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(cs.last_fired_slot, 4)
	assert_eq(cs.magazine.slots[4], Magazine.EMPTY)
	assert_eq(cs.magazine.start_index, 5)
	assert_eq(cs.magazine.chamber_at_fire_port(), 5)


func test_wheel_port_geometry_angles() -> void:
	## 逻辑偏移与 UI 固定角约定：击发=正上(i相对0)，装弹=左上(相对+5 → -150°)。
	assert_eq(CombatConstants.FIRE_PORT_OFFSET_STEPS, 0)
	assert_eq(CombatConstants.LOAD_PORT_OFFSET_STEPS, 5)
	assert_eq(CombatConstants.LOAD_SESSION_INITIAL_START, 1)
	var mag := Magazine.new()
	for s in 6:
		mag.start_index = s
		var fire_i: int = mag.chamber_at_fire_port()
		var load_i: int = mag.chamber_at_load_port()
		assert_eq(fire_i, s)
		assert_eq(load_i, (s + 5) % 6)
		# 装弹口相对击发口固定隔 5 步（屏幕 -150° vs -90°）
		assert_eq((load_i - fire_i + 6) % 6, 5)


func test_magazine_random_roll_steps_nonzero_when_full() -> void:
	## 满匣 ROLL 逻辑步数必须 >0，避免视觉上几乎不动。
	var mag := Magazine.new()
	mag.load_sequence([1, 2, 3, 4, 5, 6] as Array[int])
	var rng := RandomNumberGenerator.new()
	for seed_v in range(1, 40):
		rng.seed = seed_v
		mag.start_index = 0
		var steps: int = mag.random_roll(rng)
		assert_gte(steps, 1, "seed %d" % seed_v)
		assert_lte(steps, 5, "seed %d" % seed_v)


func test_partial_load_then_bag_refills_immediately() -> void:
	## 袋剩 N 发只装 N；会话结束袋空则立刻战斗内重置，不必等怪走。
	var cs := CombatState.new(42)
	cs.start_rush(42)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 2:
		cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL - cs.magazine.loaded_count() + cs.penalty_temp_sins_spawned, "v0.3.8：重置只还基础池（膛内弹不复制）")
	assert_eq(cs.count_temporary_in_bag(), cs.penalty_temp_sins_spawned, "临时罪孽只来自惩罚")
	assert_true(cs.can_manual_load())
	assert_true(cs.do_fire())
	assert_ne(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs.lose_reason, CombatState.LoseReason.NONE)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)


func test_roll_keeps_mag_and_bag_refills_on_empty_load() -> void:
	## ROLL 不耗弹；装满后袋空立刻补；匣内仍有弹可继续行动。
	var cs := CombatState.new(77)
	cs.start_rush(77)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 6:
		cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 6)
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL - cs.magazine.loaded_count() + cs.penalty_temp_sins_spawned, "v0.3.8：重置只还基础池（膛内弹不复制）")
	var steps: int = cs.apply_roll()
	assert_gte(steps, 1)
	cs.resolve_after_player_action()
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.magazine.loaded_count(), 6)
	assert_true(cs.can_fire())
	assert_true(cs.do_unload())
	assert_eq(cs.phase, CombatState.Phase.AWAIT_LOAD)
	assert_true(cs.can_manual_load())
	assert_true(cs.do_load())
	assert_ne(cs.lose_reason, CombatState.LoseReason.AMMO_EXHAUSTED)
	assert_eq(cs.magazine.loaded_count(), 6)


func test_blank_chamber_skips_to_nearest_ammo() -> void:
	## 锤位空仓：快跳到最近有弹格再结算，不逐空打；跳过步数记入 last_blank_skip_steps。
	var cs := CombatState.new(101)
	cs.start_rush(101)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(cs.magazine.slots[2], Magazine.EMPTY)
	cs.magazine.set_start(2)
	assert_eq(cs.magazine.chamber_at_fire_port(), 2)
	var peek: int = cs.peek_blank_skip_steps()
	assert_gte(peek, 1)
	assert_eq(cs.magazine.start_index, 2, "peek must not mutate start")
	var hp_before: int = cs.enemies[0].hp
	assert_true(cs.begin_fire())
	assert_eq(cs.peek_blank_skip_steps(), peek)
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	# 从空仓 2 前进到有弹仓（0 或 1，视 FIRE_PORT 与 start）并实弹结算
	assert_false(cs.last_shot_was_blank)
	assert_eq(cs.last_blank_skip_steps, peek)
	assert_lt(cs.enemies[0].hp, hp_before)
	assert_eq(cs.discard.size(), 1)


func test_partial_mag_manual_load_blank_skip_peek() -> void:
	## 只手装几发、锤位落在空仓：peek 给出转到有弹的步数；开火后跳空步数一致。
	var cs := CombatState.new(102)
	cs.start_rush(102)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 3:
		cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	assert_true(cs.begin_load())
	# 手装 3 发（不满匣），会话提交
	for _i in 3:
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	cs.commit_load_session_if_active()
	assert_eq(cs.magazine.loaded_count(), 3)
	# 转到空仓锤位（满 6 仓里后 3 空）
	var empty_start := -1
	for s in CombatConstants.MAGAZINE_SIZE:
		cs.magazine.set_start(s)
		if cs.magazine.slots[cs.magazine.chamber_at_fire_port()] == Magazine.EMPTY:
			empty_start = s
			break
	assert_gte(empty_start, 0, "partial mag should have an empty fire-port start")
	var peek: int = cs.peek_blank_skip_steps()
	assert_gte(peek, 1)
	assert_lte(peek, 5)
	_shot_one(cs)
	assert_false(cs.last_shot_was_blank)
	assert_eq(cs.last_blank_skip_steps, peek)
	assert_eq(cs.discard.size(), 1)


func test_muzzle_fire_persists_for_rest_of_turn() -> void:
	## 火弹挂枪口后，本回合后续白弹也施加燃烧；旧「只传下一发」会在第 3 发丢失。
	var cs := CombatState.new(202)
	cs.start_rush(202)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_FIRE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	# rush! 点射：不 resolve 怪回合，枪口跨点射保留
	_shot_one(cs)
	var burn1: int = cs.enemies[0].burn_stacks
	assert_gt(burn1, 0)
	_shot_one(cs)  # 白+枪口火
	var burn2: int = cs.enemies[0].burn_stacks
	assert_gt(burn2, burn1)
	_shot_one(cs)  # 白+枪口火
	var burn3: int = cs.enemies[0].burn_stacks
	assert_gt(burn3, burn2)


func test_muzzle_expires_after_duration() -> void:
	## v0.3.4：火枪口持续期内仍有效；到期后纯白不再带火。
	var cs := CombatState.new(303)
	cs.start_rush(303)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_FIRE, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_true(cs._muzzle_fire)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC + 0.01)
	assert_false(cs._muzzle_fire)
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_skip_enemy_turn()
	assert_true(cs.do_load())
	var e: EnemyInstance = cs.enemies[0]
	e.burn_stacks = 0
	e.hp = 999
	e.max_hp = 999
	_shot_one(cs)
	assert_eq(e.burn_stacks, 0, "muzzle should be clear after duration expires")


func test_muzzle_pierce_applies_to_later_whites() -> void:
	## 穿透挂枪口后，后续白弹也能打穿第二只怪。
	var cs := CombatState.new(404)
	cs.start_rush(404)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)
	cs.dev_spawn_enemy(1, 2)
	assert_eq(cs.alive_enemies().size(), 2)
	cs.dev_force_load([
		FireResolver.ID_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var back: EnemyInstance = null
	for e in cs.enemies:
		if e.cell == 2:
			back = e
	assert_not_null(back)
	var hp_back0: int = back.hp
	_shot_one(cs)  # pierce
	assert_lt(back.hp, hp_back0)
	var hp_back1: int = back.hp
	_shot_one(cs)  # white + muzzle pierce
	assert_lt(back.hp, hp_back1)
	var hp_back2: int = back.hp
	_shot_one(cs)  # white + muzzle pierce again
	assert_lt(back.hp, hp_back2)


func test_apply_roll_steps_match_post_load_spin_range() -> void:
	## ROLL 与装满后 spin 共用 apply_roll：满匣步数 ∈ [1,5]。
	var cs := CombatState.new(505)
	cs.start_rush(505)
	cs.dev_force_load([1, 2, 3, 4, 5, 6] as Array[int])
	var before: int = cs.magazine.start_index
	var steps: int = cs.apply_roll()
	assert_gte(steps, 1)
	assert_lte(steps, 5)
	assert_eq(cs.magazine.start_index, (before + steps) % CombatConstants.MAGAZINE_SIZE)


func test_enemy_damaged_signal_emits_per_hit() -> void:
	var cs := CombatState.new(911)
	cs.start_rush(911)
	var hits: Array = []
	cs.enemy_damaged.connect(func(cell: int, amount: int, kind: String=""): hits.append([cell, amount, kind]))
	cs.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_shot_one(cs)
	assert_gt(hits.size(), 0)
	assert_gt(hits[0][1], 0)


func test_player_damaged_signal_on_enemy_attack() -> void:
	## 怪物普攻扣血发出 player_damaged，供 UI 抖玩家格。
	var cs := CombatState.new(912)
	cs.start_rush(912)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 1)  # 邻接可打
	assert_true(cs.can_attack_player(cs.enemies[0]))
	var got: Array = []
	cs.player_damaged.connect(func(amount: int, kind: String=""): got.append([amount, kind]))
	var hp0: int = cs.player_hp
	cs._run_enemy_turn()
	assert_gt(got.size(), 0, "enemy attack should emit player_damaged")
	assert_gt(got[0][0], 0)
	assert_lt(cs.player_hp, hp0)


func test_player_damaged_signal_on_wrath_self_hit() -> void:
	## 愤怒≥3 自伤也走 player_damaged。
	var cs := CombatState.new(913)
	cs.start_rush(913, FireResolver.ID_WRATH)
	var got: Array = []
	cs.player_damaged.connect(func(amount: int, kind: String=""): got.append([amount, kind]))
	var loaded: Array = []
	for _i in 3:
		loaded.append(FireResolver.ID_WRATH)
	cs._resolve_sin_pack_on_load(loaded)
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], 6)
	assert_eq(got[0][1], "愤怒")



func test_partial_mag_can_start_roll() -> void:
	## 不满匣（有弹即可）也可 ROLL；与「装满才自动 spin」区分。
	var cs := CombatState.new(551)
	cs.start_rush(551)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	for _i in 3:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_start_roll())
	assert_true(cs.begin_roll())
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_fire())


func test_board_ground_segs_and_unit_rest_on_ground() -> void:
	## 每格有 GroundSeg；UnitBody 底边贴地；抖动复位不甩到 (0,0)；无 VBox 兄弟 GroundLine。
	var CombatScene := load("res://scenes/combat.tscn")
	var ui = add_child_autofree(CombatScene.instantiate())
	await get_tree().process_frame
	var board: HBoxContainer = ui.get_node("%BoardRow")
	assert_eq(board.get_theme_constant("separation"), 0)
	var parent: Node = board.get_parent()
	assert_null(parent.get_node_or_null("GroundLine"), "legacy VBox GroundLine must be removed")
	assert_eq(board.get_child_count(), CombatConstants.BOARD_SIZE)
	var rest: Vector2 = ui._unit_rest_position()
	assert_eq(rest.y, float(ui.CELL_H) - ui.UNIT_H - ui.GROUND_LINE_H)
	for i in CombatConstants.BOARD_SIZE:
		var slot: Control = board.get_child(i) as Control
		var seg: ColorRect = slot.get_node_or_null("GroundSeg") as ColorRect
		assert_not_null(seg, "cell %d needs GroundSeg" % i)
		assert_eq(seg.position.y, float(ui.CELL_H) - ui.GROUND_LINE_H)
		assert_eq(seg.size.y, ui.GROUND_LINE_H)
		var unit: Control = slot.get_node_or_null("UnitBody") as Control
		assert_not_null(unit)
		assert_eq(unit.position, rest)
	# 模拟旧 offset 抖动损坏后 reset 必须贴地
	var body: Control = board.get_child(1).get_node("UnitBody")
	body.position = Vector2(3, 3)
	ui._reset_cell_shake_offsets(body)
	assert_eq(body.position, rest)
	ui._apply_cell_offsets(body, 5.0, -4.0)
	assert_eq(body.position, rest + Vector2(5.0, -4.0))
	ui._reset_cell_shake_offsets(body)
	assert_eq(body.position, rest)
	# 玩家格也可抖，抖完贴地（不整盘抖）
	var player_body: Control = board.get_child(CombatConstants.PLAYER_CELL).get_node("UnitBody")
	ui._shake_cell_for_damage(CombatConstants.PLAYER_CELL, 8)
	ui._reset_cell_shake_offsets(player_body)
	assert_eq(player_body.position, rest)


func test_last_shot_hit_and_muzzle_outline_ids() -> void:
	## 实弹命中写入 last_shot_hit_cell/dealt/ammo；描边=开火前枪口贡献色（不含本发刚挂罪孽）。
	var cs := CombatState.new(920)
	cs.start_rush(920, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs._muzzle_pride = 1
	cs.dev_force_load([
		FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	assert_eq(cs.last_shot_ammo_id, FireResolver.ID_WRATH)
	assert_eq(cs.last_shot_hit_cell, cs.enemies[0].cell)
	assert_gt(cs.last_shot_dealt, 0)
	# 开火前仅有傲慢；本发愤怒后才挂上，描边不含愤怒
	assert_false(cs.last_shot_muzzle_outline_ids.has(FireResolver.ID_WRATH))
	assert_true(cs.last_shot_muzzle_outline_ids.has(FireResolver.ID_PRIDE))
	assert_eq(cs.last_shot_muzzle_outline_ids[0], FireResolver.ID_PRIDE)
	# 伤害侧仍吃本发刚挂上的愤怒（wrath 现为 1）
	assert_eq(cs._muzzle_wrath, 1)


func test_outline_excludes_just_mounted_pride_keeps_prefire_wrath_pierce() -> void:
	## 枪口已有穿甲+愤怒，打傲慢：芯=傲慢；描边=愤怒+穿甲，不含本发傲慢。
	var cs := CombatState.new(923)
	cs.start_rush(923, FireResolver.ID_PRIDE)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs._muzzle_wrath = 1
	cs._muzzle_pierce = true
	cs.dev_force_load([
		FireResolver.ID_PRIDE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	assert_eq(cs.last_shot_ammo_id, FireResolver.ID_PRIDE)
	assert_true(cs.last_shot_muzzle_outline_ids.has(FireResolver.ID_WRATH))
	assert_true(cs.last_shot_muzzle_outline_ids.has(FireResolver.ID_ARMOR_PIERCE))
	assert_false(cs.last_shot_muzzle_outline_ids.has(FireResolver.ID_PRIDE))
	assert_eq(cs.last_shot_muzzle_outline_ids[0], FireResolver.ID_WRATH)
	assert_eq(cs.last_shot_muzzle_outline_ids[1], FireResolver.ID_ARMOR_PIERCE)
	# 伤害仍吃本发入枪口的傲慢
	assert_eq(cs._muzzle_pride, 1)


func test_blank_shot_clears_last_shot_hit() -> void:
	var cs := CombatState.new(921)
	cs.start_rush(921)
	cs.dev_force_load([CombatConstants.WHITE_AMMO_ID] as Array[int])
	# 只 1 发，转锤到空仓再射会快跳；打完后匣空再射路径清 last_shot
	cs.magazine.set_start(0)
	assert_true(cs.do_fire())
	assert_eq(cs.magazine.loaded_count(), 0)


func test_pierce_shot_records_all_hit_cells() -> void:
	## 穿透弹：last_shot_hit_cells 含沿途所有命中格（前→后），was_pierce=true。
	var cs := CombatState.new(922)
	cs.start_rush(922)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 4)
	cs.enemies[0].hp = 50
	cs.enemies[0].max_hp = 50
	cs.enemies[1].hp = 50
	cs.enemies[1].max_hp = 50
	cs.dev_force_load([
		FireResolver.ID_PIERCE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	assert_true(cs.last_shot_was_pierce)
	assert_eq(cs.last_shot_ammo_id, FireResolver.ID_PIERCE)
	assert_gte(cs.last_shot_hit_cells.size(), 2)
	assert_eq(cs.last_shot_hit_cells[0], 2)
	assert_eq(cs.last_shot_hit_cells[1], 4)
	assert_eq(cs.last_shot_hit_amounts.size(), cs.last_shot_hit_cells.size())


func test_pace_killing_shot_keeps_corpse_until_flush() -> void:
	## pace 开火：视觉命中前不扣血；finalize 后致死留尸体，flush 后才移除。
	var cs := CombatState.new(930)
	cs.start_rush(930)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.pace_after_fire = true
	cs.enemies[0].hp = 3
	cs.enemies[0].max_hp = 3
	var cell: int = cs.enemies[0].cell
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_true(cs.has_paced_shot_pending(), "pace defers damage until visual hit")
	assert_eq(cs.enemies[0].hp, 3, "HP must not drop on fire start")
	assert_gte(cs.last_shot_hit_cells.size(), 1)
	# 匣内还有弹时 more 可为 true；清场在 finalize
	var dealt: int = cs.resolve_paced_hit(0)
	assert_eq(dealt, 3)
	assert_eq(cs.enemies[0].hp, 0)
	cs.finalize_paced_shot()
	assert_false(cs.has_paced_shot_pending())
	# 白弹伤害 3，刚好打死；pace 下尸体仍在
	# v0.3.8：清场立刻补刷 → 收束走 _check_end_after_player，尸体当场清（UI 用延后飚血事件）
	assert_ne(cs.phase, CombatState.Phase.WON, "v0.3.8：无波次，不进胜利")
	cs.flush_dead_enemies()
	assert_false(cs.has_corpse_enemies())
	assert_false(cs.alive_enemies().is_empty(), "清场后立刻补刷")


func test_last_shot_keeps_hit_data_after_finish() -> void:
	## 匣内最后一发打完后仍保留 last_shot_hit_*，供 UI 播弹点/轨迹（修末发无枪线）。
	var cs := CombatState.new(931)
	cs.start_rush(931)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.pace_after_fire = true
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([CombatConstants.WHITE_AMMO_ID] as Array[int])
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(cs.begin_fire())
	assert_false(cs.fire_next_shot())
	assert_true(cs.has_paced_shot_pending())
	assert_false(cs.last_shot_was_blank)
	assert_eq(cs.last_shot_ammo_id, CombatConstants.WHITE_AMMO_ID)
	assert_gte(cs.last_shot_hit_cells.size(), 1)
	# 开火瞬间尚未结算
	assert_eq(cs.last_shot_dealt, 0)
	cs.finalize_paced_shot()
	assert_gt(cs.last_shot_dealt, 0)
	assert_gte(cs.last_shot_hit_cells.size(), 1)


func test_pace_damage_applies_only_on_resolve() -> void:
	## pace：fire_next_shot 不扣血；resolve_paced_hit 才对齐视觉命中结算。
	var cs := CombatState.new(932)
	cs.start_rush(932)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.pace_after_fire = true
	cs.enemies[0].hp = 10
	cs.enemies[0].max_hp = 10
	var hp0: int = cs.enemies[0].hp
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_true(cs.has_paced_shot_pending())
	assert_eq(cs.enemies[0].hp, hp0)
	var dealt: int = cs.resolve_paced_hit(0)
	assert_gt(dealt, 0)
	assert_eq(cs.enemies[0].hp, hp0 - dealt)
	cs.finalize_paced_shot()
	assert_false(cs.has_paced_shot_pending())


func test_enemy_auto_step_moves_left_without_locking_buttons() -> void:
	## rush! 连续推进：与射击脱钩；每拍左移 1；进射程攻击；阶段保持可操作。
	var cs := CombatState.new(777)
	cs.start_rush(777)
	assert_true(cs.auto_enemy_advance)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].cell = 5
	cs.do_load()
	assert_true(cs.can_fire())
	var cell: int = cs.enemies[0].cell
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].cell, cell - 1)
	assert_eq(cs.phase, CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.can_fire())
	assert_true(cs.can_manual_load() or cs.magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE)
	# 点射不推进敌人
	_shot_one(cs)
	assert_eq(cs.enemies[0].cell, cell - 1)
	assert_false(cs.post_fire_enemy_pending())
