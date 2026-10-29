extends GutTest
## v0.3.5：三罪孽入膛即罚（跨会话/额外轮）、枪口倒计时、连点射击无冷却。

const W := FireResolver.ID_WRATH
const P := FireResolver.ID_PRIDE
const G := FireResolver.ID_GREED
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3501, sin_id: int = FireResolver.ID_WRATH) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, sin_id)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 9999
	cs.enemies[0].max_hp = 9999
	cs.player_max_hp = 999
	cs.player_hp = 999
	return cs


func _bag_only(cs: CombatState, id: int, n: int) -> void:
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in n:
		cs.bag.append(id)
		cs.bag_temp.append(false)


func _load_one(cs: CombatState) -> int:
	## 与 UI 手装一发同路径；返回装入的弹 id（失败 -1）。
	if not cs.can_manual_load():
		return -1
	if not cs.is_busy_loading():
		if not cs.begin_load():
			return -1
	var r: Dictionary = cs.load_next_chamber()
	if not bool(r.get("ok", false)):
		return -1
	if not bool(r.get("done", false)):
		cs.apply_load_rotate()
	return int(r.get("ammo_id", -1))


func _fire_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	cs.finalize_post_fire()


# ---------------- 三罪孽 ----------------

func test_wrath_triggers_immediately_on_third_insert_mid_session() -> void:
	var cs := _rush()
	cs.magazine.clear()
	_bag_only(cs, W, 6)
	var hp0: int = cs.player_hp
	assert_eq(_load_one(cs), W)
	assert_eq(_load_one(cs), W)
	assert_eq(cs.player_hp, hp0, "2 颗不罚")
	assert_eq(_load_one(cs), W)
	assert_true(cs.is_busy_loading(), "会话仍在进行")
	assert_eq(cs.player_hp, hp0 - 6, "第 3 颗入膛立刻自伤 6")


func test_sins_across_separate_sessions_with_fire_between_trigger() -> void:
	## 旧逻辑只数单次装填会话：装 2 → 开火提交 → 再装 1 永远不罚。
	var cs := _rush(3502)
	cs.magazine.clear()
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	_bag_only(cs, W, 6)
	var hp0: int = cs.player_hp
	assert_eq(_load_one(cs), W)
	assert_eq(_load_one(cs), W)
	# 开火打掉白弹（提交会话）：把锤位对到白弹
	cs.commit_load_session_if_active()
	cs.magazine.start_index = 0
	var shots: Array = cs.fire_tap()
	assert_eq(shots.size(), 1)
	assert_eq(int(shots[0]["ammo_id"]), WHITE, "先打白弹")
	assert_eq(cs.sin_count_in_cylinder(W), 2)
	assert_eq(cs.player_hp, hp0)
	assert_eq(_load_one(cs), W)
	assert_eq(cs.sin_count_in_cylinder(W), 3)
	assert_eq(cs.player_hp, hp0 - 6, "跨会话第 3 颗也立刻罚")


func test_fourth_sin_does_not_retrigger_and_refill_to_three_retriggers() -> void:
	var cs := _rush(3503)
	cs.magazine.clear()
	_bag_only(cs, W, 12)
	var hp0: int = cs.player_hp
	for _i in 3:
		_load_one(cs)
	assert_eq(cs.player_hp, hp0 - 6)
	_load_one(cs)
	assert_eq(cs.sin_count_in_cylinder(W), 4)
	assert_eq(cs.player_hp, hp0 - 6, "第 4 颗不重复罚")
	cs.commit_load_session_if_active()
	# 打掉 2 颗愤怒 → 剩 2；再装 1 颗 → 回到 3 → 再罚
	cs.fire_tap()
	cs.fire_tap()
	assert_eq(cs.sin_count_in_cylinder(W), 2)
	var hp1: int = cs.player_hp
	assert_eq(_load_one(cs), W)
	assert_eq(cs.sin_count_in_cylinder(W), 3)
	assert_eq(cs.player_hp, hp1 - 6, "降到 3 以下后再装回 3 再次触发")


func test_pride_pulls_on_third_insert() -> void:
	var cs := _rush(3504, P)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 8)
	cs.magazine.clear()
	_bag_only(cs, P, 6)
	_load_one(cs)
	_load_one(cs)
	assert_eq(cs.enemies[0].cell, 8)
	_load_one(cs)
	assert_eq(cs.enemies[0].cell, 1, "第 3 颗傲慢入膛即拉近")


