extends Node
## v0.4.97 still of the three-square reward picker. Run as a scene, not -s:
##   DISPLAY=:2 godot --path . --resolution 720x1280 --quit-after 2000 res://tools/rr_v0497_reward_picker_shot.tscn

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1280))
	CombatState.boot_campaign = true
	var ui = load("res://scenes/combat.tscn").instantiate()
	add_child(ui)
	ui.size = Vector2(720, 1280)
	for _i in 6:
		await get_tree().process_frame
	CombatState.boot_campaign = false
	if ui.get_viewport() != null:
		ui.get_viewport().size = Vector2i(720, 1280)
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var cs: CombatState = ui.state
	cs.campaign_instant_transitions = true
	if cs.campaign_offer_pending:
		cs.campaign_pick_opening(0)
	cs.pending_levelups = 1
	cs.reward_pending = true
	cs.reward_choices = [CombatConstants.WHITE_AMMO_ID, 41, 52] as Array[int]
	ui._open_reward_panel_now()
	for _j in 8:
		await get_tree().process_frame
	if not ui._reward_open:
		push_error("reward picker did not open")
		get_tree().quit(1)
		return
	var img: Image = get_viewport().get_texture().get_image()
	var repo_path: String = ProjectSettings.globalize_path("res://docs/shots/rr_v0497_reward_picker.png")
	DirAccess.make_dir_recursive_absolute(repo_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute("/workspace/rr-v0497-verification")
	var err: Error = img.save_png(repo_path)
	img.save_png("/workspace/rr-v0497-verification/rr_v0497_reward_picker.png")
	print("saved ", repo_path, " ", err, " size=", img.get_width(), "x", img.get_height(), " open=", ui._reward_open, " cells=", ui.reward_choice_buttons().size())
	get_tree().quit(0 if err == OK else 1)
