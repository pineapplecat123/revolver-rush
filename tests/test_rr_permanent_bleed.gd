extends GutTest
## 永久流血：实际命中后挂到死亡，每 0.7s -1HP，不叠层、不重置跳表；血条旁图标无倒计时。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _bio(seed_v: int = 7301, hp: int = 20, cell: int = 6) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v)
	cs.spawn_paused = true
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, cell)
	var e: EnemyInstance = cs.enemies[0]
	e.max_hp = hp
	e.hp = hp
	e.atk = 0
	return cs


func test_first_tick_is_0_7s_after_positive_hit() -> void:
	var cs := _bio()
	var e: EnemyInstance = cs.enemies[0]
	assert_eq(e.apply_hit(3), 3)
	assert_true(e.is_bleeding())
	assert_eq(e.bleed_stacks, 1)
	var hp0: int = e.hp
	assert_false(cs.tick_dot(0.6))
	assert_eq(e.hp, hp0)
	assert_true(cs.tick_dot(0.15))
	assert_eq(e.hp, hp0 - 1)
	assert_eq(e.bleed_stacks, 1)


func test_repeat_hits_do_not_stack_or_reset_timer() -> void:
	var cs := _bio()
	var e: EnemyInstance = cs.enemies[0]
	e.apply_hit(2)
	var left0: float = e.bleed_tick_left
	cs.tick_dot(0.25)
	var mid: float = e.bleed_tick_left
	assert_lt(mid, left0)
	assert_eq(e.apply_hit(2), 2)
	assert_eq(e.bleed_stacks, 1)
	assert_almost_eq(e.bleed_tick_left, mid, 0.0001)
	var hp1: int = e.hp
	cs.tick_dot(0.25)
	assert_eq(e.hp, hp1, "0.50s total is still before first tick")
	cs.tick_dot(0.21)
	assert_eq(e.hp, hp1 - 1)


func test_zero_damage_hit_does_not_start_bleed() -> void:
	var def: Dictionary = DataRegistry.get_enemy(105)
	var e := EnemyInstance.new(def, 5)
	assert_eq(e.apply_hit(3), 0)
	assert_eq(e.bleed_stacks, 0)
	assert_false(e.is_bleeding())


func test_nonflesh_immunity_but_main_zombies_do_bleed() -> void:
	var sk := EnemyInstance.new(DataRegistry.get_enemy(104), 5)
	assert_eq(sk.apply_hit(3), 3)
	assert_eq(sk.bleed_stacks, 0)
	var cs := CombatState.new(7302)
	cs.start_sandbox(7302)
	cs.sandbox_clear_enemies()
	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(50, 4)
	var dhp: int = dummy.hp
	assert_eq(dummy.apply_hit(4), 4)
	assert_eq(dummy.bleed_stacks, 0)
	assert_eq(dummy.hp, dhp - 4)
	cs.enemies.clear()
	cs.dev_spawn_enemy(4, 6)
	var z: EnemyInstance = cs.enemies[0]
	z.hp = 20
	z.max_hp = 20
	assert_true(z.has_tag("僵尸"))
	assert_false(z.has_tag("生物"))
	assert_eq(z.apply_hit(3), 3)
	assert_eq(z.bleed_stacks, 1)
	var hp0 := z.hp
	cs.tick_dot(0.7)
	assert_eq(z.hp, hp0 - 1)


func test_forced_dummy_bleed_ticks_then_clears_on_revive() -> void:
	var cs := CombatState.new(7303)
	cs.start_sandbox(7303)
	cs.sandbox_clear_enemies()
	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(8, 4)
	assert_true(cs.sandbox_set_enemy_status({"bleed": 3}))
	assert_eq(dummy.bleed_stacks, 1)
	var hp0: int = dummy.hp
	cs.tick_combat_time(CombatConstants.DOT_TICK_SEC)
	assert_eq(dummy.hp, hp0 - 1)
	dummy.hp = 0
	cs._remove_dead()
	assert_true(dummy.is_alive())
	assert_eq(dummy.bleed_stacks, 0)
	assert_eq(dummy.hp, dummy.max_hp)


func test_burn_stays_independent_of_bleed_clock() -> void:
	var cs := _bio(7304, 80)
	var e: EnemyInstance = cs.enemies[0]
	e.apply_hit(3)
	e.burn_stacks = 3
	e.burn_peak = 3
	var hp0: int = e.hp
	cs._dot_timer = 0.01
	assert_true(cs.tick_dot(0.02))
	assert_eq(e.burn_stacks, 2, "burn uses the shared pulse")
	assert_eq(e.hp, hp0 - 3, "only burn damage this pulse")
	assert_eq(e.bleed_stacks, 1)
	assert_gt(e.bleed_tick_left, 0.6)


