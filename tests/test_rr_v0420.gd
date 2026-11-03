extends GutTest
## v0.4.20：沙盒大按钮 + 默认 3 木桩 + DPS/单次最大统计；幽灵始终带 TTL；墓碑新规则；临时罪孽 20% / 10s。

const G := FireResolver.ID_GHOST


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _sandbox(seed_v: int = 42000) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH)
	return cs


func _ghosts_in_bag(cs: CombatState) -> Array:
	var out: Array = []
	for i in cs.bag.size():
		if int(cs.bag[i]) == G:
			out.append(Magazine.temp_value(cs.bag_temp[i]))
	return out


func test_version_is_0_4_20() -> void:
	assert_eq(GameVersion.STRING, "0.4.20")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.20"' in text)


func test_temp_sin_numbers_and_split_ttls() -> void:
	assert_almost_eq(CombatConstants.LOAD_TEMP_SIN_CHANCE, 0.20, 0.0001)
	assert_eq(CombatConstants.TEMP_SIN_LIFETIME_SEC, 10.0)
	# 幽灵/小石头/嫉妒复制与临时罪孽拆开，仍 18 秒
	assert_eq(CombatConstants.GHOST_TTL_SEC, 18.0)
	assert_eq(CombatConstants.PEBBLE_TTL_SEC, 18.0)
	assert_eq(CombatConstants.ENVY_COPY_TTL_SEC, 18.0)


# —— 沙盒：默认木桩 ——

func test_sandbox_starts_with_three_dummies() -> void:
	var cs := _sandbox(42001)
	assert_eq(cs.enemies.size(), 3)
	var cells: Array = []
	for e in cs.enemies:
		assert_true(e.is_dummy)
		assert_eq(e.mobility, 0)
		cells.append(e.cell)
	cells.sort()
	assert_eq(cells, [3, 5, 7])
	# 仍可手动增删
	assert_not_null(cs.sandbox_spawn_dummy(500, 9))
	assert_eq(cs.enemies.size(), 4)
	cs.sandbox_clear_enemies()
	assert_eq(cs.enemies.size(), 0)
	assert_eq(cs.sandbox_spawn_default_dummies(), 3)
	# 位置都被占时不重复摆
	assert_eq(cs.sandbox_spawn_default_dummies(), 0)


func test_sandbox_reset_respawns_three_dummies() -> void:
	var cs := _sandbox(42002)
	cs.sandbox_clear_enemies()
	cs.sandbox_reset()
	assert_eq(cs.enemies.size(), 3)


# —— 伤害统计 ——

func test_dps_window_and_recent_max_hit() -> void:
	var cs := _sandbox(42003)
	var e: EnemyInstance = cs.enemies[0]
	cs.elapsed_sec = 0.0
	cs.damage_stats_reset()
	cs.elapsed_sec = 10.0
	cs._notify_enemy_damage(e, 30, "")
	cs.elapsed_sec = 12.0
	cs._notify_enemy_damage(e, 20, "")
	# 窗口 (7,12]：30+20=50，已过 12 秒 → 除以 5 秒
	assert_eq(cs.damage_stats_window_sum(12.0), 50)
	assert_almost_eq(cs.damage_stats_dps(12.0), 10.0, 0.001)
	assert_eq(cs.damage_stats_recent_max_hit(12.0), 30)
	# t=16：30 那下（t=10）出窗口了
	assert_almost_eq(cs.damage_stats_dps(16.0), 4.0, 0.001)
	assert_eq(cs.damage_stats_recent_max_hit(16.0), 20)
	# 都出窗口：DPS/最近最大归 0，但总伤害与历史峰值还在
	assert_eq(cs.damage_stats_dps(30.0), 0.0)
	assert_eq(cs.damage_stats_recent_max_hit(30.0), 0)
	assert_eq(cs.dmg_stats_total, 50)
	assert_eq(cs.dmg_stats_peak_hit, 30)
	assert_eq(cs.dmg_stats_hits, 2)
	assert_eq(e.dmg_taken_total, 50)


