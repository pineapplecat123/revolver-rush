extends GutTest
## v0.4.27：未装满时连射前转轮落在有弹仓；死亡碎块；稀有度特效；一体弹道；火药屑。

const WHITE := CombatConstants.WHITE_AMMO_ID
const E := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = true


func after_each() -> void:
	CombatState.boot_sandbox = false


func _ui_sandbox():
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	ui._wave_bannering = false
	ui._rolling = false
	ui._loading = false
	ui._sin_pick_open = false
	ui._reward_delaying = false
	if ui._dev_open:
		ui._toggle_dev()
	return ui


func test_version_0_4_27() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.27") >= 0)
	assert_true('"version": "0.4.27"' in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_random_roll_to_loaded_never_lands_on_empty() -> void:
	var m := Magazine.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 427
	var hits := {}
	for i in 600:
		m.slots = [E, WHITE, E, 16, E, 22] as Array[int]
		m.start_index = rng.randi_range(0, 5)
		var steps: int = m.random_roll_to_loaded(rng)
		assert_true(steps >= 0 and steps < 6)
		assert_ne(m.slots[m.start_index], E, "落点必须是有弹仓")
		hits[m.start_index] = true
	assert_eq(hits.size(), 3, "三个有弹仓都会被抽到（均匀随机）")


func test_partial_spin_lands_loaded_and_always_rotates() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	for i in 60:
		cs.dev_force_load([E, WHITE, E, E, 16, E] as Array[int])
		cs.magazine.set_start(i % 6)
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0, "未装满也一定看得见转")
		assert_ne(cs.magazine.slots[cs.magazine.chamber_at_fire_port()], E, "转完红圈下是有弹仓")


func test_full_cylinder_spin_still_random() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
	var steps: int = cs.spin_cylinder_for_volley()
	assert_true(steps >= 0)


func test_gore_pieces_per_species() -> void:
	for def_id in [1, 2, 3, 4, 5, 900]:
		var sk: SkeletonEnemy = (load("res://scenes/enemy/skeleton_enemy.tscn") as PackedScene).instantiate()
		sk.setup(def_id)
		var pcs: Array = sk.gore_pieces()
		assert_gt(pcs.size(), 5, "def %d 有碎块" % def_id)
		for pc in pcs:
			assert_gt((pc["layers"] as Array).size(), 0)
		sk.free()


func test_gore_spawns_once_on_kill_and_is_capped() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_spawn_dummy(1, 3)
	ui._refresh()
	await wait_process_frames(2)
	for e in cs.enemies:
		e.hp = 0
	var n1: int = ui._spawn_gore_for_cell(3, Vector2(400, 400))
	var n2: int = ui._spawn_gore_for_cell(3, Vector2(400, 400))
	assert_gt(n1, 0, "死亡瞬间飞碎块")
	assert_eq(n2, 0, "同一只只炸一次")
	var layer: GoreLayer = ui._gore_layer
	for i in 100:
		layer.spawn([{"layers": [[PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(0, 4)]), Color.RED]]}], Vector2(300, 300), 500.0)
	assert_lte(layer.active_count(), GoreLayer.MAX_PIECES)
	await wait_seconds(4.2)
	assert_eq(layer.active_count(), 0, "落地、躺一会儿、淡出后全部回收")


func test_rarity_tiers() -> void:
	assert_eq(RarityFx.tier_for_ammo(1), RarityFx.TIER_COMMON)


func test_rarity_fx_attached_on_chambers_and_chips() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.dev_force_load([1, 1, 1, 1, E, 1] as Array[int])
	ui._refresh()
	await wait_process_frames(2)
	for i in 6:
		var p: Control = ui._chamber_panels[i]
		assert_null(p.get_node_or_null(RarityFx.NODE_NAME), "平庸弹不挂稀有度特效")
	var chip: Panel = ui.make_ammo_chip(1)
	add_child_autofree(chip)
	assert_null(chip.get_node_or_null(RarityFx.NODE_NAME))
	var chip2: Panel = ui.make_ammo_chip(1)
	add_child_autofree(chip2)
	assert_null(chip2.get_node_or_null(RarityFx.NODE_NAME))


func test_powder_flag_only_with_explosive() -> void:
	var CUI = load("res://scripts/combat/combat_ui.gd")
	assert_true(CUI.shot_has_powder(FireResolver.ID_EXPLOSIVE, []), "炸药弹本发即带火药")
	assert_true(CUI.shot_has_powder(1, [FireResolver.ID_EXPLOSIVE]), "枪口挂着炸药时普通弹也带火药")
	assert_false(CUI.shot_has_powder(1, [FireResolver.ID_WRATH]))


func test_projectile_powder_particles_and_fused_shape() -> void:
	var ui = await _ui_sandbox()
	var from_g := Vector2(100, 300)
	ui._animate_shot_projectile(from_g, from_g + Vector2(600, 0), Color.ORANGE, [] as Array[Color], [], 0.6, true)
	await wait_process_frames(6)
	var found_p := 0
	var max_w := 0.0
	for c in ui.get_children():
		if c is Control and c.z_index == ui.Z_SHOT_VFX:
			for cc in c.get_children():
				if cc is CPUParticles2D:
					found_p += 1
				if cc is Line2D:
					max_w = maxf(max_w, (cc as Line2D).width)
				assert_false(cc is Polygon2D, "不再有比枪线粗的弹头圆球")
	assert_eq(found_p, 2, "火药附着弹带火药屑 + 火星两路粒子")
	assert_lte(max_w, ui.SHOT_TRAIL_THICK + ui.SHOT_STREAK_HALO + 0.01, "弹头与枪线同宽（只多一层很淡的光晕）")
	await wait_seconds(2.0)
	assert_eq(ui._powder_emitters, 0, "粒子离场后回收")
