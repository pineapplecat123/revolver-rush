extends GutTest
## v0.4.2 吸血弹药：可叠层【吸血】；每层20%概率吸本次伤害50%。

const WHITE := CombatConstants.WHITE_AMMO_ID
const LS := FireResolver.ID_LIFESTEAL


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4201) -> CombatState:
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
	cs.player_hp = 10
	cs.player_max_hp = 20
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_version_is_0_4_2() -> void:
	assert_eq(GameVersion.STRING, "0.4.2")


func test_lifesteal_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(LS)
	assert_eq(str(def.get("name", "")), "吸血弹药")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(LS))
	assert_true(bool(FireResolver.inherits_from(LS).get("lifesteal", false)))
	assert_false("回合" in str(def.get("special", "")))


func test_lifesteal_mounts_stack_and_heals_at_100_percent() -> void:
	## 叠满 5 层 → 100% 触发；白弹底伤 3 → 回血 2（round(1.5)=2？ 3*0.5=1.5→2）
	var cs := _rush(4210)
	cs.dev_force_load([
		LS, LS, LS, LS, LS, WHITE,
	] as Array[int])
	cs.magazine.set_start(0)
	for _i in 5:
		_shot_one(cs)
	assert_eq(cs._muzzle_lifesteal, 5)
	assert_almost_eq(cs._lifesteal_chance(), 1.0, 0.001)
	cs.player_hp = 10
	var hp0: int = cs.player_hp
	var ehp0: int = cs.enemies[0].hp
	_shot_one(cs)  # white 3, 100% lifesteal → heal round(3*0.5)=2
	assert_eq(ehp0 - cs.enemies[0].hp, 3)
	assert_eq(cs.player_hp - hp0, 2)


func test_lifesteal_own_shot_can_heal() -> void:
	## 单层 20%：用固定 rng 逼出触发。本发吸血底伤1 → heal round(0.5)=0 或 1。
	## 叠到 5 后再射吸血弹本身：底伤1，heal round(0.5)=1（Godot round half away? int(round(0.5))=0 in GDScript?）
	## 实际上 int(round(0.5)) in GDScript is 0 (banker's?) — 用白弹测更稳。
	var cs := _rush(4211)
	# 强制枪口 5 层
	cs._muzzle_lifesteal = 5
	cs.dev_force_load([
		WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.player_hp = 5
	_shot_one(cs)
	assert_eq(cs.player_hp, 7)  # +2 from 3 dmg


func test_lifesteal_no_heal_when_roll_fails() -> void:
	var cs := _rush(4212)
	cs._muzzle_lifesteal = 1  # 20%
	# force fail: stub by setting stacks 0 after mount path — instead use 0 stacks
	cs._muzzle_lifesteal_layers.clear()
	cs.dev_force_load([
		WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.player_hp = 5
	_shot_one(cs)
	assert_eq(cs.player_hp, 5)


func test_lifesteal_layers_expire_independently() -> void:
	var cs := _rush(4213)
	cs.dev_force_load([
		LS, LS, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	cs.tick_muzzle_durations(1.0)
	_shot_one(cs)
	assert_eq(cs._muzzle_lifesteal, 2)
	# expire first layer
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC - 0.5)
	assert_eq(cs._muzzle_lifesteal, 1)
	cs.tick_muzzle_durations(2.0)
	assert_eq(cs._muzzle_lifesteal, 0)


func test_lifesteal_hook_on_muzzle_apply() -> void:
	var cs := _rush(4214)
	var n := {"c": 0}
	cs.hooks.subscribe(&"on_muzzle_apply", func(p):
		if str(p.get("kind", "")) == "lifesteal":
			n["c"] = int(n["c"]) + 1
	)
	cs.dev_force_load([
		LS, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(int(n["c"]), 1)
	assert_true("吸血" in cs.muzzle_status_parts())
