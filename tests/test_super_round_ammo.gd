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


## 超级回合子弹：射击后额外装填+自动射击；奖励池；额外轮可嵌套（有硬上限防软锁）。


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
	assert_eq(str(def.get("name", "")), "超级回合子弹")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_SUPER_ROUND))
	assert_false(DataRegistry.is_ammo_ephemeral(FireResolver.ID_SUPER_ROUND))
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_SUPER_ROUND, [FireResolver.ID_SUPER_ROUND], 0, 0), 1)


func test_super_round_grants_extra_load_and_autofire_after_magazine() -> void:
	## 击发超级回合后计入待追加；do_fire/点射收束时追加 1 轮（补1发再射1发）。
	var cs := CombatState.new(2121)
	cs.start_rush(2121)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	# rush!：点射超级回合 → 立刻待追加；do_fire 打完剩余并同步打额外轮（每轮补1发再射1发）
	_shot_one(cs)  # 超级回合：伤1
	assert_eq(cs.pending_gold_autofires(), 1)
	assert_true(_log_has(cs, "超级回合子弹"))
	assert_eq(hp0 - cs.enemies[0].hp, 1)
	assert_true(cs.do_fire())
	# 主匣剩余 5 白×3=15 + 超级1 + 额外轮至少 +1 白×3 → ≥19
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_gte(dealt, 19, "extra autofire should add at least one white, dealt=%d" % dealt)
	assert_true(_log_has(cs, "额外装填回合") or _log_has(cs, "额外轮"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_two_super_rounds_grant_two_extra_cycles() -> void:
	var cs := CombatState.new(2122)
	cs.start_rush(2122)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 12:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		FireResolver.ID_SUPER_ROUND,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	# rush! 点射模型：两发超级回合各记一次待追加（可能分两条日志），额外轮打完 pending=0
	var grants := 0
	for line in cs.last_log:
		if "待追加" in str(line) and "超级回合" in str(line):
			grants += 1
		elif "超级回合子弹：射击后获得额外" in str(line):
			grants += 1
	assert_gte(grants, 2, "two super rounds should each grant an extra")
	assert_eq(cs.pending_gold_autofires(), 0)


func test_extra_round_super_round_nests_with_cap() -> void:
	## 额外轮内再打出超级回合应继续入队；全匣超级时靠硬上限收束，pending 最终为 0。
	var cs := CombatState.new(2123)
	cs.start_rush(2123)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 9999
	cs.enemies[0].max_hp = 9999
	cs.bag.clear()
	cs.bag_temp.clear()
	# 袋里足够多超级回合：额外轮会再打出超级并嵌套
	for _i in 30:
		cs.bag.append(FireResolver.ID_SUPER_ROUND)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_eq(cs.pending_gold_autofires(), 0)
	var finished := 0
	for line in cs.last_log:
		var line_s := str(line)
		if "额外轮单发射击完毕" in line_s or "额外装填回合射击完毕" in line_s or "额外轮射击完毕" in line_s:
			finished += 1
	assert_gt(finished, 1, "nested extras from id=21 in bonus round should run, got %d" % finished)
	assert_lte(finished, CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN)
	# 硬上限：授予达顶时应有日志（袋极多超级时几乎必触发）
	var hit_cap := _log_has(cs, "已达上限")
	assert_true(hit_cap or finished >= 2, "cap log or at least nested extras")


func test_super_round_extra_chain_hard_cap() -> void:
	## 直接压测入队：同链授予不超过 MAX_EXTRA_AUTOFIREs_PER_CHAIN。
	var cs := CombatState.new(2126)
	cs.start_rush(2126)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs._extra_autofires_granted_this_chain = 0
	cs._in_gold_extra_round = true  # 模拟已在额外轮
	var cap: int = CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN
	for _i in cap + 5:
		cs._queue_extra_autofire_from_shot(FireResolver.ID_SUPER_ROUND)
	assert_eq(cs.pending_gold_autofires(), cap)
	assert_eq(cs._extra_autofires_granted_this_chain, cap)
	assert_true(_log_has(cs, "已达上限"))


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
	## 与墓碑爆发共存：同匣先墓碑填幽灵，再超级回合仍应计入额外轮。
	var cs := CombatState.new(2125)
	cs.start_rush(2125)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in 8:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)  # tombstone → 填幽灵入匣
	_shot_one(cs)  # super round（匣内下一发）
	assert_eq(cs.pending_gold_autofires(), 1)
	assert_true(cs.do_fire())  # 打完幽灵 + 同步额外轮
	assert_true(_log_has(cs, "额外装填回合") or _log_has(cs, "超级回合子弹") or _log_has(cs, "额外轮"))
	assert_eq(cs.pending_gold_autofires(), 0)


func test_extra_round_sync_load_triggers_wrath_pack() -> void:
	## rush! 额外轮只补 1 发：单发愤怒不触发≥3 包；普通装满会话仍会惩罚（见手装测）。
	var cs := CombatState.new(2127)
	cs.start_rush(2127, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs.magazine.clear()
	cs._in_gold_extra_round = true
	var hp0: int = cs.player_hp
	assert_true(cs._auto_load_and_fire_once())
	assert_eq(cs.player_hp, hp0, "single-chamber extra must not sin-pack")
	assert_eq(cs.magazine.loaded_count() + cs.discard.size(), 1)


func test_extra_round_stepwise_load_triggers_wrath_pack() -> void:
	## UI 金色额外：begin 后只补 1 发即结束会话（不拉满匣、不因单发愤怒包伤）。
	var cs := CombatState.new(2128)
	cs.start_rush(2128, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs.magazine.clear()
	cs._pending_gold_autofires = 1
	var hp0: int = cs.player_hp
	assert_true(cs.begin_gold_extra_load())
	var steps := 0
	while cs.is_busy_loading():
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		steps += 1
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
		assert_lte(steps, 2)
	assert_eq(steps, 1)
	assert_eq(cs.player_hp, hp0)
	assert_eq(cs.magazine.loaded_count(), 1)


func test_super_round_chain_extra_loads_sin_pack() -> void:
	## 实打：主匣超级回合 → 额外轮只补 1 发愤怒，不触发≥3 包；仍应跑额外轮。
	var cs := CombatState.new(2129)
	cs.start_rush(2129, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for id in [
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
	]:
		cs.bag.append(id)
		cs.bag_temp.append(false)
	cs.dev_force_load([
		FireResolver.ID_SUPER_ROUND,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.player_hp
	assert_true(cs.do_fire())
	assert_eq(cs.player_hp, hp0, "single-chamber extra must not sin-pack")
	assert_true(_log_has(cs, "额外装填回合") or _log_has(cs, "额外轮"))
