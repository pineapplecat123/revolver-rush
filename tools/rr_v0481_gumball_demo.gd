extends SceneTree
## v0.4.81 糖果机特写演示：走近 → 放大特写（罩内物理球沉降）→ 指针下拉拉杆 → 计量出球落到托盘 → 继续下一波。
## 不用 Buy/dispense 接口代替拉杆。静帧：
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 3600 -s tools/rr_v0481_gumball_demo.gd
## 录像：
##   xvfb-run -a godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 3600 \
##     --write-movie /tmp/rr_v0481_gumball_demo.avi -s tools/rr_v0481_gumball_demo.gd

var _ui = null
var _banner: Label = null
var _movie: bool = false
var _trace: Array = []
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
	var img: Image = _ui.get_viewport().get_texture().get_image()
	var path := "res://docs/shots/%s.png" % name
	img.save_png(path)
	var cu = _closeup()
	var extra := ""
	if cu != null:
		extra = " closeup=%s hop=%s tray=%s pull=%.2f y=%.1f" % [
			cu.visible, cu.hopper_count(), cu.tray_count(), cu.lever_pull(), cu.ball_pos().y
		]
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
	var cu = _closeup()
	if cu != null and cu.visible and cu._payload_idx >= 0:
		_trace.append({"frame":Engine.get_process_frames(),"payload_index":cu._payload_idx,"ammo_id":cu._balls[cu._payload_idx]["id"],"x":cu.ball_pos().x,"y":cu.ball_pos().y,"radius":cu.ball_radius(),"reveal_y":cu.outlet_reveal_y(),"ball_count":cu.ball_count(),"exposed":clampf((cu.ball_pos().y+cu.ball_radius()-cu.outlet_reveal_y())/(2.0*cu.ball_radius()),0.0,1.0)})
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
	await _stamp("rr_v0481_gumball_combat")

	_ui.state.alley_force_kind = CampaignRules.ALLEY_GUMBALL
	_ui.state.enemies.clear()
	_ui.state.reward_pending = false
	_ui.state.pending_levelups = 0
	_ui.state.campaign_try_advance()
	_ui._sync_alley_prop()
	_label("演示 · 糖果机从画面右边外面滑进来")
	await _stamp("rr_v0481_gumball_offscreen")
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
			await _stamp("rr_v0481_gumball_reveal")
		if acc >= approach * 0.45 and acc < approach * 0.45 + DT * 1.5:
			await _stamp("rr_v0481_gumball_approach")
	_ui._sync_alley_prop()
	_label("演示 · 放大特写：罩里的球正在往下挤")
	# 让罩内球可见地沉降，不跳过这段
	var settle_t := 0.0
	var saw_settle := false
	while settle_t < 2.8:
		_tick(DT)
		settle_t += DT
		await process_frame
		if settle_t >= 0.25 and settle_t < 0.25 + DT * 1.2:
			await _stamp("rr_v0481_gumball_offer")
		var cu0 = _closeup()
		if not saw_settle and cu0 != null and cu0.is_hopper_settled() and settle_t >= 0.8:
			saw_settle = true
			_label("演示 · 球已经在罩里停住，向下拉拉杆")
			await _stamp("rr_v0481_gumball_hopper")
	if not saw_settle:
		await _stamp("rr_v0481_gumball_hopper")

	var cu = _closeup()
	if cu == null:
		push_error("no closeup")
		quit(1)
		return
	# 真实指针拖杆，不调用 buy / play_dispense。
	_label("演示 · 用指针抓住拉杆往下拉")
	var rest: Vector2 = cu.lever_rest_pos()
	var pulled: Vector2 = cu.lever_pulled_pos()
	cu.simulate_pointer_down(rest)
	var drag_steps := 12
	var stamped_pull := false
	for i in drag_steps:
		var t: float = float(i + 1) / float(drag_steps)
		cu.simulate_pointer_move(rest.lerp(pulled, t))
		_tick(DT)
		await process_frame
		if not stamped_pull and cu.lever_pull() >= 0.45 and cu.lever_pull() < 0.85:
			stamped_pull = true
			await _stamp("rr_v0481_gumball_pull")
	cu.simulate_pointer_up(pulled)
	_tick(DT)
	await process_frame
	_label("演示 · 拉满，扣 5 金，闸门放行一发")
	await _stamp("rr_v0481_gumball_commit")

	var a := 0.0
	var saw_meter := false
	var saw_release := false
	var saw_fall := false
	var saw_bounce := false
	var saw_drop_settle := false
	while a < 6.0:
		_tick(DT)
		a += DT
		await process_frame
		cu = _closeup()
		if cu == null:
			continue
		var py: float = cu.ball_pos().y
		if not saw_meter and cu.is_commit_accepted() and cu.gate_open_amount() > 0.3 and cu.tray_count() == 0:
			if py > cu.gate_y() - 4.0 and py < cu.outlet_point().y:
				saw_meter = true
				_label("演示 · 那一发正从颈部滑下来")
				await _stamp("rr_v0481_gumball_meter")
		if not saw_release and cu.tray_count() == 1:
			saw_release = true
			_label("演示 · 球从出球口出来")
			await _stamp("rr_v0481_gumball_release")
		if saw_release and not saw_fall and not cu.has_contacted_floor():
			var mid: float = (cu.outlet_point().y + cu.floor_y()) * 0.5
			if py >= mid - 8.0:
				saw_fall = true
				_label("演示 · 球正在往下掉")
				await _stamp("rr_v0481_gumball_fall")
		if not saw_bounce and cu.has_contacted_floor() and (cu.bounce_count() >= 1 or cu.ball_vel().y < 0.0):
			saw_bounce = true
			_label("演示 · 球碰到托盘弹起来")
			await _stamp("rr_v0481_gumball_bounce")
		if not saw_drop_settle and cu.is_drop_settled():
			saw_drop_settle = true
			_label("演示 · 球停住，看清奖励后再继续")
			await _stamp("rr_v0481_gumball_settle")
			break
	if not saw_drop_settle:
		var extra := 0.0
		while extra < 2.0:
			_tick(DT)
			extra += DT
			await process_frame
			cu = _closeup()
			if cu != null and cu.is_drop_settled():
				saw_drop_settle = true
				break
		await _stamp("rr_v0481_gumball_settle")
	await _frames(16)
	await _stamp("rr_v0481_gumball_result")
	_ui._on_alley_leave()
	_label("演示 · 那发子弹进袋，糖果机向左离开")
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
			await _stamp("rr_v0481_gumball_recede")
	_ui._sync_alley_prop()
	_label("演示 · 下一波出现")
	_ui.set_process(true)
	await _frames(16)
	await _stamp("rr_v0481_gumball_resume")
	print(
		"gumball hopper demo done hopper_settle=", saw_settle,
		" pull=", stamped_pull,
		" meter=", saw_meter,
		" release=", saw_release,
		" fall=", saw_fall,
		" bounce=", saw_bounce,
		" settle=", saw_drop_settle,
		" gold=", _ui.state.gold,
		" bag=", _ui.state.bag.size(),
		" used=", _ui.state.alley_used
	)
	FileAccess.open("res://docs/shots/rr_v0481_gumball_trace.json",FileAccess.WRITE).store_string(JSON.stringify(_trace,"  "))
	quit(0)
