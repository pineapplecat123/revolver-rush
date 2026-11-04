extends GutTest
## v0.4.26：红圈=击发仓（按盘面真实角度）、射击中禁止装弹且不软锁、小动物朝向、敌人减速 50%、商店平滑。

const WHITE := CombatConstants.WHITE_AMMO_ID
const WRATH := FireResolver.ID_WRATH
const AMMO_POOL := [1, 16, 22, 24, 26]


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = true


func after_each() -> void:
	CombatState.boot_sandbox = false
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _ui_sandbox():
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	for c in CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS:
		cs.sandbox_spawn_dummy(99999, int(c))
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


func _wait_volley_done(ui, max_sec: float = 8.0) -> void:
	var t := 0.0
	while t < max_sec and (ui._volley_ui_running or ui.state.is_volley_pending() or ui.state.is_dump_pending()):
		await wait_seconds(0.05)
		t += 0.05


func test_version_0_4_26() -> void:
	assert_eq(GameVersion.STRING, "0.4.26")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.26"' in text)


func test_ring_matches_fired_chamber_randomized_volleys() -> void:
	## 多轮随机装填（满/有空/单发）、随机锤位、随机战斗速度；中间夹手装弹和多轮连射。
	## 每发实弹出膛帧：红圈下（按盘面真实旋转角）的仓 == 逻辑击发仓，且红圈下画的就是这发弹。
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	var rng := RandomNumberGenerator.new()
	rng.seed = 42601
	ui.shot_audit.clear()
	for round_i in 10:
		var six: Array[int] = []
		for _k in 6:
			six.append(Magazine.EMPTY if rng.randf() < 0.3 else int(AMMO_POOL[rng.randi_range(0, AMMO_POOL.size() - 1)]))
		if round_i % 4 == 2:
			six = [Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, WHITE, Magazine.EMPTY, Magazine.EMPTY] as Array[int]
		var any := false
		for v in six:
			if v != Magazine.EMPTY:
				any = true
		if not any:
			six[0] = WHITE
		cs.dev_force_load(six)
		cs.magazine.set_start(rng.randi_range(0, 5))
		ui._combat_speed = [1.0, 2.0, 0.75][round_i % 3]
		ui._refresh()
		await wait_process_frames(2)
		ui._on_fire()
		await _wait_volley_done(ui)
		assert_false(ui._volley_ui_running, "第 %d 轮连射结束" % round_i)
		# 连射后手装两发（袋子补弹），再打一轮，覆盖「装弹后」的盘面对齐
		if round_i % 3 == 1:
			cs.dev_add_ammo(WHITE, 4)
			for _l in 2:
				ui._on_manual_load()
				var w := 0
				while (ui._loading or ui._wheel_animating) and w < 100:
					w += 1
					await wait_seconds(0.03)
			if cs.can_fire():
				ui._on_fire()
				await _wait_volley_done(ui)
	ui._combat_speed = 1.0
	assert_gt(ui.shot_audit.size(), 15, "有足够多的实弹样本")
	for a in ui.shot_audit:
		assert_eq(int(a["ring"]), int(a["fired"]), "红圈仓 == 击发仓 %s" % str(a))
		assert_eq(int(a["shown"]), int(a["ammo"]), "红圈下显示的弹 == 打出的弹 %s" % str(a))
		assert_eq(int(a["flash"]), int(a["fired"]), "黄闪的仓 == 击发仓")


func test_load_ignored_and_button_disabled_while_shooting() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.dev_add_ammo(WHITE, 10)
	for delay in [0.0, 0.05, 0.3, 0.5, 0.75, 0.9]:
		cs.dev_force_load([WHITE, WHITE, Magazine.EMPTY, WHITE, WHITE, Magazine.EMPTY] as Array[int])
		cs.magazine.set_start(0)
		ui._refresh()
		await wait_process_frames(2)
		ui._on_fire()
		if delay > 0.0:
			await wait_seconds(delay)
		if ui.is_shooting():
			ui._refresh()
			assert_true(ui.btn_manual_load.disabled, "射击中装弹键灰掉 delay=%.2f" % delay)
			var loaded_before: int = cs.magazine.loaded_count()
			ui._on_manual_load()
			assert_false(cs.is_busy_loading(), "射击中按装弹被忽略")
			assert_eq(cs.magazine.loaded_count(), loaded_before)
		await _wait_volley_done(ui)
		await wait_seconds(0.4)
		assert_false(ui._volley_ui_running, "不软锁 delay=%.2f" % delay)
		assert_false(cs.is_volley_pending())
		assert_false(ui._wheel_animating, "转盘动画已收束")
		# 恢复：能装、能再打
		ui._refresh()
		assert_false(ui.btn_manual_load.disabled, "打完后装弹键恢复")
		ui._on_manual_load()
		var w := 0
		while (ui._loading or ui._wheel_animating) and w < 100:
			w += 1
			await wait_seconds(0.03)
		assert_gt(cs.magazine.loaded_count(), 0, "打完能装弹")


