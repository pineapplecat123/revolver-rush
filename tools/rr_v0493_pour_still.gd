extends SceneTree
## v0.4.93 native 720x1280 still: pouring the entire bag leaves the sack empty (no flash spawn).
##   godot --path . --resolution 720x1280 --quit-after 2400 -s res://tools/rr_v0493_pour_still.gd
const OUT := "/workspace/rr-v0493-verification"
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
	if cs.hand.size() > 0:
		cs.return_hand_to_bag()
		cs.dev_clear_bag()
	for _j in 6:
		cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 1)
	ui._refresh()
	await process_frame
	await process_frame
	if not ui._should_play_dump_pour():
		push_error("pour path unavailable (headless?) display=" + DisplayServer.get_name())
		quit(1)
		return
	var peak_after_empty := 0
	var saw_empty := false
	ui._on_manual_load()
	var waited := 0
	while waited < 1200:
		await process_frame
		waited += 1
		var box = ui._bag_physics
		if box == null or not is_instance_valid(box):
			continue
		var bag_bodies: int = box.bag_body_count()
		if bag_bodies == 0 and (box.fallen_count() >= 6 or box.catch_body_count() >= 6 or cs.hand.size() >= 6):
			saw_empty = true
		if saw_empty:
			peak_after_empty = maxi(peak_after_empty, bag_bodies)
		if not ui._dump_pouring and box.catch_body_count() >= 6:
			for _k in 20:
				await process_frame
				if is_instance_valid(box):
					peak_after_empty = maxi(peak_after_empty, box.bag_body_count())
			break
	var box2 = ui._bag_physics
	var n: int = box2.catch_body_count() if box2 != null else 0
	var bag_bodies2: int = box2.bag_body_count() if box2 != null else -1
	print("catch_bodies=", n, " hand=", cs.hand.size(), " bag=", cs.bag.size(), " bag_bodies=", bag_bodies2, " peak_after_empty=", peak_after_empty)
	if n != 6 or cs.hand.size() != 6 or cs.bag.size() != 0 or bag_bodies2 != 0:
		push_error("expected a full-hand pile and an empty sack")
		quit(1)
		return
	if peak_after_empty != 0:
		push_error("bag respawned after it was emptied")
		quit(1)
		return
	await _stamp("rr_v0493_full_dump_empty_bag")
	quit(0)
