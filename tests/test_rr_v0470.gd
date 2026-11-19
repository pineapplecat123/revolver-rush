extends GutTest
## v0.4.70：普通击杀掉金 25%→100%；数量仍是普通 2、超级僵尸 8；木桩不掉。所有模式共用原逻辑。


func before_each() -> void:
	DataRegistry.reload()
	CampaignRules.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func after_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func test_version_is_at_least_0_4_70() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.70") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.70" in log)
	assert_true("必定掉金币" in log or "100" in log)


func test_kill_gold_constants_and_unchanged_neighbors() -> void:
	assert_almost_eq(CombatConstants.KILL_GOLD_DROP_CHANCE, 1.0, 0.001)
	assert_eq(CombatConstants.KILL_GOLD_DROP_AMOUNT, 2)
	assert_almost_eq(CombatConstants.KILL_GOLD_BOSS_DROP_CHANCE, 1.0, 0.001)
	assert_eq(CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT, 8)
	assert_eq(CombatConstants.REWARD_BASE_GOLD, 10)
	assert_eq(CombatConstants.REWARD_SKIP_EXTRA_GOLD, 5)
	assert_eq(CombatConstants.REWARD_BOSS_BASE_GOLD, 25)
	# 贪婪掉金仍是每层 30%，不走击杀掉金概率。
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_state.gd")
	assert_true("if rng.randf() < 0.30:" in src)
	assert_true("func _try_greed_gold_drop" in src)
	# 击杀掉金只在这一处生成待拾取，所有击杀路径都走 _remove_dead。
	assert_eq(src.count("func _try_kill_gold_drop"), 1)
	assert_eq(src.count("_try_kill_gold_drop("), 2)  # 定义 + _remove_dead 一处调用
	assert_true("func dev_kill_all_enemies" in src)
	assert_true("dev_kill_all_enemies" in src and "_remove_dead()" in src)


func _rush(seed: int) -> CombatState:
	var cs := CombatState.new()
	cs.start_rush(seed, FireResolver.ID_WRATH)
	cs.spawn_paused = true
	cs.enemies.clear()
	cs.gold_drops.clear()
	cs.gold = 0
	cs.kill_gold_chance_override = -1.0
	cs.rng.seed = seed
	return cs


func _pending_amounts(cs: CombatState) -> Array:
	var out: Array = []
	for d in cs.gold_drops:
		out.append(int(d.get("remaining", 0)))
	return out


func _assert_pending_only(cs: CombatState, amount: int, msg: String = "") -> void:
	assert_eq(cs.gold, 0, "金币尚未入账" if msg.is_empty() else msg + "：尚未入账")
	assert_eq(cs.pending_gold_total(), amount, msg)
	assert_eq(cs.gold_drops.size(), 1)
	assert_eq(int(cs.gold_drops[0].get("total", 0)), amount)
	assert_eq(int(cs.gold_drops[0].get("remaining", 0)), amount)


func test_ordinary_kills_always_drop_two_across_many_seeds() -> void:
	var hook_count := 0
	for seed in 40:
		var cs := _rush(1000 + seed)
		cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 4)
		assert_eq(cs.enemies.size(), 1)
		cs.enemies[0].hp = 0
		var drops: Array = []
		cs.hooks.subscribe(&"on_kill_gold", func(p: Dictionary) -> void:
			drops.append(p)
		)
		cs._remove_dead()
		_assert_pending_only(cs, CombatConstants.KILL_GOLD_DROP_AMOUNT, "seed %d 平民" % seed)
		assert_eq(drops.size(), 1, "seed %d 只掉一次" % seed)
		assert_eq(int(drops[0].get("amount", 0)), 2)
		# 再扫一遍尸体不会再掉
		cs._remove_dead()
		assert_eq(cs.pending_gold_total(), 2)
		assert_eq(cs.gold_drops.size(), 1)
		var drop_id: int = int(cs.gold_drops[0]["id"])
		assert_eq(cs.collect_gold_piece(drop_id, 2), 2)
		assert_eq(cs.gold, 2)
		assert_eq(cs.pending_gold_total(), 0)
		assert_eq(cs.collect_gold_piece(drop_id, 2), 0, "同一堆不能再捡")
		hook_count += 1
	assert_eq(hook_count, 40)


func test_summoned_ordinary_zombie_drops_two() -> void:
	var cs := _rush(47011)
	var boss: EnemyInstance = null
	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 5)
	for e in cs.alive_enemies():
		if int(e.def_id) == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			boss = e
			break
	assert_not_null(boss)
	cs._try_super_zombie_summons()
	var summoned: EnemyInstance = null
	for e in cs.alive_enemies():
		if int(e.def_id) == CombatConstants.ZOMBIE_ENEMY_ID:
			summoned = e
			break
	assert_not_null(summoned, "超级僵尸应召唤普通僵尸")
	cs.gold = 0
	cs.gold_drops.clear()
	summoned.hp = 0
	cs._remove_dead()
	# 首领还活着，只结算被召唤的普通僵尸
	assert_eq(cs.alive_enemies().size(), 1)
	assert_eq(int(cs.alive_enemies()[0].def_id), CombatConstants.SUPER_ZOMBIE_ENEMY_ID)
	_assert_pending_only(cs, CombatConstants.KILL_GOLD_DROP_AMOUNT, "召唤僵尸")
	assert_eq(cs.collect_gold_piece(int(cs.gold_drops[0]["id"]), 2), 2)
	assert_eq(cs.gold, 2)


