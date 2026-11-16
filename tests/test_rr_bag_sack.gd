extends GutTest
## 弹药袋改成布袋外形；倒出仍是袋→手最多 6 发（逻辑与原来相同）。


func test_sack_has_neck_and_contains_bullets() -> void:
	var unit: PackedVector2Array = BagPhysicsBox.sack_interior_unit()
	assert_gt(unit.size(), 6)
	var mouth_w: float = absf(unit[0].x - unit[unit.size() - 1].x)
	var belly_w := 0.0
	for p in unit:
		if p.y > 0.45 and p.y < 0.70:
			belly_w = maxf(belly_w, absf(p.x - 0.5) * 2.0)
	assert_gt(belly_w, mouth_w + 0.15, "sack belly is wider than the neck")
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(350, 370)
	add_child_autofree(box)
	var ids: Array = []
	for i in 30:
		ids.append(1 if i % 2 == 0 else 40)
	box.sync_ammo_ids(ids)
	assert_eq(box.ball_count(), 30)
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	var poly: PackedVector2Array = box._sack_interior_local()
	assert_gt(poly.size(), 6)
	for b in box._balls:
		if bool(b.get("exited", false)):
			continue
		var p: Vector2 = b["pos"]
		assert_true(Geometry2D.is_point_in_polygon(p, poly), "every bullet stays inside the sack")
		var ext: Vector2 = box._ball_ext(b)
		var rad: float = maxf(ext.x, ext.y) * 0.85
		var np: Vector2 = box._contain_point_in_sack(p, rad)
		assert_lt(np.distance_to(p), 2.5, "bullet is not sitting on the sack wall")
	assert_gte(BagPhysicsBox.label_font_size_for_height(float(box._balls[0]["h"])), 16)


func test_bag_area_has_no_rectangle_chrome() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	ui._clear_bag_area_chrome()
	var stl = ui.bag_panel.get_theme_stylebox("panel")
	if stl is StyleBoxFlat:
		assert_lt((stl as StyleBoxFlat).bg_color.a, 0.04)
		assert_eq((stl as StyleBoxFlat).get_border_width(SIDE_LEFT), 0)
	else:
		assert_true(stl is StyleBoxEmpty)
	if ui.bag_header_label != null:
		assert_false(ui.bag_header_label.visible)
	if ui.bag_list != null:
		var stats: Label = ui.bag_list.get_node_or_null("BagStatsLabel") as Label
		assert_true(stats == null or not stats.visible)


func test_dump_to_hand_still_moves_up_to_six() -> void:
	var cs := CombatState.new()
	cs.start_rush(4050)
	cs.dev_clear_bag()
	for i in 10:
		cs.sandbox_add_ammo(1, 1, 0.0)
	assert_eq(cs.dump_to_hand(), 6)
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.bag.size(), 4)



func test_hand_uses_bullet_shape_chambers_stay_round() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var st = ui.state
	st.sandbox_add_ammo(40, 4)
	st.sandbox_add_to_hand(40, 2)
	st.magazine.set_slot(0, 40)
	ui._refresh()
	await wait_process_frames(2)
	assert_false(ui._hand_slot_panels.is_empty())
	var hand: Control = ui._hand_slot_panels[0]
	assert_true(hand is HandBulletView)
	assert_gt(hand.size.y, hand.size.x + 8.0)
	var panel: Panel = ui._chamber_panels[0]
	var stl := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_gt(stl.corner_radius_top_left, 20)


func test_pour_tilts_negative_and_has_bob() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(320, 280)
	add_child_autofree(box)
	assert_eq(box.sack_tilt, 0.0)
	assert_eq(box.sack_bob, 0.0)
	box.sack_tilt = -PI * 0.62
	box.sack_bob = -16.0
	assert_lt(box.sack_tilt, 0.0)
	assert_lt(box.sack_bob, 0.0)
	box.sack_tilt = 0.0
	box.sack_bob = 0.0
	# 逻辑倒出仍是最多 6 发（动画在无头模式会跳过）
	var cs := CombatState.new()
	cs.start_rush(4050)
	cs.dev_clear_bag()
	for i in 10:
		cs.sandbox_add_ammo(1, 1, 0.0)
	assert_eq(cs.dump_to_hand(), 6)
	assert_eq(cs.hand.size(), 6)
