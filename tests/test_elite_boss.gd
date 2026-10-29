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




