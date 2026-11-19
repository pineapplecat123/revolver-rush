extends GutTest
## v0.4.64：普通僵尸降血/再生/减速；地图商店到点先停刷，清场后再开店。


const CIV := 1
const BEAR := 3
const ZOMBIE := CombatConstants.ZOMBIE_ENEMY_ID
const SUPER := CombatConstants.SUPER_ZOMBIE_ENEMY_ID


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false


func _rush(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v)
	return cs


func _clear_field(cs: CombatState) -> void:
	for e in cs.enemies:
		e.hp = 0
	cs._remove_dead()


func _put(cs: CombatState, def_id: int, cell: int, hp: int = -1) -> EnemyInstance:
	var e := EnemyInstance.new(DataRegistry.get_enemy(def_id), cell)
	if hp >= 0:
		e.max_hp = hp
		e.hp = hp
	if cs.free_walk:
		e.pos_x = float(cell)
	cs.enemies.append(e)
	return e


func test_version_is_at_least_0_4_64() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.64") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.64" in log)
	assert_true("普通僵尸" in log)
	assert_true("地图商店" in log)


func test_ordinary_zombie_hp_regen_and_others_unchanged() -> void:
	assert_eq(int(DataRegistry.get_enemy(CIV).get("hp")), 10)
	assert_eq(int(DataRegistry.get_enemy(2).get("hp")), 15)
	assert_eq(int(DataRegistry.get_enemy(BEAR).get("hp")), 20)
	assert_eq(int(DataRegistry.get_enemy(ZOMBIE).get("hp")), 20)
	assert_eq(int(DataRegistry.get_enemy(SUPER).get("hp")), 50)
	assert_eq(CombatConstants.ZOMBIE_REGEN, 2)
	assert_eq(CombatConstants.SUPER_ZOMBIE_REGEN, 5)
	assert_eq(CombatConstants.zombie_regen_amount(ZOMBIE), 2)
	assert_eq(CombatConstants.zombie_regen_amount(SUPER), 5)
	assert_eq(CombatConstants.zombie_regen_amount(CIV), 0)
	assert_almost_eq(CombatConstants.ENEMY_AUTO_STEP_SEC, 3.3, 0.0001)
	assert_almost_eq(CombatConstants.ZOMBIE_AUTO_STEP_SEC, 4.5, 0.0001)
	assert_almost_eq(CombatConstants.enemy_auto_step_sec(ZOMBIE), 4.5, 0.0001)
	assert_almost_eq(CombatConstants.enemy_auto_step_sec(SUPER), 3.3, 0.0001)
	assert_almost_eq(CombatConstants.enemy_auto_step_sec(CIV), 3.3, 0.0001)
	assert_true("4.5" in str(DataRegistry.get_enemy(ZOMBIE).get("special", "")))
	var tag: Dictionary = DataRegistry.get_tag("僵尸")
	var effect := str(tag.get("effect", ""))
	assert_true("2" in effect)
	assert_true("5" in effect)


func test_summoned_zombie_uses_ordinary_hp() -> void:
	var cs := _rush(46401)
	cs.spawn_paused = true
	cs.enemies.clear()
	var boss := _put(cs, SUPER, 4, 50)
	assert_eq(boss.max_hp, 50)
	# 面前格 3 空，召唤普通僵尸。
	cs._try_super_zombie_summons()
	var summoned: EnemyInstance = null
	for e in cs.alive_enemies():
		if int(e.def_id) == ZOMBIE:
			summoned = e
			break
	assert_not_null(summoned, "超级僵尸应召唤普通僵尸")
	assert_eq(summoned.max_hp, 20)
	assert_eq(summoned.hp, 20)
	assert_eq(CombatConstants.enemy_auto_step_sec(summoned.def_id), 4.5)
	assert_eq(CombatConstants.zombie_regen_amount(summoned.def_id), 2)


