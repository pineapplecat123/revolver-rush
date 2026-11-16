extends GutTest
## v0.4.48：小猫待机上半身节奏晃动；弹药袋圆球换成尖头厚底子弹外形。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_0_4_48() -> void:
	assert_eq(GameVersion.STRING, "0.4.48")
	assert_true("0.4.48" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _make_cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = (load("res://scenes/player/skeleton_player.tscn") as PackedScene).instantiate() as SkeletonPlayer
	add_child_autofree(p)
	return p


func test_idle_is_105_bpm_four_beat_loop() -> void:
	var p := _make_cat()
	var idle: Animation = p.anim.get_animation(&"idle")
	assert_not_null(idle)
	assert_eq(idle.loop_mode, Animation.LOOP_LINEAR)
	assert_almost_eq(idle.length, SkeletonPlayer.IDLE_BEAT * 4.0, 0.001)
	assert_almost_eq(SkeletonPlayer.IDLE_BPM, 105.0, 0.01)
	assert_almost_eq(SkeletonPlayer.IDLE_BEAT, 60.0 / 105.0, 0.0001)


func test_idle_bobs_torso_and_plants_feet() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(0.0, true)
	# 拍点：上半身下沉，腿仍在静止位置
	var torso0: Vector2 = p.REST["Torso"][0]
	assert_gt(p.bones["Torso"].position.y, torso0.y + 1.5, "downbeat should drop the torso")
	assert_almost_eq(p.bones["Hip"].position.x, p.REST["Hip"][0].x, 0.02)
	assert_almost_eq(p.bones["Hip"].position.y, p.REST["Hip"][0].y, 0.02)
	assert_almost_eq(p.bones["ThighF"].rotation, p.REST["ThighF"][1], 0.001)
	assert_almost_eq(p.bones["ShinF"].rotation, p.REST["ShinF"][1], 0.001)
	assert_almost_eq(p.bones["ThighB"].rotation, p.REST["ThighB"][1], 0.001)
	assert_almost_eq(p.bones["ShinB"].rotation, p.REST["ShinB"][1], 0.001)
	# 弱拍：上半身抬起
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 0.5, true)
	assert_lt(p.bones["Torso"].position.y, torso0.y - 0.8, "offbeat should lift the torso")


func test_idle_gun_lags_behind_torso() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(0.0, true)
	var arm0: float = p.bones["UpperArmF"].rotation
	var hand0: float = p.bones["HandF"].rotation
	p.anim.seek(SkeletonPlayer.IDLE_GUN_LAG, true)
	var arm1: float = p.bones["UpperArmF"].rotation
	var hand1: float = p.bones["HandF"].rotation
	# 滞后结束时持枪手臂才落到拍点上的最大下沉角
	assert_gt(arm1, arm0 + 0.02, "gun arm should finish its downstroke after the torso")
	assert_gt(hand1, hand0 + 0.02, "hand / gun should lag the torso slightly")


func test_idle_blends_to_shoot_and_twirl_and_back() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 1.25, true)
	assert_eq(p.current_animation(), &"idle")
	p.play_shoot()
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle", "shoot should return to idle")
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 2.1, true)
	p.play_gun_twirl(0.15)
	assert_true(p.current_animation() == &"twirl" or p._twirling)
	p.anim.advance(0.4)
	# twirl tween may still be running; finish it
	if p._twirl_tween != null and p._twirl_tween.is_valid():
		p._twirl_tween.custom_step(1.0)
	p.anim.advance(0.2)
	assert_eq(p.current_animation(), &"idle", "twirl should return to idle")
	assert_false(p._twirling)


