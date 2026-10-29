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


## 墓碑→幽灵：生成、填空仓爆发、战后清幽灵、奖励/商店池排除。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_ammo_defs_enabled() -> void:
	var tomb: Dictionary = DataRegistry.get_ammo(FireResolver.ID_TOMBSTONE)
	var ghost: Dictionary = DataRegistry.get_ammo(FireResolver.ID_GHOST)
	assert_eq(str(tomb.get("name", "")), "墓碑弹药")
	assert_eq(str(ghost.get("name", "")), "幽灵弹药")
	assert_eq(int(tomb.get("base_damage", 0)), 2)
	assert_eq(int(ghost.get("base_damage", 0)), 2)
	assert_true(bool(tomb.get("enabled_in_combat", false)))
	assert_true(bool(ghost.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_TOMBSTONE))
	assert_false(DataRegistry.is_ammo_reward_eligible(FireResolver.ID_GHOST))
	assert_true(DataRegistry.is_ammo_ephemeral(FireResolver.ID_GHOST))


func test_tombstone_spawns_ghost_and_fills_empty_chambers() -> void:
	var cs := CombatState.new(1952)
	cs.start_rush(1952, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	# 膛：墓碑 + 1 平庸 + 4 空 → 击发墓碑后空仓（含刚打空）用幽灵填满
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
	] as Array[int])
	for _i in 4:
		cs.bag.append(FireResolver.ID_GHOST)
		cs.bag_temp.append(false)
	cs.magazine.set_start(0)
	_shot_one(cs)  # 墓碑 → 幽灵填空仓，不连射锁控
	var ghost_in_mag := 0
	for id in cs.magazine.slots:
		if int(id) == FireResolver.ID_GHOST:
			ghost_in_mag += 1
	assert_eq(ghost_in_mag, 5, "5 empty chambers filled with ghosts")
	var left_g := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			left_g += 1
	assert_eq(left_g, 0, "ghosts consumed from bag into mag")
	# 墓碑伤 2；再 do_fire 打完平庸+5幽灵 = 15；流血在自动推进拍结算
	assert_true(cs.do_fire())
	assert_eq(999 - int(cs.enemies[0].hp), 15, "shot damage before bleed tick")
	assert_eq(cs.enemies[0].bleed_stacks, 7)
	assert_true(cs.tick_enemy_auto_step())
	assert_eq(999 - int(cs.enemies[0].hp), 15 + 7, "15 shot dmg + 7 bleed tick")


func test_tombstone_generates_ghost_even_when_mag_full_of_ammo() -> void:
	var cs := CombatState.new(1953)
	cs.start_rush(1953, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 500
	cs.enemies[0].max_hp = 500
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	var left_g2 := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			left_g2 += 1
	assert_eq(left_g2, 0)
	var ghosts_in_mag := 0
	for id in cs.magazine.slots:
		if int(id) == FireResolver.ID_GHOST:
			ghosts_in_mag += 1
	assert_eq(ghosts_in_mag, 1, "emptied hammer refilled with 1 ghost; rest stay white")
	# rush!：不把幽灵塞进本发队列，留给后续点射
	assert_false(FireResolver.ID_GHOST in cs._fire_queue)


func test_ghost_never_in_reward_choices() -> void:
	var cs := CombatState.new(1955)
	cs.start_rush(1955, FireResolver.ID_GREED)
	for _i in 40:
		var choices: Array[int] = cs.generate_reward_choices()
		assert_eq(choices.size(), CombatConstants.REWARD_CHOICE_COUNT)
		for id in choices:
			assert_ne(int(id), FireResolver.ID_GHOST)
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			pool.append(aid)
	assert_true(FireResolver.ID_TOMBSTONE in pool)
	assert_false(FireResolver.ID_GHOST in pool)


func test_ghost_damage_is_two() -> void:
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_TOMBSTONE, [FireResolver.ID_TOMBSTONE], 0, 0), 2)
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_GHOST, [FireResolver.ID_GHOST], 0, 0), 2)