func test_killed_disk_tween_does_not_hang() -> void:
	## 旧软锁根因：_animate_disk_to await tween.finished，被 kill 的 Tween 永不发 finished。
	var ui = await _ui_sandbox()
	var done := [false]
	var runner := func() -> void:
		await ui._animate_disk_to(ui._wheel_visual_steps + 3.0, 1.0)
		done[0] = true
	runner.call()
	await wait_seconds(0.1)
	ui._disk_tween.kill()
	await wait_process_frames(3)
	assert_true(done[0], "被 kill 后 await 链照样结束")
	assert_false(ui._wheel_animating)


func test_dump_and_shop_during_volley_recover() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	# 倾泻弹在中间
	cs.dev_force_load([WHITE, FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE] as Array[int])
	cs.magazine.set_start(0)
	ui._refresh()
	await wait_process_frames(2)
	ui._on_fire()
	await wait_seconds(0.2)
	ui._on_manual_load()
	await _wait_volley_done(ui)
	await wait_seconds(0.3)
	assert_false(ui._volley_ui_running)
	assert_false(cs.is_dump_pending())
	assert_eq(cs.magazine.loaded_count(), 0)
	# 连射途中打开商店（暂停整棵树）再离开
	cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
	cs.magazine.set_start(0)
	ui._refresh()
	await wait_process_frames(2)
	ui._on_fire()
	await wait_seconds(0.5)
	ui._open_rush_shop()
	assert_true(get_tree().paused)
	# 暂停期间 GUT 的计时器也停，只能等 SceneTree 帧信号
	for _f in 20:
		await get_tree().process_frame
	ui._on_rush_shop_leave()
	assert_false(get_tree().paused)
	await _wait_volley_done(ui)
	await wait_seconds(0.3)
	assert_false(ui._volley_ui_running, "商店开关后连射照样结束")
	assert_eq(cs.magazine.loaded_count(), 0)


func test_enemy_speed_halved() -> void:
	assert_almost_eq(CombatConstants.ENEMY_AUTO_STEP_SEC, 3.3, 0.0001)
	assert_almost_eq(1.0 / CombatConstants.ENEMY_AUTO_STEP_SEC, 0.5 / 1.65, 0.0001)
	assert_almost_eq(CombatConstants.MAP_SHOP_STEP_SEC, 1.65, 0.0001, "商店不跟着减速")


func test_skeleton_enemy_faces_left_and_keeps_scale() -> void:
	var expect := {1: 1.0, 2: 1.0, 3: 1.25, 4: 1.0, 5: 1.55, 900: 1.05}
	for def_id in expect.keys():
		var sk: SkeletonEnemy = add_child_autofree((load("res://scenes/enemy/skeleton_enemy.tscn") as PackedScene).instantiate())
		sk.setup(int(def_id))
		assert_almost_eq(sk.scale.x, float(expect[def_id]), 0.001, "根缩放不变 %d" % def_id)
		assert_almost_eq(sk.scale.y, float(expect[def_id]), 0.001)
		assert_eq(sk.facing, -1, "默认面朝左（玩家/行进方向）%d" % def_id)
		assert_lt(sk.rig.scale.x, 0.0, "画法原生朝右 → 朝左要翻 Rig")
		if def_id != 900:
			sk.set_facing(1)
			assert_gt(sk.rig.scale.x, 0.0)
			sk.play_attack()
			assert_eq(sk.facing, -1, "攻击时面向玩家")
		assert_almost_eq(sk.scale.x, float(expect[def_id]), 0.001, "翻面后根缩放仍不变")


func test_ui_enemy_faces_walk_direction_and_walk_rate() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.auto_enemy_advance = true
	assert_true(cs.sandbox_spawn_enemy(1, 7))
	ui._refresh()
	await wait_seconds(0.6)
	var e: EnemyInstance = cs.enemies[0]
	var sk: SkeletonEnemy = ui._skel_enemies.get(e.get_instance_id())
	assert_not_null(sk)
	assert_eq(sk.facing, -1, "向左走 → 面朝左")
	assert_lt(sk.rig.scale.x, 0.0)
	assert_almost_eq(sk._walk_rate, 0.5, 0.01, "走路动画 ×0.5 跟减速同步")


func test_map_shop_overlay_position_is_idempotent() -> void:
	## 旧版商店借格子 UnitBody，任意 _refresh_board 会把它弹回格心 → 网页上一顿一顿。
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.map_shop_disabled = false
	cs.auto_enemy_advance = true
	cs.shop_cell = 6
	cs.shop_spawn_count = 1
	cs.tick_map_shop(0.7)
	var frac: float = cs.shop_glide_fraction()
	assert_gt(frac, 0.1)
	ui._position_map_shop()
	var x1: float = ui._shop_overlay.global_position.x
	ui._refresh()
	ui._refresh_hud_only()
	var x2: float = ui._shop_overlay.global_position.x
	assert_almost_eq(x2, x1, 0.01, "刷新棋盘不把商店弹回格心")
	assert_almost_eq(x1, ui.map_shop_global_x(), 0.01)
	# 跨格连续
	var prev: float = ui.map_shop_global_x()
	for _i in 120:
		cs.tick_map_shop(1.0 / 60.0)
		if cs.shop_cell < 0:
			break
		var x: float = ui.map_shop_global_x()
		assert_true(x <= prev + 0.01, "不后退")
		assert_true(prev - x < 3.0, "单帧不跳")
		prev = x
