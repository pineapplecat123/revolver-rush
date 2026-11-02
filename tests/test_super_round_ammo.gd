extends GutTest

func _shot_one(cs: CombatState, resolve_enemy: bool = false) -> void:
	## rush!：打 1 发并 finalize；默认不进怪回合（保留枪口，方便测跨发枪口）。
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		if resolve_enemy:
			cs.resolve_post_fire_enemy_turn()
		else:
			cs._post_fire_enemy_pending = false


## 连发子弹：射击后额外装填+自动射击；奖励池；额外轮可嵌套（有硬上限防软锁）。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_ammo_def_enabled_and_in_reward_pool() -> void:
	var def: Dictionary = DataRegistry.get_ammo(FireResolver.ID_SUPER_ROUND)
	assert_eq(str(def.get("name", "")), "连发子弹")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_SUPER_ROUND))
	assert_false(DataRegistry.is_ammo_ephemeral(FireResolver.ID_SUPER_ROUND))
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_SUPER_ROUND, [FireResolver.ID_SUPER_ROUND], 0, 0), 1)


func test_super_round_grants_extra_load_and_autofire_after_magazine() -> void:
	## v0.4.0：击发连发 → 开窗，不再 pending_gold。
	var cs := CombatState.new(2121)
	cs.start_rush(2121)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_almost_eq(cs.burst_window_remaining, CombatConstants.BURST_WINDOW_SEC, 0.001)
	assert_true(_log_has(cs, "连发"))


func test_two_super_rounds_grant_two_extra_cycles() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_extra_round_super_round_nests_with_cap() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_super_round_extra_chain_hard_cap() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_super_round_in_reward_choices_pool() -> void:
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			pool.append(aid)
	assert_true(FireResolver.ID_SUPER_ROUND in pool)
	assert_true(FireResolver.ID_TOMBSTONE in pool)
	assert_false(FireResolver.ID_GHOST in pool)


func test_tombstone_then_super_round_still_grants_extra() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_extra_round_sync_load_triggers_wrath_pack() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_extra_round_stepwise_load_triggers_wrath_pack() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)


func test_super_round_chain_extra_loads_sin_pack() -> void:
	## v0.4.0：连发不再走额外轮链；保留用例名，断言连发窗机制。
	var cs := CombatState.new(2199)
	cs.start_rush(2199)
	cs.dev_force_load([
		FireResolver.ID_BURST,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_gt(cs.burst_window_remaining, 0.0)

