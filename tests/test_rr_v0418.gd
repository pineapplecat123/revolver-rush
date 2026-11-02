extends GutTest
## v0.4.18 正确性：穿甲钩子 emit、暴食首跳预算、战斗秒掉枪口、沙盒 kind=flame。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _fresh(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH)
	cs.dev_clear_bag()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.sandbox_clear_enemies()
	cs.sandbox_clear_muzzle()
	cs.player_hp = CombatConstants.PLAYER_MAX_HP
	cs.auto_enemy_advance = false
	return cs


func _force_one(cs: CombatState, ammo_id: int) -> void:
	cs.dev_force_load([
		ammo_id,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func test_version_is_0_4_18() -> void:
	assert_eq(GameVersion.STRING, "0.4.18")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.18"' in text or '"version":"0.4.18"' in text)


func test_pierce_mount_emits_on_muzzle_apply() -> void:
	var cs := _fresh(41801)
	var kinds: Array = []
	cs.hooks.subscribe(&"on_muzzle_apply", func(p: Dictionary) -> void:
		kinds.append(str(p.get("kind", "")))
	)
	cs.sandbox_spawn_dummy(50, 3)
	_force_one(cs, FireResolver.ID_ARMOR_PIERCE)
	_shot_one(cs)
	assert_true("pierce" in kinds, "expected on_muzzle_apply(pierce), got %s" % str(kinds))
	assert_true(cs._muzzle_pierce)


func test_element_muzzles_emit_on_mount_path() -> void:
	var cs := _fresh(41802)
	var kinds: Dictionary = {}
	cs.hooks.subscribe(&"on_muzzle_apply", func(p: Dictionary) -> void:
		kinds[str(p.get("kind", ""))] = true
	)
	cs._mount_muzzle_from({"pierce": true, "gas": true, "water": true, "thunder": true})
	for k in ["pierce", "gas", "water", "thunder"]:
		assert_true(kinds.get(k, false), "missing on_muzzle_apply(%s)" % k)


func test_gluttony_heal_immediately_after_sandbox_set_muzzle() -> void:
	var cs := _fresh(41803)
	cs.player_hp = 10
	cs.sandbox_spawn_dummy(2, 3)
	assert_true(cs.sandbox_set_muzzle("gluttony", 3, 4.0))
	assert_gte(cs._gluttony_heal_budget, 1.0)
	# No prior tick_combat_time — white shot should kill and heal
	_force_one(cs, CombatConstants.WHITE_AMMO_ID)
	_shot_one(cs)
	assert_gte(cs.player_hp, 11, "gluttony heal should fire without pre-tick")


func test_gluttony_heal_immediately_after_ammo_mount() -> void:
	var cs := _fresh(41804)
	cs.player_hp = 10
	cs.sandbox_spawn_dummy(50, 3)
	_force_one(cs, FireResolver.ID_GLUTTONY)
	_shot_one(cs)
	assert_true(cs._muzzle_gluttony >= 1)
	assert_gte(cs._gluttony_heal_budget, 1.0)
	# Kill with white while gluttony mounted; budget already seeded from mount
	cs.sandbox_clear_enemies()
	cs.sandbox_spawn_dummy(2, 3)
	var hp0: int = cs.player_hp
	_force_one(cs, CombatConstants.WHITE_AMMO_ID)
	_shot_one(cs)
	assert_eq(cs.player_hp, hp0 + 1)


func test_tick_combat_time_decays_muzzle() -> void:
	var cs := _fresh(41805)
	assert_true(cs.sandbox_set_muzzle("echo", 1, 1.0))
	assert_true(cs._muzzle_echo)
	cs.tick_combat_time(1.1)
	assert_false(cs._muzzle_echo, "tick_combat_time should decay muzzle layers")


func test_sandbox_flame_kind_not_fire() -> void:
	var cs := _fresh(41806)
	var kinds: Array = []
	cs.hooks.subscribe(&"on_muzzle_apply", func(p: Dictionary) -> void:
		kinds.append(str(p.get("kind", "")))
	)
	assert_true(cs.sandbox_set_muzzle("flame", 1, 3.0))
	assert_true(cs._muzzle_fire)
	assert_eq(kinds, ["flame"])
	# legacy alias fire → flame
	kinds.clear()
	assert_true(cs.sandbox_set_muzzle("fire", 1, 3.0))
	assert_eq(kinds, ["flame"])
	assert_true("flame" in CombatState.sandbox_muzzle_kinds())
	assert_false("fire" in CombatState.sandbox_muzzle_kinds())
