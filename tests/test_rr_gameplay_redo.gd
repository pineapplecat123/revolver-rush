extends GutTest
## feat/gameplay-redo：倒出→手→拖装 / 仓对调（自动装入仅保留状态 API）；PLAIN_ONLY 开局。


func before_each() -> void:
	DataRegistry.reload()


func test_plain_only_starter_bag() -> void:
	var cs := CombatState.new()
	cs.start_rush(1, FireResolver.ID_WRATH)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT)
	for id in cs.bag:
		assert_eq(int(id), CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.hand.is_empty())


func test_dump_to_hand_draws_up_to_six() -> void:
	var cs := CombatState.new()
	cs.start_rush(2, FireResolver.ID_WRATH)
	assert_true(cs.can_dump_to_hand())
	var n: int = cs.dump_to_hand()
	assert_eq(n, CombatConstants.HAND_SIZE)
	assert_eq(cs.hand.size(), CombatConstants.HAND_SIZE)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT - CombatConstants.HAND_SIZE)


func test_dump_returns_hand_then_redraws() -> void:
	var cs := CombatState.new()
	cs.start_rush(3, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	var first: Array = cs.hand.duplicate()
	assert_eq(first.size(), 6)
	var bag_before_second: int = cs.bag.size()
	var n2: int = cs.dump_to_hand()
	assert_eq(n2, 6)
	# 手非空先退回再抽：袋数量应回到「总数-6」
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT - 6)
	assert_eq(bag_before_second + first.size() - 6, cs.bag.size())


