extends GutTest
## v0.4.50：袋内子弹自由旋转，短名字始终正向对着玩家。


func test_version_is_at_least_0_4_50() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.50") >= 0)
	assert_true("0.4.50" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("正向对着玩家" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_bag_bullets_rotate_freely_and_label_stays_upright() -> void:
	var src: String = (load("res://scripts/combat/bag_physics_box.gd") as GDScript).source_code
	assert_false("BULLET_MAX_TILT" in src)
	assert_true("draw_set_transform(pos, 0.0, Vector2.ONE)" in src, "label is drawn unrotated")
	assert_false("draw_set_transform(pos, ang, Vector2.ONE)" in src)
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 300)
	add_child_autofree(box)
	box.sync_ammo_ids([1, 40, 41, 42, 43, 44, 45, 46, 1, 40, 41, 42])
	assert_eq(box.ball_count(), 12)
	var spread: Dictionary = {}
	for b in box._balls:
		var a: float = float(b["ang"])
		assert_lte(absf(a), PI + 0.001)
		spread[snapped(a, 0.05)] = true
		assert_true(b.has("omega"))
	assert_gt(spread.size(), 1)
	# 单独一发横躺：点选跟外形走，也不会被拉回小倾角
	var solo: BagPhysicsBox = BagPhysicsBox.new()
	solo.size = Vector2(360, 300)
	add_child_autofree(solo)
	solo.sync_ammo_ids([40])
	var b0: Dictionary = solo._balls[0]
	b0["ang"] = PI * 0.5
	b0["omega"] = 0.0
	b0["vel"] = Vector2.ZERO
	b0["pos"] = Vector2(180, 150)
	solo._refresh_world_hull(b0)
	var pos: Vector2 = b0["pos"]
	var h: float = float(b0["h"])
	assert_not_null(solo._ball_at_pointer(pos))
	assert_null(solo._ball_at_pointer(pos + Vector2(0.0, h * 0.45)), "hits follow the rotated outline")
	for _i in 8:
		solo._physics_process(1.0 / 60.0)
	assert_gt(absf(float(b0["ang"])), 0.8, "free rotation is not clamped to a small tilt")


func test_full_bag_fits_with_free_rotation_no_scroll() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui._fit_combat_viewport(Vector2(720, 1280))
	ui.size = Vector2(720, 1280)
	await wait_process_frames(2)
	var st = ui.state
	st.dev_clear_bag()
	var ids := [1, 40, 41, 42, 43, 44, 45, 46]
	for i in 30:
		st.sandbox_add_ammo(int(ids[i % ids.size()]), 1, 0.0)
	ui._refresh()
	await wait_process_frames(3)
	var box = ui._bag_physics
	assert_not_null(box)
	assert_eq(box.ball_count(), 30)
	# 强制几发横躺，确认仍能装在盒里
	if box._balls.size() >= 6:
		for i in 6:
			box._balls[i]["ang"] = PI * 0.5 * (1 if i % 2 == 0 else -1)
			box._balls[i]["omega"] = 0.0
			box._refresh_world_hull(box._balls[i])
	for _i in 180:
		box._physics_process(1.0 / 60.0)
	var h: float = float(box._balls[0]["h"])
	assert_gte(BagPhysicsBox.label_font_size_for_height(h), BagPhysicsBox.LABEL_FONT_MIN)
	var scroll: ScrollContainer = ui.find_child("BagScroll", true, false)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.scroll_vertical, 0)
	var sz: Vector2 = box.size
	assert_gt(sz.y, 8.0)
	for b in box._balls:
		var ext: Vector2 = box._ball_ext(b)
		var p: Vector2 = b["pos"]
		assert_gte(p.x - ext.x, -1.5)
		assert_gte(p.y - ext.y, -1.5)
		assert_lte(p.x + ext.x, sz.x + 1.5)
		assert_lte(p.y + ext.y, sz.y + 1.5)
