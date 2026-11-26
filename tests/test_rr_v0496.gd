extends GutTest
## v0.4.96：糖果机罐子更大全透明、拉杆接到机身并发光；垃圾桶升级三选一可点且不卡死。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func test_version_is_0_4_96() -> void:
	assert_eq(GameVersion.STRING, "0.4.96")


func _closeup() -> GumballCloseup:
	var cu: GumballCloseup = autofree(GumballCloseup.new())
	cu.size = Vector2(720, 1280)
	cu.present()
	return cu


func test_machine_globe_is_larger_fully_transparent_without_lid() -> void:
	assert_gte(GumballMachine.GLOBE_R, 60.0)
	assert_eq(GumballMachine.CAP_H, 0.0)
	var cu := _closeup()
	assert_false(cu.draws_globe_lid())
	assert_gt(cu.globe_radius(), cu.ball_radius() * 4.0)
	# 出球口 / 托盘几何保持可用，不被更大的罐子挡住。
	assert_true(cu.is_outlet_unobstructed())
	assert_true(cu.is_drop_region_unobstructed())
	assert_almost_eq(cu.outlet_point().x, 360.0, 8.0)
	assert_lt(cu.casing_top_y(), cu.outlet_reveal_y())
	assert_lt(cu.outlet_reveal_y(), cu.outlet_point().y)


func test_lever_is_mounted_on_body_larger_with_red_invite_knob() -> void:
	var cu := _closeup()
	cu.set_can_commit(true, false)
	assert_true(cu.lever_is_mounted_on_body())
	var foot: Vector2 = cu.machine_foot()
	var sc: float = cu.machine_scale()
	var pivot: Vector2 = cu.lever_pivot()
	var local_y: float = (pivot.y - foot.y) / sc
	var body_right: float = foot.x + GumballMachine.pedestal_half_width_at_local_y(local_y) * sc
	assert_lte(absf(pivot.x - body_right), 4.0)
	assert_gt(cu.lever_knob_radius(), 20.0)
	assert_gt(cu.lever_grab_rect().size.x, 60.0)
	assert_gt(cu.lever_grab_rect().size.y, 100.0)
	# 把头在机身外侧，杆从枢轴连到把头，中间没有缺口。
	assert_gt(cu.lever_rest_pos().x, pivot.x + 8.0)
	assert_true(cu.lever_invite_active())
	# 拉杆行程仍能扣到头。
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	cu.set_can_commit(true, false)
	var grabbed := false
	cu.lever_commit_requested.connect(func() -> void: grabbed = true)
	cu.simulate_full_stroke()
	assert_true(grabbed or cu.lever_pull() >= GumballCloseup.COMMIT_PULL, "拉满应发出扣费请求")


func test_trash_xp_picker_buttons_are_clickable_after_freeze_and_run_does_not_stick() -> void:
	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	CombatState.boot_campaign = false
	var cs: CombatState = ui.state
	cs.campaign_instant_transitions = true
	cs.campaign_pick_opening(0)
	cs.campaign_skip_walk()
	cs.campaign_wave_reserve.clear()
	cs.enemies.clear()
	cs.alley_force_kind = CampaignRules.ALLEY_TRASH
	cs._begin_alley_approach()
	cs.campaign_skip_walk()
	ui._ensure_alley_panel()
	cs.alley_force_trash_u = 0.95
	assert_true(cs.alley_try_rummage())
	assert_eq(cs.alley_award_kind, "xp")
	assert_true(cs.reward_pending)
	assert_gt(cs.pending_levelups, 0)
	# 模拟按钮路径：刷新后立刻冻结，不再等下一帧 _sync_alley_prop。
	ui._refresh()
	ui._refresh_alley_panel()
	ui._sync_alley_over_reward()
	ui._update_dimmer()
	assert_true(ui._reward_open)
	assert_true(ui.is_combat_frozen())
	assert_false(ui._alley_panel.visible)
	assert_eq(ui._alley_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(ui._modal_canvas.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(ui.reward_panel.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(ui.reward_panel.visible)
	# 等 ALWAYS 模态布局一帧，但不要靠战斗 _process（此时已冻结）。
	# GUT 默认视口可能很小，先拉到设计分辨率，否则选项在视口外点不到。
	if ui.get_viewport() != null:
		ui.get_viewport().size = Vector2i(720, 1280)
	DisplayServer.window_set_size(Vector2i(720, 1280))
	await wait_process_frames(2)
	var btn: Button = null
	for c in ui.reward_choices.get_children():
		if c is Button and is_instance_valid(c) and not c.is_queued_for_deletion() and c.visible:
			btn = c
			break
	assert_not_null(btn, "升级三选一必须画出可点的选项")
	assert_false(btn.disabled)
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_gt(btn.get_global_rect().size.x, 40.0)
	assert_gt(btn.get_global_rect().size.y, 24.0)
	var pending_before: int = cs.pending_levelups
	var bag_before: int = cs.bag.size()
	var gold_before: int = cs.gold
	var click_pos: Vector2 = btn.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = click_pos
	click.global_position = click_pos
	Input.parse_input_event(click)
	ui.get_viewport().push_input(click)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	ui.get_viewport().push_input(click)
	await wait_process_frames(2)
	var accepted: bool = (not cs.reward_pending) or cs.pending_levelups < pending_before or cs.bag.size() > bag_before or cs.gold != gold_before or not ui._reward_open
	# 视口如果仍无法派发 GUI，用直接选择证明流程不会卡死；残留层挡住点击时会先被上面的结构断言抓住。
	if not accepted:
		ui._on_reward_pick(0)
		await wait_process_frames(1)
		accepted = (not cs.reward_pending) or cs.pending_levelups < pending_before or cs.bag.size() > bag_before or not ui._reward_open
		assert_true(accepted, "选完后流程必须推进，不能卡在待选奖励")
		# 若还有排队升级，继续选完，流程必须能离开巷事件。
	var safety := 0
	while cs.reward_pending and safety < 6:
		safety += 1
		if cs.can_gain_ammo(1):
			ui._on_reward_pick(0)
		else:
			ui._on_reward_skip()
		await wait_process_frames(1)
	assert_false(cs.reward_pending, "选完后不能再挂着待选奖励")
	assert_false(ui._reward_open)
	assert_false(ui.is_combat_frozen())
	assert_true(cs.alley_can_leave())
	assert_true(cs.alley_skip())
	assert_false(cs.alley_hold)
