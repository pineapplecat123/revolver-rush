extends GutTest
## v0.4.73 复核：用渲染出来的像素对照引擎门洞矩形，而不是只查 occlusion 字符串。
## 门外走近时，猫可以画在左墙前面（合法前景）。一旦 door_in / inside / door_out，
## 门洞以外的墙面上不应再出现毛色（门槛线允许极少的像素化脚尖）。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func _boot_ui() -> Node:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	ui.state.start_campaign(47301)
	if ui.state.campaign_offer_pending:
		assert_true(ui.state.campaign_pick_opening(0))
	ui.state.campaign_instant_transitions = false
	if ui.state.campaign_phase == CampaignRules.PHASE_ENTER or ui.state.campaign_walk_left > 0.0:
		ui.state.campaign_skip_walk()
	ui.state.campaign_wave = maxi(1, CampaignRules.wave_count(ui.state.campaign_floor, ui.state.campaign_segment))
	ui.state.enemies.clear()
	ui.state.reward_pending = false
	ui.state.pending_levelups = 0
	ui.state.shop_hold = false
	ui.state.shop_touch_pending = false
	ui.state.campaign_try_advance()
	if ui.has_method("_fit_combat_viewport"):
		ui._fit_combat_viewport(Vector2(720, 1280))
	ui._refresh()
	ui._ensure_campaign_backdrop()
	ui._ensure_shop_house()
	ui._sync_shop_house()
	return ui


func _tick_house(ui, dt: float) -> void:
	ui.state.tick_shop_house(dt)
	if ui.has_method("_apply_campaign_presentation"):
		ui._apply_campaign_presentation()
	ui._sync_shop_house()
	if ui.has_method("_sync_campaign_backdrop"):
		ui._sync_campaign_backdrop()
	var cat = ui.get("_skel_player")
	if cat != null and cat.has_method("_process"):
		cat._process(dt)


func _is_fur(c: Color) -> bool:
	if c.r > 0.55 and c.g > 0.25 and c.r > c.g + 0.05 and c.r > c.b + 0.08:
		return true
	if c.r > 0.65 and c.g > 0.55 and c.b > 0.38 and c.r > c.b and abs(c.r - c.g) < 0.22:
		return true
	return false


func _measure(ui, which: String) -> Dictionary:
	await wait_process_frames(2)
	var empty := {
		"occ": "",
		"in": 0,
		"leak_l": 0,
		"leak_r": 0,
		"wall_leak": 0,
		"drawn": false,
		"door": Rect2(),
	}
	# headless / dummy renderer 没有可贴的屏幕纹理，不能当失败。
	if DisplayServer.get_name() == "headless":
		empty["occ"] = ui.state.shop_house_occlusion_at(ui._player_foot_global_x())
		return empty
	var vp: Viewport = ui.get_viewport()
	if vp == null:
		return empty
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return empty
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 8 or img.get_height() < 8:
		return empty
	var house = ui.get("_shop_house")
	if house == null:
		return empty
	var door: Rect2
	if which == "exit":
		door = house.exit_inner_rect_global()
	else:
		door = house.entrance_inner_rect_global()
	var occ: String = ui.state.shop_house_occlusion_at(ui._player_foot_global_x())
	var left := int(floor(door.position.x))
	var right := int(ceil(door.position.x + door.size.x))
	var top := int(floor(door.position.y))
	var ground := int(ceil(door.position.y + door.size.y))
	var x0 := maxi(0, left - 40)
	var x1 := mini(img.get_width(), maxi(left + 1, right + 40))
	var y0 := maxi(0, top - 8)
	var y1 := mini(img.get_height(), ground + 8)
	if x1 <= x0 or y1 <= y0:
		empty["occ"] = occ
		empty["door"] = door
		return empty
	var in_n := 0
	var leak_l := 0
	var leak_r := 0
	var wall_leak := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			if not _is_fur(img.get_pixel(x, y)):
				continue
			if x >= left and x < right and y >= top and y <= ground:
				in_n += 1
				continue
			# 门槛线以下的走道不算「画在墙面上」。
			if y > ground:
				continue
			if x < left:
				leak_l += 1
				if y < ground - 2:
					wall_leak += 1
			elif x >= right:
				leak_r += 1
				if y < ground - 2:
					wall_leak += 1
	return {
		"occ": occ,
		"in": in_n,
		"leak_l": leak_l,
		"leak_r": leak_r,
		"wall_leak": wall_leak,
		"drawn": in_n + leak_l + leak_r > 40,
		"door": door,
	}


func test_inner_door_rects_match_house_constants() -> void:
	var ui := _boot_ui()
	await wait_process_frames(2)
	var house = ui.get("_shop_house")
	assert_not_null(house)
	var origin: Vector2 = house.house_origin_global()
	var ent: Rect2 = house.entrance_inner_rect_global()
	var ex: Rect2 = house.exit_inner_rect_global()
	assert_almost_eq(ent.size.x, house.ENTRANCE_W, 0.01)
	assert_almost_eq(ent.size.y, house.DOOR_H, 0.01)
	assert_almost_eq(ex.size.x, house.EXIT_W, 0.01)
	assert_almost_eq(ex.size.y, house.EXIT_DOOR_H, 0.01)
	assert_almost_eq(ent.position.x, origin.x + house.ENTRANCE_X - house.ENTRANCE_W * 0.5, 0.01)
	assert_almost_eq(ex.position.x, origin.x + house.EXIT_X - house.EXIT_W * 0.5, 0.01)
	assert_gt(ex.position.x - ent.position.x, 80.0)
	assert_almost_eq(ent.position.y + ent.size.y, origin.y, 0.01)
	assert_almost_eq(ex.position.y + ex.size.y, origin.y, 0.01)


