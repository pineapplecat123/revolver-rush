extends GutTest
## v0.4.21：头顶圆环倒计时、炸药爆炸、射速帽、删停用弹、罪孽不进商店/奖励、击杀掉金。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const SINS: Array[int] = [16, 17, 18, 34, 35, 36, 37]
const REMOVED: Array[int] = [2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _sandbox(seed_v: int = 42100) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH)
	cs.rng.seed = seed_v
	return cs


func _ring(entries: Array, id: String) -> Dictionary:
	for e in entries:
		if str(e.get("id", "")) == id:
			return e
	return {}


func test_version_and_fire_cap_constants() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.21"' in text)
	assert_almost_eq(CombatConstants.MAX_FIRE_RATE_HZ, 10.0, 0.001)
	assert_almost_eq(CombatConstants.MIN_FIRE_INTERVAL_SEC, 0.1, 0.001)
	assert_almost_eq(CombatConstants.KILL_GOLD_DROP_CHANCE, 0.25, 0.001)
	assert_eq(CombatConstants.KILL_GOLD_DROP_AMOUNT, 2)
	assert_almost_eq(CombatConstants.KILL_GOLD_BOSS_DROP_CHANCE, 1.0, 0.001)
	assert_eq(CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT, 8)


func test_second_fire_tap_inside_interval_is_swallowed() -> void:
	var cs := _sandbox(42101)
	cs.sandbox_clear_enemies()
	cs.sandbox_spawn_dummy(999, 3)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var a: Array = cs.fire_tap()
	assert_eq(a.size(), 2, "同步连射打光两发")
	assert_eq(cs.magazine.loaded_count(), 0)
	cs.magazine.set_slot(0, CombatConstants.WHITE_AMMO_ID)
	cs.magazine.start_index = 0
	var b: Array = cs.fire_tap()
	assert_eq(b.size(), 0, "射速帽内再按被吞")
	cs.tick_combat_time(CombatConstants.MIN_FIRE_INTERVAL_SEC * 0.5)
	assert_eq(cs.fire_tap().size(), 0)
	cs.tick_combat_time(CombatConstants.MIN_FIRE_INTERVAL_SEC)
	assert_eq(cs.fire_tap().size(), 1)




func test_status_rings_shrink_and_cover_dummies() -> void:
	var cs := _sandbox(42104)
	var e: EnemyInstance = cs.enemies[0]
	cs.sandbox_set_enemy_status({"burn": 4, "confuse": 2.0, "slow_stacks": 2, "slow_sec": 3.0})
	var full: Array = e.status_ring_entries(cs.dot_tick_remaining())
	assert_almost_eq(float(_ring(full, "burn").get("ratio", 0.0)), 1.0, 0.02)
	assert_almost_eq(float(_ring(full, "confuse").get("ratio", 0.0)), 1.0, 0.02)
	assert_gt(float(_ring(full, "slow").get("ratio", 0.0)), 0.9)
	cs.tick_combat_time(0.25)
	var mid: Array = e.status_ring_entries(cs.dot_tick_remaining())
	assert_lt(float(_ring(mid, "burn").get("ratio", 1.0)), float(_ring(full, "burn").get("ratio", 0.0)))
	assert_lt(float(_ring(mid, "confuse").get("ratio", 1.0)), 1.0)
	e.gas_stacks = 3
	e.tick_status_timers(5.0)
	assert_almost_eq(float(_ring(e.status_ring_entries(-1.0), "gas").get("ratio", 0.0)), 1.0, 0.001)
	# 三木桩都能挂上环
	for dummy in cs.enemies:
		dummy.burn_stacks = 2
		dummy.burn_peak = 2
		assert_false(dummy.status_ring_entries(0.5).is_empty())


func test_status_rings_draw_above_three_dummies() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(ui.state.enemies.size(), 3)
	for e in ui.state.enemies:
		e.burn_stacks = 3
		e.burn_peak = 3
		e.apply_confuse(1.5)
	ui._update_enemy_status_rings()
	for cell in CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS:
		var slot: Control = ui.board_row.get_child(cell)
		var rings: EnemyStatusRings = slot.get_node("StatusRings")
		var unit: Control = slot.get_node("UnitBody")
		assert_true(rings.visible)
		assert_gte(rings.entries.size(), 2)
		assert_lt(rings.position.y + rings.size.y, unit.position.y + 2.0)
	ui.state.tick_combat_time(0.4)
	ui._update_enemy_status_rings()
	var again: EnemyStatusRings = ui.board_row.get_child(3).get_node("StatusRings")
	assert_lt(float(_ring(again.entries, "confuse").get("ratio", 1.0)), 1.0)


