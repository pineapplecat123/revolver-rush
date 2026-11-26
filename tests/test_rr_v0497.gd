extends GutTest
## v0.4.97：去掉拉杆旁长条滑槽；奖励三选一改成三个正方形格子。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func test_version_is_0_4_97() -> void:
	assert_eq(GameVersion.STRING, "0.4.97")


func test_lever_has_no_travel_track_bar() -> void:
	var cu: GumballCloseup = autofree(GumballCloseup.new())
	cu.size = Vector2(720, 1280)
	cu.present()
	assert_false(cu.draws_lever_travel_track())
	assert_true(cu.lever_is_mounted_on_body())
	assert_gt(cu.lever_knob_radius(), 20.0)
	assert_false(cu.draws_globe_lid())


func test_base_damage_line_uses_number_or_formula() -> void:
	assert_eq(DataRegistry.format_ammo_base_damage_line(CombatConstants.INVALID_AMMO_ID), "基础伤害：0")
	var white_line := DataRegistry.format_ammo_base_damage_line(CombatConstants.WHITE_AMMO_ID)
	assert_true(white_line.begins_with("基础伤害："), white_line)
	assert_false(white_line.contains("…"))
	var found_formula := false
	for row in DataRegistry.all_ammo():
		var aid := int(row.get("id", 0))
		if row.get("base_damage", null) == null and aid > 0:
			assert_eq(DataRegistry.format_ammo_base_damage_line(aid), "基础伤害：公式")
			found_formula = true
			break
	assert_true(found_formula)