func test_approach_may_draw_cat_in_front_of_left_wall() -> void:
	var ui := _boot_ui()
	assert_eq(ui.state.shop_house_seq, CombatState.SHOP_HOUSE_APPROACH)
	var approach: float = CampaignRules.walk_to_shop_sec()
	var acc := 0.0
	while acc < approach * 0.55:
		_tick_house(ui, 1.0 / 30.0)
		acc += 1.0 / 30.0
	await wait_process_frames(1)
	var occ: String = ui.state.shop_house_occlusion_at(ui._player_foot_global_x())
	assert_eq(occ, "outside")
	var m: Dictionary = await _measure(ui, "enter")
	if m["drawn"]:
		assert_eq(m["occ"], "outside")
		assert_gt(int(m["leak_l"]), 0, "走近时猫应画在入口左侧墙前，这是合法前景")
		assert_eq(int(m["leak_r"]), 0)


func test_door_in_pixels_stay_inside_opening() -> void:
	var ui := _boot_ui()
	var approach: float = CampaignRules.walk_to_shop_sec()
	var acc := 0.0
	while acc < approach + 0.02:
		_tick_house(ui, 1.0 / 30.0)
		acc += 1.0 / 30.0
	await wait_process_frames(1)
	var occ: String = ui.state.shop_house_occlusion_at(ui._player_foot_global_x())
	assert_eq(occ, "door_in")
	var drawn_poses := 0
	var worst_wall := 0
	var worst_sill := 0
	for i in 8:
		var cat = ui.get("_skel_player")
		if cat != null and cat.has_method("_process"):
			cat._process(1.0 / 30.0)
		ui._sync_shop_house()
		var m: Dictionary = await _measure(ui, "enter")
		assert_eq(m["occ"], "door_in")
		if m["drawn"]:
			drawn_poses += 1
			worst_wall = maxi(worst_wall, int(m["wall_leak"]))
			worst_sill = maxi(worst_sill, int(m["leak_l"]) + int(m["leak_r"]))
			assert_eq(int(m["wall_leak"]), 0, "进门后门洞以外的墙面上不应有毛色，wall_leak=%d pose=%d" % [int(m["wall_leak"]), i])
			assert_lte(int(m["leak_l"]) + int(m["leak_r"]), 8, "门槛线脚尖像素过多 L=%d R=%d pose=%d" % [int(m["leak_l"]), int(m["leak_r"]), i])
			assert_gt(int(m["in"]), 200)
	if drawn_poses > 0:
		assert_eq(worst_wall, 0)
		assert_lte(worst_sill, 8)


func test_exit_door_pixels_stay_inside_opening() -> void:
	var ui := _boot_ui()
	var approach: float = CampaignRules.walk_to_shop_sec()
	var acc := 0.0
	while acc < approach + 0.02:
		_tick_house(ui, 1.0 / 30.0)
		acc += 1.0 / 30.0
	if ui.state.shop_touch_pending:
		ui.state.campaign_on_shop_left()
	ui._sync_shop_house()
	var exit_sec: float = CampaignRules.walk_from_shop_sec()
	var ex := 0.0
	var seen_inside := false
	var seen_door_out := false
	var drawn_out := 0
	var worst_wall := 0
	while ex < exit_sec + 0.05:
		_tick_house(ui, 1.0 / 30.0)
		ex += 1.0 / 30.0
		var occ: String = ui.state.shop_house_occlusion_at(ui._player_foot_global_x())
		if occ == "inside":
			seen_inside = true
			var mid: Dictionary = await _measure(ui, "exit")
			if mid["drawn"]:
				# 还没到出门洞时，不应在出口左侧的实墙上露出身体（门槛线除外）。
				assert_eq(int(mid["wall_leak"]), 0, "室内阶段墙面泄漏 %d t=%.2f" % [int(mid["wall_leak"]), ex])
		elif occ == "door_out":
			seen_door_out = true
			var m: Dictionary = await _measure(ui, "exit")
			if m["drawn"]:
				drawn_out += 1
				worst_wall = maxi(worst_wall, int(m["wall_leak"]))
				assert_eq(int(m["wall_leak"]), 0, "出门后门洞以外的墙面上不应有毛色 t=%.2f" % ex)
				assert_lte(int(m["leak_l"]) + int(m["leak_r"]), 8, "出门门槛线脚尖过多 L=%d R=%d t=%.2f" % [int(m["leak_l"]), int(m["leak_r"]), ex])
				assert_gt(int(m["in"]), 200)
	assert_true(seen_inside, "出门过程应经过室内墙后")
	assert_true(seen_door_out, "出门过程应经过另一扇门")
	if drawn_out > 0:
		assert_eq(worst_wall, 0)
