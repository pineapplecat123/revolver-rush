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


func test_wave_spawn_count_mult_1_5() -> void:
	assert_almost_eq(CombatConstants.WAVE_SPAWN_COUNT_MULT, 1.5, 0.001)
	var cs := _rush(3402)
	assert_eq(cs.enemies.size(), 2, "wave1: 1×1.5 → 2")
	# wave 3 → 2×1.5=3
	cs.phase = CombatState.Phase.WON
	cs.reward_resolved = true
	cs.reward_pending = false
	cs.rush_shop_done = true
	cs.wave_index = 2
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 3)
	assert_eq(cs.enemies.size(), 3)
	# boss wave 10 → ceil(1×1.5)=2
	cs.phase = CombatState.Phase.WON
	cs.reward_resolved = true
	cs.reward_pending = false
	cs.rush_shop_done = true
	cs.wave_index = 9
	assert_true(cs.start_next_wave())
	assert_eq(cs.enemies.size(), 2)
	assert_eq(cs.enemies[0].def_id, CombatConstants.SUPER_ZOMBIE_ENEMY_ID)


func test_bag_refills_immediately_on_empty_for_manual_load() -> void:
	## 袋空时 can_manual_load 立刻补，不必等怪走一格。
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
	assert_true(cs.can_manual_load(), "should refill inside can_manual_load")
	assert_eq(cs.bag_reset_count, 1)
	assert_false(cs.bag.is_empty())
	assert_eq(cs.count_temporary_in_bag(), 1)


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
	var cs := _rush(3406)
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 1.0
	cs._muzzle_pride = 2
	cs.tick_muzzle_durations(0.5)
	assert_eq(cs._muzzle_wrath, 1)
	assert_almost_eq(cs._muzzle_wrath_t, 0.5, 0.001)
	assert_eq(cs._muzzle_pride, 2)
	# 叠层刷新
	cs._mount_sin_muzzle_from({"wrath": true})
	assert_eq(cs._muzzle_wrath, 2)
	assert_almost_eq(cs._muzzle_wrath_t, CombatConstants.MUZZLE_DURATION_WRATH_SEC, 0.01)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_WRATH_SEC + 0.01)
	assert_eq(cs._muzzle_wrath, 0)
	assert_eq(cs._muzzle_pride, 2, "傲慢整场")


func test_muzzle_duration_constants() -> void:
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_WRATH_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_GREED_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 4.0, 0.001)


func test_game_version_0_3_4() -> void:
	assert_eq(GameVersion.STRING, "0.3.4")