func _assert_three_square_cells(ui, ammo_ids: Array) -> void:
	assert_eq(ui.reward_choices.get_child_count(), 3)
	assert_true(ui.reward_choices is HBoxContainer)
	var btns: Array = ui.reward_choice_buttons()
	assert_eq(btns.size(), 3)
	var xs: Array = []
	for i in 3:
		var wrap: Control = ui.reward_choices.get_child(i) as Control
		assert_not_null(wrap)
		if wrap is AspectRatioContainer:
			assert_almost_eq((wrap as AspectRatioContainer).ratio, 1.0, 0.001)
		var btn: Button = btns[i]
		assert_eq(btn.get_parent(), wrap)
		var min_s: Vector2 = wrap.custom_minimum_size
		assert_gte(min_s.x, 200.0)
		assert_gte(min_s.y, 200.0)
		assert_almost_eq(min_s.x, min_s.y, 0.5, "格子应是正方形")
		var ball: Control = btn.find_child("RewardBullet", true, false) as Control
		var dmg: Label = btn.find_child("RewardDamage", true, false) as Label
		var desc: Label = btn.find_child("RewardDesc", true, false) as Label
		assert_not_null(ball, "中间要有子弹")
		assert_not_null(dmg, "下面要有基础伤害")
		assert_not_null(desc, "再下面要有游戏内描述")
		var aid: int = int(ammo_ids[i])
		assert_eq(int(ball.get_meta("ammo_id")), aid)
		assert_eq(dmg.text, DataRegistry.format_ammo_base_damage_line(aid))
		var want: String = DataRegistry.ammo_game_description(aid)
		if want.is_empty():
			want = DataRegistry.DEFAULT_AMMO_GAME_DESCRIPTION
		assert_eq(desc.text, want, "描述必须完整，不能截成短摘要或省略号")
		assert_false(desc.text.contains("…"))
		assert_eq(desc.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
		assert_eq(desc.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING)
		assert_false(desc.clip_text)
		assert_true(bool(desc.get_meta("reward_desc_italic")))
		var font: Font = desc.get_theme_font("font")
		assert_true(font is FontVariation, "游戏内描述应是斜体字")
		var fv := font as FontVariation
		assert_gt(fv.variation_transform.x.y, 0.1)
		# 子弹在伤害/描述之上（中间偏上）。
		assert_lt(ball.position.y, dmg.position.y)
		assert_lt(dmg.position.y, desc.position.y)
		xs.append(wrap.position.x)
	assert_lt(xs[0], xs[1], "左中右排列")
	assert_lt(xs[1], xs[2], "左中右排列")


func test_levelup_reward_picker_uses_three_square_cells() -> void:
	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	CombatState.boot_campaign = false
	if ui.get_viewport() != null:
		ui.get_viewport().size = Vector2i(720, 1280)
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var cs: CombatState = ui.state
	cs.campaign_instant_transitions = true
	if cs.campaign_offer_pending:
		cs.campaign_pick_opening(0)
	cs.pending_levelups = 1
	cs.reward_pending = true
	cs.reward_choices = [CombatConstants.WHITE_AMMO_ID, 41, 52] as Array[int]
	ui._open_reward_panel_now()
	await wait_process_frames(3)
	assert_true(ui._reward_open)
	_assert_three_square_cells(ui, cs.reward_choices)
	# 点击中间格仍能选中。
	var bag_before: int = cs.bag.size()
	ui._on_reward_pick(1)
	assert_eq(cs.bag.size(), bag_before + 1)
	assert_false(ui._reward_open)


func test_campaign_opening_picker_uses_the_same_square_cells() -> void:
	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	CombatState.boot_campaign = false
	if ui.get_viewport() != null:
		ui.get_viewport().size = Vector2i(720, 1280)
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var cs: CombatState = ui.state
	if not cs.campaign_offer_pending:
		cs.start_campaign(497)
		ui._refresh()
	ui._open_reward_panel_now()
	await wait_process_frames(3)
	assert_true(ui._reward_open)
	assert_true(cs.campaign_offer_pending)
	assert_eq(cs.campaign_offer_choices.size(), 3)
	_assert_three_square_cells(ui, cs.campaign_offer_choices)


func test_alley_globe_fill_is_sparse_and_settled_at_the_bottom() -> void:
	var pts: PackedVector2Array = GumballMachine.decor_globe_ball_offsets()
	assert_eq(pts.size(), GumballMachine.DECOR_GLOBE_BALL_COUNT)
	assert_eq(GumballMachine.DECOR_GLOBE_BALL_COUNT, 8)
	assert_lt(pts.size(), 18, "比旧的密铺更稀")
	var sum_y := 0.0
	for off in pts:
		assert_gte(off.y, 0.0, "应在下半球、靠近底部，不能悬空")
		assert_lt(off.length(), GumballMachine.GLOBE_R - 8.0)
		sum_y += off.y
	assert_gt(sum_y / float(pts.size()), 12.0, "整堆重心应靠下")


func test_closeup_hopper_is_live_under_gravity_before_any_lever_pull() -> void:
	var cu: GumballCloseup = autofree(GumballCloseup.new())
	cu.size = Vector2(720, 1280)
	cu.present()
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	cu.set_can_commit(true, false)
	assert_eq(cu.lever_pull(), 0.0)
	assert_false(cu.is_commit_accepted())
	assert_true(cu.hopper_is_simulating())
	var y0: Array = []
	var p0: Array = []
	for b in cu._balls:
		assert_false(bool(b["asleep"]), "进场时不应睡着")
		y0.append(float(b["pos"].y))
		p0.append(Vector2(b["pos"]))
	var moved_down := 0
	var max_shift := 0.0
	for _i in 12:
		cu.tick(1.0 / 30.0)
		assert_lt(cu.lever_pull(), 0.05, "测试过程中不能拉拉杆")
	for i in cu._balls.size():
		var p: Vector2 = cu._balls[i]["pos"]
		var dy: float = p.y - float(y0[i])
		if dy > 0.8:
			moved_down += 1
		max_shift = maxf(max_shift, p.distance_to(p0[i]))
		assert_lt(p.y, cu.outlet_point().y - 4.0, "拉杆前不应掉到出球口外")
	assert_true(cu.hopper_is_simulating() or moved_down >= 4)
	assert_gte(moved_down, 4, "进特写后、拉杆前应有球被重力拉下去")
	assert_gt(max_shift, 2.0)
	# 互相碰撞：不应整排仍保持出生时的相对间距完全平移。
	var rel_changed := 0
	for i in cu._balls.size():
		for j in range(i + 1, cu._balls.size()):
			var d0: float = (p0[i] as Vector2).distance_to(p0[j])
			var d1: float = (cu._balls[i]["pos"] as Vector2).distance_to(cu._balls[j]["pos"])
			if absf(d1 - d0) > 1.5:
				rel_changed += 1
	assert_gte(rel_changed, 3, "球与球应发生碰撞/挤堆，不只是各自自由落体")