func test_dps_early_span_uses_elapsed_time_min_1s() -> void:
	var cs := _sandbox(42004)
	cs.elapsed_sec = 100.0
	cs.damage_stats_reset()
	cs.elapsed_sec = 102.0
	cs._notify_enemy_damage(cs.enemies[0], 10, "")
	# 清零后才过 2 秒：10/2
	assert_almost_eq(cs.damage_stats_dps(102.0), 5.0, 0.001)
	# 不足 1 秒按 1 秒算，避免开头一发就虚高
	cs.damage_stats_reset()
	cs.elapsed_sec = 102.2
	cs._notify_enemy_damage(cs.enemies[0], 10, "")
	assert_almost_eq(cs.damage_stats_dps(102.2), 10.0, 0.001)


func test_damage_stats_reset_clears_everything() -> void:
	var cs := _sandbox(42005)
	cs.elapsed_sec = 3.0
	cs._notify_enemy_damage(cs.enemies[0], 40, "")
	cs._notify_enemy_damage(cs.enemies[1], 7, "燃烧")
	assert_eq(cs.dmg_stats_total, 47)
	cs.damage_stats_reset()
	assert_eq(cs.dmg_stats_total, 0)
	assert_eq(cs.dmg_stats_peak_hit, 0)
	assert_eq(cs.dmg_stats_hits, 0)
	assert_eq(cs.damage_stats_recent_max_hit(), 0)
	assert_eq(cs.damage_stats_dps(), 0.0)
	for e in cs.enemies:
		assert_eq(e.dmg_taken_total, 0)


func test_stats_come_from_real_damage_including_dot() -> void:
	## 真打木桩：统计总伤害 = 木桩掉的血；燃烧 DoT 也计入。
	var cs := _sandbox(42006)
	cs.damage_stats_reset()
	var hp0: int = 0
	for e in cs.enemies:
		hp0 += e.hp
	cs.sandbox_set_muzzle("wrath", 2, 30.0)
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID, CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.fire_tap()
	cs.fire_tap()
	# 挂燃烧再推时间跑 DoT
	cs.sandbox_set_enemy_status({"burn": 5})
	cs.tick_combat_time(2.0)
	var hp1: int = 0
	for e in cs.enemies:
		hp1 += e.hp
	assert_gt(cs.dmg_stats_total, 0)
	assert_eq(cs.dmg_stats_total, hp0 - hp1, "stats total == hp actually lost")
	assert_gt(cs.dmg_stats_hits, 2, "DoT ticks count as separate hits")
	assert_gt(cs.dmg_stats_peak_hit, 0)


# —— 幽灵 TTL ——

func test_ghost_never_permanent_on_any_append() -> void:
	var cs := _sandbox(42007)
	cs.dev_clear_bag()
	cs._bag_append(G, false)
	cs.sandbox_add_ammo(G, 1, 0.0)
	cs.dev_add_ammo(G, 1)
	cs._discard_append(G, false)
	for tv in _ghosts_in_bag(cs):
		assert_eq(tv, CombatConstants.GHOST_TTL_SEC)
	assert_eq(Magazine.temp_value(cs.discard_temp[cs.discard.size() - 1]), CombatConstants.GHOST_TTL_SEC)
	# 沙盒手动把幽灵 TTL 写 0 也不会变永久
	assert_true(cs.sandbox_set_bag_temp(0, 0.0))
	assert_eq(Magazine.temp_value(cs.bag_temp[0]), CombatConstants.GHOST_TTL_SEC)


func test_bag_reset_keeps_ghost_remaining_ttl_and_drops_expired() -> void:
	var cs := CombatState.new(42008)
	cs.start_rush(42008, FireResolver.ID_GREED)
	cs._snapshot_combat_bag_baseline()
	cs.discard.clear()
	cs.discard_temp.clear()
	for id in cs.bag:
		cs._discard_append(int(id), false)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._discard_append(G, 7.0)
	cs._discard_append(G, 3.0)
	# 旧数据：已过期（0）的幽灵直接塞数组
	cs.discard.append(G)
	cs.discard_temp.append(0.0)
	assert_true(cs._reset_bag_in_combat())
	var lives := _ghosts_in_bag(cs)
	lives.sort()
	assert_eq(lives, [3.0, 7.0], "remaining TTL kept, expired dropped")
	# 继续倒计时、到期消失
	cs.tick_temp_sin_lifetimes(3.5)
	assert_eq(_ghosts_in_bag(cs).size(), 1)
	cs.tick_temp_sin_lifetimes(4.0)
	assert_eq(_ghosts_in_bag(cs).size(), 0)


