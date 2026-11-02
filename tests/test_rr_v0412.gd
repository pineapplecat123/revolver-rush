extends GutTest
## v0.4.12 嫉妒：击杀复制上一发非罪 TTL；三罪弃 2 永久非罪。

const ENVY := FireResolver.ID_ENVY
const WHITE := CombatConstants.WHITE_AMMO_ID
const ECHO := FireResolver.ID_ECHO


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41201) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, ENVY)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 5
		e.max_hp = 5
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


func test_changelog_has_0_4_12_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.12"' in text or '"version":"0.4.12"' in text)


func test_envy_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(ENVY)
	assert_eq(str(def.get("name", "")), "嫉妒弹药")
	assert_true(DataRegistry.is_sin_ammo(ENVY))
	assert_true(bool(FireResolver.inherits_from(ENVY).get("envy", false)))


func test_envy_copy_on_kill() -> void:
	var cs := _rush(41210)
	cs.last_non_sin_ammo_id = ECHO
	cs._muzzle_envy = 5  # 100%
	var bag0: int = cs.bag.size()
	# kill via remove_dead path
	cs.enemies[0].hp = 0
	cs._remove_dead()
	var echo_ttl := 0
	for i in cs.bag.size():
		if int(cs.bag[i]) == ECHO and Magazine.temp_value(cs.bag_temp[i] if i < cs.bag_temp.size() else 0.0) > 0.0:
			echo_ttl += 1
	assert_gt(echo_ttl, 0)
	assert_gt(cs.bag.size(), bag0)


func test_envy_three_sin_discards_permanent_nonsin() -> void:
	var cs := _rush(41211)
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 5:
		cs._bag_append(WHITE, false)
	cs._bag_append(ENVY, false)
	var disc0: int = cs.discard.size()
	var moved: int = cs._envy_discard_permanent_nonsin(2)
	assert_eq(moved, 2)
	assert_eq(cs.discard.size(), disc0 + 2)
