extends GutTest
## v0.4.14 懒惰：命中叠加减速；三罪 4s 射速−50% 窗。

const SLOTH := FireResolver.ID_SLOTH
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41401) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, SLOTH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	cs.pace_after_fire = false
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_version_is_0_4_14() -> void:
	assert_eq(GameVersion.STRING, "0.4.14")
	assert_true("0.4.14" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_sloth_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(SLOTH)
	assert_eq(str(def.get("name", "")), "懒惰弹药")
	assert_true(DataRegistry.is_sin_ammo(SLOTH))
	assert_true(bool(FireResolver.inherits_from(SLOTH).get("sloth", false)))


func test_sloth_applies_slow_on_hit() -> void:
	var cs := _rush(41410)
	cs.dev_force_load([SLOTH, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)
	assert_gt(cs._muzzle_sloth, 0)
	assert_gt(cs.enemies[0].slow_stacks(), 0)


func test_sloth_three_sin_fire_lock() -> void:
	var cs := _rush(41411)
	cs._resolve_sin_pack_on_load([SLOTH, SLOTH, SLOTH])
	assert_almost_eq(cs.sloth_fire_penalty_remaining, CombatConstants.SLOTH_FIRE_PENALTY_SEC, 0.001)
	cs.dev_force_load([WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	# fire_tap path sets lock
	cs.fire_tap()
	assert_gt(cs.fire_lock_remaining, 0.0)
	assert_false(cs.can_fire())
	cs.tick_combat_time(cs.fire_lock_remaining + 0.01)
	# may still need ammo ready
	assert_eq(cs.fire_lock_remaining, 0.0)