func test_campaign_non_id5_boss_drops_ordinary_two() -> void:
	# 前五关首领分别是 2/3/4/4/105，都不是超级僵尸。
	for floor_i in range(1, 6):
		var cs := CombatState.new()
		cs.start_campaign(47020 + floor_i)
		cs.campaign_instant_transitions = true
		if cs.campaign_offer_pending:
			assert_true(cs.campaign_pick_opening(0))
		cs.campaign_skip_walk()
		cs.enemies.clear()
		cs.gold_drops.clear()
		cs.gold = 0
		cs.campaign_floor = floor_i
		cs._campaign_start_boss()
		assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)
		assert_eq(cs.alive_enemies().size(), 1)
		var boss: EnemyInstance = cs.alive_enemies()[0]
		var want_id: int = int(CampaignRules.boss_def(floor_i).get("id", -1))
		assert_eq(int(boss.def_id), want_id)
		assert_ne(int(boss.def_id), CombatConstants.SUPER_ZOMBIE_ENEMY_ID)
		boss.hp = 0
		cs._remove_dead()
		_assert_pending_only(cs, CombatConstants.KILL_GOLD_DROP_AMOUNT, "闯关第%d关非超级首领" % floor_i)
		assert_eq(cs.collect_gold_piece(int(cs.gold_drops[0]["id"]), 2), 2)
		assert_eq(cs.gold, 2)


func test_super_zombie_and_campaign_id5_boss_drop_eight() -> void:
	var rush := _rush(47031)
	rush.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 6)
	rush.enemies[0].hp = 0
	rush._remove_dead()
	_assert_pending_only(rush, CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT, "rush 超级僵尸")
	assert_eq(rush.collect_gold_piece(int(rush.gold_drops[0]["id"]), 8), 8)
	assert_eq(rush.gold, 8)

	# 第 6 关首领是超级僵尸 id 5。
	var cs := CombatState.new()
	cs.start_campaign(47032)
	cs.campaign_instant_transitions = true
	if cs.campaign_offer_pending:
		assert_true(cs.campaign_pick_opening(0))
	cs.campaign_skip_walk()
	cs.enemies.clear()
	cs.gold_drops.clear()
	cs.gold = 0
	cs.campaign_floor = 6
	cs._campaign_start_boss()
	assert_eq(cs.alive_enemies().size(), 1)
	assert_eq(int(cs.alive_enemies()[0].def_id), CombatConstants.SUPER_ZOMBIE_ENEMY_ID)
	cs.alive_enemies()[0].hp = 0
	cs._remove_dead()
	_assert_pending_only(cs, CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT, "闯关第6关超级首领")
	assert_eq(cs.gold, 0)
	assert_eq(cs.collect_gold_piece(int(cs.gold_drops[0]["id"]), 8), 8)
	assert_eq(cs.gold, 8)


func test_dummy_drops_nothing() -> void:
	var cs := CombatState.new()
	cs.start_sandbox(47041, FireResolver.ID_WRATH, true)
	cs.enemies.clear()
	cs.gold = 0
	cs.gold_drops.clear()
	cs.kill_gold_chance_override = 1.0
	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(20, 4)
	assert_not_null(dummy)
	dummy.hp = 0
	cs._remove_dead()
	assert_eq(cs.pending_gold_total(), 0)
	assert_eq(cs.gold, 0)
	assert_true(cs.enemies.size() >= 1)
	assert_true(cs.enemies[0].is_dummy)
	assert_gt(cs.enemies[0].hp, 0, "沙盒木桩死后应复活，且不掉金")


func test_shared_kill_paths_drop_exactly_once_and_not_early() -> void:
	# 伤害打空后走 _remove_dead（与开火/持续伤害同一出口）。
	var cs := _rush(47051)
	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 3)
	var e: EnemyInstance = cs.enemies[0]
	e.apply_damage(e.hp)
	assert_eq(e.hp, 0)
	assert_eq(cs.pending_gold_total(), 0, "打死当帧、移出前还不掉")
	assert_eq(cs.gold, 0)
	cs._remove_dead()
	_assert_pending_only(cs, 2, "伤害击杀")
	var first_id: int = int(cs.gold_drops[0]["id"])
	cs._remove_dead()
	assert_eq(cs.gold_drops.size(), 1)
	assert_eq(int(cs.gold_drops[0]["id"]), first_id)

	# dev_kill_all 也走同一套，两只普通怪各掉 2，尚未入账。
	var cs2 := _rush(47052)
	cs2.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 3)
	cs2.dev_spawn_enemy(CombatConstants.ZOMBIE_ENEMY_ID, 6)
	assert_eq(cs2.alive_enemies().size(), 2)
	cs2.dev_kill_all_enemies()
	assert_eq(cs2.gold, 0, "一键击杀也不提前入账")
	assert_eq(cs2.pending_gold_total(), 4)
	assert_eq(cs2.gold_drops.size(), 2)
	for amt in _pending_amounts(cs2):
		assert_eq(amt, 2)
	var took: int = cs2.collect_gold_piece(int(cs2.gold_drops[0]["id"]), 2)
	assert_eq(took, 2)
	assert_eq(cs2.gold, 2)
	assert_eq(cs2.pending_gold_total(), 2)
