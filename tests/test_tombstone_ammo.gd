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
	## v0.4.0：不再填空仓；改为袋+临时幽灵并连射袋内幽灵。
	var cs := CombatState.new(1952)
	cs.start_rush(1952, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	for _i in 2:
		cs._bag_append(FireResolver.ID_GHOST, CombatConstants.GHOST_TTL_SEC)
	_shot_one(cs)
	assert_eq(cs.magazine.loaded_count(), 1, "white remains; no ghost fill")
	var ghosts_left := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			ghosts_left += 1
	assert_eq(ghosts_left, 0)
	# v0.4.20：墓碑2 + 预置幽灵 2×2 = 6（袋里有幽灵时不再新生成）
	assert_eq(999 - int(cs.enemies[0].hp), 6)


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
	_shot_one(cs)
	# v0.4.20：袋里没幽灵 → 生成 2 颗临时幽灵留在袋里，本发不带幽灵
	var left_g2 := 0
	for id in cs.bag:
		if int(id) == FireResolver.ID_GHOST:
			left_g2 += 1
	assert_eq(left_g2, CombatConstants.TOMBSTONE_GHOST_SPAWN)
	var ghosts_in_mag := 0
	for id in cs.magazine.slots:
		if int(id) == FireResolver.ID_GHOST:
			ghosts_in_mag += 1
	assert_eq(ghosts_in_mag, 0, "v0.4.0 no chamber fill")
	assert_eq(500 - int(cs.enemies[0].hp), 2, "tombstone only; new ghosts wait in bag")


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
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_TOMBSTONE, [FireResolver.ID_TOMBSTONE], 0), 2)
	assert_eq(FireResolver.base_damage_for(FireResolver.ID_GHOST, [FireResolver.ID_GHOST], 0), 2)

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
	# v0.4.20：幽灵永远带 TTL，所以袋里的临时弹 = 2 颗幽灵；重置本身不再加临时罪孽
	assert_eq(cs.count_temporary_in_bag(), 2, "only the 2 ghosts are temporary (v0.3.8: reset adds no temp sins)")
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
	## v0.4.0：不再填仓；仍保留 last_fired_slot 为墓碑锤位。
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
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hammer: int = cs.magazine.chamber_at_fire_port()
	_shot_one(cs)
	assert_eq(cs.last_fired_slot, hammer)

