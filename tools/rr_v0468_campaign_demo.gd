extends SceneTree
## v0.4.68 闯关演示（加速）：开局三选一、战斗慢走边打、走进商店快走。
## 静帧：
##   godot --path . --headless --quit-after 400 -s tools/rr_v0468_campaign_demo.gd
## 录像（加速、有标签）：
##   godot --path . -w --resolution 720x1280 --fixed-fps 30 --quit-after 300 \
##     --write-movie /tmp/rr_v0468_campaign_demo.avi -s tools/rr_v0468_campaign_demo.gd

var _ui = null
var _banner: Label = null


func _initialize() -> void:
	call_deferred("_run")


func _stamp(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = _ui.get_viewport().get_texture().get_image()
	var path := "/tmp/%s.png" % name
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height(), " phase=", _ui.state.campaign_phase, " progress=", _ui.state.campaign_progress_text())


func _label(text: String) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.name = "CampaignDemoBanner"
		_banner.position = Vector2(16, 8)
		_banner.size = Vector2(688, 36)
		_banner.add_theme_font_size_override("font_size", 20)
		_banner.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(_banner)
	_banner.text = text


func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_campaign", true)
	cs_script.set("boot_sandbox", false)
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	for _i in 180:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.campaign_mode:
			break
	if _ui == null or _ui.state == null:
		push_error("campaign ui failed to boot")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(720, 1280))
	_ui._fit_combat_viewport(Vector2(720, 1280))
	_label("闯关演示（加速）· 开局三选一")
	for _hold in 40:
		await process_frame
	await _stamp("rr_v0468_offer")

	if _ui.state.campaign_offer_pending:
		_ui.state.campaign_pick_opening(0)
	_ui.state.campaign_instant_transitions = false
	# 进场快走：拉长过场，中途截帧，避免还没拍就已经开战
	_ui.state.campaign_walk_left = 2.4
	_ui._refresh()
	_label("闯关演示（加速）· 进场快走")
	for _j in 28:
		await process_frame
	await _stamp("rr_v0468_enter_walk")
	for _j2 in 40:
		await process_frame

	_ui.state.campaign_skip_walk()
	_ui._refresh()
	_label("闯关演示（加速）· 战斗慢走边打")
	var cat = _ui.get("_skel_player")
	if cat != null:
		cat.set_walk_tempo(_ui.state.campaign_walk_tempo())
		cat.set_walking(true)
		cat.play_shoot()
	for _k in 70:
		if cat != null and int(_k) % 10 == 0:
			cat.play_shoot()
		await process_frame
	await _stamp("rr_v0468_combat_walk_fire")

	# 清完本段（含升级选择），走到商店（快走）
	for _n in 40:
		if _ui.state.campaign_phase == CampaignRules.PHASE_WALK_SHOP:
			break
		if _ui.state.reward_pending:
			_ui.state.skip_reward_for_gold()
			_ui._refresh()
			await process_frame
			continue
		if _ui.state.alive_enemies().size() > 0:
			_ui.state.dev_kill_all_enemies()
		else:
			_ui.state.campaign_try_advance()
		_ui._refresh()
		await process_frame
	if _ui.state.campaign_phase != CampaignRules.PHASE_WALK_SHOP:
		push_warning("demo did not reach walk-to-shop, phase=%s" % _ui.state.campaign_phase)
	_ui.state.campaign_walk_left = 2.6
	_ui._refresh()
	_label("闯关演示（加速）· 走进商店（快走）")
	if cat != null:
		cat.set_walk_tempo(_ui.state.campaign_walk_tempo())
		cat.set_walking(true)
	for _m in 30:
		await process_frame
	await _stamp("rr_v0468_shop_walk")
	for _m2 in 40:
		await process_frame
	print("demo done")
	quit(0)
