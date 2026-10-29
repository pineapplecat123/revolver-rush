extends GutTest
## v0.3.8：经验升级取代波次；连续刷怪；状态不刷新；临时罪孽独立寿命；罪孽惩罚 +1 临时；枪口多层条。

const W := FireResolver.ID_WRATH
const P := FireResolver.ID_PRIDE
const G := FireResolver.ID_GREED
const WHITE := CombatConstants.WHITE_AMMO_ID
const LIFE := CombatConstants.TEMP_SIN_LIFETIME_SEC


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3801) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _kill_all(cs: CombatState) -> void:
	for e in cs.enemies:
		e.hp = 0
	cs._check_end_after_player()


# ——— 经验 ———

func test_xp_curve_values() -> void:
	assert_eq(CombatState.xp_needed_for_level(1), 30)
	assert_eq(CombatState.xp_needed_for_level(2), 55)
	assert_eq(CombatState.xp_needed_for_level(3), 90)
	assert_eq(CombatState.xp_needed_for_level(4), 135)
	assert_eq(CombatState.xp_needed_for_level(5), 190)


func test_rush_starts_lv1_no_xp() -> void:
	var cs := _rush()
	assert_eq(cs.level, 1)
	assert_eq(cs.xp, 0)
	assert_false(cs.reward_pending)


func test_kill_grants_xp_by_max_hp() -> void:
	var cs := _rush()
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].max_hp = 12
	cs.enemies[0].hp = 0
	cs._check_end_after_player()
	assert_eq(cs.xp, 12)
	assert_eq(cs.level, 1)


func test_boss_xp_doubled() -> void:
	var cs := _rush()
	var e = cs.enemies[0]
	e.max_hp = 40
	e.def_id = CombatConstants.SUPER_ZOMBIE_ENEMY_ID
	assert_eq(cs.xp_for_enemy(e), 40 * CombatConstants.XP_BOSS_MULT)


func test_overflow_carries() -> void:
	var cs := _rush()
	cs.gain_xp(30 + 7)
	assert_eq(cs.level, 2)
	assert_eq(cs.xp, 7)
	assert_true(cs.reward_pending)
	assert_eq(cs.pending_levelups, 1)


func test_multi_levelup_queues_pickers() -> void:
	var cs := _rush()
	cs.gain_xp(30 + 55 + 3)  # Lv1→Lv3
	assert_eq(cs.level, 3)
	assert_eq(cs.xp, 3)
	assert_eq(cs.pending_levelups, 2)
	var bag0: int = cs.bag.size()
	assert_true(cs.pick_reward_ammo(0))
	assert_true(cs.reward_pending, "第二次三选一仍在排队")
	assert_eq(cs.pending_levelups, 1)
	assert_true(cs.pick_reward_ammo(1))
	assert_false(cs.reward_pending)
	assert_eq(cs.pending_levelups, 0)
	assert_eq(cs.bag.size(), bag0 + 2)


func test_skip_reward_gives_gold_and_continues() -> void:
	var cs := _rush()
	var g0: int = cs.gold
	cs.gain_xp(cs.xp_needed())
	assert_true(cs.skip_reward_for_gold())
	assert_eq(cs.gold, g0 + CombatConstants.REWARD_SKIP_EXTRA_GOLD)
	assert_false(cs.reward_pending)


func test_reward_pauses_fire_load_and_time() -> void:
	var cs := _rush()
	cs.gain_xp(cs.xp_needed())
	assert_true(cs.reward_pending)
	assert_false(cs.can_fire())
	assert_false(cs.can_manual_load())
	var t0: float = cs.elapsed_sec
	assert_false(cs.tick_combat_time(5.0))
	assert_almost_eq(cs.elapsed_sec, t0, 0.0001, "三选一期间战斗时钟暂停")


# ——— 无波次 / 连续刷怪 ———

func test_clear_field_respawns_never_won() -> void:
	var cs := _rush()
	_kill_all(cs)
	assert_ne(cs.phase, CombatState.Phase.WON)
	assert_false(cs.alive_enemies().is_empty(), "清场立刻补刷")


func test_spawn_interval_ramp() -> void:
	var cs := _rush()
	cs.elapsed_sec = 0.0
	assert_almost_eq(cs.spawn_interval_now(), 4.0, 0.001)
	cs.elapsed_sec = 100.0
	assert_almost_eq(cs.spawn_interval_now(), 2.0, 0.001)
	cs.elapsed_sec = 1000.0
	assert_almost_eq(cs.spawn_interval_now(), CombatConstants.SPAWN_INTERVAL_MIN, 0.001)


func test_spawn_cap_ramp_1_5x() -> void:
	var cs := _rush()
	var want := {0.0: 2, 45.0: 3, 90.0: 5, 180.0: 8, 900.0: 9}
	for t in want.keys():
		cs.elapsed_sec = float(t)
		assert_eq(cs.spawn_alive_cap_now(), int(want[t]), "t=%s" % str(t))