func test_auto_load_from_hand() -> void:
	var cs := CombatState.new()
	cs.start_rush(4, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	var loaded: int = cs.auto_load_from_hand()
	assert_eq(loaded, 6)
	assert_true(cs.hand.is_empty())
	assert_eq(cs.magazine.loaded_count(), 6)


func test_load_hand_into_specific_chamber() -> void:
	var cs := CombatState.new()
	cs.start_rush(5, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	assert_true(cs.load_hand_index_into_chamber(0, 2))
	assert_eq(cs.hand.size(), 5)
	assert_ne(cs.magazine.slots[2], Magazine.EMPTY)
	assert_eq(cs.magazine.slots[0], Magazine.EMPTY)


func test_swap_magazine_slots() -> void:
	var cs := CombatState.new()
	cs.start_rush(6, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	cs.auto_load_from_hand()
	var a: int = cs.magazine.slots[0]
	var b: int = cs.magazine.slots[3]
	assert_true(cs.swap_magazine_slots(0, 3))
	assert_eq(cs.magazine.slots[0], b)
	assert_eq(cs.magazine.slots[3], a)


func test_do_load_still_works_for_tests() -> void:
	## 旧 API 保留：测试/金色额外轮仍可直接袋→匣。
	var cs := CombatState.new()
	cs.start_rush(7, FireResolver.ID_WRATH)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 6)


func test_reward_pool_plain_only() -> void:
	var cs := CombatState.new()
	cs.start_rush(8, FireResolver.ID_WRATH)
	var choices: Array[int] = cs.generate_reward_choices()
	assert_eq(choices.size(), CombatConstants.REWARD_CHOICE_COUNT)
	for id in choices:
		assert_eq(int(id), CombatConstants.WHITE_AMMO_ID)


func test_ui_no_autoload_button_and_hand_scatter() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_null(ui.get_node_or_null("%BtnAutoLoad"))
	ui.state.dump_to_hand()
	ui._refresh()
	await wait_process_frames(2)
	assert_gt(ui._hand_slot_panels.size(), 0)
	# 散落：至少两颗位置不完全相同
	if ui._hand_slot_panels.size() >= 2:
		var a: Vector2 = ui._hand_slot_panels[0].position
		var b: Vector2 = ui._hand_slot_panels[1].position
		assert_ne(a, b, "hand balls should scatter")


func _ammo_total(cs: CombatState) -> int:
	var mag := 0
	if cs.magazine != null:
		mag = cs.magazine.loaded_count()
	return cs.bag.size() + cs.hand.size() + mag + cs.discard.size()


func _assert_hand_separated(ui, area: Vector2) -> void:
	var panels: Array = ui._hand_slot_panels
	assert_gte(panels.size(), 2)
	var ball: float = panels[0].size.x
	assert_gt(ball, 4.0)
	var ys: Array = []
	var xs: Array = []
	for i in panels.size():
		var p: Control = panels[i]
		assert_almost_eq(p.size.x, ball, 0.2)
		assert_gte(p.position.x, -0.6, "hand ball left")
		assert_gte(p.position.y, -0.6, "hand ball top")
		assert_lte(p.position.x + p.size.x, area.x + 0.6, "hand ball right")
		assert_lte(p.position.y + p.size.y, area.y + 0.6, "hand ball bottom")
		xs.append(p.position.x)
		ys.append(p.position.y)
		for j in range(i + 1, panels.size()):
			var q: Control = panels[j]
			var dist: float = p.position.distance_to(q.position)
			assert_gte(dist, ball - 0.75, "hand balls overlap %s vs %s dist %s ball %s" % [i, j, dist, ball])
	var uniq_x := 0
	var uniq_y := 0
	xs.sort()
	ys.sort()
	var last_x := -9999.0
	var last_y := -9999.0
	for v in xs:
		if absf(float(v) - last_x) > 1.0:
			uniq_x += 1
			last_x = float(v)
	for v2 in ys:
		if absf(float(v2) - last_y) > 1.0:
			uniq_y += 1
			last_y = float(v2)
	assert_gt(uniq_x, 1, "scatter should not share one column")
	if area.y >= ball * 2.0:
		assert_gt(uniq_y, 1, "scatter should not be one neat row when the area is tall")


func test_hand_scatter_no_overlap_and_stable() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui.state.dump_to_hand()
	ui._refresh()
	await wait_process_frames(2)
	for area in [Vector2(320, 170), Vector2(180, 96), Vector2(140, 88)]:
		ui.hand_slots.custom_minimum_size = area
		ui.hand_slots.size = area
		ui._hand_scatter_dirty = true
		ui._hand_layout_area = Vector2.ZERO
		ui._layout_hand_scatter()
		var used: Vector2 = ui.hand_slots.size
		assert_almost_eq(used.x, area.x, 1.0, "hand area width")
		assert_almost_eq(used.y, area.y, 1.0, "hand area height")
		_assert_hand_separated(ui, used)
	var first: Array = []
	for p in ui._hand_slot_panels:
		first.append(p.position)
	ui._hand_scatter_dirty = true
	ui._layout_hand_scatter()
	for i in first.size():
		assert_eq(ui._hand_slot_panels[i].position, first[i], "same hand and area keep the scatter")
	# One drag-load must not dump the rest of the hand.
	var bag0: int = ui.state.bag.size()
	var hand0: int = ui.state.hand.size()
	assert_true(ui.state.load_hand_index_into_chamber(0, 0))
	assert_eq(ui.state.hand.size(), hand0 - 1)
	assert_eq(ui.state.bag.size(), bag0)


func test_shoot_returns_unused_hand_and_conserves_ammo() -> void:
	## Trigger is commit_unused_hand_for_fire, which _on_fire calls before resolving the shot.
	var cs := CombatState.new()
	cs.start_rush(11, FireResolver.ID_WRATH)
	var total := _ammo_total(cs)
	assert_eq(cs.dump_to_hand(), 6)
	assert_true(cs.load_hand_index_into_chamber(0, 1))
	assert_true(cs.load_hand_index_into_chamber(0, 4))
	assert_eq(cs.hand.size(), 4)
	assert_eq(cs.magazine.loaded_count(), 2)
	var slot1: int = cs.magazine.slots[1]
	var slot4: int = cs.magazine.slots[4]
	var n: int = cs.commit_unused_hand_for_fire()
	assert_eq(n, 4)
	assert_true(cs.hand.is_empty())
	assert_eq(cs.magazine.slots[1], slot1)
	assert_eq(cs.magazine.slots[4], slot4)
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(_ammo_total(cs), total)
	assert_true(cs.do_fire())
	assert_true(cs.hand.is_empty())
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_eq(cs.discard.size(), 2)
	assert_eq(_ammo_total(cs), total)


func test_fire_button_returns_hand_then_shoots() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui._combat_speed = 2.0
	ui.state.dump_to_hand()
	assert_true(ui.state.load_hand_index_into_chamber(0, 0))
	var leftover: int = ui.state.hand.size()
	var bag_before: int = ui.state.bag.size()
	var total := _ammo_total(ui.state)
	assert_gt(leftover, 0)
	var labels: Array = []
	for ch in ui.get_node("%ActionRow").get_children():
		if ch is Button and ch.visible:
			labels.append(ch.text)
	assert_eq(labels, ["倒出", "射击"])
	assert_null(ui.get_node_or_null("%BtnAutoLoad"))
	ui._on_fire()
	assert_true(ui.state.hand.is_empty(), "pressing 射击 returns unused hand before the shot resolves")
	assert_eq(ui.state.bag.size(), bag_before + leftover)
	assert_eq(_ammo_total(ui.state), total)
	for _i in 240:
		if not ui._volley_ui_running and not ui.is_shooting():
			break
		await get_tree().process_frame
	assert_false(ui._volley_ui_running)
	assert_true(ui.state.hand.is_empty())
	assert_eq(_ammo_total(ui.state), total)
	assert_eq(ui.state.discard.size(), 1)
	assert_eq(ui.state.magazine.loaded_count(), 0)


func test_rotated_snap_matches_rendered_hole() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	ui.state.dump_to_hand()
	ui._refresh()
	await wait_process_frames(2)
	assert_gte(ui.state.hand.size(), 6)
	var steps: Array = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 0.5, 2.5, 5.75]
	for s in steps:
		ui._apply_disk_rotation(float(s))
		var diverged := fposmod(float(s), 6.0) > 0.05 and absf(fposmod(float(s), 6.0) - 6.0) > 0.05
		var saw_gap := false
		for i in 6:
			var panel: Control = ui._chamber_panels[i]
			var vis: Vector2 = ui.chamber_visual_center(i)
			var aabb: Vector2 = panel.get_global_rect().get_center()
			if vis.distance_to(aabb) > 6.0:
				saw_gap = true
			ui._drag_kind = "hand"
			ui._update_drag_snap(vis)
			assert_eq(ui._drag_snap_chamber, i, "snap at rendered hole step %s slot %s" % [s, i])
			assert_eq(ui._chamber_index_at(vis), i, "drop hit step %s slot %s" % [s, i])
			var touch := InputEventScreenTouch.new()
			touch.position = panel.size * 0.5
			touch.pressed = true
			var mapped: Vector2 = ui._pointer_global(touch, panel)
			assert_almost_eq(mapped.distance_to(vis), 0.0, 0.75, "touch local center maps to hole step %s slot %s" % [s, i])
			ui._update_drag_snap(mapped)
			assert_eq(ui._drag_snap_chamber, i)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = true
			mouse.global_position = vis
			assert_almost_eq(ui._pointer_global(mouse, panel).distance_to(vis), 0.0, 0.01)
		if diverged:
			assert_true(saw_gap, "rotation must move hole centers off axis-aligned rects at step %s" % s)
	# load -> rotate -> load, snap lands in the hole that is actually under the pointer
	ui._apply_disk_rotation(2.0)
	var target := 3
	var center: Vector2 = ui.chamber_visual_center(target)
	var bag_before: int = ui.state.bag.size()
	var hand_before: int = ui.state.hand.size()
	ui._drag_begin("hand", 0, center + Vector2(110, 70))
	ui._drag_move(center)
	assert_eq(ui._drag_snap_chamber, target)
	var hl: CanvasItem = ui._chamber_panels[target].get_node_or_null("SnapHighlight")
	assert_true(hl != null and hl.visible, "highlight sits on the snapped hole")
	ui._drag_end(center)
	assert_eq(ui.state.hand.size(), hand_before - 1, "loading one round leaves the rest in hand")
	assert_eq(ui.state.bag.size(), bag_before)
	assert_ne(ui.state.magazine.slots[target], Magazine.EMPTY)
	for i in 6:
		if i == target:
			continue
		assert_eq(ui.state.magazine.slots[i], Magazine.EMPTY)
	# scale / narrow viewport: snap still tracks the transformed hole
	ui._fit_combat_viewport(Vector2(390, 844))
	await wait_process_frames(1)
	ui._apply_disk_rotation(4.5)
	for i in 6:
		var vis2: Vector2 = ui.chamber_visual_center(i)
		ui._drag_kind = "hand"
		ui._update_drag_snap(vis2)
		assert_eq(ui._drag_snap_chamber, i, "scaled snap slot %s" % i)
		assert_eq(ui._chamber_index_at(vis2), i)
	ui._fit_combat_viewport(Vector2(1280, 720))
	await wait_process_frames(1)
	ui._apply_disk_rotation(1.25)
	for i in 6:
		var vis3: Vector2 = ui.chamber_visual_center(i)
		ui._drag_kind = "hand"
		ui._update_drag_snap(vis3)
		assert_eq(ui._drag_snap_chamber, i, "desktop snap slot %s" % i)


func test_bag_shows_every_bullet_without_scroll() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	var scroll: ScrollContainer = ui.find_child("BagScroll", true, false)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	var box = ui._bag_physics
	assert_eq(box.ball_count(), ui.state.bag.size())
	assert_eq(box.ball_count(), CombatConstants.STARTER_PLAIN_ONLY_COUNT)
	if box.size.y < 8.0:
		box.size = Vector2(260, 160)
		box._update_radii_for_count()
	for _i in 120:
		box._physics_process(1.0 / 60.0)
	var sz: Vector2 = box.size
	assert_gt(sz.x, 8.0)
	assert_gt(sz.y, 8.0)
	for b in box._balls:
		var p: Vector2 = b["pos"]
		var r: float = float(b["r"])
		assert_gte(p.x - r, -1.0)
		assert_gte(p.y - r, -1.0)
		assert_lte(p.x + r, sz.x + 1.0)
		assert_lte(p.y + r, sz.y + 1.0)
	assert_eq(scroll.scroll_vertical, 0)
	# narrow and short viewports keep the scaled layout inside the screen
	for avail in [Vector2(720, 1280), Vector2(1280, 720), Vector2(390, 844)]:
		ui._fit_combat_viewport(avail)
		var margin: Control = ui.get_node("Margin")
		var scaled := margin.size * margin.scale
		assert_lte(scaled.x, avail.x + 1.5)
		assert_lte(scaled.y, avail.y + 1.5)
		if avail.x + 0.5 >= ui.UI_FIT_MIN.x and avail.y + 0.5 >= ui.UI_FIT_MIN.y:
			assert_almost_eq(margin.scale.x, 1.0, 0.02)
		else:
			assert_lt(margin.scale.x, 0.999)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)


