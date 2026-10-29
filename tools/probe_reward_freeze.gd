extends SceneTree
## 探针：真实场景里升级三选一开/关前后，敌人/转轮/袋/计时是否被刷新。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/probe_reward_freeze.gd

func _initialize() -> void:
	call_deferred("_run")


func _snap(scene) -> Dictionary:
	var cs = scene.state
	var es: Array = []
	for e in cs.enemies:
		var slot: Control = scene.board_row.get_child(e.cell)
		var unit: Control = slot.get_node_or_null("UnitBody")
		es.append([e.def_id, e.cell, e.hp, e.status_text(), snappedf(cs.enemy_glide_fraction(e), 0.0001), snappedf(unit.position.x, 0.01) if unit else -1.0])
	return {
		"enemies": es,
		"step": snappedf(cs.enemy_step_progress, 0.0001),
		"elapsed": snappedf(cs.elapsed_sec, 0.0001),
		"spawn_t": snappedf(cs._spawn_timer, 0.0001),
		"bag": cs.bag.duplicate(),
		"bag_temp": cs.bag_temp.duplicate(),
		"mag": cs.magazine.slots.duplicate(),
		"mag_temp": cs.magazine.temp_slots.duplicate(),
		"wrath": cs._muzzle_wrath_layers.duplicate(),
		"hp": cs.player_hp,
		"phase": cs.phase,
		"disk_rot": snappedf(scene._disk.rotation, 0.0001) if scene._disk else 0.0,
		"in_flight": scene._in_flight_shots,
		"frozen": scene.is_combat_frozen(),
	}


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a.keys():
		if str(a[k]) != str(b[k]):
			out.append("%s: %s -> %s" % [k, str(a[k]), str(b[k])])
	return out


func _run() -> void:
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	for _i in 10:
		await process_frame
	var cs = scene.state
	for e in cs.enemies:
		e.hp = 500
		e.max_hp = 500
		e.atk = 0
	cs._bag_append(FireResolver.ID_WRATH, 18.0)
	# 装 2 发
	for _k in 2:
		scene._on_manual_load()
		for _i in 90:
			await process_frame
			if not scene._busy():
				break
	await create_timer(0.7).timeout  # 让怪滑到半格
	var target = cs.enemies[0]
	for e in cs.enemies:
		if e.cell < target.cell:
			target = e
	target.hp = 1
	target.max_hp = 1
	cs.xp = cs.xp_needed() - 1
	var before: Dictionary = _snap(scene)
	print("[probe] BEFORE ", before)
	scene._on_fire()
	await process_frame
	await create_timer(0.08).timeout
	var s0b: Dictionary = _snap(scene)
	print("[probe] open-now=", scene._reward_open, " in_flight=", s0b["in_flight"])
	var s0: Dictionary = _snap(scene)
	print("[probe] after-fire reward_pending=", cs.reward_pending, " diff:", _diff(before, s0))
	await create_timer(1.5).timeout
	var s1: Dictionary = _snap(scene)
	print("[probe] open=", scene._reward_open, " diff(s0b->s1 while open 1.5s):", _diff(s0b, s1))
	scene._on_reward_pick(0)
	var s2: Dictionary = _snap(scene)
	print("[probe] after-pick diff(s1->s2):", _diff(s1, s2))
	await process_frame
	await process_frame
	var s3: Dictionary = _snap(scene)
	print("[probe] 2 frames later diff(s2->s3):", _diff(s2, s3))
	quit(0)
