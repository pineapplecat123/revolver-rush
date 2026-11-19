extends GutTest
## v0.4.69：闯关静止战斗底；地上碎块随走路左移（战斗慢、进店快），暂停/他模式不移。


func before_each() -> void:
	DataRegistry.reload()
	CampaignRules.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func after_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func test_version_is_at_least_0_4_69() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.69") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.69" in log)
	assert_true("静止" in log or "滚动背景" in log)


func _boot_campaign(seed: int = 11) -> CombatState:
	var cs := CombatState.new()
	cs.start_campaign(seed)
	cs.campaign_instant_transitions = true
	assert_true(cs.campaign_pick_opening(0))
	cs.campaign_skip_walk()
	return cs


func _settled_piece(gore: GoreLayer, pos: Vector2) -> Dictionary:
	var node := Node2D.new()
	gore.add_child(node)
	node.global_position = pos
	var rec := {
		"node": node,
		"vel": Vector2.ZERO,
		"spin": 0.0,
		"rest_t": 0.0,
		"bounces": 3,
		"age": 0.0,
		"trail": GoreLayer.BLOOD_TRAIL,
		"trail_t": 0.0,
	}
	gore._pieces.append(rec)
	return rec


func test_drift_slow_vs_fast_and_pause() -> void:
	var gore: GoreLayer = add_child_autofree(GoreLayer.new())
	await wait_process_frames(1)
	var a := _settled_piece(gore, Vector2(400, 200))
	var b := _settled_piece(gore, Vector2(420, 200))
	var c := _settled_piece(gore, Vector2(440, 200))
	var x0a: float = a["node"].global_position.x
	var x0b: float = b["node"].global_position.x
	var x0c: float = c["node"].global_position.x
	var slow: float = -CampaignRules.walk_combat_tempo() * CampaignRules.walk_world_drift_px()
	var fast: float = -CampaignRules.walk_shop_tempo() * CampaignRules.walk_world_drift_px()
	assert_lt(fast, slow, "shop drift is more leftward (faster back)")
	assert_lt(slow, 0.0)

	# GoreLayer 单帧积分上限 0.05s，测试按该步长累加，避免一次喂 0.25 被截断。
	var step := 0.05
	var steps := 5
	gore.set_world_drift(slow)
	for _i in steps:
		gore._process(step)
	var d_slow: float = a["node"].global_position.x - x0a
	assert_almost_eq(d_slow, slow * step * float(steps), 0.05)
	assert_lt(d_slow, 0.0, "settled gore moves left during combat walk")

	gore.set_world_drift(fast)
	for _j in steps:
		gore._process(step)
	var d_fast: float = b["node"].global_position.x - x0b - d_slow
	assert_almost_eq(d_fast, fast * step * float(steps), 0.05)
	assert_lt(d_fast, d_slow, "shop-walk drift covers more ground in the same time")

	var x_before_pause: float = c["node"].global_position.x
	gore.set_world_drift(0.0)
	for _k in steps:
		gore._process(step)
	assert_almost_eq(c["node"].global_position.x, x_before_pause, 0.01, "paused / no walk: settled gore stays")


func test_drift_cleans_up_offscreen_and_keeps_cap() -> void:
	var gore: GoreLayer = add_child_autofree(GoreLayer.new())
	await wait_process_frames(1)
	var rec := _settled_piece(gore, Vector2(-120, 200))
	gore.set_world_drift(-80.0)
	gore._process(0.05)
	assert_eq(gore.active_count(), 0, "offscreen settled gore is recycled")


func test_campaign_drift_rates_pause_and_other_modes() -> void:
	var cs := _boot_campaign(5)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
	var combat_d: float = cs.campaign_world_drift_px_per_sec()
	assert_almost_eq(combat_d, -CampaignRules.walk_combat_tempo() * CampaignRules.walk_world_drift_px(), 0.01)

	cs.campaign_phase = CampaignRules.PHASE_WALK_SHOP
	cs.campaign_walk_left = 1.0
	var shop_d: float = cs.campaign_world_drift_px_per_sec()
	assert_almost_eq(shop_d, -CampaignRules.walk_shop_tempo() * CampaignRules.walk_world_drift_px(), 0.01)
	assert_lt(shop_d, combat_d)

	cs.campaign_phase = CampaignRules.PHASE_COMBAT
	cs.reward_pending = true
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)
	cs.reward_pending = false
	cs.shop_hold = true
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)
	cs.shop_hold = false
	cs._lose_hp()
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)

	var rush := CombatState.new()
	rush.start_rush(21, FireResolver.ID_WRATH)
	assert_false(rush.campaign_mode)
	assert_eq(rush.campaign_world_drift_px_per_sec(), 0.0)

	var box := CombatState.new()
	box.start_sandbox(21, FireResolver.ID_WRATH, true)
	assert_false(box.campaign_mode)
	assert_eq(box.campaign_world_drift_px_per_sec(), 0.0)