func test_ghost_loaded_into_chamber_keeps_ttl() -> void:
	var cs := _sandbox(42009)
	cs.dev_clear_bag()
	cs._bag_append(G, 5.0)
	cs.magazine.clear()
	assert_eq(cs._fill_empty_chambers_with_ghosts(), 1)
	var s := cs.magazine.slots.find(G)
	assert_true(s >= 0)
	assert_eq(cs.magazine.slot_temp_life(s), 5.0)


# —— 墓碑新规则 ——

func _tomb_setup(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	cs.enemies.clear()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.dev_force_load([
		FireResolver.ID_TOMBSTONE,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	return cs


func test_tombstone_without_ghosts_spawns_two_ttl_ghosts() -> void:
	var cs := _tomb_setup(42010)
	var shots: Array = cs.fire_tap()
	var ghost_shots := 0
	for r in shots:
		if int(r.get("ammo_id", -1)) == G:
			ghost_shots += 1
	assert_eq(ghost_shots, 0, "no ghost fires this time")
	var lives := _ghosts_in_bag(cs)
	assert_eq(lives.size(), 2)
	for tv in lives:
		assert_eq(tv, CombatConstants.GHOST_TTL_SEC)
	assert_eq(999 - cs.enemies[0].hp, 2, "tombstone only")


func test_tombstone_with_ghosts_fires_all_and_spawns_none() -> void:
	var cs := _tomb_setup(42011)
	for _i in 3:
		cs._bag_append(G, 9.0)
	var left_events: Array = []
	cs.hooks.subscribe(&"on_bag_leave", func(p: Dictionary):
		if str(p.get("reason", "")) == "ghost_fire":
			left_events.append(p)
	)
	var virtual_ghost_shots: Array = []
	cs.hooks.subscribe(&"on_shot", func(p: Dictionary):
		if int(p.get("ammo_id", -1)) == G and bool(p.get("virtual", false)):
			virtual_ghost_shots.append(p)
	)
	cs.fire_tap()
	assert_eq(_ghosts_in_bag(cs).size(), 0, "bag ghosts all fired, none spawned")
	assert_eq(left_events.size(), 3)
	assert_eq(virtual_ghost_shots.size(), 3)
	assert_eq(999 - cs.enemies[0].hp, 2 + 3 * 2)


# —— UI ——

func test_sandbox_ui_controls_are_touch_sized_and_hud_shows() -> void:
	CombatState.boot_sandbox = true
	var scene = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(scene.state.sandbox_mode)
	assert_eq(scene.state.enemies.size(), 3)
	for tab in 5:
		scene._sandbox_select_tab(tab)
		await get_tree().process_frame
		var n_btn := 0
		for b in scene.dev_panel.find_children("*", "Button", true, false):
			if not (b as Button).is_visible_in_tree():
				continue
			n_btn += 1
			assert_true((b as Button).get_combined_minimum_size().y >= 56.0,
				"tab %d button '%s' too small" % [tab, (b as Button).text])
		assert_gt(n_btn, 3)
		assert_eq(scene.dev_panel.find_children("*", "SpinBox", true, false).size(), 0, "no tiny SpinBox arrows")
	var hud: Control = scene.get_node_or_null("SandboxStatsHud")
	assert_not_null(hud)
	assert_true(hud.visible)
	var clear_btn: Button = hud.find_child("StatsClear", true, false)
	assert_not_null(clear_btn)
	assert_true(clear_btn.get_combined_minimum_size().y >= 56.0)
	scene.state._notify_enemy_damage(scene.state.enemies[0], 12, "")
	scene._update_sandbox_stats_hud()
	assert_true("单次最大 12" in str(scene.sandbox_stats_text()["main"]))
	clear_btn.pressed.emit()
	assert_eq(scene.state.dmg_stats_total, 0)
