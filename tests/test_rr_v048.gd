extends GutTest
## v0.4.8 石头 + 小石头链：命中产小石头；相邻≥2 点射融合。

const STONE := FireResolver.ID_STONE
const PEBBLE := FireResolver.ID_PEBBLE
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4801) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func _count_bag(cs: CombatState, ammo_id: int) -> int:
	var n := 0
	for x in cs.bag:
		if int(x) == ammo_id:
			n += 1
	return n


func test_version_is_0_4_8() -> void:
	assert_eq(GameVersion.STRING, "0.4.8")


func test_stone_pebble_defs() -> void:
	var stone: Dictionary = DataRegistry.get_ammo(STONE)
	var peb: Dictionary = DataRegistry.get_ammo(PEBBLE)
	assert_eq(str(stone.get("name", "")), "石头弹药")
	assert_eq(str(peb.get("name", "")), "小石头弹药")
	assert_true(bool(stone.get("enabled_in_combat", false)))
	assert_true(bool(peb.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(STONE))
	assert_false(DataRegistry.is_ammo_reward_eligible(PEBBLE))
	assert_true(DataRegistry.is_ammo_ephemeral(PEBBLE))
	assert_eq(FireResolver.base_damage_for(STONE, [STONE], 0, 0), 3)
	assert_eq(FireResolver.base_damage_for(PEBBLE, [PEBBLE], 0, 0), 1)


func test_stone_hit_spawns_pebbles_equal_to_dealt() -> void:
	var cs := _rush(4810)
	cs.dev_force_load([STONE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var before: int = _count_bag(cs, PEBBLE)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_eq(dealt, 3)
	assert_eq(_count_bag(cs, PEBBLE), before + dealt)


func test_single_pebble_fires_damage_1() -> void:
	var cs := _rush(4811)
	cs.dev_force_load([PEBBLE, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 1)
	# 只消耗 1 仓小石头，白弹仍在
	assert_true(cs.magazine.slots.has(WHITE) or WHITE in cs.magazine.slots)


func test_adjacent_pebbles_fuse_on_point_fire() -> void:
	var cs := _rush(4812)
	cs.dev_force_load([PEBBLE, PEBBLE, PEBBLE, WHITE, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
	# 三段小石头清空，白弹仍在匣内
	var peb_left := 0
	for id in cs.magazine.slots:
		if int(id) == PEBBLE:
			peb_left += 1
	assert_eq(peb_left, 0)
	assert_true(WHITE in cs.magazine.slots)


func test_gap_breaks_pebble_adjacency() -> void:
	var cs := _rush(4813)
	# 锤位小石头，下一仓空，再小石头——不融合
	cs.dev_force_load([PEBBLE, Magazine.EMPTY, PEBBLE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 1)
	# 第二颗小石头仍在
	assert_true(PEBBLE in cs.magazine.slots)
