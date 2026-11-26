extends SceneTree
## v0.4.96 native 720x1280 candy-machine clip: bigger clear globe, connected red glowing lever, pull, roll.
##   DISPLAY=:2 godot --path . --resolution 720x1280 --quit-after 2400 -s res://tools/rr_v0496_candy_machine.gd
const OUT := "/workspace/rr-v0496-verification"
const FRAMES := "/tmp/rr_v0496_frames"
const SHOTS := "res://docs/shots"
const SEED := 49614

func _initialize() -> void:
	call_deferred("_run")


func _grab(dir: String, i: int) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("%s/f%04d.png" % [dir, i])


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = Vector2(720, 1280)
	root.add_child(bg)
	var cu := GumballCloseup.new()
	cu.size = Vector2(720, 1280)
	cu.set_anchors_preset(Control.PRESET_FULL_RECT)
	cu.drop_rng = RandomNumberGenerator.new()
	cu.drop_rng.seed = SEED
	root.add_child(cu)
	cu.present()
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	cu.set_can_commit(true, false)
	# Hold on the idle machine so the bigger globe, connected shaft, and glowing red knob are visible.
	DirAccess.make_dir_recursive_absolute(FRAMES)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var n := 0
	for _idle in 24:
		cu.tick(1.0 / 30.0)
		print("frame=", n, " idle knob=", cu.lever_handle_pos(), " pivot=", cu.lever_pivot(), " mounted=", cu.lever_is_mounted_on_body())
		await _grab(FRAMES, n)
		n += 1
	cu.lever_commit_requested.connect(func(): cu.accept_commit(), CONNECT_ONE_SHOT)
	# Animate the pull over a few frames instead of a one-shot stroke snap.
	cu.simulate_pointer_down(cu.lever_rest_pos())
	var steps := 10
	for i in steps:
		var t: float = float(i + 1) / float(steps)
		cu.simulate_pointer_move(cu.lever_rest_pos().lerp(cu.lever_pulled_pos(), t))
		cu.tick(1.0 / 30.0)
		print("frame=", n, " pull=", cu.lever_pull(), " handle=", cu.lever_handle_pos())
		await _grab(FRAMES, n)
		n += 1
	cu.simulate_pointer_up(cu.lever_pulled_pos())
	var started := false
	var path: Array = []
	var guard := 0
	while n < 110 and guard < 180:
		guard += 1
		cu.tick(1.0 / 30.0)
		var p: Vector2 = cu.ball_pos()
		if not started and p.y > cu.outlet_reveal_y() - 8.0:
			started = true
		if started:
			path.append(p)
			print("frame=", n, " pos=", p, " kick=", cu.payload_exit_kick())
			await _grab(FRAMES, n)
			n += 1
		else:
			# Still grab a few pre-exit frames so the pull-to-drop is visible.
			if n < 50:
				print("frame=", n, " wait pos=", p)
				await _grab(FRAMES, n)
				n += 1
			else:
				await process_frame
		if started and cu.is_drop_settled() and n > 40:
			for _k in 14:
				cu.tick(1.0 / 30.0)
				var p2: Vector2 = cu.ball_pos()
				path.append(p2)
				print("frame=", n, " pos=", p2, " kick=", cu.payload_exit_kick())
				await _grab(FRAMES, n)
				n += 1
			break
	var mid: float = cu.outlet_point().x
	var max_dx := 0.0
	for q in path:
		max_dx = maxf(max_dx, absf(q.x - mid))
	print("frames=", n, " kick=", cu.last_exit_kick, " mid_x=", mid, " max_dx=", max_dx, " floor=", cu.has_contacted_floor(), " bounce=", cu.bounce_count(), " mounted=", cu.lever_is_mounted_on_body(), " lid=", cu.draws_globe_lid())
	if n < 24 or not cu.has_contacted_floor() or cu.bounce_count() < 1 or max_dx < 24.0 or cu.last_exit_kick == 0.0 or not cu.lever_is_mounted_on_body() or cu.draws_globe_lid():
		push_error("machine clip incomplete or machine/lever/roll not as specified")
		quit(1)
		return
	print("ready_to_encode")
	quit(0)
