extends GutTest
## v0.4.7 聚能弹药：本装填周期内第 n 发伤害 = 2+n。

const FOCUS := FireResolver.ID_FOCUS
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4701) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_version_is_0_4_7() -> void:
	assert_eq(GameVersion.STRING, "0.4.7")


func test_focus_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(FOCUS)
	assert_eq(str(def.get("name", "")), "聚能弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(FOCUS))


func test_focus_damage_increments_per_shot() -> void:
	var cs := _rush(4710)
	cs.dev_force_load([
		FOCUS, FOCUS, FOCUS, WHITE, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
	hp0 = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 4)
	hp0 = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 5)


func test_focus_counter_resets_on_force_load() -> void:
	var cs := _rush(4711)
	cs.dev_force_load([FOCUS, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	_shot_one(cs)  # 3
	cs.dev_force_load([FOCUS, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