func test_explosive_detonation_signal_and_vfx() -> void:
	var cs := _sandbox(42105)
	cs.sandbox_clear_enemies()
	var e: EnemyInstance = cs.sandbox_spawn_dummy(999, 4)
	e.burn_stacks = 4
	var booms: Array = []
	cs.explosive_detonated.connect(func(cell: int, n_side: int) -> void:
		booms.append({"cell": cell, "n": n_side})
	)
	cs.sandbox_set_muzzle("explosive", 1, 4.0)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = e.hp
	cs.fire_tap()
	assert_eq(booms.size(), 1)
	assert_eq(int(booms[0]["cell"]), e.cell)
	assert_lt(e.hp, hp0)
	# 没在烧就不炸
	var cs2 := _sandbox(42106)
	cs2.sandbox_clear_enemies()
	var quiet: EnemyInstance = cs2.sandbox_spawn_dummy(999, 4)
	var booms2: Array = []
	cs2.explosive_detonated.connect(func(_c: int, _n: int) -> void:
		booms2.append(1)
	)
	cs2.dev_force_load([
		FireResolver.ID_EXPLOSIVE,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs2.fire_tap()
	assert_eq(booms2.size(), 0)
	assert_lt(quiet.hp, 999)

	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	ui._spawn_explosion_vfx(5, 1)
	var vfx: Node = ui.find_child("ExplosionVfx", true, false)
	assert_not_null(vfx)
	assert_gt(vfx.get_child_count(), 2)


func test_removed_ammo_ids_are_gone() -> void:
	for aid in REMOVED:
		assert_true(DataRegistry.get_ammo(aid).is_empty(), "id %d should be deleted" % aid)
		assert_false(DataRegistry.is_ammo_reward_eligible(aid))


func test_shop_and_rewards_never_offer_sins() -> void:
	for aid in SINS:
		assert_true(DataRegistry.is_sin_ammo(aid))
		assert_true(DataRegistry.is_ammo_enabled(aid))
		assert_false(DataRegistry.is_ammo_reward_eligible(aid))
	for seed_v in range(1, 41):
		var shop := ShopState.new()
		shop.begin(999, [CombatConstants.WHITE_AMMO_ID], 1, seed_v * 17)
		for aid in shop.stock:
			assert_false(DataRegistry.is_sin_ammo(int(aid)), "shop seed %d stock %s" % [seed_v, aid])
		shop.reroll()
		for aid2 in shop.stock:
			assert_false(DataRegistry.is_sin_ammo(int(aid2)))
		var cs := CombatState.new(seed_v + 9000)
		cs.start_sandbox(seed_v + 9000, FireResolver.ID_WRATH)
		for _i in 8:
			for choice in cs.generate_reward_choices():
				assert_false(DataRegistry.is_sin_ammo(int(choice)), "reward %s" % choice)
	# 开局仍有 5 颗所选罪孽；沙盒仍可手动塞
	var rush := CombatState.new(42110)
	rush.start_rush(42110, FireResolver.ID_LUST)
	var n := 0
	for x in rush.bag:
		if int(x) == FireResolver.ID_LUST:
			n += 1
	assert_eq(n, CombatConstants.STARTER_SIN_COUNT)
	var sb := _sandbox(42111)
	sb.dev_clear_bag()
	sb.sandbox_add_ammo(FireResolver.ID_ENVY, 1, 0.0)
	assert_true(FireResolver.ID_ENVY in sb.bag)


func test_kill_gold_chance_override_and_dummies() -> void:
	var cs := _sandbox(42120)
	cs.sandbox_clear_enemies()
	cs.gold = 0
	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 4)
	cs.enemies[0].hp = 0
	cs.kill_gold_chance_override = 0.0
	cs.rng.seed = 1
	var got: Array = []
	cs.hooks.subscribe(&"on_kill_gold", func(p: Dictionary) -> void:
		got.append(p)
	)
	cs._remove_dead()
	assert_eq(cs.gold, 0, "概率 0 不掉")
	assert_eq(got.size(), 0)

	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 5)
	cs.enemies[0].hp = 0
	cs.kill_gold_chance_override = 1.0
	cs.rng.seed = 2
	var kills: Array = []
	cs.hooks.subscribe(&"on_kill", func(p: Dictionary) -> void:
		kills.append(int(p.get("gold", -1)))
	)
	cs._remove_dead()
	assert_eq(cs.gold, 0, "掉落还没捡到，钱包不加")
	assert_eq(cs.pending_gold_total(), CombatConstants.KILL_GOLD_DROP_AMOUNT)
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].get("amount", 0)), CombatConstants.KILL_GOLD_DROP_AMOUNT)
	assert_eq(kills[kills.size() - 1], CombatConstants.KILL_GOLD_DROP_AMOUNT)
	assert_eq(cs.collect_gold_piece(int(cs.gold_drops[0]["id"]), CombatConstants.KILL_GOLD_DROP_AMOUNT), CombatConstants.KILL_GOLD_DROP_AMOUNT)
	assert_eq(cs.gold, CombatConstants.KILL_GOLD_DROP_AMOUNT)

	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(20, 6)
	dummy.hp = 0
	cs.kill_gold_chance_override = 1.0
	var before: int = cs.gold
	cs._remove_dead()
	assert_eq(cs.gold, before, "木桩不掉金")

	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 7)
	cs.enemies[0].hp = 0
	cs.kill_gold_chance_override = 0.0
	cs.rng.seed = 3
	cs._remove_dead()
	assert_eq(cs.pending_gold_total(), CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT)
	assert_eq(cs.collect_gold_piece(int(cs.gold_drops[0]["id"]), CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT), CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT)
	assert_eq(cs.gold, before + CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT, "Boss 必掉，不受普通概率覆盖")
