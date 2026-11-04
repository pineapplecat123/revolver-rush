extends GutTest
## v0.4.22：连射、永久弹药不丢、商店暂停、射速帽独立计时、金币拾取入账、玩家状态环。

const WHITE := CombatConstants.WHITE_AMMO_ID
const W := FireResolver.ID_WRATH


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func after_each() -> void:
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _rush(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _load_full(cs: CombatState) -> void:
	var guard := 8
	while guard > 0 and cs.magazine.loaded_count() < CombatConstants.MAGAZINE_SIZE and cs.can_manual_load():
		guard -= 1
		if not cs.is_busy_loading():
			if not cs.begin_load():
				break
		var r: Dictionary = cs.load_next_chamber()
		if not bool(r.get("ok", false)):
			break
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	cs.commit_load_session_if_active()


func test_version_0_4_22() -> void:
	assert_eq(GameVersion.STRING, "0.4.22")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.22"' in text)


func test_volley_spins_then_empties_and_ignores_repress() -> void:
	var cs := _rush(42201)
	cs.dev_force_load([
		WHITE, WHITE, WHITE, WHITE, WHITE, WHITE,
	] as Array[int])
	cs.magazine.set_start(0)
	var steps: int = cs.spin_cylinder_for_volley()
	assert_gte(steps, 1, "两发以上必转")
	assert_eq(cs.magazine.start_index, steps % CombatConstants.MAGAZINE_SIZE)
	var async_first: Array = cs.fire_tap(false)
	assert_eq(async_first.size(), 1)
	assert_true(cs.is_volley_pending())
	assert_eq(cs.fire_tap(false).size(), 0, "连射中再按忽略")
	assert_eq(cs.magazine.loaded_count(), 5)
	var guard := 8
	while cs.is_volley_pending() and guard > 0:
		guard -= 1
		var more: Array = cs.take_volley_shot()
		assert_false(more.is_empty())
	assert_false(cs.is_volley_pending())
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_eq(cs.fire_tap().size(), 0, "打光后再按不出弹")


func test_empty_chambers_do_not_each_cost_a_shot_record() -> void:
	var cs := _rush(42202)
	cs.magazine.clear()
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(4, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var shots: Array = cs.fire_tap(true)
	assert_eq(shots.size(), 2)
	assert_gte(int(shots[0].get("blank_skip", 0)), 1)
	assert_true(cs.magazine.is_empty())


func test_fire_gate_ticks_without_auto_advance_and_stops_in_shop() -> void:
	var cs := _rush(42203)
	cs.auto_enemy_advance = false
	cs.player_fire_gate_remaining = 0.4
	cs.tick_player_fire_gate(0.15)
	assert_almost_eq(cs.player_fire_gate_remaining, 0.25, 0.001)
	var elapsed: float = cs.elapsed_sec
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = 4.0
	cs._bag_append(WHITE, 3.0)
	var life_before: float = float(cs.bag_temp[cs.bag_temp.size() - 1])
	cs.shop_hold = true
	cs.tick_player_fire_gate(1.0)
	cs.tick_combat_time(2.0)
	var glide_before: float = cs.enemy_step_progress
	cs.advance_enemy_glide(0.7)
	assert_almost_eq(cs.player_fire_gate_remaining, 0.25, 0.001, "商店里射速帽停")
	assert_almost_eq(cs.elapsed_sec, elapsed, 0.001)
	assert_almost_eq(cs._muzzle_wrath_t, 4.0, 0.001)
	assert_almost_eq(float(cs.bag_temp[cs.bag_temp.size() - 1]), life_before, 0.001)
	assert_almost_eq(cs.enemy_step_progress, glide_before, 0.001)
	cs.shop_hold = false
	cs.tick_player_fire_gate(0.25)
	assert_almost_eq(cs.player_fire_gate_remaining, 0.0, 0.001)


func test_ui_fire_gate_ticks_when_enemies_do_not_auto_advance() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	ui.state.auto_enemy_advance = false
	ui.state.player_fire_gate_remaining = 0.4
	ui._process(0.1)
	assert_almost_eq(ui.state.player_fire_gate_remaining, 0.3, 0.02)
	ui._open_rush_shop()
	assert_true(get_tree().paused)
	assert_eq(ui._shop_panel.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(ui.state.shop_hold)
	var gate: float = ui.state.player_fire_gate_remaining
	var elapsed: float = ui.state.elapsed_sec
	ui._process(0.5)
	ui.state.tick_combat_time(1.5)
	assert_almost_eq(ui.state.player_fire_gate_remaining, gate, 0.001)
	assert_almost_eq(ui.state.elapsed_sec, elapsed, 0.001)
	ui._on_rush_shop_leave()
	assert_false(get_tree().paused)
	assert_false(ui.state.shop_hold)


func test_map_shop_visual_cell_is_fractional() -> void:
	var cs := _rush(42204)
	cs.elapsed_sec = CombatConstants.MAP_SHOP_FIRST_SEC
	cs.shop_spawn_count = 0
	cs.shop_cell = -1
	cs.tick_map_shop(0.25)
	assert_gte(cs.shop_cell, 0)
	var vis: float = cs.shop_visual_cell()
	assert_lt(vis, float(cs.shop_cell))
	assert_gt(vis, float(cs.shop_cell) - 1.0)
	assert_gt(cs.shop_glide_fraction(), 0.05)


func test_permanent_ammo_survives_shop_reset_and_temp_expiry() -> void:
	## 根因回归：离店若只把袋子拍进基线，膛/弃里的永久弹会在下次袋空重置时消失。
	var cs := _rush(42205)
	var expected: int = cs.count_permanent_owned()
	assert_eq(expected, CombatConstants.STARTER_BAG_TOTAL)
	cs.reward_pending = true
	cs.reward_resolved = false
	cs.reward_choices = [WHITE, WHITE, WHITE] as Array[int]
	assert_true(cs.pick_reward_ammo(0))
	expected += 1
	assert_eq(cs.count_permanent_owned(), expected)
	_load_full(cs)
	cs.player_fire_gate_remaining = 0.0
	var fired: Array = cs.fire_tap(true)
	assert_gt(fired.size(), 0)
	assert_eq(cs.count_permanent_owned(), expected, "打进弃牌堆不算丢")
	# 袋里塞临时弹：罪孽 / 幽灵 / 小石头 / 嫉妒式白弹。它们到期不能连带永久弹。
	cs._bag_append(W, CombatConstants.TEMP_SIN_LIFETIME_SEC)
	cs._bag_append(FireResolver.ID_GHOST, CombatConstants.GHOST_TTL_SEC)
	cs._bag_append(FireResolver.ID_PEBBLE, CombatConstants.PEBBLE_TTL_SEC)
	cs._bag_append(WHITE, CombatConstants.ENVY_COPY_TTL_SEC)
	assert_eq(cs.count_permanent_owned(), expected)
	var temps: Array = []
	for i in cs.bag.size():
		temps.append(cs.bag_temp[i] if i < cs.bag_temp.size() else 0.0)
	var shop := ShopState.new()
	shop.begin(999, cs.bag.duplicate(), 1, 42205)
	assert_true(shop.buy(0))
	temps.append(0.0)
	cs.apply_shop_session(shop.bag, temps, shop.gold)
	expected += 1
	assert_eq(cs.count_permanent_owned(), expected, "离店后膛+弃+新买的都还在，临时弹没变成永久")
	cs.tick_temp_sin_lifetimes(30.0)
	assert_eq(cs.count_permanent_owned(), expected, "临时弹到期不删永久弹")
	for _cycle in 4:
		cs.player_fire_gate_remaining = 0.0
		if cs.magazine != null and not cs.magazine.is_empty():
			cs.fire_tap(true)
		_load_full(cs)
		cs.player_fire_gate_remaining = 0.0
		if cs.magazine != null and not cs.magazine.is_empty():
			cs.fire_tap(true)
		cs.tick_temp_sin_lifetimes(3.0)
		assert_eq(cs.count_permanent_owned(), expected, "袋空重置后永久弹总数不变")


func test_collect_gold_piece_credits_wallet() -> void:
	var cs := _rush(42206)
	cs.enemies.clear()
	cs.gold = 0
	cs.kill_gold_chance_override = 1.0
	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 4)
	cs.enemies[0].hp = 0
	cs._remove_dead()
	assert_eq(cs.gold, 0)
	assert_eq(cs.pending_gold_total(), CombatConstants.KILL_GOLD_DROP_AMOUNT)
	var drop_id: int = int(cs.gold_drops[0]["id"])
	assert_eq(cs.collect_gold_piece(drop_id, 1), 1)
	assert_eq(cs.gold, 1)
	assert_eq(cs.collect_gold_piece(drop_id, 5), 1, "不会超过这次掉落剩余")
	assert_eq(cs.gold, CombatConstants.KILL_GOLD_DROP_AMOUNT)
	assert_eq(cs.pending_gold_total(), 0)
	cs.player_hp = 0
	cs._lose_hp()
	cs.kill_gold_chance_override = 1.0
	assert_eq(cs.collect_gold_piece(1, 2), 0, "战败后不再入账")


func test_player_status_rings_sit_on_anchor() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	var cs: CombatState = ui.state
	cs.player_confuse_remaining = CombatConstants.LUST_SELF_CONFUSE_SEC
	cs.sloth_fire_penalty_remaining = CombatConstants.SLOTH_FIRE_PENALTY_SEC * 0.5
	cs.gluttony_self_dot_remaining = 2.0
	var entries: Array = cs.player_status_ring_entries()
	assert_gte(entries.size(), 3)
	var labels: PackedStringArray = PackedStringArray()
	for e in entries:
		labels.append(str(e.get("label", "")))
	assert_true("乱" in labels)
	assert_true("缓" in labels)
	assert_true("伤" in labels)
	var slow_ratio := 1.0
	for e in entries:
		if str(e.get("id", "")) == "slow":
			slow_ratio = float(e.get("ratio", 1.0))
	assert_almost_eq(slow_ratio, 0.5, 0.05)
	ui._update_player_status_rings()
	var rings: Control = ui.get_node("PlayerStatusRings")
	var anchor: Vector2 = ui.player_status_anchor_global()
	assert_true(rings.visible)
	assert_lte(rings.global_position.y + rings.size.y, anchor.y + 1.5)
	# 有骨骼小猫时锚点在帽顶/血条上方；否则退回玩家块顶边中点
	if ui._skel_player != null and is_instance_valid(ui._skel_player):
		assert_almost_eq(anchor.y, ui._skel_player.status_anchor_global_position().y, 1.0)
	else:
		var top: Vector2 = ui._cell_unit_global_center(CombatConstants.PLAYER_CELL) - Vector2(0, ui.UNIT_H * 0.5)
		assert_almost_eq(anchor.y, top.y, 1.0)
	cs.enemies[0].burn_stacks = 3
	ui._update_burn_vfx()
	var unit: Control = ui.board_row.get_child(cs.enemies[0].cell).get_node("UnitBody")
	assert_not_null(unit.get_node_or_null("BurnVfx"))
	ui._spawn_explosion_vfx(cs.enemies[0].cell, 2)
	var vfx = ui.find_child("ExplosionVfx", true, false)
	assert_not_null(vfx)
	assert_gt(vfx.z_index, ui.Z_DMG_FLOAT)
	assert_gt(vfx.span_px, float(ui.CELL_W) * 2.0)
	assert_eq(ui.BLOOD_TRAIL_HISTORY, 8)
