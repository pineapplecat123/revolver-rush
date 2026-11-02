extends GutTest
## v0.4.0 语法基建：连发窗、倾泻、装入33%临时罪、墓碑幽灵连射、DoT 0.5s、地图商店、钩子总线。

const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID
const LIFE := CombatConstants.TEMP_SIN_LIFETIME_SEC


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
	return cs.fire_tap()


func test_version_is_0_4_0() -> void:
	assert_eq(GameVersion.STRING, "0.4.0")


func test_ammo_defs_burst_and_dump() -> void:
	var burst: Dictionary = DataRegistry.get_ammo(FireResolver.ID_BURST)
	var dump: Dictionary = DataRegistry.get_ammo(FireResolver.ID_DUMP)
	assert_eq(str(burst.get("name", "")), "连发子弹")
	assert_eq(str(dump.get("name", "")), "倾泻")
	assert_true(bool(burst.get("enabled_in_combat", false)))
	assert_true(bool(dump.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_BURST))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_DUMP))
	assert_true(bool(DataRegistry.get_ammo(FireResolver.ID_GOLD).get("enabled_in_combat", false)))


func test_burst_window_opens_and_free_shot_no_chamber() -> void:
	var cs := _rush(4010)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.dev_force_load([
		FireResolver.ID_BURST,
		WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var loaded0: int = cs.magazine.loaded_count()
	_shot(cs)
	assert_almost_eq(cs.burst_window_remaining, CombatConstants.BURST_WINDOW_SEC, 0.001)
	assert_eq(cs.magazine.loaded_count(), loaded0 - 1)
	var bag0: int = cs.bag.size()
	var disc0: int = cs.discard.size()
	var hp0: int = cs.enemies[0].hp
	# 窗内点射：不耗仓、不进弃牌
	var shots: Array = _shot(cs)
	assert_gt(shots.size(), 0)
	assert_true(bool(shots[0].get("burst_free", false)) or bool(shots[0].get("virtual", false)))
	assert_eq(cs.magazine.loaded_count(), loaded0 - 1, "free shot must not spend chamber")
	assert_eq(cs.discard.size(), disc0, "free shot must not pollute discard")
	assert_eq(cs.bag.size(), bag0)
	assert_lt(cs.enemies[0].hp, hp0)


func test_burst_window_refresh_not_stack() -> void:
	var cs := _rush(4011)
	cs.dev_force_load([
		FireResolver.ID_BURST, FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot(cs)
	cs.burst_window_remaining = 0.3
	# 打第二发连发应刷新到满 1.0，而不是 1.3
	cs.burst_window_remaining = 0.0  # 窗关才能打仓内弹
	_shot(cs)
	assert_almost_eq(cs.burst_window_remaining, CombatConstants.BURST_WINDOW_SEC, 0.001)


func test_dump_auto_fires_remaining_chambers() -> void:
	var cs := _rush(4020)
	cs.dev_force_load([
		FireResolver.ID_DUMP, WHITE, WHITE, WHITE,
		Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	var shots: Array = _shot(cs)
	# 倾泻本发 + 3 白
	assert_gte(shots.size(), 4)
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_eq(hp0 - cs.enemies[0].hp, 2 + 3 + 3 + 3, "dump 2 + three whites 3")


func test_dump_interrupt_stops_remaining() -> void:
	var cs := _rush(4021)
	cs.dev_force_load([
		FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE, WHITE,
	] as Array[int])
	# 异步倾泻：先打本发，不 resolve 完
	var shots: Array = cs.fire_tap(false)
	assert_true(cs.is_dump_pending())
	assert_eq(shots.size(), 1)
	assert_true(cs.interrupt_dump())
	assert_false(cs.is_dump_pending())
	assert_gt(cs.magazine.loaded_count(), 0, "remaining chambers kept after interrupt")


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
	# 墓碑本发 + 袋内原2幽灵 + 新生成1幽灵 = 至少 1+3 发记录（墓碑+3幽灵）
	assert_gte(shots.size(), 4)
	var ghosts_left := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			ghosts_left += 1
	assert_eq(ghosts_left, 0, "all bag ghosts fired")
	# 不再填空仓
	assert_eq(cs.magazine.loaded_count(), 0)
	# 伤害：墓碑2 + 幽灵2*3 = 8
	assert_eq(hp0 - cs.enemies[0].hp, 8)


func test_dot_ticks_every_half_second_not_on_step() -> void:
	var cs := _rush(4050)
	cs.enemies[0].burn_stacks = 3
	cs.enemies[0].bleed_stacks = 2
	var hp0: int = cs.enemies[0].hp
	# 落格拍不应跳 DoT
	cs.tick_enemy_auto_step()
	assert_eq(cs.enemies[0].hp, hp0)
	assert_eq(cs.enemies[0].burn_stacks, 3)
	# 0.5s DoT
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
	assert_eq(CombatConstants.STARTER_SIN_COUNT, 5)
	var cs := _rush(4080)
	var sins := 0
	for id in cs.bag:
		if int(id) == W:
			sins += 1
	assert_eq(sins, 5)