func test_regen_amounts_on_cell_tick() -> void:
	## v0.4.65：普通僵尸不再走全局落格拍；超级僵尸仍每拍 +5。
	var cs := _rush(46402)
	cs.spawn_paused = true
	cs.enemies.clear()
	var z := _put(cs, ZOMBIE, 3, 20)
	var s := _put(cs, SUPER, 5, 50)
	z.hp = 10
	s.hp = 40
	cs._tick_zombie_regen_end_of_enemy_turn()
	assert_eq(z.hp, 10, "普通僵尸不再吃全局落格拍再生")
	assert_eq(s.hp, 45, "超级僵尸每拍仍 +5")
	s.hp = 49
	cs._tick_zombie_regen_end_of_enemy_turn()
	assert_eq(s.hp, 50, "超级僵尸再生不超过上限")


func test_ordinary_zombie_walks_slower_in_free_walk() -> void:
	var cs := CombatState.new(46403)
	cs.free_walk = true
	cs.start_rush(46403)
	cs.spawn_paused = true
	cs.enemies.clear()
	var civ := _put(cs, CIV, 8)
	var z := _put(cs, ZOMBIE, 8)
	var s := _put(cs, SUPER, 8)
	civ.speed_mul = 1.0
	z.speed_mul = 1.0
	s.speed_mul = 1.0
	civ.atk = 0
	z.atk = 0
	s.atk = 0
	cs.advance_enemy_glide(1.0)
	assert_almost_eq(civ.pos_x, 7.0, 0.0001, "其他敌人仍按 3.3 秒/格")
	assert_almost_eq(s.pos_x, 7.0, 0.0001, "超级僵尸移速不变")
	assert_almost_eq(z.pos_x, 8.0 - (3.3 / 4.5), 0.0001, "普通僵尸按 4.5 秒/格")
	# 个体 ±13% 仍叠在基础速度上（单独再走一格，避免和上面那只已经走过的比较）
	cs.enemies.clear()
	var z2 := _put(cs, ZOMBIE, 8)
	z2.speed_mul = 1.13
	z2.atk = 0
	var z3 := _put(cs, ZOMBIE, 8)
	z3.speed_mul = 0.87
	z3.atk = 0
	cs.advance_enemy_glide(1.0)
	var base_step: float = 3.3 / 4.5
	assert_almost_eq(z2.pos_x, 8.0 - base_step * 1.13, 0.0001, "更快的个体走得更远")
	assert_almost_eq(z3.pos_x, 8.0 - base_step * 0.87, 0.0001, "更慢的个体走得更近")


func test_shop_milestone_drains_while_enemies_alive() -> void:
	var cs := _rush(46410)
	cs.spawn_paused = true
	assert_false(cs.alive_enemies().is_empty())
	var n0: int = cs.alive_enemies().size()
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	assert_eq(cs.shop_spawn_count, 1)
	assert_false(cs.shop_touch_pending, "场上有怪时不开店")
	assert_eq(cs.shop_cell, -1)
	assert_true(cs.encounter_spawns_blocked())
	assert_eq(cs.alive_enemies().size(), n0, "排空不改现有敌人")


func test_last_kill_opens_shop_once_without_refill() -> void:
	var cs := _rush(46411)
	cs.spawn_paused = false
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	var before: int = cs.alive_enemies().size()
	assert_gt(before, 0)
	_clear_field(cs)
	# 清场路径必须开始走进店铺，不能立刻补刷。
	assert_false(cs._field_cleared())
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH, "先走向门口")
	assert_false(cs.shop_touch_pending, "走进去之前不开店")
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(cs.shop_touch_pending, "进门完成后才 pending 开店")
	assert_false(cs.shop_drain)
	assert_eq(cs.alive_enemies().size(), 0, "排空清场不得立刻补怪")
	# 再走一遍清场/时钟，不能开第二次、不能补怪。
	assert_false(cs._field_cleared())
	cs.tick_combat_time(1.0)
	assert_true(cs.shop_touch_pending)
	assert_eq(cs.alive_enemies().size(), 0)
	assert_eq(cs.shop_spawn_count, 1)


