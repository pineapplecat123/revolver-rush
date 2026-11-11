extends GutTest
## v0.4.28：命中才掉血（画面）；罪孽危险特效；视野外刷怪走进来/个体速度/可重叠；删连发与倾泻；火药加亮；肢体飞更远+血迹。

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


func test_version_0_4_28() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.28") >= 0)
	assert_true('"version": "0.4.28"' in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_burst_and_dump_deleted() -> void:
	assert_true(DataRegistry.get_ammo(21).is_empty(), "连发已删")
	assert_true(DataRegistry.get_ammo(23).is_empty(), "倾泻已删")
	for a in DataRegistry.all_ammo():
		assert_false(str(a.get("name", "")) in ["连发子弹", "倾泻"])
	var cs_src := FileAccess.get_file_as_string("res://scripts/combat/combat_state.gd")
	assert_false("burst_window_remaining" in cs_src)
	assert_false("take_dump_shot" in cs_src)
	assert_false("ID_BURST" in FileAccess.get_file_as_string("res://scripts/combat/fire_resolver.gd"))
	var shop := ShopState.new()
	shop.begin(999, [], 1, 4281)
	for i in 30:
		shop._roll_stock()
		for aid in shop.stock:
			assert_false(int(aid) in [21, 23])


func test_hp_shown_only_when_bullet_lands() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_spawn_dummy(50, 7)
	ui._refresh()
	await wait_process_frames(2)
	var e: EnemyInstance = cs.enemies[0]
	cs.dev_force_load([WHITE, E, E, E, E, E] as Array[int])
	cs.magazine.set_start(0)
	ui._refresh()
	ui._combat_speed = 0.5
	ui._on_fire()
	await wait_process_frames(1)
	assert_eq(e.hp, 50, "按下射击不扣血，等子弹打到")
	assert_eq(ui.display_hp(e), 50)
	var t := 0.0
	while t < 8.0 and (ui._volley_ui_running or ui._in_flight_shots > 0 or cs.pending_impact_count() > 0):
		await wait_seconds(0.05)
		t += 0.05
	assert_lt(e.hp, 50, "子弹打到才扣血")
	assert_eq(ui.display_hp(e), e.hp)
	assert_false(ui.has_hp_hold())


func test_free_walk_spawns_offscreen_and_walks_in() -> void:
	var cs := CombatState.new(4282)
	cs.free_walk = true
	cs.start_rush(4282, FireResolver.ID_WRATH)
	assert_gt(cs.enemies.size(), 0)
	var muls := {}
	for e in cs.enemies:
		assert_gt(e.pos_x, float(CombatConstants.BOARD_SIZE - 1) + 0.5, "刷在视野外")
		assert_true(cs.is_entering(e))
		assert_true(e.speed_mul >= 0.86 and e.speed_mul <= 1.14)
		muls[snappedf(e.speed_mul, 0.001)] = true
	assert_eq(cs.enemies_sorted_by_cell().size(), 0, "没走进来之前打不到")
	for i in 120:
		cs.advance_enemy_glide(0.05)
	for e in cs.alive_enemies():
		assert_false(cs.is_entering(e), "走进来了")
	assert_gt(cs.enemies_sorted_by_cell().size(), 0)


func test_free_walk_speed_variation_and_overlap() -> void:
	var cs := CombatState.new(4283)
	cs.free_walk = true
	cs.start_rush(4283, FireResolver.ID_WRATH)
	cs.spawn_paused = true
	cs.enemies.clear()
	for k in 3:
		var e := EnemyInstance.new(DataRegistry.get_enemy(1), 8)
		e.pos_x = 8.0
		e.speed_mul = [0.88, 1.0, 1.12][k]
		e.atk = 0
		e.hp = 999
		e.max_hp = 999
		cs.enemies.append(e)
	cs.advance_enemy_glide(1.0)
	var xs: Array = []
	for e in cs.enemies:
		xs.append(e.pos_x)
	assert_true(xs[0] > xs[1] and xs[1] > xs[2], "速度有差别")
	for i in 400:
		cs.advance_enemy_glide(0.05)
	for e in cs.enemies:
		assert_eq(e.cell, CombatConstants.PLAYER_CELL + 1, "不互相阻挡，都走到玩家面前（重叠）")
	assert_eq(cs.occupied_cells().size(), 1)
	assert_true(cs.can_attack_player(cs.enemies[2]))


func test_logic_mode_still_one_per_cell() -> void:
	var cs := CombatState.new(4284)
	cs.start_rush(4284, FireResolver.ID_WRATH)
	assert_false(cs.free_walk)
	var cells := {}
	for e in cs.enemies:
		assert_false(cells.has(e.cell))
		cells[e.cell] = true


func test_powder_brighter_two_layers() -> void:
	assert_gte(load("res://scripts/combat/combat_ui.gd").POWDER_PARTICLES, 50)


func test_gore_flies_farther_and_leaves_trail() -> void:
	var layer := GoreLayer.new()
	add_child_autofree(layer)
	var sk: SkeletonEnemy = (load("res://scenes/enemy/skeleton_enemy.tscn") as PackedScene).instantiate()
	sk.setup(1)
	var pcs: Array = sk.gore_pieces()
	sk.free()
	layer.spawn(pcs, Vector2(360, 300), 360.0)
	var min_y := 9999.0
	for i in 20:
		await wait_process_frames(1)
		for c in layer.get_children():
			if c is Node2D:
				min_y = minf(min_y, (c as Node2D).global_position.y)
	assert_lt(min_y, 300.0 - 60.0, "飞得够高")
	assert_gt(layer.trail_count(), 0, "空中拖血迹")
	assert_lte(layer.trail_count(), GoreLayer.TRAIL_MAX)
	await wait_seconds(4.5)
	assert_eq(layer.active_count(), 0)
	assert_eq(layer.trail_count(), 0)
