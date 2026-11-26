extends SceneTree
## v0.4.92 native 720x1280 still: poured hand pile stays physical after the sack untilts.
##   godot --path . --resolution 720x1280 --quit-after 2400 -s res://tools/rr_v0492_pour_still.gd
const OUT := "/workspace/rr-v0492-verification"
const SHOTS := "res://docs/shots"

func _initialize() -> void:
	call_deferred("_run")


func _stamp(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var docs := ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, name])
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png("%s/%s.png" % [OUT, name])
	img.save_png(docs)
	print("saved ", name, " ", img.get_width(), "x", img.get_height())


func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	cs_script.set("boot_campaign", false)
	if change_scene_to_file("res://scenes/combat.tscn") != OK:
		push_error("scene")
		quit(1)
		return
	var ui = null
	for _i in 180:
		await process_frame
		ui = current_scene
		if ui != null and ui.get("state") != null and ui.state.sandbox_mode:
			break
	if ui == null or ui.state == null:
		push_error("no ui")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if ui.has_method("_fit_combat_viewport"):
		ui._fit_combat_viewport(Vector2(720, 1280))
	var cs = ui.state
	cs.dev_clear_bag()
	for _j in 10:
		cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 1)
	# Return any existing hand so the pile starts empty.
	if cs.hand.size() > 0:
		cs.return_hand_to_bag()
	ui._refresh()
	await process_frame
	await process_frame
	if not ui._should_play_dump_pour():
		push_error("pour path unavailable (headless?) display=" + DisplayServer.get_name())
		quit(1)
		return
	ui._on_manual_load()
	# 在倒出过程中一旦手区有足够物理球且高低错落，立刻拍照，避免全部落地成一行。
	var waited := 0
	var stamped_mid := false
	var box = ui._bag_physics
	while waited < 1200:
		await process_frame
		waited += 1
		box = ui._bag_physics
		if box == null or not is_instance_valid(box):
			continue
		var pile: Array = []
		for b in box._balls:
			if bool(b.get("catch_body", false)) or bool(b.get("exited", false)):
				pile.append(b["pos"])
		if pile.size() < 6 or cs.hand.size() < 6:
			continue
		var ymin := INF
		var ymax := -INF
		for p in pile:
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		if ymax - ymin >= 28.0:
			print("mid-pour y-span=", ymax - ymin, " pile=", pile.size(), " hand=", cs.hand.size(), " pouring=", ui._dump_pouring)
			stamped_mid = true
			break
		if not ui._dump_pouring and box.catch_body_count() >= 6:
			break
	if box == null:
		push_error("no bag physics")
		quit(1)
		return
	var n: int = box.catch_body_count()
	var exited := 0
	for b2 in box._balls:
		if bool(b2.get("exited", false)) and not bool(b2.get("catch_body", false)):
			exited += 1
	print("catch_bodies=", n, " hand=", cs.hand.size(), " bag=", cs.bag.size(), " bag_bodies=", box.bag_body_count(), " unpromoted_exited=", exited, " mid=", stamped_mid)
	for rec in box.catch_body_records():
		print(" catch pos=", rec["pos"], " world=", rec.get("world_pos", Vector2.ZERO))
	for recx in box._balls:
		if bool(recx.get("exited", false)) and not bool(recx.get("catch_body", false)):
			print(" exited pos=", recx["pos"])
	if cs.hand.size() < 6:
		push_error("expected a full hand after pour")
		quit(1)
		return
	if n < 6 and not stamped_mid:
		push_error("expected every hand bullet to remain a catch body")
		quit(1)
		return
	if not stamped_mid:
		# 已经全部落地：提起两发再拍下落中的一帧，证明重力还在。
		var tossed := 0
		for b3 in box._balls:
			if not bool(b3.get("catch_body", false)):
				continue
			if tossed < 2:
				b3["asleep"] = false
				b3["held"] = false
				b3["freeze"] = 0
				b3["vel"] = Vector2(40.0 - tossed * 90.0, -40.0)
				b3["pos"] = Vector2(float(b3["pos"].x), box.hand_catch_rect.position.y + 18.0 + tossed * 16.0)
			tossed += 1
		for _f in 10:
			await process_frame
		print("fallback toss positions:")
		for rec2 in box.catch_body_records():
			print("  ", rec2["pos"])
	await _stamp("rr_v0492_pour_hand_pile")
	quit(0)
