extends Node
## v0.4.97 closeup enter: hopper already under gravity, no lever pull.
##   DISPLAY=:2 godot --path . --resolution 720x1280 --quit-after 2400 res://tools/rr_v0497_hopper_settle.tscn
const OUT := "/workspace/rr-v0497-verification"
const FRAMES := "/tmp/rr_v0497_hopper_frames"
const SHOTS := "res://docs/shots"
const SEED := 49714

func _ready() -> void:
	call_deferred("_run")


func _grab(dir: String, i: int) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/f%04d.png" % [dir, i])


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if get_viewport() != null:
		get_viewport().size = Vector2i(720, 1280)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = Vector2(720, 1280)
	add_child(bg)
	var cu := GumballCloseup.new()
	cu.size = Vector2(720, 1280)
	cu.set_anchors_preset(Control.PRESET_FULL_RECT)
	cu.drop_rng = RandomNumberGenerator.new()
	cu.drop_rng.seed = SEED
	add_child(cu)
	cu.present()
	cu.set_can_commit(true, false)
	cu.begin_session_with_ids([49, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52])
	DirAccess.make_dir_recursive_absolute(FRAMES)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	await get_tree().process_frame
	var n := 0
	var max_dy := 0.0
	var y0: Array = []
	for b in cu._balls:
		y0.append(float(b["pos"].y))
	while n < 75:
		cu.tick(1.0 / 30.0)
		if cu.lever_pull() > 0.01:
			push_error("lever moved during idle hopper clip")
			get_tree().quit(1)
			return
		for i in cu._balls.size():
			max_dy = maxf(max_dy, float(cu._balls[i]["pos"].y) - float(y0[i]))
		print("frame=", n, " sim=", cu.hopper_is_simulating(), " pull=", cu.lever_pull(), " dy=", max_dy, " settled=", cu.is_hopper_settled())
		await _grab(FRAMES, n)
		n += 1
		if n > 24 and cu.is_hopper_settled() and max_dy > 8.0:
			for _k in 8:
				cu.tick(1.0 / 30.0)
				await _grab(FRAMES, n)
				n += 1
			break
	print("frames=", n, " max_dy=", max_dy, " sim=", cu.hopper_is_simulating(), " pull=", cu.lever_pull(), " settled=", cu.is_hopper_settled())
	if n < 18 or max_dy < 8.0 or cu.lever_pull() > 0.01:
		push_error("hopper settle clip did not show pre-pull gravity")
		get_tree().quit(1)
		return
	print("ready_to_encode")
	get_tree().quit(0)
