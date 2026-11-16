extends GutTest
## 束口皮袋用真实墙承载圆形弹；倒出时袋口转到手区上方，弹靠重力掉进去。


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
	for _i in 120:
		box._physics_process(1.0 / 60.0)
	var poly: PackedVector2Array = box._sack_walls_world()
	assert_gt(poly.size(), 6)
	var low_y := 0.0
	for b in box._balls:
		if bool(b.get("exited", false)):
			assert_true(false, "mouth closed, no bullet should leave")
			continue
		var p: Vector2 = b["pos"]
		assert_true(Geometry2D.is_point_in_polygon(p, poly), "every bullet stays inside the sack")
		low_y += p.y
	# 靠重力歇在圆底，不是停在袋口
	assert_gt(low_y / 30.0, box.size.y * 0.45)
	assert_gte(BagPhysicsBox.label_font_size_for_height(float(box._balls[0]["h"])), 16)


func test_sack_walls_rotate_and_still_hold() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(350, 370)
	add_child_autofree(box)
	var ids: Array = []
	for i in 16:
		ids.append(1)
	box.sync_ammo_ids(ids)
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	var before: Array = []
	for b in box._balls:
		before.append(Vector2(b["pos"]))
	box.mouth_open = false
	box.sack_tilt = -0.9
	for _j in 150:
		box._physics_process(1.0 / 60.0)
	var poly: PackedVector2Array = box._sack_walls_world()
	var moved := 0
	for i in box._balls.size():
		var b: Dictionary = box._balls[i]
		assert_false(bool(b.get("exited", false)))
		var p: Vector2 = b["pos"]
		assert_true(Geometry2D.is_point_in_polygon(p, poly), "tilted sack still holds every bullet")
		if p.distance_to(before[i]) > 6.0:
			moved += 1
	assert_gt(moved, 4, "bullets rest on the rotating wall by gravity, not a freeze")


func test_pour_into_hand_by_physics() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	var ids: Array = []
	for i in 12:
		ids.append(40 + (i % 6))
	box.sync_ammo_ids(ids)
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	box.pour_cap = 6
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	# 慢慢转到口朝下，让墙带着弹走，再开口
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.mouth_open = true
	box.impulse_pour_balls()
	var closed := false
	for _j in 300:
		box._physics_process(1.0 / 60.0)
		if not closed and box.fallen_count() >= 6:
			box.mouth_open = false
			closed = true
	if box.mouth_open:
		box.mouth_open = false
	for _k in 60:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 6, "exactly six leave through the mouth")
	assert_eq(box.sack_remaining_count(), 6, "the rest stay in the sack")
	var r: Rect2 = box.hand_catch_rect.grow(8.0)
	for b in box._balls:
		if bool(b.get("exited", false)):
			var p: Vector2 = b["pos"]
			assert_true(r.has_point(p), "fallen bullets land in the hand catcher")
	var fallen: Array = box.take_fallen_balls()
	assert_eq(fallen.size(), 6)
	assert_eq(box.ball_count(), 6)
	var cs := CombatState.new()
	cs.start_rush(4050)
	cs.dev_clear_bag()
	for rec in fallen:
		cs.sandbox_add_ammo(int(rec["id"]), 1, 0.0)
	# 袋里再留 6 发，总共 12 发里 6 发入手
	for i in 6:
		cs.sandbox_add_ammo(1, 1, 0.0)
	assert_eq(cs.bag.size(), 12)
	assert_eq(cs.dump_to_hand_items(fallen), 6)
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.bag.size(), 6)
	for rec2 in fallen:
		assert_true(int(rec2["id"]) in cs.hand, "the six in hand are the six that fell")


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


func test_hand_uses_round_bullets_chambers_stay_round() -> void:
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
	assert_lt(absf(hand.size.y - hand.size.x), 10.0, "hand bullets are round")
	var panel: Panel = ui._chamber_panels[0]
	var stl := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_gt(stl.corner_radius_top_left, 20)


func test_pour_tilts_negative_and_has_bob() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(320, 280)
	add_child_autofree(box)
	assert_eq(box.sack_tilt, 0.0)
	assert_eq(box.sack_bob, 0.0)
	box.sack_tilt = -PI
	box.sack_bob = -16.0
	box.sack_shift = Vector2(10, 20)
	assert_lt(box.sack_tilt, 0.0)
	assert_lt(box.sack_bob, 0.0)
	assert_gt(box.sack_shift.length(), 1.0)
	box.reset_pour_pose()
	assert_eq(box.sack_tilt, 0.0)
	assert_eq(box.sack_shift, Vector2.ZERO)
