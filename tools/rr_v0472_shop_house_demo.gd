extends SceneTree
## v0.4.72 演示：右侧巷边店铺，走进入口才购物，从另一扇门离开。
## 本脚本会加速清段/过场，画面会标明「加速演示」。
## 静帧：
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 900 -s tools/rr_v0472_shop_house_demo.gd
## 录像（Movie Maker 约 450x800）：
##   xvfb-run -a godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 420 \
##     --write-movie /tmp/rr_v0472_shop_house_demo.avi -s tools/rr_v0472_shop_house_demo.gd

var _ui = null
var _banner: Label = null
var _movie: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _label(text: String) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.name = "ShopHouseDemoBanner"
		_banner.position = Vector2(16, 4)
		_banner.size = Vector2(688, 52)
		_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner.add_theme_font_size_override("font_size", 17)
		_banner.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
		_banner.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.85))
		_banner.add_theme_constant_override("outline_size", 4)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.z_index = 120
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
	var hs := "none"
	var occ := "?"
	if _ui.state != null:
		hs = str(_ui.state.shop_house_seq)
		occ = _ui.state.shop_house_occlusion_at(0.0)
	print("saved ", path, " ", img.get_width(), "x", img.get_height(),
		" phase=", _ui.state.campaign_phase, " house=", hs, " occ=", occ)

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _force_shop_walk() -> void:
	_ui.state.campaign_wave = maxi(1, CampaignRules.wave_count(_ui.state.campaign_floor, _ui.state.campaign_segment))
	_ui.state.enemies.clear()
	_ui.state.reward_pending = false
	_ui.state.pending_levelups = 0
	_ui.state.shop_hold = false
	_ui.state.shop_touch_pending = false
	_ui.state.campaign_try_advance()
	_ui._refresh()
	_ui._apply_campaign_presentation()
	_ui._sync_campaign_backdrop()
	_ui._sync_shop_house()

func _run() -> void:
	_movie = OS.get_cmdline_user_args().has("--movie") or OS.has_feature("movie")
	# Movie Maker sets a project setting; also detect write-movie via engine
	if DisplayServer.get_name() != "":
		pass
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
		push_error("campaign ui failed")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if _ui.has_method("_fit_combat_viewport"):
		_ui._fit_combat_viewport(Vector2(720, 1280))
	if _ui.state.campaign_offer_pending:
		_ui.state.campaign_pick_opening(0)
	_ui.state.campaign_instant_transitions = false
	_ui.state.campaign_skip_walk()
	_ui._refresh()
	_ui._ensure_campaign_backdrop()
	_ui._ensure_shop_house()
	_ui._sync_campaign_backdrop()
	_label("加速演示 · 静止巷景（非完整 9 关）")
	await _frames(10)
	await _stamp("rr_v0472_after_combat")

	_ui.set_process(false)
	_force_shop_walk()
	_label("加速演示 · 右侧店铺靠近，走向入口")
	# 走到约 40%，房子应出现在右侧、入口尚未落到猫身上
	var approach: float = CampaignRules.walk_to_shop_sec()
	var acc := 0.0
	while acc < approach * 0.40:
		var dt := 0.05
		_ui.state.tick_shop_house(dt)
		_ui._apply_campaign_presentation()
		_ui._sync_shop_house()
		_ui._sync_campaign_backdrop()
		var cat = _ui.get("_skel_player")
		if cat != null and cat.has_method("_process"):
			cat._process(dt)
		acc += dt
		await process_frame
	_ui._sync_shop_house()
	await _stamp("rr_v0472_after_house_approach")

	while acc < approach + 0.02:
		var dt2 := 0.05
		_ui.state.tick_shop_house(dt2)
		_ui._apply_campaign_presentation()
		_ui._sync_shop_house()
		var cat2 = _ui.get("_skel_player")
		if cat2 != null and cat2.has_method("_process"):
			cat2._process(dt2)
		acc += dt2
		await process_frame
	_ui._sync_shop_house()
	_label("加速演示 · 走进入口（进门后才开店）")
	await _frames(6)
	await _stamp("rr_v0472_after_enter_door")

	_ui.set_process(true)
	if _ui.state.shop_touch_pending and _ui.has_method("_open_rush_shop"):
		_ui._open_rush_shop()
	_label("加速演示 · 购物界面（进门完成后）")
	await _frames(12)
	await _stamp("rr_v0472_after_shop")

	if _ui.has_method("_on_rush_shop_leave"):
		_ui._on_rush_shop_leave()
	_ui.set_process(false)
	_label("加速演示 · 从另一扇门走出")
	await _frames(4)
	var exit_sec: float = CampaignRules.walk_from_shop_sec()
	var ex := 0.0
	# 出门中段：猫在门间或侧门口
	var exit_mid: float = (CampaignRules.shop_house_exit_x() - CampaignRules.shop_house_entrance_x()) / _ui.state.shop_house_exit_travel()
	while ex < exit_sec * clampf(exit_mid, 0.4, 0.75):
		var dt3 := 0.05
		_ui.state.tick_shop_house(dt3)
		_ui._apply_campaign_presentation()
		_ui._sync_shop_house()
		var cat3 = _ui.get("_skel_player")
		if cat3 != null and cat3.has_method("_process"):
			cat3._process(dt3)
		ex += dt3
		await process_frame
	_ui._sync_shop_house()
	await _stamp("rr_v0472_after_exit_door")

	while ex < exit_sec + 0.05:
		var dt4 := 0.05
		_ui.state.tick_shop_house(dt4)
		_ui._apply_campaign_presentation()
		_ui._sync_shop_house()
		var cat4 = _ui.get("_skel_player")
		if cat4 != null and cat4.has_method("_process"):
			cat4._process(dt4)
		ex += dt4
		await process_frame
	_ui._sync_shop_house()
	_label("加速演示 · 出门完毕，继续下一段")
	await _frames(10)
	await _stamp("rr_v0472_after_resume")
	print("demo done phase=", _ui.state.campaign_phase, " house=", _ui.state.shop_house_seq, " segment=", _ui.state.campaign_segment)
	quit()