func test_greed_takes_gold_on_third_insert() -> void:
	var cs := _rush(3505, G)
	cs.gold = 50
	cs.magazine.clear()
	_bag_only(cs, G, 6)
	_load_one(cs)
	_load_one(cs)
	assert_eq(cs.gold, 50)
	_load_one(cs)
	assert_eq(cs.gold, 44)


func test_super_round_extra_load_bringing_third_sin_triggers() -> void:
	## 超级回合额外轮补的一发是第 3 颗愤怒 → 同步触发惩罚。
	var cs := _rush(3506)
	cs.magazine.clear()
	cs.magazine.set_slot(0, FireResolver.ID_SUPER_ROUND)
	cs.magazine.set_slot(1, W)
	cs.magazine.set_slot(2, W)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	_bag_only(cs, W, 6)
	var hp0: int = cs.player_hp
	var shots: Array = cs.fire_tap()
	assert_true(shots.size() >= 2, "超级回合 + 额外轮至少 2 发")
	assert_eq(int(shots[0]["ammo_id"]), FireResolver.ID_SUPER_ROUND)
	assert_true(bool(shots[1]["extra"]))
	# 额外轮装入 W → 转轮 3 颗愤怒（触发），随后额外轮射出 1 颗
	assert_eq(cs.player_hp, hp0 - 6, "额外轮装入第 3 颗愤怒应触发")


# ---------------- 枪口倒计时 ----------------

func test_muzzle_entries_countdown_and_pride_timed() -> void:
	## v0.3.7：傲慢也显示秒数（不再 ∞）；多层显示最短剩余。
	var cs := _rush(3507)
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 3.2
	cs._muzzle_pride = 2
	var es: Array = cs.muzzle_status_entries()
	assert_eq(es.size(), 2)
	assert_eq(str(es[0]["name"]), "愤怒")
	assert_almost_eq(float(es[0]["remaining"]), 3.2, 0.001)
	assert_eq(CombatState.format_muzzle_countdown(es[0]), "愤怒 3.2s")
	assert_almost_eq(float(es[1]["total"]), CombatConstants.MUZZLE_DURATION_PRIDE_SEC, 0.001)
	assert_eq(CombatState.format_muzzle_countdown(es[1]), "傲慢×2 %.1fs" % float(es[1]["remaining"]))
	cs.tick_muzzle_durations(1.0)
	assert_almost_eq(float(cs.muzzle_status_entries()[0]["remaining"]), 2.2, 0.001, "计时递减")


func test_muzzle_countdown_stack_adds_layer_not_refresh() -> void:
	var cs := _rush(3508)
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 0.5
	# 再次挂载愤怒 → 追加新层，旧层不刷新；显示最短=旧层
	cs.magazine.clear()
	cs.magazine.set_slot(0, W)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap()
	var e: Dictionary = cs.muzzle_status_entries()[0]
	assert_eq(int(e["stacks"]), 2)
	assert_almost_eq(float(e["remaining"]), 0.5, 0.05)
	assert_almost_eq(float(cs._muzzle_wrath_layers[1]), CombatConstants.MUZZLE_DURATION_WRATH_SEC, 0.01)


func test_ui_muzzle_chip_shows_countdown_and_bar() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 2.0
	cs._muzzle_pride = 1
	cs._muzzle_pride_t = 6.0
	ui._refresh_muzzle_hud()
	assert_eq(ui._muzzle_chip_nodes.size(), 2)
	var lab: Label = ui._muzzle_chip_nodes[0]["label"]
	assert_eq(lab.text, "愤怒 2.0s")
	var bar: ColorRect = ui._muzzle_chip_nodes[0]["bar"]
	assert_almost_eq(bar.anchor_right, 0.5, 0.01)
	cs._muzzle_wrath_t = 1.0
	ui._update_muzzle_countdowns()
	assert_eq(lab.text, "愤怒 1.0s", "原地更新不重建")
	assert_almost_eq(bar.anchor_right, 0.25, 0.01)
	assert_eq((ui._muzzle_chip_nodes[1]["label"] as Label).text, "傲慢 6.0s")


