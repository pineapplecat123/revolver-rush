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
	assert_gte(HUD.flame_envelope([{"remaining":5}]).x, 180.0)
	assert_gte(HUD.flame_envelope([{"remaining":5}]).y, 70.0)
	assert_eq(HUD.flame_envelope([]), Vector2.ZERO)
func test_live_hud_icons_and_fire_follow_actual_consumption() -> void:
	var cs := CombatState.new(48101)
	var hud = HUD.new()
	add_child_autofree(hud)
	hud.setup(cs, func() -> Vector2: return Vector2(120,160))
	cs._volley_muzzle_buffs = [FireResolver.make_flame(52,0,5,1.0)]
	hud._process(2.0)
	assert_eq(hud._icons.size(),5)
	assert_true(hud._flame.visible)
	var original_size: Vector2 = hud._flame.envelope
	cs._volley_muzzle_buffs = FireResolver.consume_flame_layers(cs._volley_muzzle_buffs,0.0)
	hud._process(2.0)
	assert_eq(hud._icons.size(),5)
	assert_eq(hud._flame.envelope,original_size)
	for n in range(4,-1,-1):
		cs._volley_muzzle_buffs = FireResolver.consume_flame_layers(cs._volley_muzzle_buffs,3.0)
		hud._process(0.1)
		assert_eq(hud._icons.size(),n)
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
				assert_lte(y-previous_y,cu.ball_radius()/3.0)
			saw_partial = true
			previous_y = y
		if cu.is_drop_settled():break
	assert_gte(partial_frames,8,"normal-speed progressive reveal needs >=8 distinct 30fps frames")
	assert_eq(cu.all_ball_ids(),identities,"same simulated bodies, none spawned or removed")
	assert_eq(cu.tray_count(),1)
	assert_eq(cu.ball_count(),12)
	assert_eq(GumballCloseup.GRAVITY,BagPhysicsBox.GRAVITY)
	assert_eq(GumballCloseup.RESTITUTION,BagPhysicsBox.RESTITUTION)

func test_animated_flame_outline_never_self_intersects() -> void:
	for n in range(1,6):
		var shape := HUD.flame_envelope([{"remaining":n}])
		for frame in 160:
			var pts: PackedVector2Array = HUD._Flame.body_polygon(shape.x,shape.y*0.5,float(frame)/60.0,0)
			assert_false(Geometry2D.triangulate_polygon(pts).is_empty(),"flame polygon must not flicker/disappear at frame %d" % frame)
	for frame in 160:
		assert_false(Geometry2D.triangulate_polygon(EnhancedTracerFlame.flame_outline(float(frame)/60.0)).is_empty(),"burning tracer contour must stay drawable")