func test_campaign_ui_has_static_bg_and_walk_stays_on() -> void:
	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui._fit_combat_viewport(Vector2(720, 1280))
	await wait_process_frames(4)
	assert_true(ui.state.campaign_mode)
	assert_true(ui.state.campaign_pick_opening(0))
	ui.state.campaign_instant_transitions = true
	ui.state.campaign_skip_walk()
	ui._refresh()
	await wait_process_frames(3)
	assert_eq(ui.state.campaign_phase, CampaignRules.PHASE_COMBAT)
	# 没有滚动景物节点
	assert_null(ui.find_child("CampaignScenery", true, false))
	var top: Node = ui.get_node_or_null("Margin/RootVBox/TopPanel")
	if top != null:
		assert_null(top.get_node_or_null("CampaignScenery"))
	var cat = ui.get("_skel_player")
	assert_not_null(cat)
	assert_true(cat.is_walking(), "combat walk remains")
	var thigh0: float = (cat.bones["ThighF"] as Bone2D).rotation
	for _i in 8:
		cat._process(0.03)
	assert_ne((cat.bones["ThighF"] as Bone2D).rotation, thigh0)
	# 地上碎块会左移，且 drift 已接到 GoreLayer
	ui._ensure_gore_layer()
	ui._apply_campaign_presentation()
	var gore: GoreLayer = ui.get("_gore_layer")
	assert_not_null(gore)
	assert_almost_eq(gore.world_drift_px_per_sec, ui.state.campaign_world_drift_px_per_sec(), 0.05)
	assert_lt(gore.world_drift_px_per_sec, 0.0)
	var rec := {
		"node": Node2D.new(), "vel": Vector2.ZERO, "spin": 0.0, "rest_t": 0.0,
		"bounces": 3, "age": 0.0, "trail": GoreLayer.BLOOD_TRAIL, "trail_t": 0.0,
	}
	gore.add_child(rec["node"])
	rec["node"].global_position = Vector2(500, 200)
	gore._pieces.append(rec)
	var x0: float = rec["node"].global_position.x
	for _g in 5:
		gore._process(0.05)
	assert_lt(rec["node"].global_position.x, x0)

	# 暂停选择时碎块停、猫也不走
	ui.state.reward_pending = true
	ui._apply_campaign_presentation()
	assert_eq(gore.world_drift_px_per_sec, 0.0)
	assert_false(cat.is_walking())
	ui.state.reward_pending = false
	ui._apply_campaign_presentation()
	assert_true(cat.is_walking())


func test_rush_and_sandbox_gore_do_not_drift() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui._fit_combat_viewport(Vector2(720, 1280))
	await wait_process_frames(4)
	if ui.get("_dev_open") == true:
		ui._toggle_dev()
	assert_true(ui.state.sandbox_mode)
	assert_false(ui.state.campaign_mode)
	ui._ensure_gore_layer()
	var gore: GoreLayer = ui.get("_gore_layer")
	ui._apply_campaign_presentation()
	assert_eq(gore.world_drift_px_per_sec, 0.0)
	var node := Node2D.new()
	gore.add_child(node)
	node.global_position = Vector2(400, 200)
	gore._pieces.append({
		"node": node, "vel": Vector2.ZERO, "spin": 0.0, "rest_t": 0.0,
		"bounces": 3, "age": 0.0, "trail": GoreLayer.BLOOD_TRAIL, "trail_t": 0.0,
	})
	var x0: float = node.global_position.x
	for _g2 in 6:
		gore._process(0.05)
	assert_almost_eq(node.global_position.x, x0, 0.01)
	CombatState.boot_sandbox = false
