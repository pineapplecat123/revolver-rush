extends GutTest
## v0.3.9：升级三选一 = 纯暂停遮罩。开/关前后敌人（id/格/滑行/HP/状态）、转轮、袋、计时全部不变，
## 只多出所选奖励；清场补刷推迟到选完；多级排队同样。

const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3901) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	for e in cs.enemies:
		e.hp = 500
		e.max_hp = 500
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


static func snap_state(cs) -> Dictionary:
	var es: Array = []
	for e in cs.enemies:
		es.append([e.get_instance_id(), e.def_id, e.cell, e.hp, e.max_hp, e.bleed_stacks, e.gas_stacks, e.burn_stacks, e.wet_stacks, e.status_text(), snappedf(cs.enemy_glide_fraction(e), 0.000001)])
	return {
		"enemies": es,
		"step": snappedf(cs.enemy_step_progress, 0.000001),
		"elapsed": snappedf(cs.elapsed_sec, 0.000001),
		"spawn_t": snappedf(cs._spawn_timer, 0.000001),
		"boss": cs._boss_spawned,
		"bag": str(cs.bag),
		"bag_temp": str(cs.bag_temp),
		"discard": str(cs.discard),
		"discard_temp": str(cs.discard_temp),
		"mag": str(cs.magazine.slots),
		"mag_temp": str(cs.magazine.temp_slots),
		"mag_start": cs.magazine.start_index,
		"muzzle": str([cs._muzzle_wrath_layers, cs._muzzle_pride_layers, cs._muzzle_greed_layers, cs._muzzle_fire_layers, cs._muzzle_pierce_layers]),
		"hp": cs.player_hp,
		"gold": cs.gold,
		"phase": cs.phase,
	}


static func diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a.keys():
		if str(a[k]) != str(b[k]):
			out.append("%s: %s -> %s" % [k, str(a[k]), str(b[k])])
	return out


func _prep_mid_slide(cs: CombatState) -> void:
	cs.advance_enemy_glide(0.6)
	cs._bag_append(W, 11.0)
	cs.magazine.set_slot(3, W, 7.0)
	cs._muzzle_wrath_layers = [1.5, 3.0]
	cs.enemies[0].bleed_stacks = 2
	cs.enemies[0].burn_stacks = 1


func _simulate_frames_while_open(cs: CombatState, sec: float) -> void:
	## 与 UI _process 同顺序调用；即便 UI 门控漏了，状态层也不得前进。
	var n := int(sec / 0.016)
	for _i in n:
		cs.tick_muzzle_durations(0.016)
		cs.tick_combat_time(0.016)
		cs.advance_enemy_glide(0.016)


func test_levelup_pick_changes_only_reward() -> void:
	var cs := _rush()
	_prep_mid_slide(cs)
	cs.gain_xp(cs.xp_needed())
	assert_true(cs.reward_pending)
	var before := snap_state(cs)
	_simulate_frames_while_open(cs, 2.0)
	assert_eq(diff(before, snap_state(cs)), [], "三选一打开期间一切冻结")
	var choice: int = cs.reward_choices[0]
	assert_true(cs.pick_reward_ammo(0))
	var after := snap_state(cs)
	var d := diff(before, after)
	assert_eq(d.size(), 2, "只多所选奖励：%s" % str(d))
	assert_eq(int(cs.bag.back()), choice)
	assert_eq(float(cs.bag_temp.back()), 0.0)
	# 恢复后接着走（从原处继续，不复位）
	var step0: float = cs.enemy_step_progress
	cs.advance_enemy_glide(0.1)
	assert_almost_eq(cs.enemy_step_progress, step0 + 0.1, 0.0001)


func test_skip_changes_only_gold() -> void:
	var cs := _rush()
	_prep_mid_slide(cs)
	cs.gain_xp(cs.xp_needed())
	var before := snap_state(cs)
	_simulate_frames_while_open(cs, 1.0)
	assert_true(cs.skip_reward_for_gold())
	var d := diff(before, snap_state(cs))
	assert_eq(d.size(), 1, str(d))
	assert_eq(cs.gold, int(before["gold"]) + CombatConstants.REWARD_SKIP_EXTRA_GOLD)


func test_queued_levelups_freeze_between_picks() -> void:
	var cs := _rush()
	_prep_mid_slide(cs)
	cs.gain_xp(30 + 55 + 90)  # 连升 3 级
	assert_eq(cs.pending_levelups, 3)
	var before := snap_state(cs)
	var picked: Array = []
	for k in 3:
		_simulate_frames_while_open(cs, 0.5)
		picked.append(cs.reward_choices[0])
		assert_true(cs.pick_reward_ammo(0))
		if k < 2:
			assert_true(cs.reward_pending, "还在排队 → 仍暂停")
	assert_false(cs.reward_pending)
	var after := snap_state(cs)
	var d := diff(before, after)
	assert_eq(d.size(), 2, "只有袋多了 3 发：%s" % str(d))
	assert_eq(cs.bag.slice(cs.bag.size() - 3), picked)


