extends GutTest
## rush!：攻击射程 + 第 10 波超级僵尸 Boss 波奖励金。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_can_attack_player_uses_attack_range() -> void:
	var cs := CombatState.new(1)
	cs.start_rush(1)
	var e: EnemyInstance = cs.front_enemy()
	e.cell = 2
	e.attack_range = 1
	assert_false(cs.can_attack_player(e))
	e.attack_range = 2
	assert_true(cs.can_attack_player(e))
	e.cell = 1
	e.attack_range = 1
	assert_true(cs.can_attack_player(e))




func test_rush_wave10_is_boss_with_boss_gold() -> void:
	var cs := CombatState.new(303)
	cs.start_rush(303)
	cs.wave_index = 9
	cs.phase = CombatState.Phase.WON
	cs.reward_resolved = true
	cs.reward_pending = false
	cs.rush_shop_done = true
	assert_true(cs.start_next_wave())
	assert_eq(cs.wave_index, 10)
	assert_eq(cs.encounter_kind, CombatState.EncounterKind.BOSS)
	for e in cs.alive_enemies():
		assert_eq(e.def_id, CombatConstants.SUPER_ZOMBIE_ENEMY_ID)
	cs.dev_kill_all_enemies()
	assert_eq(cs.last_reward_base_gold, CombatConstants.REWARD_BOSS_BASE_GOLD)
