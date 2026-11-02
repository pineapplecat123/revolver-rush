extends GutTest
## v0.4.5 散射弹药：伤害均分全场；<3 人则各 30%。

const SCATTER := FireResolver.ID_SCATTER


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4501) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.player_hp = 99999
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_version_is_0_4_5() -> void:
	assert_eq(GameVersion.STRING, "0.4.5")


func test_scatter_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(SCATTER)
	assert_eq(str(def.get("name", "")), "散射弹药")
	assert_eq(int(def.get("base_damage", 0)), 5)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(SCATTER))
	assert_eq(FireResolver.base_damage_for(SCATTER, [SCATTER], 0, 0), 5)


func test_scatter_splits_among_three_plus() -> void:
	var cs := _rush(4510)
	for cell in [2, 3, 4, 5]:
		cs.dev_spawn_enemy(1, cell)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	cs.dev_force_load([
		SCATTER, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hps: Array[int] = []
	for e in cs.enemies_sorted_by_cell():
		hps.append(e.hp)
	_shot_one(cs)
	# 5 / 4 = 1.25 → round 1 each
	var sorted: Array = cs.enemies_sorted_by_cell()
	for i in sorted.size():
		assert_eq(hps[i] - sorted[i].hp, 1)


func test_scatter_under_three_takes_thirty_percent() -> void:
	var cs := _rush(4511)
	cs.dev_spawn_enemy(1, 3)
	cs.dev_spawn_enemy(1, 4)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	cs.dev_force_load([
		SCATTER, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var sorted: Array = cs.enemies_sorted_by_cell()
	var hp0: Array[int] = [sorted[0].hp, sorted[1].hp]
	_shot_one(cs)
	# round(5*0.3)=round(1.5)=2
	assert_eq(hp0[0] - sorted[0].hp, 2)
	assert_eq(hp0[1] - sorted[1].hp, 2)
