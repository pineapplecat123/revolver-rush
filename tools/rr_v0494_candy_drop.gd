extends SceneTree
## v0.4.94 native 720x1280 candy-drop clip.
##   DISPLAY=:2 godot --path . --resolution 720x1280 --quit-after 2400 -s res://tools/rr_v0494_candy_drop.gd
const OUT := "/workspace/rr-v0494-verification"
const FRAMES := "/tmp/rr_v0494_frames"
const SHOTS := "res://docs/shots"

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
	root.add_child(cu)
	cu.present()
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	for _i in 90:
		cu.tick(1.0 / 30.0)
		await process_frame
	cu.set_can_commit(true, false)
	cu.lever_commit_requested.connect(func(): cu.accept_commit(), CONNECT_ONE_SHOT)
	cu.simulate_full_stroke()
	DirAccess.make_dir_recursive_absolute(FRAMES)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	# 丢掉闸门未开的前段，从球接近出球口开始录。
	var started := false
	var n := 0
	var max_frames := 90
	while n < max_frames:
		cu.tick(1.0 / 30.0)
		var y: float = cu.ball_pos().y
		if not started and y > cu.outlet_reveal_y() - 8.0:
			started = true
		if started:
			await _grab(FRAMES, n)
			n += 1
		else:
			await process_frame
		if started and cu.is_drop_settled() and n > 18:
			# 落地后再留十几帧看弹跳和停下。
			for _k in 16:
				cu.tick(1.0 / 30.0)
				await _grab(FRAMES, n)
				n += 1
			break
	print("frames=", n, " y=", cu.ball_pos().y, " floor=", cu.has_contacted_floor(), " bounce=", cu.bounce_count(), " tray=", cu.tray_count())
	if n < 12 or not cu.has_contacted_floor() or cu.bounce_count() < 1:
		push_error("drop clip incomplete")
		quit(1)
		return
	print("ready_to_encode")
	quit(0)
