extends SceneTree
## v0.4.78 静帧：开局三选一奖励文案、袋内详情，都来自游戏内描述。
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 800 -s tools/rr_v0478_desc_stills.gd

var _ui = null
var _reg = null

func _initialize() -> void:
	call_deferred("_run")


func _stamp(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = _ui.get_viewport().get_texture().get_image()
	var path := "res://docs/shots/%s.png" % name
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("saved ", abs_path, " ", img.get_width(), "x", img.get_height())


func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_campaign", true)
	cs_script.set("boot_sandbox", false)
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed")
		quit(1)
		return
	for _i in 180:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.campaign_mode:
			break
	if _ui == null or _ui.state == null:
		push_error("no ui")
		quit(1)
		return
	_reg = root.get_node("DataRegistry")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if _ui.has_method("_fit_combat_viewport"):
		_ui._fit_combat_viewport(Vector2(720, 1280))
	_ui.state.campaign_instant_transitions = true
	_ui.set_process(false)
	_ui._refresh()
	if _ui.has_method("_set_reward_open"):
		_ui._set_reward_open(true)
	_ui._refresh_reward_panel()
	for _j in 8:
		await process_frame
	var choices: Array = _ui.state.campaign_offer_choices.duplicate()
	print("opening_choices=", choices)
	for ammo_id in choices:
		print("choice id=", ammo_id, " name=", _reg.ammo_display_name(ammo_id),
			" gd=", _reg.ammo_game_description(ammo_id),
			" blurb=", _reg.format_ammo_reward_blurb(ammo_id))
	await _stamp("rr_v0478_opening_offer")

	# 选完开局，装弹后打开袋内详情（白板弹 + 选中的那发）
	if _ui.state.campaign_offer_pending:
		_ui.state.campaign_pick_opening(0)
	if _ui.state.campaign_phase == CampaignRules.PHASE_ENTER:
		_ui.state.campaign_skip_walk()
	_ui._set_reward_open(false)
	_ui._refresh()
	for _k in 6:
		await process_frame
	var show_id: int = CombatConstants.WHITE_AMMO_ID
	if not choices.is_empty():
		show_id = int(choices[0])
	_ui._show_ammo_detail(show_id, null, false, true)
	for _m in 6:
		await process_frame
	print("detail_id=", show_id, " name=", _reg.ammo_display_name(show_id))
	print("detail_text=\n", _reg.format_ammo_detail_text(show_id))
	await _stamp("rr_v0478_ammo_detail")
	# 白板详情再拍一张便于对照已有描述未被默认文案覆盖
	_ui._show_ammo_detail(CombatConstants.WHITE_AMMO_ID, null, false, true)
	for _n in 4:
		await process_frame
	print("white_detail=\n", _reg.format_ammo_detail_text(CombatConstants.WHITE_AMMO_ID))
	await _stamp("rr_v0478_white_detail")
	quit(0)
