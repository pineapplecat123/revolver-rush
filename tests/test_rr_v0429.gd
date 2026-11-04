extends GutTest
## v0.4.29：空仓算正常一拍（不快跳）、命中特效只认活着的目标（不在空中飙血）、袋内小球性能、商店删除列出弃牌堆。

const WHITE := CombatConstants.WHITE_AMMO_ID
const E := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _rush(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _ui_sandbox():
	CombatState.boot_sandbox = true
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


func _wait_volley_done(ui, max_sec: float = 10.0) -> void:
	var t := 0.0
	while t < max_sec and (ui._volley_ui_running or ui.state.is_volley_pending()):
		await wait_seconds(0.05)
		t += 0.05


func test_version_0_4_29() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.29") >= 0)
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.29"' in text)


# ---------------------------------------------------------------- 2 空仓一拍

func test_volley_blank_beats_logic_one_chamber_per_beat() -> void:
	## 槽 0、3 有弹，锤位 1（空）：拍序 1空 2空 3弹 4空 5空 0弹 → 共 6 拍，打完最后一颗就结束。
	var cs := _rush(42901)
	cs.dev_force_load([WHITE, E, E, WHITE, E, E] as Array[int])
	cs.magazine.set_start(1)
	var first: Array = cs.fire_tap(false)
	assert_eq(first.size(), 0, "空仓开局：第一拍空响，不出弹")
	assert_true(cs.is_volley_pending())
	var beats: Array = ["blank"]
	var ports: Array = [1]
	assert_true(cs.take_volley_blank_beat())
	var guard := 20
	while cs.is_volley_pending() and guard > 0:
		guard -= 1
		ports.append(cs.magazine.chamber_at_fire_port())
		if cs.volley_port_empty():
			assert_true(cs.take_volley_blank_beat())
			beats.append("blank")
		else:
			var more: Array = cs.take_volley_shot()
			assert_eq(more.size(), 1)
			assert_eq(int(more[0]["slot"]), int(ports[ports.size() - 1]), "打的就是击发位那一仓")
			assert_eq(int(more[0].get("blank_skip", 0)), 0, "不快跳")
			beats.append("shot")
	assert_eq(ports, [1, 2, 3, 4, 5, 0])
	assert_eq(beats, ["blank", "blank", "shot", "blank", "blank", "shot"])
	assert_false(cs.is_volley_pending(), "最后一颗打完就结束")
	assert_true(cs.magazine.is_empty())


func test_blank_beat_refused_outside_volley_or_on_loaded() -> void:
	var cs := _rush(42902)
	cs.dev_force_load([WHITE, E, E, E, E, E] as Array[int])
	cs.magazine.set_start(2)
	assert_false(cs.take_volley_blank_beat(), "没在连射里")
	cs.magazine.set_start(0)
	cs.fire_tap(false)
	assert_false(cs.take_volley_blank_beat())


func test_empty_skip_constant_removed() -> void:
	var consts: Dictionary = (load("res://scripts/combat/combat_constants.gd") as GDScript).get_script_constant_map()
	assert_false(consts.has("VOLLEY_EMPTY_SKIP_SEC"))
	assert_almost_eq(CombatConstants.VOLLEY_SHOT_INTERVAL_SEC, 0.25, 0.0001)


func test_ui_blank_beats_take_full_beat_and_ring_matches() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	ui._combat_speed = 1.0
	ui.shot_audit.clear()
	ui.blank_audit.clear()
	cs.dev_force_load([WHITE, E, E, WHITE, E, E] as Array[int])
	cs.magazine.set_start(1)
	ui._refresh()
	await wait_process_frames(2)
	# 只有 2 颗 → 会预转到随机一颗有弹仓；先关掉预转影响：单独测「从空仓起」用单颗
	cs.dev_force_load([E, E, E, WHITE, E, E] as Array[int])
	cs.magazine.set_start(0)
	ui._refresh()
	await wait_process_frames(2)
	ui._on_fire()
	await _wait_volley_done(ui)
	assert_eq(ui.blank_audit.size(), 3, "槽 0/1/2 各空响一拍")
	for b in ui.blank_audit:
		assert_eq(int(b["ring"]), int(b["slot"]), "红圈 = 空响的那一仓")
	assert_eq(ui.shot_audit.size(), 1)
	assert_eq(int(ui.shot_audit[0]["ring"]), 3)
	# 拍长：空拍之间 ≈ 一个整拍（间隔+停留+转一格），远大于旧的 0.04 快转
	var beat_ms: float = (CombatState.volley_shot_interval_sec() + CombatState.volley_rotate_sec()) * 1000.0
	for i in range(1, ui.blank_audit.size()):
		var d: int = int(ui.blank_audit[i]["ms"]) - int(ui.blank_audit[i - 1]["ms"])
		assert_gt(float(d), beat_ms * 0.8, "空拍间隔 %d ms" % d)
	var d2: int = int(ui.shot_audit[0]["ms"]) - int(ui.blank_audit[2]["ms"])
	assert_gt(float(d2), beat_ms * 0.8, "最后一空拍到实弹也是一整拍")
	assert_true(cs.magazine.is_empty())


# ---------------------------------------------------------------- 1 不在空中飙血

func test_hit_fx_skips_dead_or_gone_target() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	await wait_process_frames(2)
	var live: EnemyInstance = null
	for e in cs.enemies:
		if e != null and e.is_alive():
			live = e
			break
	assert_not_null(live)
	ui.hit_fx_log.clear()
	var skipped0: int = ui.air_blood_skipped
	# 活的：喷在它身上
	ui._spawn_hit_event({"cell": live.cell, "amount": 3, "kind": "", "enemy": live, "lethal": false})
	assert_eq(ui.hit_fx_log.size(), 1)
	assert_lt(Vector2(ui.hit_fx_log[0]["g"]).distance_to(ui._enemy_hit_global(live)), 2.0)
	# 致死那一下：喷血浆，之后再打它（旧子弹）→ 哑火
	ui._spawn_hit_event({"cell": live.cell, "amount": 3, "kind": "", "enemy": live, "lethal": true})
	assert_eq(ui.hit_fx_log.size(), 2)
	ui._spawn_hit_event({"cell": live.cell, "amount": 3, "kind": "", "enemy": live, "lethal": false})
	assert_eq(ui.hit_fx_log.size(), 2, "已死目标不再飙血")
	assert_eq(ui.air_blood_skipped, skipped0 + 1)
	# 已离场（清掉、小动物也没了）：不喷
	var gone := EnemyInstance.new()
	gone.cell = 5
	gone.hp = 0
	ui._spawn_hit_event({"cell": 5, "amount": 3, "kind": "", "enemy": gone, "lethal": false})
	assert_eq(ui.hit_fx_log.size(), 2)
	assert_eq(ui.air_blood_skipped, skipped0 + 2)


func test_old_cell_event_on_empty_cell_no_blood() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	ui._refresh()
	await wait_process_frames(2)
	var s0: int = ui.air_blood_skipped
	ui._spawn_hit_event({"cell": 4, "amount": 5, "kind": ""})
	assert_eq(ui.air_blood_skipped, s0 + 1)


func test_kill_then_more_shots_no_air_blood() -> void:
	## 一只 3 血的木桩，连射 4 发：第一发打死后后面的子弹不在它原位喷血。
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.sandbox_spawn_dummy(3, 3)
	cs.sandbox_spawn_dummy(99999, 6)
	ui._refresh()
	await wait_process_frames(2)
	ui.hit_fx_log.clear()
	cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
	ui._refresh()
	await wait_process_frames(2)
	var d3: EnemyInstance = null
	for e in cs.enemies:
		if e.hp == 3:
			d3 = e
	ui._on_fire()
	await wait_process_frames(1)
	assert_true(ui._skel_enemies.has(d3.get_instance_id()), "逻辑已死，但子弹没到前小动物还在原地")
	await _wait_volley_done(ui)
	await wait_seconds(0.6)
	var by_eid: Dictionary = {}
	var lethal_n := 0
	for h in ui.hit_fx_log:
		if bool(h["lethal"]):
			lethal_n += 1
		by_eid[int(h["eid"])] = int(by_eid.get(int(h["eid"]), 0)) + 1
	assert_eq(lethal_n, 1, "只炸一次")
	# 致死之后，同一只不再有任何飙血记录
	var dead_eid := -1
	var after_dead := 0
	for h2 in ui.hit_fx_log:
		if dead_eid >= 0 and int(h2["eid"]) == dead_eid:
			after_dead += 1
		if bool(h2["lethal"]):
			dead_eid = int(h2["eid"])
	assert_eq(after_dead, 0)
	assert_eq(int(ui.hit_fx_log[0]["eid"]), d3.get_instance_id(), "致死那下喷在它身上")
	await wait_seconds(1.0)
	assert_false(ui._skel_enemies.has(d3.get_instance_id()), "死亡动画播完后清掉")


# ---------------------------------------------------------------- 3 袋内小球性能

func test_bag_style_cached_and_no_redraw_when_settled_common() -> void:
	var box = load("res://scripts/combat/bag_physics_box.gd").new()
	var calls := [0]
	box.color_lookup = func(_aid: int) -> Dictionary:
		calls[0] += 1
		return {"bg": Color(0.9, 0.9, 0.9), "fg": Color(0, 0, 0)}
	box.size = Vector2(300, 300)
	add_child_autofree(box)
	var ids: Array = []
	for i in 40:
		ids.append(WHITE)
	box.sync_ammo_ids(ids)
	assert_eq(calls[0], 1, "同种弹只查一次颜色")
	assert_false(box.needs_redraw_every_frame(), "普通弹没有动态特效")
	ids = []
	for i in 30:
		ids.append(WHITE)
	ids.append(FireResolver.ID_WRATH)
	box.sync_ammo_ids(ids)
	assert_true(box.needs_redraw_every_frame(), "有罪孽/稀有特效就每帧画")


func test_bag_broadphase_separates_overlaps() -> void:
	var box = load("res://scripts/combat/bag_physics_box.gd").new()
	box.size = Vector2(300, 300)
	add_child_autofree(box)
	box.sync_ammo_ids([WHITE, WHITE, WHITE])
	box._balls[0]["pos"] = Vector2(100, 200)
	box._balls[1]["pos"] = Vector2(105, 200)
	box._balls[2]["pos"] = Vector2(250, 200)
	for b in box._balls:
		b["vel"] = Vector2.ZERO
		b["asleep"] = false
	for _i in 30:
		box._physics_step(1.0 / 60.0)
	var d: float = Vector2(box._balls[0]["pos"]).distance_to(box._balls[1]["pos"])
	assert_gt(d, float(box._balls[0]["r"]) * 2.0 - 1.5, "重叠的球被推开")


func test_sin_star_fill_no_triangulation_path() -> void:
	## 锯齿环用中心扇形三角化提交（自交也不会报错/不画）。
	var src: String = (load("res://scripts/combat/rarity_fx.gd") as GDScript).source_code
	assert_true("_fill_star(ci, center, outer" in src)
	assert_false("draw_colored_polygon(outer" in src)


# ---------------------------------------------------------------- 4 商店删除含弃牌堆

func test_shop_state_remove_from_discard() -> void:
	var sh := ShopState.new()
	sh.begin(500, [WHITE, FireResolver.ID_WRATH], 1, 7, [WHITE, 22, 22])
	assert_eq(sh.discard.size(), 3)
	assert_true(sh.can_remove_from("discard", 1))
	assert_true(sh.remove_from("discard", 1))
	assert_eq(sh.discard, [WHITE, 22] as Array[int])
	assert_eq(sh.bag.size(), 2, "袋不动")
	assert_true(sh.remove_from("bag", 0))
	assert_eq(sh.bag, [FireResolver.ID_WRATH] as Array[int])
	assert_false(sh.can_remove_from("bag", 0), "罪孽不可删")
	var payload: Dictionary = sh.end_session()
	assert_eq(payload["discard"], [WHITE, 22])


func test_apply_shop_session_rebuilds_discard_and_baseline() -> void:
	var cs := _rush(42903)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs._bag_append(WHITE, 0.0)
	cs.discard.append(22)
	cs.discard_temp.append(0.0)
	cs.discard.append(WHITE)
	cs.discard_temp.append(0.0)
	cs.magazine.set_slot(0, 26)
	cs._snapshot_combat_bag_baseline()
	assert_eq(cs._combat_bag_baseline.size(), 4)
	# 店里删掉弃牌堆的穿甲（22）
	cs.apply_shop_session([WHITE], [0.0], 100, [WHITE], [0.0])
	assert_eq(cs.discard, [WHITE] as Array[int])
	assert_eq(cs.total_ammo_count(22), 0)
	var base: Array = cs._combat_bag_baseline.duplicate()
	base.sort()
	var want: Array = [WHITE, WHITE, 26]
	want.sort()
	assert_eq(base, want, "基线 = 袋 + 膛 + 弃（删掉的不回来，膛/弃里的不丢）")
	# 不传弃牌 = 弃牌不动（兼容旧调用）
	cs.apply_shop_session([WHITE], [0.0], 100)
	assert_eq(cs.discard, [WHITE] as Array[int])


func test_shop_ui_lists_bag_and_discard() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.gold = 999
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(WHITE, 0.0)
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.discard.append(22)
	cs.discard_temp.append(0.0)
	ui._open_rush_shop()
	await wait_process_frames(2)
	var rows: Array = ui.shop_remove_rows()
	var has_bag := false
	var has_disc := false
	for r in rows:
		if r["pile"] == "bag" and int(r["id"]) == WHITE:
			has_bag = true
		if r["pile"] == "discard" and int(r["id"]) == 22:
			has_disc = true
	assert_true(has_bag, "列出袋内")
	assert_true(has_disc, "列出弃牌堆")
	ui._on_rush_shop_remove(22, "discard")
	assert_eq(ui._shop.discard.size(), 0)
	assert_eq(ui._shop.bag.size(), 1, "删弃牌不动袋")
	ui._on_rush_shop_leave()
	assert_eq(cs.total_ammo_count(22), 0)
	assert_eq(cs.bag.size(), 1)
