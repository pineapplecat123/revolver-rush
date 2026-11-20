extends SceneTree
## v0.4.76 糖果机特写演示：走近 → 放大特写（出球口不被挡住）→ 物理出球弹跳 → 继续下一波。
## 静帧：
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 2400 -s tools/rr_v0476_gumball_demo.gd
## 录像：
##   xvfb-run -a godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 2400 \
##     --write-movie /tmp/rr_v0476_gumball_demo.avi -s tools/rr_v0476_gumball_demo.gd

var _ui = null
var _banner: Label = null
var _movie: bool = false
const DT := 1.0 / 30.0


func _initialize() -> void:
	call_deferred("_run")


func _label(text: String) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.name = "GumballDemoBanner"
		_banner.position = Vector2(16, 4)
		_banner.size = Vector2(688, 52)
		_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner.add_theme_font_size_override("font_size", 17)
		_banner.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
		_banner.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.85))
		_banner.add_theme_constant_override("outline_size", 4)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.z_index = 130
		_ui.add_child(_banner)
	_banner.text = text


func _stamp(name: String) -> void:
	if _movie:
		return
	await process_frame
	await process_frame
	var img: Image = _ui.get_viewport().get_texture().get_image()
	var path := "/tmp/%s.png" % name
	img.save_png(path)
	var cu = _ui.get("_gumball_closeup")
	var extra := ""
	if cu != null:
		extra = " closeup=%s ball=%s y=%.1f" % [cu.visible, cu.is_ball_active(), cu.ball_pos().y]
	print("saved ", path, " phase=", _ui.state.campaign_phase, " alley=", _ui.state.alley_seq, extra)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _tick(dt: float) -> void:
	if _ui.state.alley_is_walking() or _ui.state.alley_seq == 1 or _ui.state.alley_seq == 3:
		_ui.state.tick_alley(dt)
	_ui._apply_campaign_presentation()
	_ui._sync_campaign_backdrop()
	var bg = _ui.get("_campaign_backdrop")
	if bg != null and bg.has_method("advance"):
		bg.advance(dt, float(_ui.get("_campaign_debris_drift")))
	_ui._sync_shop_house()
	_ui._sync_alley_prop()
	_ui._tick_alley_anim(dt)
	var cu = _ui.get("_gumball_closeup")
	if _banner != null and cu != null and cu.visible:
		_banner.position = Vector2(16, 1168)
		_banner.z_index = 130
	elif _banner != null:
		_banner.position = Vector2(16, 4)
	var cat = _ui.get("_skel_player")
	if cat != null and cat.has_method("_process"):
		cat._process(dt)


func _closeup():
	return _ui.get("_gumball_closeup")


