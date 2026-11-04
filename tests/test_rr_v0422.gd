extends GutTest
## v0.4.22：炸药爆炸特效加大。只测画面节点，不改伤害和射速。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_0_4_22() -> void:
	assert_eq(GameVersion.STRING, "0.4.22")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.22"' in text)
	assert_almost_eq(CombatConstants.MAX_FIRE_RATE_HZ, 10.0, 0.001)
	assert_almost_eq(CombatConstants.MIN_FIRE_INTERVAL_SEC, 0.1, 0.001)


func test_explosion_vfx_spawns_above_labels_and_frees_itself() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	ui._spawn_explosion_vfx(5, 1)
	ui._spawn_explosion_vfx(3, 2)
	var bursts: Array = []
	for n in ui.get_children():
		if str(n.name).begins_with("ExplosionVfx"):
			bursts.append(n)
	assert_gte(bursts.size(), 2)
	var vfx: Node = bursts[0]
	assert_gt(vfx.z_index, ui.Z_DMG_FLOAT, "爆炸要盖过伤害飘字")
	assert_gt(int(vfx.get("particle_count")), 40, "火星要够多")
	var sparks_a: Array = vfx.get("_sparks")
	var sparks_b: Array = bursts[1].get("_sparks")
	var vel_a: Vector2 = sparks_a[0]["v"]
	var vel_b: Vector2 = sparks_b[0]["v"]
	assert_false(vel_a.is_equal_approx(vel_b), "连着两下爆炸不该长得一样")
	for burst in bursts:
		(burst as Node).set_process(false)
		for _i in 16:
			burst._process(0.1)
	await get_tree().process_frame
	for burst in bursts:
		assert_false(is_instance_valid(burst), "播完要自己删掉")
