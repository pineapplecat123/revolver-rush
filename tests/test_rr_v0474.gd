extends GutTest
## v0.4.74：店铺从右屏外连续进场、两门同尺寸、门槛贴地、近快远远的视差。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func _boot_campaign(seed_v: int = 47401) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_campaign(seed_v)
	cs.campaign_instant_transitions = false
	if cs.campaign_offer_pending:
		assert_true(cs.campaign_pick_opening(0))
	return cs


func _force_walk_to_shop(cs: CombatState) -> void:
	if cs.campaign_phase == CampaignRules.PHASE_ENTER or cs.campaign_walk_left > 0.0:
		cs.campaign_skip_walk()
	cs.campaign_wave = maxi(1, CampaignRules.wave_count(cs.campaign_floor, cs.campaign_segment))
	cs.enemies.clear()
	cs.reward_pending = false
	cs.pending_levelups = 0
	cs.campaign_try_advance()


func test_version_is_0_4_74() -> void:
	assert_eq(GameVersion.STRING, "0.4.74")
	assert_true("0.4.74" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_both_doors_share_geometry() -> void:
	assert_eq(CampaignRules.shop_house_door_w(), ShopHouse.DOOR_W)
	assert_eq(CampaignRules.shop_house_door_h(), ShopHouse.DOOR_H)
	assert_eq(CampaignRules.shop_house_door_frame(), ShopHouse.DOOR_FRAME)
	assert_eq(CampaignRules.shop_house_threshold(), ShopHouse.THRESHOLD_H)
	assert_eq(ShopHouse.ENTRANCE_W, ShopHouse.EXIT_W)
	assert_eq(ShopHouse.DOOR_H, ShopHouse.EXIT_DOOR_H)
	assert_eq(CampaignRules.shop_house_entrance_half_w(), CampaignRules.shop_house_exit_half_w())
	assert_eq(CampaignRules.shop_house_entrance_half_w(), CampaignRules.shop_house_door_w() * 0.5)
	assert_gt(CampaignRules.shop_house_exit_x() - CampaignRules.shop_house_entrance_x(), 80.0)
	var house := ShopHouse.new()
	add_child_autofree(house)
	assert_almost_eq(house.entrance_inner_rect_global().size.x, house.exit_inner_rect_global().size.x, 0.01)
	assert_almost_eq(house.entrance_inner_rect_global().size.y, house.exit_inner_rect_global().size.y, 0.01)


func test_house_starts_fully_offscreen_right() -> void:
	var cs := _boot_campaign(47410)
	_force_walk_to_shop(cs)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	assert_almost_eq(cs.shop_house_progress(), 0.0, 0.001)
	var cat_x := 80.0
	var left: float = cs.shop_house_left_at(cat_x)
	var roof := 8.0
	var view_r: float = CampaignRules.shop_house_view_width()
	assert_gt(left - roof, view_r, "开场时屋顶也要在设计宽度右外侧，left=%s" % left)
	assert_gt(left + CampaignRules.shop_house_width() + roof, view_r)
	# 还没走进去，不能直接把房子放在门口
	var final_left: float = cat_x - CampaignRules.shop_house_entrance_x()
	assert_gt(left - final_left, CampaignRules.shop_house_view_width() * 0.5)


func test_approach_and_exit_are_monotonic_and_continuous() -> void:
	var cs := _boot_campaign(47411)
	_force_walk_to_shop(cs)
	var cat_x := 80.0
	var dt := 1.0 / 30.0
	var prev: float = cs.shop_house_left_at(cat_x)
	var start: float = prev
	var max_step: float = CampaignRules.shop_walk_speed_px() * dt + 1.5
	var steps := 0
	while cs.shop_house_seq == CombatState.SHOP_HOUSE_APPROACH:
		cs.tick_shop_house(dt)
		var left: float = cs.shop_house_left_at(cat_x)
		assert_lt(left, prev + 0.001, "进场过程房屋应持续向左，不能跳回或原地出现")
		assert_gt(left, prev - max_step, "单帧位移过大，像瞬移到终点 prev=%s left=%s" % [prev, left])
		prev = left
		steps += 1
		if steps > 400:
			assert_true(false, "approach did not finish")
			return
	assert_gt(steps, 30, "进场应能在成片里看清，不能一晃而过")
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_INSIDE)
	assert_true(cs.shop_touch_pending, "进门后才打开商店")
	assert_almost_eq(cs.shop_house_left_at(cat_x), cat_x - CampaignRules.shop_house_entrance_x(), 0.6)
	# 走过的总路程应接近从右屏外到门口
	assert_gt(start - prev, CampaignRules.shop_house_view_width() * 0.8)

	cs.shop_hold = true
	cs.campaign_on_shop_left()
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_EXITING)
	assert_eq(cs.alive_enemies().size(), 0, "出门途中不刷下一波")
	prev = cs.shop_house_left_at(cat_x)
	steps = 0
	while cs.shop_house_seq == CombatState.SHOP_HOUSE_EXITING:
		cs.tick_shop_house(dt)
		var left2: float = cs.shop_house_left_at(cat_x) if cs.shop_house_seq != CombatState.SHOP_HOUSE_NONE else prev - 0.01
		if cs.shop_house_seq == CombatState.SHOP_HOUSE_NONE:
			break
		assert_lt(left2, prev + 0.001)
		assert_gt(left2, prev - max_step)
		prev = left2
		steps += 1
		if steps > 400:
			assert_true(false, "exit did not finish")
			return
	# 结束时应整栋在左屏外
	var end_left: float = prev
	assert_lt(end_left + CampaignRules.shop_house_width() + 8.0, CampaignRules.shop_house_view_width() * 0.0 + 1.0)
	assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_gt(cs.alive_enemies().size(), 0, "整栋离开后才继续遭遇")
	assert_eq(cs.campaign_segment, 2)


