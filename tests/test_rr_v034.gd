extends GutTest
## v0.3.4：敌人 HP 砍半、波次数量 ×1.5、袋一空立刻补、枪口改持续时间。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3401) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v)
	return cs


func test_enemy_hp_halved() -> void:
	assert_eq(int(DataRegistry.get_enemy(1).get("hp")), 10)
	assert_eq(int(DataRegistry.get_enemy(2).get("hp")), 15)
	assert_eq(int(DataRegistry.get_enemy(3).get("hp")), 20)
	assert_eq(int(DataRegistry.get_enemy(4).get("hp")), 25)
	assert_eq(int(DataRegistry.get_enemy(5).get("hp")), 50)
	assert_eq(int(DataRegistry.get_enemy(104).get("hp")), 5)
	assert_eq(int(DataRegistry.get_enemy(105).get("hp")), 10)
	var cs := _rush()
	assert_eq(cs.enemies[0].max_hp, 10)


func test_bag_refills_immediately_on_empty_for_manual_load() -> void:
	## 袋空时可立刻手装（不必等怪走一格）；v0.3.6：can_manual_load 只是查询不改状态，begin_load 真正补袋。
	var cs := _rush(3403)
	for e in cs.enemies:
		e.hp = 9999
		e.max_hp = 9999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	assert_true(cs.bag.is_empty())
	assert_eq(cs.bag_reset_count, 0)
	assert_true(cs.can_manual_load(), "bag empty but refillable → can load")
	assert_eq(cs.bag_reset_count, 0, "查询不改状态")
	assert_true(cs.bag.is_empty())
	assert_true(cs.begin_load())
	assert_eq(cs.bag_reset_count, 1)
	assert_false(cs.bag.is_empty())
	assert_eq(cs.count_temporary_in_bag(), 0, "v0.3.8：重置不再 +N 临时罪孽")


func test_bag_refills_when_load_session_empties_bag() -> void:
	var cs := _rush(3404)
	for e in cs.enemies:
		e.hp = 9999
		e.max_hp = 9999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 2:
		cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(cs.bag_reset_count, 1)
	assert_gt(cs.bag.size(), 0)


func test_muzzle_element_lasts_duration_across_shots() -> void:
	var cs := _rush(3405)
	cs.enemies.resize(1)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_FIRE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	cs.finalize_post_fire()
	assert_true(cs._muzzle_fire)
	assert_almost_eq(cs._muzzle_fire_t, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 0.01)
	var burn1: int = cs.enemies[0].burn_stacks
	assert_gt(burn1, 0)
	# 收束后仍挂火：再打白弹应叠燃烧
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	cs.finalize_post_fire()
	assert_gt(cs.enemies[0].burn_stacks, burn1)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC + 0.05)
	assert_false(cs._muzzle_fire)


func test_muzzle_wrath_duration_refresh_and_pride_permanent() -> void:
	## v0.3.7：叠层不刷新旧层；显示最短剩余。傲慢也计时（12s），4s 内仍在。
	var cs := _rush(3406)
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 1.0
	cs._muzzle_pride = 2
	cs.tick_muzzle_durations(0.5)
	assert_eq(cs._muzzle_wrath, 1)
	assert_almost_eq(cs._muzzle_wrath_t, 0.5, 0.001)
	assert_eq(cs._muzzle_pride, 2)
	cs._mount_sin_muzzle_from({"wrath": true})
	assert_eq(cs._muzzle_wrath, 2)
	assert_almost_eq(cs._muzzle_wrath_t, 0.5, 0.01, "最短层仍是旧层")
	assert_eq(cs._muzzle_wrath_layers.size(), 2)
	assert_almost_eq(float(cs._muzzle_wrath_layers[1]), CombatConstants.MUZZLE_DURATION_WRATH_SEC, 0.01)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_WRATH_SEC + 0.01)
	assert_eq(cs._muzzle_wrath, 0)
	assert_eq(cs._muzzle_pride, 2, "傲慢 12s，未随愤怒清掉")


func test_muzzle_duration_constants() -> void:
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_WRATH_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_GREED_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 4.0, 0.001)


func test_changelog_has_0_3_4() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	var found := false
	for e in d["entries"]:
		if str(e["version"]) == "0.3.4":
			found = true
	assert_true(found)
