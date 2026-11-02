extends GutTest
## v0.4.4 炸药弹药：打已燃烧目标 3 倍 + 左右溅射。

const WHITE := CombatConstants.WHITE_AMMO_ID
const FLAME := FireResolver.ID_FLAME
const EXP := FireResolver.ID_EXPLOSIVE


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4401) -> CombatState:
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
	cs.player_hp = 99999
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_changelog_has_0_4_4_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.4"' in text or '"version":"0.4.4"' in text)


func test_explosive_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(EXP)
	assert_eq(str(def.get("name", "")), "炸药弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(EXP))
	assert_true(bool(FireResolver.inherits_from(EXP).get("explosive", false)))
	assert_false("回合" in str(def.get("special", "")))


func test_explosive_mounts_muzzle() -> void:
	var cs := _rush(4410)
	cs.dev_force_load([
		EXP, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_true(cs._muzzle_explosive)
	assert_true("炸药" in cs.muzzle_status_parts())


func test_explosive_triples_and_splashes_when_burning() -> void:
	## 三只相邻；前排已燃烧；白弹底伤3 + 炸药 → 主目标 9，左右各最多 N=max(1,3-2)=1 格也吃 9。
	var cs := _rush(4411)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 2)
	cs.dev_spawn_enemy(1, 3)
	cs.dev_spawn_enemy(1, 4)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	var sorted: Array = cs.enemies_sorted_by_cell()
	sorted[1].burn_stacks = 2  # middle burning
	cs._muzzle_explosive = true
	cs.dev_force_load([
		WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	# aim at middle: need hammer to hit nearest = front (cell 2)
	# So put burn on front instead
	sorted[0].burn_stacks = 2
	sorted[1].burn_stacks = 0
	var hp0: Array[int] = [sorted[0].hp, sorted[1].hp, sorted[2].hp]
	_shot_one(cs)
	# front takes 3*3=9; right side N=1 → mid takes 9; far may be 0
	assert_eq(hp0[0] - sorted[0].hp, 9)
	assert_eq(hp0[1] - sorted[1].hp, 9)
	assert_eq(hp0[2] - sorted[2].hp, 0)


func test_explosive_no_bonus_without_burn() -> void:
	var cs := _rush(4412)
	cs._muzzle_explosive = true
	cs.enemies[0].burn_stacks = 0
	cs.dev_force_load([
		WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)


func test_explosive_max_one_layer_refresh() -> void:
	var cs := _rush(4413)
	cs.dev_force_load([
		EXP, EXP, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs._muzzle_explosive_layers.size(), 1)
	cs.tick_muzzle_durations(1.2)
	_shot_one(cs)
	assert_eq(cs._muzzle_explosive_layers.size(), 1)
	assert_almost_eq(cs._muzzle_explosive_t, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 0.001)