func test_parallax_near_matches_gore_and_freezes() -> void:
	assert_gt(CampaignBackdrop.DEPTH_NEAR, CampaignBackdrop.DEPTH_MID)
	assert_gt(CampaignBackdrop.DEPTH_MID, CampaignBackdrop.DEPTH_FAR)
	assert_almost_eq(CampaignBackdrop.DEPTH_NEAR, 1.0, 0.001)
	var bg := CampaignBackdrop.new()
	add_child_autofree(bg)
	bg.configure(Vector2(720, 1280), 300.0, 20.0, 700.0)
	var speed: float = -CampaignRules.shop_walk_speed_px()
	bg.advance(1.0, speed)
	assert_almost_eq(bg.shift_for(CampaignBackdrop.DEPTH_NEAR), speed, 0.01)
	assert_lt(absf(bg.shift_for(CampaignBackdrop.DEPTH_MID)), absf(bg.shift_for(CampaignBackdrop.DEPTH_NEAR)))
	assert_lt(absf(bg.shift_for(CampaignBackdrop.DEPTH_FAR)), absf(bg.shift_for(CampaignBackdrop.DEPTH_MID)))
	var mid0: float = bg.shift_for(CampaignBackdrop.DEPTH_MID)
	bg.advance(1.0, 0.0)
	assert_almost_eq(bg.shift_for(CampaignBackdrop.DEPTH_MID), mid0, 0.001)

	var cs := _boot_campaign(47412)
	cs.campaign_skip_walk()
	# 战斗慢走
	if cs.campaign_phase == CampaignRules.PHASE_COMBAT:
		var combat_drift: float = cs.campaign_world_drift_px_per_sec()
		assert_lt(combat_drift, 0.0)
		assert_almost_eq(absf(combat_drift), CampaignRules.walk_combat_tempo() * CampaignRules.walk_world_drift_px(), 0.05)
	_force_walk_to_shop(cs)
	var shop_drift: float = cs.campaign_world_drift_px_per_sec()
	assert_lt(shop_drift, 0.0)
	assert_almost_eq(absf(shop_drift), CampaignRules.shop_walk_speed_px(), 0.05)
	assert_gt(absf(shop_drift), CampaignRules.walk_combat_tempo() * CampaignRules.walk_world_drift_px())
	cs.shop_touch_pending = true
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)
	cs.shop_touch_pending = false
	cs.reward_pending = true
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)
	cs.reward_pending = false
	cs._set_phase(CombatState.Phase.LOST)
	assert_eq(cs.campaign_world_drift_px_per_sec(), 0.0)


func test_rendered_floor_contact_and_offscreen_start() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui.state.start_campaign(47420)
	if ui.state.campaign_offer_pending:
		assert_true(ui.state.campaign_pick_opening(0))
	ui.state.campaign_instant_transitions = false
	_force_walk_to_shop(ui.state)
	if ui.has_method("_fit_combat_viewport"):
		ui._fit_combat_viewport(Vector2(720, 1280))
	ui.clip_contents = true
	ui._refresh()
	ui._ensure_campaign_backdrop()
	ui._ensure_shop_house()
	ui._sync_shop_house()
	await wait_process_frames(3)
	var house = ui.get("_shop_house")
	assert_not_null(house)
	assert_true(house.visible)
	var origin: Vector2 = house.house_origin_global()
	var gy: float = ui._board_ground_global_y()
	assert_almost_eq(origin.y, gy, 1.0, "门槛/墙根应贴走道顶边")
	# 开场整栋在战斗控件右外侧
	assert_gt(origin.x - 8.0, ui.global_position.x + ui.size.x - 2.0)
	# 小猫位置不变（不跟房子一起被带走）
	var cat = ui.get("_skel_player")
	assert_not_null(cat)
	var cat0: float = cat.global_position.x
	ui.state.tick_shop_house(0.25)
	ui._sync_shop_house()
	await wait_process_frames(2)
	assert_almost_eq(cat.global_position.x, cat0, 1.5)
	assert_lt(house.house_origin_global().x, origin.x)
	assert_almost_eq(house.house_origin_global().y, gy, 1.0)
	# 进门后才 pending 商店
	assert_false(ui.state.shop_touch_pending)
	ui.state.tick_shop_house(CampaignRules.walk_to_shop_sec() + 0.05)
	ui._sync_shop_house()
	assert_true(ui.state.shop_touch_pending)
	assert_almost_eq(house.house_origin_global().y, ui._board_ground_global_y(), 1.0)
	# 出门结束前不应刷怪
	ui.state.campaign_on_shop_left()
	ui._sync_shop_house()
	assert_eq(ui.state.alive_enemies().size(), 0)
	ui.state.tick_shop_house(CampaignRules.walk_from_shop_sec() + 0.05)
	ui._sync_shop_house()
	assert_eq(ui.state.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
	assert_gt(ui.state.alive_enemies().size(), 0)
