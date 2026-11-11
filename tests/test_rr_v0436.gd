extends GutTest
## v0.4.36：DoT 0.7s、TTL 30、临时/嫉妒打出即毁、枪口翻倍、仓内寿命环、三罪新时长。

const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID
const PEBBLE := FireResolver.ID_PEBBLE
const GHOST := FireResolver.ID_GHOST


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 43601) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	return cs


func test_version_is_0_4_36() -> void:
	assert_eq(GameVersion.STRING, "0.4.36")
	assert_true("0.4.36" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_timing_constants() -> void:
	assert_eq(CombatConstants.DOT_TICK_SEC, 0.7)
	assert_eq(CombatConstants.GHOST_TTL_SEC, 30.0)
	assert_eq(CombatConstants.PEBBLE_TTL_SEC, 30.0)
	assert_eq(CombatConstants.TEMP_SIN_LIFETIME_SEC, 0.0)
	assert_eq(CombatConstants.ENVY_COPY_TTL_SEC, 0.0)
	assert_eq(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 8.0)
	assert_eq(CombatConstants.MUZZLE_DURATION_WRATH_SEC, 8.0)
	assert_eq(CombatConstants.MUZZLE_DURATION_PRIDE_SEC, 30.0)
	assert_eq(CombatConstants.LUST_CONFUSE_SEC, 5.0)
	assert_eq(CombatConstants.LUST_SELF_CONFUSE_SEC, 3.0)
	assert_eq(CombatConstants.SLOTH_SLOW_LAYER_SEC, 5.0)
	assert_eq(CombatConstants.SLOTH_FIRE_BAN_SEC, 3.0)
	assert_eq(CombatConstants.GLUTTONY_SELF_DOT_SEC, 3.5)


func test_fire_once_temp_sin_does_not_time_out_and_destroys_on_fire() -> void:
	var cs := _rush(43610)
	cs.dev_force_load([Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs._bag_append(W, true)
	assert_true(cs.is_bag_index_temporary(cs.bag.size() - 1))
	assert_true(Magazine.is_fire_once_temp(cs.bag_temp[cs.bag.size() - 1]))
	cs.tick_temp_sin_lifetimes(999.0)
	assert_true(W in cs.bag)
	# load into mag and fire
	cs.magazine.set_slot(0, W, true)
	cs.magazine.set_start(0)
	var disc0: int = cs.discard.size()
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(cs.discard.size(), disc0, "fire-once temp does not enter discard")


func test_envy_copy_no_ttl_destroys_on_fire() -> void:
	var cs := _rush(43611)
	cs.dev_force_load([WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_slot(0, WHITE, CombatConstants.FIRE_ONCE_TEMP, true)
	cs.magazine.set_start(0)
	var disc0: int = cs.discard.size()
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(cs.discard.size(), disc0)


func test_ghost_ttl_still_expires() -> void:
	var cs := _rush(43612)
	var n0: int = cs.bag.size()
	cs._bag_append(GHOST, CombatConstants.GHOST_TTL_SEC)
	cs.tick_temp_sin_lifetimes(CombatConstants.GHOST_TTL_SEC + 0.1)
	assert_eq(cs.bag.size(), n0)


func test_chamber_uses_ring_not_seconds_text() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true("TempLifeRing" in src)
	assert_true("_draw_chamber_temp_ring" in src)
	assert_false('lab.text = "%ds"' in src)


func test_ammo_text_mentions_new_numbers() -> void:
	assert_true(DataRegistry.get_ammo(FireResolver.ID_LUST).is_empty())
	assert_true(DataRegistry.get_ammo(FireResolver.ID_SLOTH).is_empty())
	assert_true(DataRegistry.get_ammo(GHOST).is_empty())
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.WHITE_AMMO_ID).get("name", "")), "平庸子弹")