func test_spawns_only_in_lane_cells_and_free() -> void:
	var cs := _rush()
	cs.enemies.clear()
	cs.elapsed_sec = 900.0
	cs._spawn_up_to_cap()
	var seen := {}
	for e in cs.enemies:
		assert_true(e.cell >= CombatConstants.BOARD_SIZE - CombatConstants.SPAWN_LANE_CELLS, "刷在最右 3 格")
		assert_false(seen.has(e.cell), "不叠格")
		seen[e.cell] = true
	assert_eq(cs.enemies.size(), CombatConstants.SPAWN_LANE_CELLS, "刷怪口满了就停")
	assert_eq(cs._free_spawn_cell(), -1)


func test_timer_spawns_over_time() -> void:
	var cs := _rush()
	var n0: int = cs.alive_enemies().size()
	for e in cs.enemies:
		e.cell = 3  # 腾出刷怪口
	cs.elapsed_sec = 100.0
	for _i in 40:
		cs.tick_combat_time(0.25)
	assert_gt(cs.alive_enemies().size(), n0)


func test_boss_at_180s() -> void:
	var cs := _rush()
	cs.enemies.clear()
	cs.elapsed_sec = CombatConstants.BOSS_EVERY_SEC - 0.1
	cs.tick_combat_time(0.2)
	var bosses := 0
	for e in cs.enemies:
		if int(e.def_id) == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			bosses += 1
	assert_eq(bosses, 2, "第 1 次 Boss：ceil(1×1.5)=2 只超级僵尸")


func test_state_persists_across_clear() -> void:
	var cs := _rush()
	cs._muzzle_wrath_layers = [3.0, 2.0]
	cs.gold = 17
	cs.player_hp = 50
	cs.magazine.set_slot(0, WHITE)
	var bag_n: int = cs.bag.size()
	_kill_all(cs)
	assert_eq(cs._muzzle_wrath_layers.size(), 2, "枪口不清")
	assert_eq(cs.gold, 17)
	assert_eq(cs.player_hp, 50)
	assert_eq(cs.magazine.slots[0], WHITE, "转轮不清")
	assert_eq(cs.bag.size(), bag_n, "袋不重置")


# ——— 临时罪孽寿命 ———

func test_temp_sin_expires_from_bag() -> void:
	var cs := _rush()
	var n0: int = cs.bag.size()
	cs._bag_append(W, LIFE)
	cs.tick_temp_sin_lifetimes(LIFE - 0.5)
	assert_eq(cs.bag.size(), n0 + 1)
	cs.tick_temp_sin_lifetimes(1.0)
	assert_eq(cs.bag.size(), n0)
	assert_eq(str(cs.expired_temp_events.back()["where"]), "bag")


func test_temp_sin_expires_from_discard() -> void:
	var cs := _rush()
	cs._discard_append(W, 2.0)
	var d0: int = cs.discard.size()
	cs.tick_temp_sin_lifetimes(2.5)
	assert_eq(cs.discard.size(), d0 - 1)


func test_temp_sin_expires_from_magazine_slot_becomes_empty() -> void:
	var cs := _rush()
	cs.magazine.set_slot(2, W, 3.0)
	assert_true(cs.magazine.is_slot_temporary(2))
	assert_almost_eq(cs.magazine.slot_temp_life(2), 3.0, 0.001)
	cs.tick_temp_sin_lifetimes(3.5)
	assert_eq(cs.magazine.slots[2], Magazine.EMPTY)
	assert_false(cs.magazine.is_slot_temporary(2))


func test_each_temp_sin_has_own_lifetime() -> void:
	var cs := _rush()
	var n0: int = cs.bag.size()
	cs._bag_append(W, LIFE)
	cs.tick_temp_sin_lifetimes(10.0)
	cs._bag_append(W, LIFE)
	cs.tick_temp_sin_lifetimes(LIFE - 10.0 + 0.1)
	assert_eq(cs.bag.size(), n0 + 1, "先来的到期，后来的还在")


func test_temp_life_paused_during_reward() -> void:
	var cs := _rush()
	cs._bag_append(W, 2.0)
	var n: int = cs.bag.size()
	cs.gain_xp(cs.xp_needed())
	cs.tick_combat_time(10.0)
	assert_eq(cs.bag.size(), n, "三选一暂停时寿命不走")


func test_temp_life_survives_moves() -> void:
	var cs := _rush()
	cs.magazine.set_slot(1, W, 7.5)
	var entries: Array = cs.magazine.unload_all_entries()
	var found := false
	for en in entries:
		if float(en.get("temp", 0.0)) > 0.0:
			assert_almost_eq(float(en["temp"]), 7.5, 0.001)
			found = true
	assert_true(found)


# ——— 罪孽惩罚 → +1 临时；袋重置不再 +N ———

