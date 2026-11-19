extends SceneTree
## v0.4.68 闯关演示（加速）：开局三选一、战斗慢走边打、走进商店快走。
## 本片不是完整 9 关自然游玩。加速清段时会连续一键杀光整波，若保留碎块会在短时间内叠满既有死亡特效。
## 演示里清掉这些叠加碎块，避免被误认成闯关把血浆放大了；游戏内碎块逻辑未改。
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


func _clear_demo_gore() -> void:
	## 只清演示层上的碎块/血迹，不碰 CombatState。立即 free，避免等 queue_free 的那几帧被录像拍到。
	if _ui == null:
		return
	var gore = _ui.get("_gore_layer")
	if gore == null or not is_instance_valid(gore):
		return
	gore._pieces.clear()
	gore._drops.clear()
	var kids: Array = gore.get_children()
	for c in kids:
		if is_instance_valid(c):
			gore.remove_child(c)
			c.free()
	# 升级面板也不要在快进里闪一下
	if _ui.get("_reward_open") == true and _ui.has_method("_set_reward_open"):
		if _ui.state != null and not _ui.state.reward_pending and not _ui.state.campaign_offer_pending:
			_ui._set_reward_open(false)


func _silent_jump_to_shop_walk() -> void:
	## 只改本演示的推进，不发击杀通知、不刷碎块。
	if _ui == null or _ui.state == null:
		return
	var st = _ui.state
	st.enemies.clear()
	st.reward_pending = false
	st.pending_levelups = 0
	st._clear_reward_state()
	st.shop_touch_pending = false
	st.shop_hold = false
	st.campaign_instant_transitions = false
	st.campaign_transition_lock = true
	st.campaign_phase = CampaignRules.PHASE_WALK_SHOP
	st.campaign_walk_left = 2.6
	st.encounter_kind = 0
	# 卸掉场上敌人骨架，走离场分支（不调用致死碎块）
	var skels = _ui.get("_skel_enemies")
	if skels is Dictionary:
		for eid in skels.keys():
			var sk = skels[eid]
			if sk != null and is_instance_valid(sk):
				sk.queue_free()
		skels.clear()
	if _ui.has_method("_set_reward_open"):
		_ui._set_reward_open(false)


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

	# 加速只跳状态、不走一键杀敌：连续 dev_kill 会在短片里叠满既有死亡碎块，容易误导。
	_label("闯关演示（加速）· 走进商店（快走）")
	_silent_jump_to_shop_walk()
	_ui._refresh()
	_clear_demo_gore()
	if cat != null:
		cat.set_walk_tempo(_ui.state.campaign_walk_tempo())
		cat.set_walking(true)
	for _m in 30:
		_clear_demo_gore()
		await process_frame
	_clear_demo_gore()
	await _stamp("rr_v0468_shop_walk")
	for _m2 in 40:
		_clear_demo_gore()
		await process_frame
	print("demo done")
	quit(0)
