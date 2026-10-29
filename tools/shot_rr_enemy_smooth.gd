extends SceneTree
## v0.3.3：敌人连续滑行 + 随时装/射压测（不覆盖已有弹）+ 截图。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_enemy_smooth.gd

const OUT_DIR := "res://docs/shots"
const OUT_ABS := "/workspace/rr_enemy_smooth.png"

var _issues: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _unit_x(scene, cell: int) -> float:
	var slot: Control = scene.board_row.get_child(cell) as Control
	var unit: Control = slot.get_node("UnitBody") as Control
	return unit.global_position.x


func _front(scene):
	var arr: Array = scene.state.enemies_sorted_by_cell()
	return arr[0] if not arr.is_empty() else null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	# 等波次大字结束
	var guard := 0
	while scene._wave_bannering and guard < 400:
		await process_frame
		guard += 1
	for e in scene.state.enemies:
		e.hp = 400
		e.max_hp = 400
		e.atk = 0
	var front = _front(scene)
	front.cell = 8
	scene.state.reset_enemy_glide()
	scene._refresh()
	# 1) 连续性：逐帧记录最前怪单位块的全局 x（换算连续格位）
	var max_jump := 0.0
	var last_x := -1.0
	var x0 := -1.0
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
		frames += 1
		var e = front
		if e == null or not e.is_alive():
			break
		var x: float = _unit_x(scene, e.cell)
		if x0 < 0.0:
			x0 = x
		if last_x >= 0.0:
			max_jump = maxf(max_jump, absf(x - last_x))
			if x > last_x + 0.5:
				_issues.append("enemy moved right %.2f -> %.2f" % [last_x, x])
		last_x = x
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var px_per_sec := (x0 - last_x) / secs
	print("GLIDE frames=%d secs=%.2f moved_px=%.1f px/s=%.1f (expect ~%.1f) max_frame_jump=%.2fpx" % [
		frames, secs, x0 - last_x, px_per_sec, 68.0 / float(load("res://scripts/combat/combat_constants.gd").ENEMY_AUTO_STEP_SEC), max_jump
	])
	if max_jump > 12.0:
		_issues.append("frame jump too big: %.2f" % max_jump)
	# 2) 截图：滑行到半格位置时
	var img: Image = await _snap_mid_glide(scene)
	img.save_png(OUT_ABS)
	img.save_png(ProjectSettings.globalize_path("%s/rr_enemy_smooth.png" % OUT_DIR))
	print("SHOT %s" % OUT_ABS)
	# 3) 随机狂点 装弹/射击 8 秒：每次手装后已有弹不得被改
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var loads := 0
	var fires := 0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 8000:
		if scene.state.phase_name() == "胜利" or scene.state.phase_name() == "失败":
			break
		if rng.randf() < 0.55:
			if not scene._busy() and scene.state.can_manual_load():
				var before: Array = scene.state.magazine.slots.duplicate()
				var cnt: int = scene.state.magazine.loaded_count()
				await scene._run_manual_load_one()
				loads += 1
				var after: Array = scene.state.magazine.slots.duplicate()
				for i in before.size():
					if int(before[i]) != -1 and int(after[i]) != int(before[i]) and not scene._firing:
						_issues.append("overwrite slot %d %d->%d" % [i, before[i], after[i]])
				if scene.state.magazine.loaded_count() > cnt + 1:
					_issues.append("loaded >1 per press")
		else:
			if not scene._busy() and scene.state.can_fire():
				scene._on_fire()
				fires += 1
		# 一些帧里让敌人走
		for _f in rng.randi_range(0, 6):
			await process_frame
		# 抖动/滑行后单位不得离地或飞出棋盘
		for e in scene.state.alive_enemies():
			var slot: Control = scene.board_row.get_child(e.cell) as Control
			var unit: Control = slot.get_node("UnitBody") as Control
			if absf(unit.position.x - scene._unit_rest_position_for_cell(e.cell).x) > 60.0:
				_issues.append("unit off its glide position cell %d" % e.cell)
	await create_timer(1.5).timeout
	print("STRESS loads=%d fires=%d phase=%s mag=%s" % [loads, fires, scene.state.phase_name(), scene.state.magazine.slots])
	print("ISSUES %d %s" % [_issues.size(), str(_issues.slice(0, 8))])
	quit(0)


func _snap_mid_glide(scene) -> Image:
	var guard := 0
	while guard < 600:
		await process_frame
		guard += 1
		var p: float = scene.state.enemy_step_progress
		if p > 0.45 and p < 0.6:
			break
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	print("SNAP progress=%.2f" % scene.state.enemy_step_progress)
	return img
