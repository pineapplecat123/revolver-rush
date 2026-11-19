extends SceneTree
## v0.4.74 演示：走进入口（门框挡住身体）→ 可读的购物界面停住 → 从另一扇门走出。
## 闯关清段会跳过；店铺从右屏外按原速滑入，购物界面停住可读，再从另一扇门走出并离开左屏。
## 静帧：
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 1200 -s tools/rr_v0474_shop_house_demo.gd
## 录像（Movie Maker 约 450x800）：
##   xvfb-run -a godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1200 \
##     --write-movie /tmp/rr_v0474_shop_house_demo.avi -s tools/rr_v0474_shop_house_demo.gd

var _ui = null
var _banner: Label = null
var _movie: bool = false
const DT := 1.0 / 30.0

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
		occ = _ui.state.shop_house_occlusion_at(_ui._player_foot_global_x())
	print("saved ", path, " ", img.get_width(), "x", img.get_height(),
		" phase=", _ui.state.campaign_phase, " house=", hs, " occ=", occ)

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _tick_house(dt: float) -> void:
	_ui.state.tick_shop_house(dt)
	_ui._apply_campaign_presentation()
	_ui._sync_campaign_backdrop()
	var bg = _ui.get("_campaign_backdrop")
	if bg != null and bg.has_method("advance"):
		bg.advance(dt, float(_ui.get("_campaign_debris_drift")))
	_ui._sync_shop_house()
	var cat = _ui.get("_skel_player")
	if cat != null and cat.has_method("_process"):
		cat._process(dt)

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
	_label("演示 · 清段已跳过；先慢走，再看店铺从右边进来")
	# 战斗慢走几帧，让近景地板先动起来
	_ui.set_process(false)
	for _w in 24:
		_tick_house(DT)
		await process_frame
	_ui.set_process(true)
	await _frames(8)
	await _stamp("rr_v0474_after_combat")

	_ui.set_process(false)
	_force_shop_walk()
	_label("演示 · 清场后，店铺从画面右边外面进来")
	var approach: float = CampaignRules.walk_to_shop_sec()
	var acc := 0.0
	var view_r: float = CampaignRules.shop_house_view_width()
	var revealed := false
	# 先拍一帧：房子还在右屏外
	await _stamp("rr_v0474_after_house_offscreen")
	while acc < approach - 0.02:
		_tick_house(DT)
		acc += DT
		await process_frame
		var left_now: float = _ui.state.shop_house_left_at(_ui._player_foot_global_x())
		if not revealed and left_now < view_r - 80.0:
			revealed = true
			_label("演示 · 右缘露出店铺，持续走近")
			_ui._sync_shop_house()
			await _stamp("rr_v0474_after_house_reveal")
		if acc >= approach * 0.45 and acc < approach * 0.45 + DT * 1.5:
			_ui._sync_shop_house()
			await _stamp("rr_v0474_after_house_approach")

	# 走到门口，停一下让门框关系看清楚，此时还不开店
	while acc < approach - 0.02:
		_tick_house(DT)
		acc += DT
		await process_frame
	_ui._sync_shop_house()
	_label("演示 · 走进入口（进门后才开店）")
	await _frames(24)
	await _stamp("rr_v0474_after_enter_door")

	# 把最后一点点走完，触发进店
	while acc < approach + 0.02:
		_tick_house(DT)
		acc += DT
		await process_frame
	_ui._sync_shop_house()

	_ui.set_process(true)
	if _ui.state.shop_touch_pending and _ui.has_method("_open_rush_shop"):
		_ui._open_rush_shop()
	_label("演示 · 购物界面（进门完成后）")
	# 先等布局，再拍一张可读的商店，然后停住约 3 秒
	await _frames(8)
	await _stamp("rr_v0474_after_shop")
	await _frames(90)

	if _ui.has_method("_on_rush_shop_leave"):
		_ui._on_rush_shop_leave()
	_ui.set_process(false)
	_label("演示 · 从另一扇门走出")
	await _frames(8)
	var exit_sec: float = CampaignRules.walk_from_shop_sec()
	var ex := 0.0
	# 出门刚开始：门框开始挡住身体
	while ex < exit_sec * 0.08:
		_tick_house(DT)
		ex += DT
		await process_frame
	_ui._sync_shop_house()
	await _stamp("rr_v0474_after_enter_occlude")

	var exit_mid: float = (CampaignRules.shop_house_exit_x() - CampaignRules.shop_house_entrance_x()) / _ui.state.shop_house_exit_travel()
	while ex < exit_sec * clampf(exit_mid, 0.4, 0.75):
		_tick_house(DT)
		ex += DT
		await process_frame
	_ui._sync_shop_house()
	await _frames(18)
	await _stamp("rr_v0474_after_exit_door")

	var receded := false
	while ex < exit_sec + 0.05:
		_tick_house(DT)
		ex += DT
		await process_frame
		var left_exit: float = _ui.state.shop_house_left_at(_ui._player_foot_global_x()) if _ui.state.shop_house_seq != 0 else -999.0
		var house_right: float = left_exit + CampaignRules.shop_house_width() + 8.0
		if not receded and house_right < 200.0 and house_right > 16.0:
			receded = true
			_label("演示 · 店铺向左离开画面")
			_ui._sync_shop_house()
			await _stamp("rr_v0474_after_house_recede")
	_ui._sync_shop_house()
	_label("演示 · 出门完毕，店铺已离开，继续下一段")
	await _frames(24)
	await _stamp("rr_v0474_after_resume")
	print("demo done phase=", _ui.state.campaign_phase, " house=", _ui.state.shop_house_seq, " segment=", _ui.state.campaign_segment)
	quit()