func test_bag_can_hold_multiple_tombstones() -> void:
	## 设计未限制墓碑唯一；袋可持有多发。奖励/商店入袋可叠加（地图/无限均保留构筑；练习胜利仍回 10+5）。
	var cs := CombatState.new(1919)
	cs.start_rush(1919)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(FireResolver.ID_TOMBSTONE, false)
	cs._bag_append(FireResolver.ID_TOMBSTONE, false)
	cs._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	var n := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_TOMBSTONE:
			n += 1
	assert_eq(n, 2)
	assert_eq(cs.bag.size(), 3)


func test_endless_win_keeps_tombstones_then_reward_stacks() -> void:
	## 无限每波胜利：保留构筑（墓碑不打回 10+5）；幽灵清；再领奖可再叠墓碑。
	var cs := CombatState.new(1920)
	cs.start_rush(1920, FireResolver.ID_WRATH)
	cs._bag_append(FireResolver.ID_TOMBSTONE, false)
	cs._bag_append(FireResolver.ID_TOMBSTONE, false)
	cs._snapshot_combat_bag_baseline()
	var before := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_TOMBSTONE:
			before += 1
	assert_eq(before, 2)
	cs.enemies[0].hp = 1
	cs.enemies[0].max_hp = 1
	cs.dev_force_load([CombatConstants.WHITE_AMMO_ID] as Array[int])
	assert_true(cs.do_fire())
	assert_eq(cs.phase, CombatState.Phase.WON)
	var mid := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_TOMBSTONE:
			mid += 1
		assert_ne(int(id), FireResolver.ID_GHOST)
	assert_eq(mid, 2, "tombstones must survive endless wave win")
	assert_gt(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	cs.reward_choices = [FireResolver.ID_TOMBSTONE, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID]
	assert_true(cs.pick_reward_ammo(0))
	var after := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_TOMBSTONE:
			after += 1
	assert_eq(after, 3)


func test_mid_combat_bag_reset_keeps_tombstone_and_ghost() -> void:
	## 同波袋空自动重置：墓碑（构筑基线）与幽灵（战斗临时）均保留；另加 1 发临时罪孽。
	var cs := CombatState.new(1921)
	cs.start_rush(1921, FireResolver.ID_GREED)
	cs._bag_append(FireResolver.ID_TOMBSTONE, false)
	cs._snapshot_combat_bag_baseline()
	# 模拟打空：永久弹进弃牌，幽灵在弃牌，袋空
	cs.discard.clear()
	cs.discard_temp.clear()
	for id in cs.bag:
		cs._discard_append(int(id), false)
	cs._discard_append(FireResolver.ID_GHOST, false)
	cs._discard_append(FireResolver.ID_GHOST, false)
	cs.bag.clear()
	cs.bag_temp.clear()
	assert_true(cs._auto_reset_bag_if_empty_at_turn_start())
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.count_temporary_in_bag(), 1)
	var tombs := 0
	var ghosts := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_TOMBSTONE:
			tombs += 1
		elif int(id) == FireResolver.ID_GHOST:
			ghosts += 1
	assert_eq(tombs, 1, "tombstone must survive mid-combat bag reset")
	assert_eq(ghosts, 2, "ghosts must survive mid-combat bag reset")
	assert_eq(cs.discard.size(), 0)


func test_tombstone_fill_keeps_last_fired_slot() -> void:
	## 幽灵填仓会改槽内容（含刚打空的仓），但 last_fired_slot 仍是本发锤位，不跳到别仓。
	var cs := CombatState.new(1960)
	cs.start_rush(1960, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
		Magazine.EMPTY,
	] as Array[int])
	for _i in 4:
		cs.bag.append(FireResolver.ID_GHOST)
		cs.bag_temp.append(false)
	cs.magazine.set_start(0)
	var hammer: int = cs.magazine.chamber_at_fire_port()
	_shot_one(cs)
	assert_eq(cs.last_fired_slot, hammer, "ghost fill must not retarget last_fired_slot")
	assert_eq(cs.magazine.slots[hammer], FireResolver.ID_GHOST, "emptied hammer may be refilled with ghost")