# ---------------- 连点射击 ----------------

func test_rapid_taps_fire_exactly_n_shots_no_desync() -> void:
	var cs := _rush(3509)
	_bag_only(cs, WHITE, 20)
	cs.magazine.clear()
	for i in 6:
		cs.magazine.set_slot(i, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var d0: int = cs.discard.size()
	var hp0: int = cs.enemies[0].hp
	for n in 6:
		var start: int = cs.magazine.start_index
		var shots: Array = cs.fire_tap()
		assert_eq(shots.size(), 1, "第 %d 次点击恰好 1 发" % (n + 1))
		assert_eq(int(shots[0]["slot"]), start, "打的是锤位那一仓")
		assert_eq(cs.magazine.loaded_count(), 5 - n)
		assert_eq(cs.discard.size(), d0 + n + 1, "弃弹堆 +1，无丢/重发")
		assert_eq(cs.magazine.slots[start], Magazine.EMPTY)
		assert_false(cs.is_busy_firing(), "点完立即可再点")
	assert_true(cs.enemies[0].hp < hp0)
	assert_eq(cs.fire_tap().size(), 0, "空匣点击不出弹")


func test_rapid_taps_skip_empty_chambers() -> void:
	var cs := _rush(3510)
	cs.magazine.clear()
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(4, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var a: Array = cs.fire_tap()
	var b: Array = cs.fire_tap()
	assert_eq(a.size(), 1)
	assert_eq(b.size(), 1)
	assert_eq(int(a[0]["slot"]), 1)
	assert_eq(int(b[0]["slot"]), 4)
	assert_true(cs.magazine.is_empty())


func test_rapid_tap_super_round_extras_still_run() -> void:
	var cs := _rush(3511)
	_bag_only(cs, WHITE, 10)
	cs.magazine.clear()
	cs.magazine.set_slot(0, FireResolver.ID_SUPER_ROUND)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var shots: Array = cs.fire_tap()
	assert_eq(shots.size(), 2, "超级回合 1 发 + 额外轮 1 发")
	assert_false(bool(shots[0]["extra"]))
	assert_true(bool(shots[1]["extra"]))
	assert_eq(cs.pending_gold_autofires(), 0)
	assert_false(cs.is_busy_firing())
	assert_false(cs.is_busy_loading())
	assert_true(cs.can_fire(), "仍可继续连点")


func test_rapid_tap_muzzle_mounts() -> void:
	var cs := _rush(3512)
	cs.magazine.clear()
	cs.magazine.set_slot(0, W)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap()
	assert_eq(cs._muzzle_wrath, 1, "愤怒挂枪口")
	var hp0: int = cs.enemies[0].hp
	cs.fire_tap()
	assert_true(cs.enemies[0].hp < hp0)


func test_ui_n_taps_same_frame_n_shots() -> void:
	## UI：同一帧点 N 次射击 = N 发，不被上一发动画/转盘锁住。
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 8)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 9999
	cs.enemies[0].max_hp = 9999
	_bag_only(cs, WHITE, 10)
	cs.magazine.clear()
	for i in 6:
		cs.magazine.set_slot(i, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	# 开局波次大字/ROLL 等弹窗不在本测范围
	ui._wave_bannering = false
	ui._rolling = false
	ui._loading = false
	ui._sin_pick_open = false
	ui._reward_delaying = false
	ui._refresh()
	assert_false(ui._fire_blocked())
	assert_true(cs.can_fire())
	var d0: int = cs.discard.size()
	for _i in 4:
		ui._on_fire()
	assert_eq(cs.magazine.loaded_count(), 2, "4 次点击 = 4 发")
	assert_eq(cs.discard.size(), d0 + 4)
	assert_false(ui.btn_fire.disabled, "射击键不因动画禁用")
	ui._on_fire()
	ui._on_fire()
	ui._on_fire()
	assert_eq(cs.magazine.loaded_count(), 0, "第 7 次空匣不重发")
	await wait_seconds(0.6)
	assert_eq(ui._in_flight_shots, 0, "所有弹道落地")
	assert_false(ui._wheel_animating)


func test_changelog_has_0_3_5() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	var found := false
	for e in d["entries"]:
		if str(e["version"]) == "0.3.5":
			found = true
	assert_true(found)
