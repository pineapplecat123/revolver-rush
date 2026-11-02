extends GutTest
## v0.4.13 暴食：击杀回血（非吸血窗）；三罪持续自 DoT。

const GLUT := FireResolver.ID_GLUTTONY
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41301) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, GLUT)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 5
		e.max_hp = 5
		e.atk = 0
	cs.player_hp = 10
	cs.player_max_hp = 20
	cs.pace_after_fire = false
	return cs


func test_gluttony_def_not_lifesteal() -> void:
	var def: Dictionary = DataRegistry.get_ammo(GLUT)
	assert_eq(str(def.get("name", "")), "暴食弹药")
	assert_true(DataRegistry.is_sin_ammo(GLUT))
	assert_true(bool(FireResolver.inherits_from(GLUT).get("gluttony", false)))
	assert_false(bool(FireResolver.inherits_from(GLUT).get("lifesteal", false)))
	assert_true("击杀" in str(def.get("special", "")) or "回血" in str(def.get("blurb", "")))


func test_gluttony_heal_on_kill() -> void:
	var cs := _rush(41310)
	cs._muzzle_gluttony = 2
	cs._gluttony_heal_budget = 2.0
	var hp0: int = cs.player_hp
	cs.enemies[0].hp = 0
	cs._remove_dead()
	assert_eq(cs.player_hp, hp0 + 1)


func test_gluttony_three_sin_self_dot() -> void:
	var cs := _rush(41311)
	cs._resolve_sin_pack_on_load([GLUT, GLUT, GLUT])
	assert_gt(cs.gluttony_self_dot_remaining, 0.0)
	var hp0: int = cs.player_hp
	cs._dot_timer = 0.0
	cs.tick_dot(CombatConstants.DOT_TICK_SEC)
	assert_lt(cs.player_hp, hp0)
