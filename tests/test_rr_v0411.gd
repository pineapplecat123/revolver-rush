extends GutTest
## v0.4.11 色欲：枪口混乱；三罪自混乱期间攻击打自己。

const LUST := FireResolver.ID_LUST
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41101) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, LUST)
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
	cs.pace_after_fire = false
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_changelog_has_0_4_11_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.11"' in text or '"version":"0.4.11"' in text)


func test_lust_def_and_opening_sin() -> void:
	var def: Dictionary = DataRegistry.get_ammo(LUST)
	assert_eq(str(def.get("name", "")), "色欲弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_sin_ammo(LUST))
	assert_eq(FireResolver.base_damage_for(LUST, [LUST], 0), 2)
	assert_true(bool(FireResolver.inherits_from(LUST).get("lust", false)))
	var cs := _rush(41110)
	assert_eq(cs.selected_sin_ammo_id, LUST)
	var n := 0
	for x in cs.bag:
		if int(x) == LUST:
			n += 1
	assert_eq(n, CombatConstants.STARTER_SIN_COUNT)


func test_lust_muzzle_confuses_on_hit() -> void:
	var cs := _rush(41111)
	cs.dev_force_load([LUST, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	# force confuse: 1 layer → 20%; seed enough shots or set layers high
	cs._muzzle_lust = 5  # 100% chance
	cs.dev_spawn_enemy(1, 6)
	for e in cs.enemies:
		e.hp = 999
		e.atk = 0
	_shot_one(cs)
	assert_gt(cs._muzzle_lust, 0)
	var confused := 0
	for e in cs.enemies:
		if e.confuse_remaining > 0.0:
			confused += 1
	assert_gt(confused, 0, "at least one enemy should be confused")


func test_confused_enemy_attacks_neighbor() -> void:
	var cs := _rush(41112)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	for e in cs.enemies:
		e.hp = 50
		e.max_hp = 50
		e.atk = 4
		e.attack_range = 5
	cs.enemies[0].apply_confuse(1.0)
	var hp1: int = cs.enemies[1].hp
	cs._enemy_attack_or_confuse(cs.enemies[0])
	assert_lt(cs.enemies[1].hp, hp1)
	assert_eq(cs.player_hp, 99999)


func test_three_lust_self_confuse_redirects_damage() -> void:
	var cs := _rush(41113)
	cs.dev_force_load([LUST, LUST, LUST, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	# trigger 2→3 style by checking threshold after inserts already done via force load
	cs._resolve_sin_pack_on_load([LUST, LUST, LUST])
	assert_gt(cs.player_confuse_remaining, 0.0)
	var hp0: int = cs.player_hp
	cs.dev_force_load([WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	assert_lt(cs.player_hp, hp0)
	assert_eq(cs.enemies[0].hp, 999)


func test_load_33_temp_sin_works_for_lust() -> void:
	var cs := _rush(41114)
	var hits := 0
	for i in 80:
		var before: int = cs.bag.size()
		cs._try_spawn_temp_sin_on_load(LUST)
		if cs.bag.size() > before:
			hits += 1
	assert_gt(hits, 0)
