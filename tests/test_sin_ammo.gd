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


## 罪孽：开局 10+5、装≥3 负面、枪口叠层、敌人数值与超僵面前召唤。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_starter_bag_is_ten_mediocre_plus_five_sin() -> void:
	var cs := CombatState.new(901)
	cs.start_rush(901, FireResolver.ID_GREED)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	var white := 0
	var sin_n := 0
	for id in cs.bag:
		if int(id) == CombatConstants.WHITE_AMMO_ID:
			white += 1
		elif int(id) == FireResolver.ID_GREED:
			sin_n += 1
	assert_eq(white, 10, "must be 10 mediocre/white")
	assert_eq(sin_n, 5, "must be 5 chosen sin")
	assert_eq(cs.selected_sin_ammo_id, FireResolver.ID_GREED)


func test_choose_sin_refills_bag() -> void:
	var cs := CombatState.new(902)
	cs.start_rush(902, FireResolver.ID_WRATH)
	cs.choose_sin(FireResolver.ID_PRIDE)
	assert_eq(cs.selected_sin_ammo_id, FireResolver.ID_PRIDE)
	var pride := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_PRIDE:
			pride += 1
	assert_eq(pride, 5)
	assert_eq(cs.bag.size(), 15)


func test_wrath_pack_of_three_self_damage() -> void:
	var cs := CombatState.new(903)
	cs.start_rush(903, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	for id in [FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	var hp0: int = cs.player_hp
	assert_true(cs.do_load())
	assert_eq(cs.player_hp, hp0 - 6)


func test_wrath_muzzle_doubles_damage() -> void:
	var cs := CombatState.new(904)
	cs.start_rush(904, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 500
	cs.enemies[0].max_hp = 500
	cs.dev_force_load([
		FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(cs._muzzle_wrath, 1)
	assert_eq(hp0 - cs.enemies[0].hp, 6)


func test_pride_pack_pulls_enemies_forward() -> void:
	var cs := CombatState.new(905)
	cs.start_rush(905, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 7)
	cs.dev_spawn_enemy(1, 9)
	cs.bag.clear()
	for id in [FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	var cells: Array = []
	for e in cs.enemies_sorted_by_cell():
		cells.append(e.cell)
	assert_eq(cells, [1, 2])


func test_greed_pack_subtracts_gold() -> void:
	var cs := CombatState.new(906)
	cs.start_rush(906, FireResolver.ID_GREED)
	cs.gold = 2
	cs.bag.clear()
	for id in [FireResolver.ID_GREED, FireResolver.ID_GREED, FireResolver.ID_GREED,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	assert_eq(cs.gold, -4)


func test_pride_persists_greed_clears_by_duration() -> void:
	## 傲慢时长 12s > 贪婪 4s：贪婪整段到期后傲慢仍在。
	var cs := CombatState.new(907)
	cs.start_rush(907, FireResolver.ID_PRIDE)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].cell = 9
	cs._muzzle_pride = 2
	cs._muzzle_greed = 3
	cs._muzzle_greed_t = CombatConstants.MUZZLE_DURATION_GREED_SEC
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = CombatConstants.MUZZLE_DURATION_WRATH_SEC
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs._muzzle_pride, 2)
	assert_eq(cs._muzzle_greed, 3)
	assert_eq(cs._muzzle_wrath, 1)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_GREED_SEC + 0.01)
	assert_eq(cs._muzzle_pride, 2)
	assert_eq(cs._muzzle_greed, 0)
	assert_eq(cs._muzzle_wrath, 0)


func test_enemy_table_hp_and_zombie_tag() -> void:
	assert_eq(int(DataRegistry.get_enemy(1).get("hp")), 10)
	assert_eq(int(DataRegistry.get_enemy(2).get("hp")), 15)
	assert_eq(int(DataRegistry.get_enemy(3).get("hp")), 20)
	assert_eq(int(DataRegistry.get_enemy(4).get("hp")), 25)
	var tags = DataRegistry.get_enemy(4).get("tags", [])
	assert_true("僵尸" in tags)
	assert_eq(int(DataRegistry.get_enemy(5).get("hp")), 50)


func test_super_zombie_summons_in_front() -> void:
	var cs := CombatState.new(908)
	cs.start_rush(908, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 5)
	assert_true(cs.tick_enemy_auto_step())
	var boss: EnemyInstance = null
	var zcell := -1
	for e in cs.enemies:
		if e.def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			boss = e
		elif e.def_id == CombatConstants.ZOMBIE_ENEMY_ID:
			zcell = e.cell
	assert_ne(boss, null)
	assert_eq(zcell, boss.cell - 1, "summon must be in front (toward player)")


func test_zombie_regens_five_hp() -> void:
	var cs := CombatState.new(909)
	cs.start_rush(909, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.ZOMBIE_ENEMY_ID, 8)
	cs.enemies[0].hp = 20
	cs.enemies[0].max_hp = 50
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(cs.enemies[0].hp, 25)


func test_manual_load_one_chamber_at_a_time() -> void:
	var cs := CombatState.new(910)
	cs.start_rush(910, FireResolver.ID_WRATH)
	cs.bag.clear()
	for _i in 3:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.can_manual_load())
	assert_true(cs.begin_load())
	var r1: Dictionary = cs.load_next_chamber()
	assert_true(bool(r1.get("ok", false)))
	assert_false(bool(r1.get("done", false)))
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(cs.can_manual_load())
	cs.apply_load_rotate()
	var r2: Dictionary = cs.load_next_chamber()
	assert_true(bool(r2.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 2)
	cs.apply_load_rotate()
	var r3: Dictionary = cs.load_next_chamber()
	assert_true(bool(r3.get("ok", false)))
	assert_true(bool(r3.get("done", false)), "bag empty after 3rd should complete session")
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_false(cs.is_busy_loading())
	assert_eq(cs.bag_reset_count, 1)
	assert_true(cs.can_manual_load(), "bag refilled immediately; mag not full")


func test_manual_load_one_then_can_continue_and_fire() -> void:
	## 手装 1 发后仍可再装；且可直接开火（提交装填会话）。
	var cs := CombatState.new(920)
	cs.start_rush(920, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	for _i in 4:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.begin_load())
	var r1: Dictionary = cs.load_next_chamber()
	assert_true(bool(r1.get("ok", false)))
	assert_false(bool(r1.get("done", false)))
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_true(cs.is_busy_loading())
	assert_true(cs.can_manual_load(), "should still manual-load after 1")
	assert_true(cs.can_fire(), "should be able to fire after 1 manual load")
	cs.apply_load_rotate()
	var r2: Dictionary = cs.load_next_chamber()
	assert_true(bool(r2.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_true(cs.can_fire())
	assert_true(cs.begin_fire())
	assert_false(cs.is_busy_loading(), "fire should commit load session")
	assert_eq(cs.phase, CombatState.Phase.FIRING)


func test_pride_pack_four_or_more_also_pulls() -> void:
	## 口头：≥3 触发；4 发傲慢也应拉近。
	var cs := CombatState.new(930)
	cs.start_rush(930, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 7)
	cs.dev_spawn_enemy(1, 9)
	cs.bag.clear()
	for id in [FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE, FireResolver.ID_PRIDE,
			CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]:
		cs.bag.append(id)
	assert_true(cs.do_load())
	var cells: Array = []
	for e in cs.enemies_sorted_by_cell():
		cells.append(e.cell)
	assert_eq(cells, [1, 2])


func test_manual_load_three_pride_then_fire_pulls() -> void:
	## v0.3.5：手装第 3 颗傲慢入膛即刻拉近（不再等提交/开火）。袋内仅傲慢，避免随机抽偏。
	var cs := CombatState.new(931)
	cs.start_rush(931, FireResolver.ID_PRIDE)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 8)
	cs.bag.clear()
	for _i in 5:
		cs.bag.append(FireResolver.ID_PRIDE)
	assert_true(cs.begin_load())
	for _i in 3:
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	assert_true(cs.is_busy_loading(), "3/6 手装后会话应仍进行")
	assert_eq(cs.enemies[0].cell, 1, "第 3 颗入膛即拉近，无需提交")
	assert_true(cs.begin_fire(), "开火应提交装填会话")
	assert_eq(cs.enemies[0].cell, 1)


func test_outgoing_damage_rounds_half_up() -> void:
	## 傲慢×1 → ×1.25；底伤 3 → 3.75 → 四舍五入 4（旧 floor 会得 3）。
	var cs := CombatState.new(932)
	cs.start_rush(932, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 1
	assert_eq(cs._scale_outgoing_damage(3), 4)
	assert_eq(cs.muzzle_outgoing_multiplier(), 1.25)
	cs._muzzle_wrath = 1
	# ×2 × 1.25 = 2.5；3×2.5=7.5 → 8
	assert_eq(cs._scale_outgoing_damage(3), 8)


func test_muzzle_damage_tip_no_mod_and_with_stacks() -> void:
	var cs := CombatState.new(933)
	cs.start_rush(933, FireResolver.ID_WRATH)
	var tip0 := cs.muzzle_damage_tip_text()
	assert_true(tip0.contains("无修正") or tip0.contains("×1"))
	cs._muzzle_wrath = 2
	cs._muzzle_pride = 1
	var tip := cs.muzzle_damage_tip_text()
	assert_true(tip.contains("愤怒"))
	assert_true(tip.contains("傲慢"))
	assert_true(tip.contains("合成输出倍率"))
	assert_true(tip.contains("四舍五入"))


func test_lose_clears_pride_muzzle() -> void:
	var cs := CombatState.new(934)
	cs.start_rush(934, FireResolver.ID_PRIDE)
	cs._muzzle_pride = 4
	cs._muzzle_wrath = 2
	cs.player_hp = 0
	cs._lose_hp()
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs._muzzle_pride, 0)
	assert_eq(cs._muzzle_wrath, 0)


func test_greed_gold_gained_signal_emits_amount() -> void:
	var cs := CombatState.new(936)
	cs.start_rush(936, FireResolver.ID_GREED)
	cs._muzzle_greed = 10
	cs.rng.seed = 1
	var got: Array = []
	cs.gold_gained.connect(func(cell, amount): got.append([cell, amount]))
	# 强制多次掉金：层数高 + 固定种子
	cs._try_greed_gold_drop(6, 3)
	assert_gt(got.size(), 0, "should emit at least one gold float")
	assert_eq(got[0][0], 3)
	assert_eq(got[0][1], 6)


func test_empty_bag_at_turn_start_auto_resets_nonempty_skips() -> void:
	var cs := CombatState.new(940)
	cs.start_rush(940, FireResolver.ID_WRATH)
	assert_eq(cs.bag_reset_count, 0)
	assert_false(cs._auto_reset_bag_if_empty_at_turn_start())
	assert_eq(cs.bag_reset_count, 0)
	cs.bag.clear()
	cs.bag_temp.clear()
	assert_true(cs._auto_reset_bag_if_empty_at_turn_start())
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL, "v0.3.8：重置只还基础池，不再 +N")
	assert_eq(cs.count_temporary_in_bag(), 0)
	assert_true(cs.can_manual_load())