func test_removing_one_hand_bullet_does_not_move_the_rest() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui.state.dump_to_hand()
	ui._refresh()
	await wait_process_frames(2)
	var area := Vector2(320, 170)
	ui.hand_slots.custom_minimum_size = area
	ui.hand_slots.size = area
	ui._hand_scatter_dirty = true
	ui._hand_layout_area = Vector2.ZERO
	ui._layout_hand_scatter()
	_assert_hand_separated(ui, ui.hand_slots.size)
	var before := {}
	for i in ui.state.hand.size():
		before[int(ui.state.hand_uid[i])] = ui._hand_slot_panels[i].position
	var removed: int = int(ui.state.hand_uid[0])
	assert_true(ui.state.load_hand_index_into_chamber(0, 0))
	ui.hand_slots.custom_minimum_size = area
	ui.hand_slots.size = area
	ui._hand_scatter_dirty = false
	ui._hand_layout_area = area
	ui._refresh()
	await wait_process_frames(2)
	ui.hand_slots.size = area
	ui._hand_scatter_dirty = false
	ui._hand_layout_area = area
	ui._layout_hand_scatter()
	assert_eq(ui.state.hand.size(), before.size() - 1)
	for i in ui.state.hand.size():
		var uid := int(ui.state.hand_uid[i])
		assert_true(before.has(uid), "survivor uid stays")
		assert_eq(ui._hand_slot_panels[i].position, before[uid], "survivor stays put")
	assert_false(ui._hand_pos_by_uid.has(removed))
	ui.state._hand_append(CombatConstants.WHITE_AMMO_ID, false)
	ui.hand_slots.size = area
	ui._hand_scatter_dirty = false
	ui._hand_layout_area = area
	ui._refresh()
	await wait_process_frames(1)
	ui.hand_slots.size = area
	ui._hand_scatter_dirty = false
	ui._hand_layout_area = area
	ui._layout_hand_scatter()
	var newcomers := 0
	for i in ui.state.hand.size():
		var uid2 := int(ui.state.hand_uid[i])
		if before.has(uid2):
			assert_eq(ui._hand_slot_panels[i].position, before[uid2], "return does not shove others")
		else:
			newcomers += 1
	assert_eq(newcomers, 1)
	_assert_hand_separated(ui, ui.hand_slots.size)
	ui._hand_pos_by_uid[int(ui.state.hand_uid[0])] = Vector2(1, 1)
	ui._hand_scatter_dirty = false
	ui._hand_layout_area = ui.hand_slots.size
	ui._layout_hand_scatter()
	assert_eq(ui._hand_slot_panels[0].position, Vector2(1, 1), "layout keeps an existing spot")
	ui._on_manual_load()
	await wait_process_frames(2)
	ui.hand_slots.size = area
	ui._layout_hand_scatter()
	var all_stacked := true
	for p in ui._hand_slot_panels:
		if (p as Control).position != Vector2(1, 1):
			all_stacked = false
	assert_false(all_stacked, "倒出重新散开")
	_assert_hand_separated(ui, ui.hand_slots.size)