func test_combat_clock_pause_holds_bleed() -> void:
	var cs := _bio(7305, 20)
	var e: EnemyInstance = cs.enemies[0]
	e.apply_hit(3)
	var left: float = e.bleed_tick_left
	var hp0: int = e.hp
	cs.shop_hold = true
	assert_false(cs.tick_combat_time(2.0))
	assert_eq(e.hp, hp0)
	assert_almost_eq(e.bleed_tick_left, left, 0.0001)
	cs.shop_hold = false
	cs.reward_pending = true
	assert_false(cs.tick_combat_time(2.0))
	assert_eq(e.hp, hp0)
	assert_almost_eq(e.bleed_tick_left, left, 0.0001)
	cs.reward_pending = false
	assert_true(cs.tick_combat_time(CombatConstants.DOT_TICK_SEC))
	assert_eq(e.hp, hp0 - 1)


func test_enemy_turn_and_auto_step_do_not_tick_bleed() -> void:
	var cs := _bio(7306, 20, 8)
	var e: EnemyInstance = cs.enemies[0]
	e.apply_hit(3)
	var hp0: int = e.hp
	var left: float = e.bleed_tick_left
	cs._run_enemy_turn()
	assert_eq(e.hp, hp0)
	assert_almost_eq(e.bleed_tick_left, left, 0.0001)
	cs.tick_enemy_auto_step()
	assert_eq(e.hp, hp0)
	assert_almost_eq(e.bleed_tick_left, left, 0.0001)


func test_bleed_kill_rewards_exactly_once() -> void:
	var cs := _bio(7307, 2, 6)
	var e: EnemyInstance = cs.enemies[0]
	var kills: Array = []
	cs.hooks.subscribe(&"on_kill", func(p: Dictionary) -> void:
		kills.append(p)
	)
	assert_eq(e.apply_hit(1), 1)
	assert_eq(e.hp, 1)
	var xp0: int = cs.xp
	var gold_before: int = cs.gold_drops.size()
	assert_true(cs.tick_dot(CombatConstants.DOT_TICK_SEC))
	assert_eq(kills.size(), 1)
	assert_eq(cs.alive_enemies().size(), 0)
	assert_gt(cs.xp, xp0)
	assert_eq(cs.gold_drops.size(), gold_before + 1)
	cs._remove_dead()
	assert_eq(kills.size(), 1)
	assert_eq(cs.gold_drops.size(), gold_before + 1)


func test_stone_keeps_bleed_but_ignores_sub4_tick() -> void:
	var e := EnemyInstance.new(DataRegistry.get_enemy(105), 5)
	e.arm_bleed_from_sandbox(1)
	assert_eq(e.bleed_stacks, 1)
	assert_eq(e.apply_damage(CombatConstants.BLEED_TICK_DAMAGE), 0)
	assert_eq(e.hp, e.max_hp)
	var cs := CombatState.new(7308)
	cs.start_rush(7308)
	cs.spawn_paused = true
	cs.enemies.clear()
	cs.enemies.append(e)
	var hp0: int = e.hp
	cs.tick_dot(CombatConstants.DOT_TICK_SEC)
	assert_eq(e.hp, hp0)
	assert_eq(e.bleed_stacks, 1)


func test_bleed_omitted_from_timed_status_rings() -> void:
	var e := EnemyInstance.new(DataRegistry.get_enemy(1), 5)
	e.start_permanent_bleed()
	e.burn_stacks = 2
	e.burn_peak = 2
	var ids: Array = []
	for row in e.status_ring_entries(0.7):
		ids.append(str(row.get("id", "")))
	assert_true("burn" in ids)
	assert_false("bleed" in ids)
	assert_eq(e.status_text(), "燃2 血")


func test_hp_bar_bleed_icon_has_no_ttl_and_clears_on_death() -> void:
	var sk: SkeletonEnemy = (load("res://scenes/enemy/skeleton_enemy.tscn") as PackedScene).instantiate() as SkeletonEnemy
	sk.setup(1)
	add_child_autofree(sk)
	sk.set_hp(10, 10)
	assert_false(sk.is_bleeding_visual())
	var icon: Node2D = sk.find_child("BleedIcon", true, false) as Node2D
	assert_not_null(icon)
	assert_false(icon.visible)
	sk.set_bleeding(true)
	assert_true(icon.visible)
	assert_true(sk.is_bleeding_visual())
	assert_eq(icon.get_child_count(), 2, "geometric drop, no label/font")
	sk.tick_bleed_visual(0.25)
	var drips := 0
	for child in sk.get_children():
		if str(child.name).begins_with("BleedDrip"):
			drips += 1
	assert_gte(drips, 1)
	sk.play_death()
	assert_false(icon.visible)
	assert_false(sk.is_bleeding_visual())
