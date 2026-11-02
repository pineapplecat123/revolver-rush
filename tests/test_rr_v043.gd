extends GutTest
## v0.4.3 火焰弹药 + 燃烧扩散跳伤。

const WHITE := CombatConstants.WHITE_AMMO_ID
const FLAME := FireResolver.ID_FLAME


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4301) -> CombatState:
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
	cs.player_hp = 99999
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_changelog_has_0_4_3_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.3"' in text or '"version":"0.4.3"' in text)


func test_flame_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(FLAME)
	assert_eq(str(def.get("name", "")), "火焰弹药")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FLAME))
	assert_true(bool(FireResolver.inherits_from(FLAME).get("fire", false)))
	assert_false("回合" in str(def.get("special", "")))


func test_flame_mounts_and_applies_burn_equal_damage() -> void:
	var cs := _rush(4310)
	cs.dev_force_load([
		FLAME, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_true(cs._muzzle_fire)
	assert_true("火焰" in cs.muzzle_status_parts())
	# 本发伤害 1 → 燃烧 +1
	assert_eq(cs.enemies[0].burn_stacks, 1)
	var burn0: int = cs.enemies[0].burn_stacks
	_shot_one(cs)  # white 3 + flame muzzle → burn +3
	assert_eq(cs.enemies[0].burn_stacks, burn0 + 3)


func test_flame_muzzle_max_one_refresh() -> void:
	var cs := _rush(4311)
	cs.dev_force_load([
		FLAME, FLAME, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs._muzzle_fire_layers.size(), 1)
	cs.tick_muzzle_durations(1.5)
	_shot_one(cs)
	assert_eq(cs._muzzle_fire_layers.size(), 1)
	assert_almost_eq(cs._muzzle_fire_t, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 0.001)


func test_burn_spreads_half_ceil_to_adjacent() -> void:
	var cs := _rush(4312)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 3)
	cs.dev_spawn_enemy(1, 4)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	var sorted: Array = cs.enemies_sorted_by_cell()
	var front: EnemyInstance = sorted[0]
	var back: EnemyInstance = sorted[1]
	back.burn_stacks = 5  # ceil(5/2)=3 spread to front
	front.burn_stacks = 0
	cs._dot_timer = 0.01
	assert_true(cs.tick_dot(0.02))
	# front gained 3, then both take damage equal to their stacks after spread and -1
	# after spread: front=3, back=5; then damage; then -1 → front=2, back=4
	assert_eq(front.burn_stacks, 2)
	assert_eq(back.burn_stacks, 4)


func test_burn_alone_no_spread_still_damages() -> void:
	var cs := _rush(4313)
	cs.enemies[0].burn_stacks = 3
	var hp0: int = cs.enemies[0].hp
	cs._dot_timer = 0.01
	assert_true(cs.tick_dot(0.02))
	assert_eq(cs.enemies[0].burn_stacks, 2)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