func _run() -> void:
	_movie = OS.get_cmdline_user_args().has("--movie") or OS.has_feature("movie")
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
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if _ui.has_method("_fit_combat_viewport"):
		_ui._fit_combat_viewport(Vector2(720, 1280))
	if _ui.state.campaign_offer_pending:
		_ui.state.campaign_pick_opening(0)
	_ui.state.campaign_instant_transitions = false
	_ui.state.campaign_skip_walk()
	_ui.state.gold = 20
	_ui._refresh()
	_ui._ensure_campaign_backdrop()
	_ui._ensure_alley_props()
	_label("演示 · 第一波打完后，糖果机从右边进来")
	_ui.set_process(false)
	for _w in 16:
		_tick(DT)
		await process_frame
	await _stamp("rr_v0476_gumball_combat")

	_ui.state.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_ui.state.enemies.clear()
	_ui.state.reward_pending = false
	_ui.state.pending_levelups = 0
	_ui.state.campaign_try_advance()
	_ui._sync_alley_prop()
	_label("演示 · 糖果机从画面右边外面滑进来")
	await _stamp("rr_v0476_gumball_offscreen")
	var approach: float = CampaignRules.walk_to_alley_sec(CampaignRules.ALLEY_GUMBALL)
	var acc := 0.0
	var view_r: float = CampaignRules.shop_house_view_width()
	var revealed := false
	while acc < approach + 0.02:
		_tick(DT)
		acc += DT
		await process_frame
		var left_now: float = _ui.state.alley_left_at(_ui._player_foot_global_x())
		if not revealed and left_now < view_r - 40.0:
			revealed = true
			_label("演示 · 右缘露出糖果机，继续走近")
			await _stamp("rr_v0476_gumball_reveal")
		if acc >= approach * 0.45 and acc < approach * 0.45 + DT * 1.5:
			await _stamp("rr_v0476_gumball_approach")
	_ui._sync_alley_prop()
	_label("演示 · 放大特写，出球口和托盘都看得见")
	await _frames(20)
	await _stamp("rr_v0476_gumball_offer")
	_ui._on_alley_use()
	_ui._sync_alley_prop()
	_label("演示 · 投币、摇把，子弹从出球口掉下来")
	var cu = _closeup()
	var a := 0.0
	var saw_release := false
	var saw_fall := false
	var saw_bounce := false
	var saw_settle := false
	# 摇把约 0.95s，下落约 0.5s，弹跳再 1s+，至少看 1.25s
	while a < 4.2:
		_tick(DT)
		a += DT
		await process_frame
		cu = _closeup()
		if cu == null:
			continue
		if not saw_release and cu.is_ball_active():
			saw_release = true
			_label("演示 · 球从出球口出来")
			await _stamp("rr_v0476_gumball_release")
		if saw_release and not saw_fall and cu.is_ball_active() and not cu.has_contacted_floor():
			var mid: float = (cu.outlet_point().y + cu.floor_y()) * 0.5
			if cu.ball_pos().y >= mid - 8.0:
				saw_fall = true
				_label("演示 · 球正在往下掉")
				await _stamp("rr_v0476_gumball_fall")
		if not saw_bounce and cu.has_contacted_floor() and (cu.bounce_count() >= 1 or cu.ball_vel().y < 0.0):
			saw_bounce = true
			_label("演示 · 球碰到托盘弹起来")
			await _stamp("rr_v0476_gumball_bounce")
		if not saw_settle and cu.is_drop_settled():
			saw_settle = true
			_label("演示 · 球停住，看清奖励后再继续")
			await _stamp("rr_v0476_gumball_settle")
			break
	cu = _closeup()
	if cu != null and not cu.is_drop_settled():
		# 再补一段时间，确保能继续
		var extra := 0.0
		while extra < 1.5 and cu != null and not cu.is_drop_settled():
			_tick(DT)
			extra += DT
			await process_frame
			cu = _closeup()
		await _stamp("rr_v0476_gumball_settle")
	await _frames(16)
	await _stamp("rr_v0476_gumball_result")
	_ui._on_alley_leave()
	_label("演示 · 子弹进袋，糖果机向左离开")
	var exit_sec: float = CampaignRules.walk_from_alley_sec(CampaignRules.ALLEY_GUMBALL)
	var ex := 0.0
	var receded := false
	while ex < exit_sec + 0.05:
		_tick(DT)
		ex += DT
		await process_frame
		var left_exit: float = _ui.state.alley_left_at(_ui._player_foot_global_x()) if _ui.state.alley_seq != 0 else -999.0
		var right: float = left_exit + CampaignRules.gumball_width() + 8.0
		if not receded and right < 200.0 and right > 16.0:
			receded = true
			await _stamp("rr_v0476_gumball_recede")
	_ui._sync_alley_prop()
	_label("演示 · 下一波出现")
	_ui.set_process(true)
	await _frames(16)
	await _stamp("rr_v0476_gumball_resume")
	print("gumball closeup demo done release=", saw_release, " fall=", saw_fall, " bounce=", saw_bounce, " settle=", saw_settle)
	quit(0)
