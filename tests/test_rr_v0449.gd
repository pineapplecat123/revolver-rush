extends GutTest
## v0.4.49：待机上下点头；袋内更大、带台阶的单色子弹，碰撞和点选跟外形走。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_49() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.49") >= 0)
	assert_true("0.4.49" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _make_cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = (load("res://scenes/player/skeleton_player.tscn") as PackedScene).instantiate() as SkeletonPlayer
	add_child_autofree(p)
	return p


func test_idle_smile_path_dips_at_extremes_and_plants_feet() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	var beat: float = SkeletonPlayer.IDLE_BEAT
	var length: float = beat * 4.0
	var torso0: Vector2 = p.REST["Torso"][0]
	# t=0 前端下点，且在身体前方
	p.anim.seek(0.0, true)
	assert_gt(p.bones["Torso"].position.y, torso0.y + 1.5, "forward extreme should dip")
	assert_gt(p.bones["Torso"].position.x, torso0.x + 1.5, "first dip is on the forward side")
	assert_almost_eq(p.bones["Hip"].position.y, p.REST["Hip"][0].y, 0.02)
	assert_almost_eq(p.bones["ThighF"].rotation, p.REST["ThighF"][1], 0.001)
	assert_almost_eq(p.bones["ShinF"].rotation, p.REST["ShinF"][1], 0.001)
	# 一拍：回到中间并抬起
	p.anim.seek(beat, true)
	assert_lt(p.bones["Torso"].position.y, torso0.y - 0.5, "center should be up")
	assert_almost_eq(p.bones["Torso"].position.x, torso0.x, 1.2)
	# 两拍：后端下点
	p.anim.seek(beat * 2.0, true)
	assert_gt(p.bones["Torso"].position.y, torso0.y + 1.5, "back extreme should dip")
	assert_lt(p.bones["Torso"].position.x, torso0.x - 1.5, "second dip is on the back side")
	# 靠近前端前下点仍浅（快 ease-in）；离开端点后才慢慢抬、水平已离开中线
	var approach: Vector2 = SkeletonPlayer.idle_torso_offset(length - beat * 0.25, length)
	var mid_dip: float = SkeletonPlayer.idle_dip_amount(0.0, length)
	var approach_dip: float = SkeletonPlayer.idle_dip_amount(length - beat * 0.25, length)
	assert_gt(mid_dip, 0.85)
	assert_lt(approach_dip, 0.35, "dip should stay shallow until near the extreme")
	assert_gt(approach.x, 1.0)
	assert_eq(p.current_animation(), &"idle")


func test_idle_gun_lags_and_blends() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(0.0, true)
	var arm0: float = p.bones["UpperArmF"].rotation
	p.anim.seek(SkeletonPlayer.IDLE_GUN_LAG, true)
	var arm1: float = p.bones["UpperArmF"].rotation
	assert_gt(arm1, arm0 + 0.015, "gun arm should finish the dip after the torso")
	p.play_shoot()
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle", "shoot should return to idle")


func test_bag_shape_has_shoulder_groove_and_readable_label() -> void:
	var pts: PackedVector2Array = BagPhysicsBox.build_bag_bullet_unit()
	assert_gt(pts.size(), 20)
	var tip: Vector2 = pts[0]
	assert_almost_eq(tip.x, 0.0, 0.02)
	assert_lt(tip.y, -0.49)
	var max_x := 0.0
	var body_x := 0.0
	var nose_base_x := 0.0
	var groove_x := 100.0
	for p in pts:
		max_x = maxf(max_x, absf(p.x))
		if p.y > -0.05 and p.y < 0.30:
			body_x = maxf(body_x, absf(p.x))
		if absf(p.y - (-0.5 + BagPhysicsBox.BULLET_NOSE_FRAC)) < 0.002:
			nose_base_x = maxf(nose_base_x, absf(p.x))
		if absf(p.y - (-0.5 + BagPhysicsBox.BULLET_GROOVE_Y)) < 0.002:
			if absf(p.x) > 0.05:
				groove_x = minf(groove_x, absf(p.x))
	assert_almost_eq(BagPhysicsBox.BULLET_BODY_W, 0.39, 0.001)
	assert_almost_eq(body_x * 2.0, BagPhysicsBox.BULLET_BODY_W, 0.02)
	assert_almost_eq(max_x * 2.0, BagPhysicsBox.BULLET_RIM_W, 0.03)
	assert_almost_eq(BagPhysicsBox.BULLET_RIM_W / BagPhysicsBox.BULLET_BODY_W, 1.04, 0.001)
	# 弹头底部 0.90w，然后台阶接到弹身（肩部可见）
	assert_almost_eq(BagPhysicsBox.BULLET_NOSE_W / BagPhysicsBox.BULLET_BODY_W, 0.90, 0.001)
	assert_gt(body_x, nose_base_x * 0.5 + 0.01, "shoulder steps out from nose to case")
	assert_lt(groove_x * 2.0, BagPhysicsBox.BULLET_BODY_W - 0.01, "extractor groove is inset")
	assert_almost_eq(BagPhysicsBox.BULLET_NOSE_FRAC, 0.30, 0.001)
	assert_gte(BagPhysicsBox.label_font_size_for_height(BagPhysicsBox.DEFAULT_HEIGHT), BagPhysicsBox.LABEL_FONT_MIN)
	var hull: PackedVector2Array = BagPhysicsBox.build_bag_bullet_hull_unit()
	assert_gt(hull.size(), 8)
	assert_lt(hull.size(), pts.size() + 1)


func test_bag_outline_hit_and_collision_not_a_disc() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(320, 260)
	box.size = Vector2(320, 260)
	box.color_lookup = func(_aid: int) -> Dictionary:
		return {"bg": Color(0.32, 0.78, 0.42), "fg": Color(0.07, 0.16, 0.08)}
	box.name_lookup = func(_aid: int) -> String:
		return "起"
	add_child_autofree(box)
	box.sync_ammo_ids([40])
	assert_eq(box.ball_count(), 1)
	var b: Dictionary = box._balls[0]
	b["ang"] = 0.0
	b["pos"] = Vector2(160, 130)
	b["vel"] = Vector2.ZERO
	box._update_radii_for_count()
	box._refresh_world_hull(b)
	var h: float = float(b["h"])
	var pos: Vector2 = b["pos"]
	# 中心和弹身在外形内
	assert_not_null(box._ball_at_pointer(pos))
	assert_not_null(box._ball_at_pointer(pos + Vector2(0, h * 0.1)))
	# 圆形：半径内能点到，半径外不能
	var side: Vector2 = pos + Vector2(h * 0.75, 0)
	assert_null(box._ball_at_pointer(side), "hits follow the circle")
	var rim: Vector2 = pos + Vector2(BagPhysicsBox.circle_radius_for_height(h) * 0.5, 0)
	assert_not_null(box._ball_at_pointer(rim), "inside the circle")
	assert_null(box._ball_at_pointer(Vector2(-40, -40)))
	assert_lte(absf(float(b["ang"])), PI + 0.001)
	# 两发肩并肩时按圆推开，间距接近直径
	box.sync_ammo_ids([40, 41])
	box._balls[0]["ang"] = 0.0
	box._balls[1]["ang"] = 0.0
	box._balls[0]["pos"] = Vector2(160, 140)
	box._balls[1]["pos"] = Vector2(168, 140)
	box._balls[0]["vel"] = Vector2.ZERO
	box._balls[1]["vel"] = Vector2.ZERO
	box._update_radii_for_count()
	for _i in 20:
		box._physics_process(1.0 / 60.0)
	var gap: float = absf(float(box._balls[1]["pos"].x) - float(box._balls[0]["pos"].x))
	var hh: float = float(box._balls[0]["h"])
	var cr: float = BagPhysicsBox.circle_radius_for_height(hh)
	assert_gt(gap, cr * 2.0 - 3.0)
	assert_lt(gap, cr * 2.0 + 8.0)


func test_full_bag_fits_without_scroll_and_labels_stay_readable() -> void:
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
	if box.size.y < 8.0:
		box.size = Vector2(330, 220)
		box._update_radii_for_count()
	for _i in 160:
		box._physics_process(1.0 / 60.0)
	var h: float = float(box._balls[0]["h"])
	assert_gte(BagPhysicsBox.label_font_size_for_height(h), 16)
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
	# 弹仓仍是圆
	assert_false(ui._chamber_panels.is_empty())
	var panel: Panel = ui._chamber_panels[0]
	var stl := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_gt(stl.corner_radius_top_left, 20)
