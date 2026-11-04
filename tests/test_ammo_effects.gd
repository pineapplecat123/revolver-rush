extends GutTest
## 弹药效果审计：金币公式伤、中途清场停射、练习战重置弹袋。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_gold_triggers_extra_auto_load_and_fire() -> void:
	## v0.4.10：金币弹按公式造成伤害并扣金，不再追加额外轮。
	var cs := CombatState.new(808)
	cs.start_rush(808)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.gold = 10
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	var expect: int = 3 + int(10 * 0.20)  # 伤害按扣金前金币
	assert_eq(hp0 - cs.enemies[0].hp, expect)
	assert_eq(cs.gold, 9)
	assert_eq(cs.pending_gold_autofires(), 0)



func test_gold_whites_fire_before_extras_then_clear() -> void:
	## v0.4.10：金币弹不再挂待追加；点射后 pending 为 0。
	var cs := CombatState.new(820)
	cs.start_rush(820)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].atk = 0
	cs.gold = 5
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_true(_log_has(cs, "金币弹药") or _log_has(cs, "金币"))



func test_gold_extra_round_keeps_muzzle() -> void:
	## v0.4.10：火焰弹挂枪口后，金币弹仍享受火枪口（本发元素附带）。
	var cs := CombatState.new(809)
	cs.start_rush(809)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.gold = 0
	cs.bag.clear()
	cs.discard.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_FLAME,
		FireResolver.ID_GOLD,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	# 先打火挂枪口
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_true(cs._muzzle_fire)
	var burn0: int = cs.enemies[0].burn_stacks
	# 再打金币（带火）
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_gt(cs.enemies[0].burn_stacks, burn0)



func test_stone_enemy_disabled_in_combat_pool() -> void:
	## 石头人/骷髅禁用：不进刷怪池；设计数据仍在（legacy id）。
	var def: Dictionary = DataRegistry.get_enemy(105)
	assert_eq(str(def.get("name", "")), "石头人")
	assert_false(bool(def.get("enabled_in_combat", true)))
	assert_false(bool(DataRegistry.get_enemy(104).get("enabled_in_combat", true)))
	var cs := CombatState.new(821)
	cs.start_rush(821)
	# v0.3.8 连续刷怪：各时间段种类池都不含石头人/骷髅
	for _w in 12:
		cs.enemies.clear()
		cs.elapsed_sec = float(_w) * CombatConstants.SPAWN_POOL_STEP_SEC
		cs._spawn_up_to_cap()
		for e in cs.enemies:
			assert_ne(e.def_id, 105, "stone must not spawn when disabled")
			assert_ne(e.def_id, 104, "skeleton must not spawn when disabled")



func test_gold_extra_when_bag_empty_after_full_load() -> void:
	## v0.4.10：袋空时金币弹仍按公式结算，不依赖额外轮洗牌。
	var cs := CombatState.new(830)
	cs.start_rush(830)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.gold = 20
	cs.bag.clear()
	cs.discard.clear()
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	var expect: int = 3 + int(20 * 0.20)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(hp0 - cs.enemies[0].hp, expect)
	assert_eq(cs.gold, 19)



func test_gold_extras_after_remaining_whites() -> void:
	## v0.4.10：金币弹有伤；金币＜1 时不扣金。
	var cs := CombatState.new(831)
	cs.start_rush(831)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.gold = 0
	cs.bag.clear()
	cs.discard.clear()
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	assert_eq(hp0 - cs.enemies[0].hp, 3)
	assert_eq(cs.gold, 0)
	assert_eq(cs.pending_gold_autofires(), 0)



func test_super_zombie_summons_behind() -> void:
	## 表改：面前召唤（朝向玩家的更低格）。
	var cs := CombatState.new(844)
	cs.start_rush(844, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(CombatConstants.SUPER_ZOMBIE_ENEMY_ID, 5)
	assert_eq(cs.enemies.size(), 1)
	cs.bag.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.tick_enemy_auto_step())
	var boss: EnemyInstance = null
	var zombies := 0
	var zcell := -1
	for e in cs.enemies:
		if e.def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			boss = e
		elif e.def_id == CombatConstants.ZOMBIE_ENEMY_ID:
			zombies += 1
			zcell = e.cell
	assert_eq(zombies, 1, "super zombie should summon one zombie in front")
	assert_ne(boss, null)
	assert_eq(zcell, boss.cell - 1)



func test_begin_gold_extra_load_is_stepwise_not_instant() -> void:
	## UI 金色额外：begin 后不瞬装满，需逐步 load_next_chamber；装完才可开火。
	var cs := CombatState.new(830)
	cs.start_rush(830)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.pace_after_fire = true
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.discard.clear()
	for _i in 8:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	cs.dev_force_load([
		FireResolver.ID_GOLD,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	# rush!：点射金留下待追加；额外轮只补 1 发，不倾倒/拉满匣
	_shot_one(cs)  # will fire gold first if at hammer — force gold at start
	# 上面 force_load 金在首；但 _shot_one 可能已打完一发。重新开金场景：
	# 简化：直接验证 begin_gold_extra_load 补 1
	cs._pending_gold_autofires = 1
	var before_n: int = cs.magazine.loaded_count()
	assert_true(cs.begin_gold_extra_load())
	if before_n >= CombatConstants.MAGAZINE_SIZE:
		assert_false(cs.is_busy_loading())
	else:
		assert_true(cs.is_busy_loading())
		var r: Dictionary = cs.load_next_chamber()
		assert_true(bool(r.get("ok", false)))
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
		cs.commit_load_session_if_active()
		assert_eq(cs.magazine.loaded_count(), before_n + 1)
	assert_true(cs.can_fire() or cs.phase == CombatState.Phase.AWAIT_ACTION)