func test_bag_bullet_unit_is_pointed_ogive_with_thick_rim() -> void:
	var pts: PackedVector2Array = BagPhysicsBox.build_bag_bullet_unit()
	assert_gt(pts.size(), 20)
	# 尖在上方中轴
	var tip: Vector2 = pts[0]
	assert_almost_eq(tip.x, 0.0, 0.02)
	assert_lt(tip.y, -0.49)
	# 最宽处是底缘
	var max_x := 0.0
	var body_x := 0.0
	for p in pts:
		max_x = maxf(max_x, absf(p.x))
		if p.y > -0.05 and p.y < 0.30:
			body_x = maxf(body_x, absf(p.x))
	assert_almost_eq(body_x * 2.0, BagPhysicsBox.BULLET_BODY_W, 0.02)
	assert_almost_eq(max_x * 2.0, BagPhysicsBox.BULLET_RIM_W, 0.03)
	assert_almost_eq(BagPhysicsBox.BULLET_RIM_W / BagPhysicsBox.BULLET_BODY_W, 1.18, 0.001)
	assert_almost_eq(BagPhysicsBox.BULLET_NOSE_FRAC, 0.40, 0.001)
	assert_almost_eq(BagPhysicsBox.BULLET_RIM_FRAC, 0.12, 0.001)


func test_bag_spawns_rotated_bullets_and_keeps_round_physics_and_clicks() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.custom_minimum_size = Vector2(220, 240)
	box.size = Vector2(220, 240)
	box.color_lookup = func(_aid: int) -> Dictionary:
		return {"bg": Color(0.32, 0.78, 0.42), "fg": Color(0.07, 0.16, 0.08)}
	box.name_lookup = func(_aid: int) -> String:
		return "起"
	add_child_autofree(box)
	box.sync_ammo_ids([40, 40, 1, 43])
	assert_eq(box.ball_count(), 4)
	var angs: Dictionary = {}
	for b in box._balls:
		assert_true(b.has("ang"), "each bag bullet should have a random rotation")
		var a: float = float(b["ang"])
		assert_between(a, 0.0, TAU)
		angs[snapped(a, 0.0001)] = true
		# 碰撞仍按圆盘
		assert_almost_eq(float(b["r"]), box.DEFAULT_RADIUS, 0.2)
	assert_gt(angs.size(), 1, "rotations should not all be identical")
	# 点击仍按圆心半径判定（邻球可能靠近，半径外取一个明确远离所有球的点）
	var target: Dictionary = box._balls[0]
	var hit = box._ball_at_pointer(target["pos"])
	assert_not_null(hit)
	assert_eq(int(hit["id"]), int(target["id"]))
	var just_out: Vector2 = target["pos"] + Vector2(float(target["r"]) + 1.0, 0)
	var edge = box._ball_at_pointer(just_out)
	assert_true(edge == null or not (edge["pos"] as Vector2).is_equal_approx(target["pos"]))
	var miss = box._ball_at_pointer(Vector2(-40, -40))
	assert_null(miss)
	# 重力仍让球下落
	var y0: float = float(box._balls[0]["pos"].y)
	for _i in 30:
		box._physics_process(1.0 / 60.0)
	assert_gt(float(box._balls[0]["pos"].y), y0)
	box.queue_redraw()
	await wait_frames(1)
	assert_eq(box.ball_count(), 4)


func test_hand_and_chamber_stay_circles() -> void:
	## 只换袋内外形；手和弹仓仍是圆。
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var st = ui.state
	st.sandbox_add_ammo(40, 4)
	st.sandbox_add_to_hand(40, 1)
	st.magazine.set_slot(0, 40)
	ui._refresh()
	await wait_process_frames(2)
	assert_not_null(ui._bag_physics)
	assert_gt(ui._bag_physics.ball_count(), 0)
	assert_true(ui._bag_physics._balls[0].has("ang"))
	# 弹仓格子仍是圆角面板（圆形）
	var panel: Panel = ui._chamber_panels[0]
	var stl := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(stl)
	assert_gt(stl.corner_radius_top_left, 20)
	# 手里的球仍是圆面板
	assert_false(ui._hand_slot_panels.is_empty())
	var hand: Panel = ui._hand_slot_panels[0]
	var hst := hand.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(hst)
	assert_gt(hst.corner_radius_top_left, 20)