func test_last_kill_levelup_defers_respawn_until_pick() -> void:
	var cs := _rush()
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].max_hp = cs.xp_needed()
	cs.enemies[0].hp = 0
	cs._check_end_after_player()
	assert_true(cs.reward_pending)
	assert_true(cs.enemies.is_empty(), "三选一期间不刷怪")
	_simulate_frames_while_open(cs, 2.0)
	assert_true(cs.enemies.is_empty())
	assert_true(cs.pick_reward_ammo(0))
	cs.tick_combat_time(0.016)
	assert_false(cs.alive_enemies().is_empty(), "选完恢复第一帧才补刷")


func test_mid_slide_kill_keeps_other_enemies_slide() -> void:
	var cs := _rush()
	cs.advance_enemy_glide(0.55)
	var other = cs.enemies[0]
	var victim = cs.enemies[1]
	var frac0: float = cs.enemy_glide_fraction(other)
	var cell0: int = other.cell
	victim.max_hp = cs.xp_needed()
	victim.hp = 0
	cs._check_end_after_player()
	assert_true(cs.reward_pending)
	_simulate_frames_while_open(cs, 1.0)
	cs.pick_reward_ammo(1)
	assert_eq(other.cell, cell0)
	assert_almost_eq(cs.enemy_glide_fraction(other), frac0, 0.00001, "滑行到一半的位置保持")


# ——— 场景级（真实 combat.tscn：装弹 → 开火击杀 → 升级） ———

func _ui_snap(ui) -> Dictionary:
	var d: Dictionary = snap_state(ui.state)
	var xs: Array = []
	for i in CombatConstants.BOARD_SIZE:
		var unit: Control = ui.board_row.get_child(i).get_node_or_null("UnitBody")
		xs.append([unit.visible, snappedf(unit.position.x, 0.01)] if unit else [])
	d["unit_x"] = str(xs)
	d["disk_rot"] = snappedf(ui._disk.rotation, 0.0001)
	d["in_flight"] = ui._in_flight_shots
	d["chips"] = ui._muzzle_chip_sig
	d["bag_balls"] = ui._bag_physics.ball_count() if ui._bag_physics else -1
	return d


func _start_ui_and_kill(levels: int):
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	ui._on_sin_picked(W)
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	for e in cs.enemies:
		e.hp = 500
		e.max_hp = 500
		e.atk = 0
	for _k in 2:
		ui._on_manual_load()
		await wait_seconds(0.6)
	await wait_seconds(0.5)  # 滑到半格
	var target = cs.enemies[0]
	for e in cs.enemies:
		if e.cell < target.cell:
			target = e
	target.hp = 1
	var need := 0
	for k in levels:
		need += CombatState.xp_needed_for_level(cs.level + k)
	target.max_hp = 1
	cs.xp = need - 1
	ui._on_fire()
	await wait_process_frames(3)
	return ui


func test_scene_levelup_is_pure_pause_overlay() -> void:
	var ui = await _start_ui_and_kill(1)
	var cs: CombatState = ui.state
	assert_true(cs.reward_pending)
	assert_true(ui._reward_open, "升级立即弹三选一")
	assert_true(ui.is_combat_frozen(), "战斗场景冻结")
	var s0 := _ui_snap(ui)
	await wait_seconds(1.0)
	var s1 := _ui_snap(ui)
	assert_eq(diff(s0, s1), [], "打开期间：敌人位置/HP/状态、转盘、飞行中子弹、袋、计时全不变")
	var choice: int = cs.reward_choices[0]
	ui._on_reward_pick(0)
	assert_false(ui._reward_open)
	assert_false(ui.is_combat_frozen())
	var s2 := _ui_snap(ui)
	var d := diff(s1, s2)
	for line in d:
		assert_true(str(line).begins_with("bag"), "关闭后只有袋变化：%s" % str(line))
	assert_eq(int(cs.bag.back()), choice)
	await wait_seconds(0.2)
	assert_gt(cs.elapsed_sec, float(s1["elapsed"]), "选完接着计时")
	assert_gt(cs.enemy_step_progress + float(cs.enemies.size() == 0), float(s1["step"]) - 0.0001)


func test_scene_queued_levelups_stay_frozen() -> void:
	var ui = await _start_ui_and_kill(2)
	var cs: CombatState = ui.state
	assert_eq(cs.pending_levelups, 2)
	var s0 := _ui_snap(ui)
	await wait_seconds(0.5)
	ui._on_reward_pick(0)
	assert_true(ui._reward_open, "第二次三选一接着弹")
	assert_true(ui.is_combat_frozen())
	await wait_seconds(0.5)
	var s1 := _ui_snap(ui)
	for line in diff(s0, s1):
		assert_true(str(line).begins_with("bag"), "第一次选完仍冻结，只有袋变：%s" % str(line))
	ui._on_reward_skip()
	assert_false(ui._reward_open)
	assert_false(ui.is_combat_frozen())
	var s2 := _ui_snap(ui)
	for line in diff(s1, s2):
		assert_true(str(line).begins_with("gold"), "放弃只加金币：%s" % str(line))


func test_game_version_0_3_9() -> void:
	assert_eq(GameVersion.STRING, "0.3.9")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_eq(str(d["entries"][0]["version"]), "0.3.9")