func test_shot_damage_resolves_on_impact_not_on_press() -> void:
	var cs := CombatState.new()
	cs.start_rush(21, FireResolver.ID_WRATH)
	cs.defer_impacts = true
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	var e: EnemyInstance = cs.enemies[0]
	e.hp = 3
	e.max_hp = 3
	e.atk = 0
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hits := {"n": 0}
	cs.enemy_damaged.connect(func(_c, _a, _k): hits["n"] = int(hits["n"]) + 1)
	var xp_before: int = cs.xp
	var first: Array = cs.fire_tap(false)
	assert_eq(first.size(), 1)
	assert_eq(e.hp, 3, "按下射击不扣血")
	assert_eq(int(hits["n"]), 0)
	assert_eq(cs.pending_impact_count(), 1)
	assert_true(cs.is_volley_pending())
	var second: Array = cs.take_volley_shot()
	assert_eq(second.size(), 1)
	assert_eq(e.hp, 3, "下一仓击发也不扣血")
	assert_eq(cs.pending_impact_count(), 2)
	assert_false(cs.is_volley_pending(), "最后一发实弹后连射结束")
	var dealt1: int = cs.resolve_pending_impact_hit(int(first[0]["impact_id"]), 0)
	assert_eq(dealt1, 3)
	assert_eq(e.hp, 0)
	assert_eq(int(hits["n"]), 1)
	cs.finalize_pending_impact(int(first[0]["impact_id"]))
	assert_gt(cs.xp, xp_before, "击杀经验在命中时入账")
	var dealt2 := 0
	var cells: Array = second[0].get("hit_cells", [])
	if not cells.is_empty():
		dealt2 = cs.resolve_pending_impact_hit(int(second[0]["impact_id"]), 0)
	cs.finalize_pending_impact(int(second[0]["impact_id"]))
	assert_eq(dealt2, 0, "目标已死，后一发不造成伤害")
	assert_eq(int(hits["n"]), 1, "后一发不发伤害信号")
	assert_eq(cs.pending_impact_count(), 0)


func test_ui_damage_waits_until_bullet_arrives() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	assert_true(cs.defer_impacts)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	var e: EnemyInstance = cs.enemies[0]
	e.hp = 3
	e.max_hp = 3
	e.atk = 0
	e.cell = 4
	e.pos_x = 4.0
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	ui._wave_bannering = false
	ui._combat_speed = 4.0
	assert_true(cs.can_fire())
	ui.hit_fx_log.clear()
	ui.air_blood_skipped = 0
	ui._on_fire()
	assert_eq(e.hp, 3, "射击键按下当帧不扣血")
	assert_eq(ui.hit_fx_log.size(), 0, "按下时不喷血")
	for _i in 360:
		if cs.pending_impact_count() == 0 and not ui._volley_ui_running and not ui.is_shooting():
			break
		await get_tree().process_frame
	assert_eq(cs.pending_impact_count(), 0)
	assert_eq(e.hp, 0)
	assert_eq(ui.hit_fx_log.size(), 1, "只在命中的那一发喷血")
	assert_true(bool(ui.hit_fx_log[0].get("lethal", false)))
	assert_eq(ui.air_blood_skipped, 0)
