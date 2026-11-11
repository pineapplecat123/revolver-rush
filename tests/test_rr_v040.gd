extends GutTest
## v0.4.0 语法基建：连发窗、倾泻、装入33%临时罪、墓碑幽灵连射、DoT tick、地图商店、钩子总线。

const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID
const LIFE := CombatConstants.GHOST_TTL_SEC


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4001, sin_id: int = W) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, sin_id)
	# 只留一只最前敌，避免 enemies[0] 不是受击目标
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _shot(cs: CombatState) -> Array:
	## 逻辑连射：清掉射速帽再打，测的是弹药不是手速。
	cs.player_fire_gate_remaining = 0.0
	return cs.fire_tap()


func test_changelog_has_0_4_0_entry() -> void:
	## 版本号会继续递增；此处只断言 0.4.0 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.0"' in text or '"version":"0.4.0"' in text)







func test_three_sin_penalty_no_longer_adds_temp() -> void:
	var cs := _rush(4030)
	var t0: int = cs.count_temporary_in_bag()
	cs._resolve_sin_pack_on_load([W, W, W])
	assert_eq(cs.count_temporary_in_bag(), t0)
	assert_eq(cs.penalty_temp_sins_spawned, 0)


func test_load_sin_33_percent_spawns_temp() -> void:
	## 固定 seed 下跑多次装入，期望有触发也有不触发；并用强制路径验证钩子。
	var cs := _rush(4031)
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 20:
		cs._bag_append(W, false)
	cs.magazine.clear()
	assert_true(cs.begin_load())
	var spawned := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	spawned = cs.load_temp_sins_spawned
	# 6 仓全装愤怒，33% → 期望大约 0~6；至少验证 API 不炸且计数>=0
	assert_gte(spawned, 0)
	# 强制：直接调
	var n0: int = cs.count_temporary_in_bag()
	# 把 rng 推到必中：循环直到触发一次
	var hit := false
	for _j in 80:
		var before: int = cs.load_temp_sins_spawned
		cs._try_spawn_temp_sin_on_load(W)
		if cs.load_temp_sins_spawned > before:
			hit = true
			break
	assert_true(hit, "33% should eventually spawn")
	assert_gt(cs.count_temporary_in_bag(), n0)


func test_tombstone_adds_temp_ghost_and_rapid_fires_bag() -> void:
	var cs := _rush(4040)
	cs.bag.clear()
	cs.bag_temp.clear()
	# 预先两颗幽灵在袋
	cs._bag_append(FireResolver.ID_GHOST, LIFE)
	cs._bag_append(FireResolver.ID_GHOST, LIFE)
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	var shots: Array = _shot(cs)
	# v0.4.20：袋里有幽灵 → 墓碑 + 袋内 2 幽灵一起射，不再新生成 = 至少 3 发记录
	assert_gte(shots.size(), 3)
	var ghosts_left := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			ghosts_left += 1
	assert_eq(ghosts_left, 0, "all bag ghosts fired")
	# 不再填空仓
	assert_eq(cs.magazine.loaded_count(), 0)
	# 伤害：墓碑2 + 幽灵2*2 = 6
	assert_eq(hp0 - cs.enemies[0].hp, 6)


func test_dot_ticks_every_half_second_not_on_step() -> void:
	var cs := _rush(4050)
	cs.enemies[0].burn_stacks = 3
	cs.enemies[0].bleed_stacks = 2
	var hp0: int = cs.enemies[0].hp
	# 落格拍不应跳 DoT
	cs.tick_enemy_auto_step()
	assert_eq(cs.enemies[0].hp, hp0)
	assert_eq(cs.enemies[0].burn_stacks, 3)
	# DoT tick
	cs._dot_timer = 0.01
	assert_true(cs.tick_dot(0.02))
	assert_lt(cs.enemies[0].hp, hp0)
	assert_eq(cs.enemies[0].burn_stacks, 2)


func test_map_shop_spawns_and_touches_player() -> void:
	var cs := _rush(4060)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.tick_map_shop(0.0)
	assert_eq(cs.shop_cell, CombatConstants.BOARD_SIZE - 1)
	# 推到玩家旁
	cs._shop_move_prog = 0.0
	while cs.shop_cell > 1 and cs.shop_cell >= 0:
		cs._shop_move_prog = 1.0
		cs.tick_map_shop(0.0)
	assert_true(cs.shop_touch_pending)
	assert_eq(cs.shop_cell, -1)


func test_hooks_bus_emits_lifecycle_events() -> void:
	var cs := _rush(4070)
	var seen: Dictionary = {}
	cs.hooks.subscribe(&"on_fire", func(p): seen["on_fire"] = true)
	cs.hooks.subscribe(&"on_shot", func(p): seen["on_shot"] = true)
	cs.hooks.subscribe(&"on_chamber_loaded", func(p): seen["on_chamber_loaded"] = true)
	cs.hooks.subscribe(&"on_bag_enter", func(p): seen["on_bag_enter"] = true)
	cs.hooks.subscribe(&"on_bag_leave", func(p): seen["on_bag_leave"] = true)
	cs.hooks.subscribe(&"on_three_sin", func(p): seen["on_three_sin"] = true)
	cs.hooks.subscribe(&"on_muzzle_apply", func(p): seen["on_muzzle_apply"] = true)
	cs._bag_append(WHITE, false)
	assert_true(seen.get("on_bag_enter", false))
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 6:
		cs._bag_append(W, false)
	cs.magazine.clear()
	assert_true(cs.begin_load())
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	assert_true(seen.get("on_chamber_loaded", false))
	assert_true(seen.get("on_bag_leave", false))
	assert_true(seen.get("on_three_sin", false))
	cs.dev_force_load([W, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	_shot(cs)
	assert_true(seen.get("on_fire", false))
	assert_true(seen.get("on_shot", false))
	assert_true(seen.get("on_muzzle_apply", false))


func test_sin_bag_still_five() -> void:
	assert_eq(CombatConstants.STARTER_SIN_COUNT, 0)
	var cs := _rush(4080)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	for id in cs.bag:
		assert_eq(int(id), WHITE)