func test_no_regular_or_boss_refill_during_drain() -> void:
	var cs := _rush(46412)
	cs.enemies.clear()
	_put(cs, CIV, 4, 10)
	cs.spawn_paused = false
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs._spawn_timer = 0.01
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	var n0: int = cs.alive_enemies().size()
	cs.tick_combat_time(2.0)
	assert_eq(cs.alive_enemies().size(), n0, "定时遭遇刷怪在排空期停止")
	# 把时钟推到 Boss 点：只记次数，不刷超级僵尸，离店也不把这次补回来。
	cs.elapsed_sec = CombatConstants.BOSS_EVERY_SEC
	cs._boss_spawned = 0
	cs.tick_combat_time(0.05)
	for e in cs.alive_enemies():
		assert_ne(int(e.def_id), SUPER, "排空期间到点 Boss 不刷")
	assert_eq(cs._boss_spawned, 1)
	_clear_field(cs)
	cs._field_cleared()
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(cs.shop_touch_pending)
	# 模拟离店并走完出门。此时已过 135 秒节点，应跳过该点（下次 225），不要立刻再开店。
	cs.shop_hold = true
	cs.acknowledge_shop_touch()
	cs.shop_hold = false
	cs.conclude_shop_visit()
	cs.shop_house_walk_left = 0.0
	cs.tick_shop_house(0.0)
	cs.clear_shop_house()
	assert_false(cs.encounter_spawns_blocked())
	assert_eq(cs.shop_spawn_count, 2, "已过的 135 秒节点被跳过")
	assert_false(cs.shop_drain)
	# 离店后不应把刚才跳过的那次 Boss 一次涌出；已记 _boss_spawned=1。
	var after: int = cs.alive_enemies().size()
	cs.tick_combat_time(0.05)
	for e in cs.alive_enemies():
		assert_ne(int(e.def_id), SUPER, "跳过的 Boss 不会在离店后补出")
	assert_gt(cs.alive_enemies().size(), after, "离店后恢复普通遭遇刷怪")


func test_super_summons_still_work_during_drain() -> void:
	var cs := _rush(46413)
	cs.spawn_paused = true
	cs.enemies.clear()
	_put(cs, SUPER, 4, 50)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	cs._try_super_zombie_summons()
	var z_count := 0
	for e in cs.alive_enemies():
		if int(e.def_id) == ZOMBIE:
			z_count += 1
	assert_eq(z_count, 1, "排空不静默关掉超级僵尸召唤")
	assert_false(cs.shop_touch_pending)


func test_reward_and_death_do_not_open_shop() -> void:
	var cs := _rush(46414)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	cs.reward_pending = true
	_clear_field(cs)
	cs._field_cleared()
	assert_true(cs.shop_drain)
	assert_false(cs.shop_touch_pending, "升级三选一期间先不开店")
	assert_eq(cs.alive_enemies().size(), 0, "也不补刷")
	cs.reward_pending = false
	cs._field_cleared()
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	assert_false(cs.shop_touch_pending, "刚能走去时仍未进门")
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(cs.shop_touch_pending)

	var cs2 := _rush(46415)
	cs2.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs2.tick_map_shop(0.0)
	cs2._set_phase(CombatState.Phase.LOST)
	_clear_field(cs2)
	cs2._field_cleared()
	assert_false(cs2.shop_touch_pending, "战败不清空开店")


func test_sandbox_shop_and_spawn_unchanged() -> void:
	var cs := CombatState.new(46416)
	cs.start_sandbox(46416)
	assert_true(cs.spawn_paused)
	assert_true(cs.map_shop_disabled)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_false(cs.shop_drain)
	assert_false(cs.shop_touch_pending)
	cs.sandbox_clear_enemies()
	assert_false(cs._field_cleared())
	assert_eq(cs.alive_enemies().size(), 0, "沙盒清场仍不自动补怪")


func test_next_shop_keeps_existing_cadence() -> void:
	var cs := _rush(46417)
	cs.spawn_paused = true
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	_clear_field(cs)
	cs.tick_map_shop(0.0)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	cs.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	assert_true(cs.shop_touch_pending)
	assert_eq(cs.shop_spawn_count, 1)
	cs.acknowledge_shop_touch()
	cs.conclude_shop_visit()
	cs.clear_shop_house()
	# 第二次节点仍是 45+90=135，不是另起一套频率。
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC + CombatConstants.MAP_SHOP_RESPAWN_SEC - 1.0
	_put(cs, CIV, 5, 10)
	cs.tick_map_shop(0.0)
	assert_false(cs.shop_drain)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC + CombatConstants.MAP_SHOP_RESPAWN_SEC
	cs.tick_map_shop(0.0)
	assert_true(cs.shop_drain)
	assert_eq(cs.shop_spawn_count, 2)
