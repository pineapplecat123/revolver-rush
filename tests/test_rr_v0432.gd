extends GutTest
## v0.4.32：预转不抢播姿势；致死无趴地；图鉴网格+详情。

const WHITE := CombatConstants.WHITE_AMMO_ID
const E := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false


func _ui_sandbox():
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.sandbox_spawn_dummy(99999, 3)
	cs.player_hp = 99999
	ui._wave_bannering = false
	ui._rolling = false
	ui._loading = false
	if ui._dev_open:
		ui._toggle_dev()
	return ui


func test_version_0_4_32() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.32") >= 0)
	assert_true('"version": "0.4.32"' in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_false(RrAa.ENABLED)


func test_prespin_does_not_play_shoot_until_present() -> void:
	## 逻辑 fire_tap 会 emit on_shot，但 suppress 后姿势日志只在出膛帧增加。
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	assert_true(ui._skel_player != null)
	assert_true(ui._skel_player.suppress_shot_from_hook)
	cs.dev_force_load([WHITE, WHITE, WHITE, E, E, E] as Array[int])
	ui.fire_anim_log.clear()
	ui._refresh()
	await wait_process_frames(2)
	# 只跑逻辑结算（模拟预转前）
	var pack: Dictionary = ui._resolve_fire_logic()
	assert_gt(pack.get("shots", []).size(), 0)
	assert_eq(ui.fire_anim_log.size(), 0, "预转前不应记出膛姿势")
	# 出膛呈现才记
	await ui._present_resolved_fire_async(pack)
	assert_gt(ui.fire_anim_log.size(), 0, "出膛后应有姿势")


func test_enemy_play_death_does_not_use_death_anim() -> void:
	var sk: SkeletonEnemy = add_child_autofree(load("res://scenes/enemy/skeleton_enemy.tscn").instantiate())
	sk.setup(1)
	sk.play_death()
	assert_true(sk.is_dead)
	assert_false(sk.visible)
	assert_ne(sk.current_animation(), &"death")


func test_dot_and_explosion_kills_instant_gore_no_lie_pose() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.sandbox_spawn_dummy(3, 3)
	cs.sandbox_spawn_dummy(3, 6)
	ui._refresh()
	await wait_process_frames(2)
	assert_eq(ui._skel_enemies.size(), 2)
	# 灼烧式：直接扣死并走 enemy_damaged（不 defer）
	var e0: EnemyInstance = cs.enemies[0]
	var eid0: int = e0.get_instance_id()
	e0.hp = 0
	cs.last_damaged_enemy = e0
	cs.last_damage_lethal = true
	ui._on_enemy_damaged(e0.cell, 3, "burn")
	assert_false(ui._skel_enemies.has(eid0), "灼烧致死应卸小动物")
	assert_true(ui._visual_dead.has(eid0))
	# 爆炸式：另一只通过 sync shown_hp<=0
	var e1: EnemyInstance = cs.enemies[1] if cs.enemies.size() > 1 else null
	if e1 == null:
		cs.sandbox_spawn_dummy(1, 5)
		e1 = cs.enemies[cs.enemies.size() - 1]
		ui._refresh()
		await wait_process_frames(1)
	var eid1: int = e1.get_instance_id()
	e1.hp = 0
	ui._refresh()
	await wait_process_frames(2)
	assert_false(ui._skel_enemies.has(eid1), "爆炸/同步 0 血应碎块卸除")
	# 场上不应再有播 death 动画的活体小动物
	for sk in ui._skel_enemies.values():
		if sk != null and is_instance_valid(sk):
			assert_ne(sk.current_animation(), &"death")


func test_codex_grid_and_detail() -> void:
	var menu = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_process_frames(2)
	menu._on_codex_pressed()
	await wait_process_frames(2)
	var list: GridContainer = menu.get_node("%CodexList")
	assert_gt(list.columns, 1)
	var cells := 0
	var first_id := -1
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			cells += 1
			if first_id < 0:
				first_id = int(str(c.name).get_slice("_", 1))
	assert_gt(cells, 5)
	menu._on_codex_cell_pressed(first_id)
	await wait_process_frames(1)
	assert_true(menu.get_node("%CodexDetailPanel").visible)
	assert_gt(menu.get_node("%CodexDetailBody").get_child_count(), 0)
	menu._on_codex_detail_close_pressed()
	assert_false(menu.get_node("%CodexDetailPanel").visible)