func test_penalty_adds_exactly_one_temp_sin() -> void:
	var cs := _rush()
	var n0: int = cs.bag.size()
	var t0: int = cs.count_temporary_in_bag()
	cs._resolve_sin_pack_on_load([W, W, W, WHITE])
	assert_eq(cs.bag.size(), n0 + 1)
	assert_eq(cs.count_temporary_in_bag(), t0 + 1)
	assert_eq(cs.penalty_temp_sins_spawned, 1)
	var lifes: Array = cs.temp_lifetimes_in_bag()
	assert_almost_eq(float(lifes.back()), LIFE, 0.001)


func test_penalty_per_type() -> void:
	var cs := _rush()
	cs.gold = 100
	var n0: int = cs.bag.size()
	cs._resolve_sin_pack_on_load([G, G, G, P, P, P])
	assert_eq(cs.bag.size(), n0 + 2)
	assert_true(cs.bag.has(G))
	assert_true(cs.bag.has(P))


func test_two_sins_no_penalty_temp() -> void:
	var cs := _rush()
	var n0: int = cs.bag.size()
	cs._resolve_sin_pack_on_load([W, W, WHITE])
	assert_eq(cs.bag.size(), n0)


func test_bag_reset_adds_no_temp() -> void:
	var cs := _rush()
	for _i in 3:
		while not cs.bag.is_empty():
			cs._discard_append(cs.bag.pop_back(), 0.0)
			cs.bag_temp.pop_back()
		cs._reset_bag_in_combat()
	assert_eq(cs.count_temporary_in_bag(), 0)
	assert_eq(cs.total_ammo_count(W), 5, "整池只回基础")


# ——— 枪口多层条数据 ———

func test_muzzle_entries_expose_layers_sorted() -> void:
	var cs := _rush()
	cs._muzzle_wrath_layers = [3.5, 1.2, 2.0]
	var e: Dictionary = cs.muzzle_status_entries()[0]
	assert_eq(int(e["stacks"]), 3)
	assert_eq((e["layers"] as Array).size(), 3)
	assert_almost_eq(float(e["layers"][0]), 1.2, 0.001)
	assert_almost_eq(float(e["remaining"]), 1.2, 0.001)


func test_game_version_0_3_8() -> void:
	assert_eq(GameVersion.STRING, "0.3.8")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_eq(str(d["entries"][0]["version"]), "0.3.8")


# ——— UI ———

func test_ui_muzzle_one_translucent_bar_per_layer() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	cs._muzzle_wrath_layers = [0.8, 2.0, 4.0]
	ui._refresh_muzzle_hud()
	var node: Dictionary = ui._muzzle_chip_nodes[0]
	var bars: Array = node["bars"]
	assert_eq(bars.size(), 3)
	var parent: Node = (bars[0] as ColorRect).get_parent()
	for b in bars:
		var cr: ColorRect = b
		assert_eq(cr.get_parent(), parent, "所有层叠在同一条轨道上")
		assert_true(cr.color.a >= 0.35 and cr.color.a <= 0.45, "半透明")
	assert_almost_eq((bars[0] as ColorRect).anchor_right, 0.2, 0.01)
	assert_almost_eq((bars[2] as ColorRect).anchor_right, 1.0, 0.01)
	assert_gt((bars[0] as ColorRect).color.r, (bars[0] as ColorRect).color.g * 2.0, "≤25% 那层变红")
	assert_lt((bars[2] as ColorRect).color.r, (bars[2] as ColorRect).color.g * 2.0)
	assert_eq((node["label"] as Label).text, "愤怒×3 0.8s")


func test_ui_wheel_position_independent_of_chip_count() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	var xs: Array = []
	for setup in [[], [1.0], [1.0, 2.0, 3.0]]:
		cs._muzzle_wrath_layers = setup.duplicate()
		cs._muzzle_fire_layers = [2.0] if setup.size() >= 3 else []
		cs._muzzle_pride_layers = [5.0] if setup.size() >= 3 else []
		cs._muzzle_greed_layers = [1.5] if setup.size() >= 3 else []
		ui._refresh_muzzle_hud()
		await wait_process_frames(2)
		var col: Control = ui.get_node("Margin/RootVBox/MidPanel/MidSection/MagCol")
		var wheel: Control = ui.get_node("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel")
		xs.append(wheel.get_global_rect().get_center().x)
		assert_almost_eq(wheel.get_global_rect().get_center().x, col.get_global_rect().get_center().x, 1.0, "转轮在列内居中")
		assert_almost_eq(wheel.size.x, 220.0, 0.5, "转轮不被芯片撑宽")
	assert_almost_eq(float(xs[0]), float(xs[1]), 0.5)
	assert_almost_eq(float(xs[0]), float(xs[2]), 0.5)


func test_ui_chamber_shows_temp_seconds() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	cs.magazine.set_slot(0, W, 9.2)
	ui._update_temp_sin_timers()
	var lab: Label = ui._chamber_panels[0].get_node_or_null("TempLife")
	assert_not_null(lab)
	assert_eq(lab.text, "10s")
