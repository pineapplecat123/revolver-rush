extends GutTest
const HUD := preload("res://scripts/combat/muzzle_status_hud.gd")
func before_each() -> void:
	DataRegistry.reload()
func test_persistent_fire_has_large_envelope_and_shrinks_each_layer() -> void:
	var previous := Vector2(999,999)
	for n in range(5,0,-1):
		var shape := HUD.flame_envelope([{"remaining":n}])
		assert_lt(shape.x, previous.x)
		assert_lt(shape.y, previous.y)
		previous = shape
	var five := HUD.flame_envelope([{"remaining":5}])
	assert_almost_eq(five.x, 67.8, 0.05)
	assert_almost_eq(five.y, 106.8, 0.05)
	assert_gt(five.y, five.x)
	assert_eq(HUD.flame_envelope([]), Vector2.ZERO)
func test_live_hud_icons_and_fire_follow_actual_consumption() -> void:
	var cs := CombatState.new(48101)
	var hud = HUD.new()
	add_child_autofree(hud)
	hud.setup(cs, func() -> Vector2: return Vector2(120,160))
	cs._volley_muzzle_buffs = [FireResolver.make_flame(52,0,5,1.0)]
	hud._process(2.0)
	assert_eq(hud._icons.size(),1)
	assert_eq(int(hud._icons[0].stack_count),5)
	assert_eq(hud._icons[0].count_text(),"×5")
	assert_true(hud._flame.visible)
	var original_size: Vector2 = hud._flame.envelope
	cs._volley_muzzle_buffs = FireResolver.consume_flame_layers(cs._volley_muzzle_buffs,0.0)
	hud._process(2.0)
	assert_eq(hud._icons.size(),1)
	assert_eq(int(hud._icons[0].stack_count),5)
	assert_eq(hud._flame.envelope,original_size)
	for n in range(4,-1,-1):
		cs._volley_muzzle_buffs = FireResolver.consume_flame_layers(cs._volley_muzzle_buffs,3.0)
		hud._process(0.1)
		if n == 0:
			assert_eq(hud._icons.size(),0)
		else:
			assert_eq(hud._icons.size(),1)
			assert_eq(int(hud._icons[0].stack_count),n)
			assert_eq(hud._icons[0].count_text(), "" if n == 1 else "×%d" % n)
		assert_eq(hud._flame.visible,n>0)
func test_payload_progressively_emerges_for_readable_multiple_frames() -> void:
	var cu := GumballCloseup.new()
	cu.size = Vector2(720,1280)
	add_child_autofree(cu)
	cu.present()
	cu.begin_session_with_ids([49,40,41,42,43,44,45,46,47,50,51,52])
	for i in 150:
		cu.tick(1.0/30.0)
	cu.set_can_commit(true,false)
	cu.lever_commit_requested.connect(func():cu.accept_commit(),CONNECT_ONE_SHOT)
	cu.simulate_full_stroke()
	assert_true(cu.is_commit_accepted())
	var identities: Array = cu.all_ball_ids().duplicate()
	var partial_frames := 0
	var previous_y := -INF
	var saw_partial := false
	for i in 240:
		cu.tick(1.0/30.0)
		var y := cu.ball_pos().y
		var exposed := y + cu.ball_radius() - cu.outlet_reveal_y()
		if exposed > 0 and exposed < 2.0*cu.ball_radius():
			partial_frames += 1
			if saw_partial:
				assert_gte(y,previous_y-0.1)
				# 过闸后是重力下落，帧位移可以大于半径/3；整球瞬移出罩才算坏。
				assert_lte(y-previous_y,cu.ball_radius()*3.0)
			saw_partial = true
			previous_y = y
		if cu.is_drop_settled():break
	assert_gte(partial_frames,2,"ball must be visibly emerging for more than one frame, not teleporting out")
	assert_true(saw_partial)
	assert_eq(cu.all_ball_ids(),identities,"same simulated bodies, none spawned or removed")
	assert_eq(cu.tray_count(),1)
	assert_eq(cu.ball_count(),12)
	assert_eq(GumballCloseup.GRAVITY,BagPhysicsBox.GRAVITY)
	assert_eq(GumballCloseup.RESTITUTION,BagPhysicsBox.RESTITUTION)

func test_persistent_flame_silhouette_is_upright() -> void:
	var shape := HUD.flame_envelope([{"remaining":5}])
	var pts: PackedVector2Array = HUD._Flame.body_polygon(shape.x, shape.y, 0.2, 0)
	var min_x := 9999.0
	var max_x := -9999.0
	var min_y := 9999.0
	var max_y := -9999.0
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	assert_gt(max_y - min_y, max_x - min_x, "silhouette must be taller than wide")
	assert_gt(-min_y, max_y, "most of the body must extend upward from the muzzle")
	assert_lt(max_x, -min_y, "must not be a forward horizontal jet")

func test_animated_flame_outline_never_self_intersects() -> void:
	for n in range(1,6):
		var shape := HUD.flame_envelope([{"remaining":n}])
		for frame in 160:
			var pts: PackedVector2Array = HUD._Flame.body_polygon(shape.x,shape.y,float(frame)/60.0,0)
			assert_false(Geometry2D.triangulate_polygon(pts).is_empty(),"flame polygon must not flicker/disappear at frame %d" % frame)
	for frame in 160:
		assert_false(Geometry2D.triangulate_polygon(EnhancedTracerFlame.flame_outline(float(frame)/60.0)).is_empty(),"burning tracer contour must stay drawable")

func test_top_hud_stays_readable_over_largest_flame() -> void:
	# Layering only: do not shrink the owner-requested tall 🔥 silhouette.
	var five := HUD.flame_envelope([{"remaining":5}])
	assert_almost_eq(five.x, 67.8, 0.05)
	assert_almost_eq(five.y, 106.8, 0.05)
	assert_gt(five.y, five.x)
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	assert_not_null(ui._muzzle_status_hud)
	assert_lt(ui._muzzle_status_hud.z_index, ui.Z_MODAL_DIMMER)
	assert_lt(ui._muzzle_status_hud.z_index, ui.Z_TOP_HUD)
	for path in [
		"Margin/RootVBox/TopPanel/TopSection/TopButtons",
		"Margin/RootVBox/TopPanel/TopSection/TopBarPad",
		"Margin/RootVBox/TopPanel/TopSection/BoardTitle",
	]:
		var c: CanvasItem = ui.get_node(path)
		assert_false(c.z_as_relative)
		assert_eq(c.z_index, ui.Z_TOP_HUD)
		assert_gt(c.z_index, ui._muzzle_status_hud.z_index)
