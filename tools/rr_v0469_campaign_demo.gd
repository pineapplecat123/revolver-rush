extends SceneTree
## v0.4.69 演示：闯关背景静止；地上碎块战斗慢走左移、进店快走左移、停步时不动。
## 不是完整 9 关自然游玩。碎块是演示里种在地上的，方便对照位移。
## 静帧：
##   xvfb-run -a godot --path . --resolution 720x1280 --quit-after 500 -s tools/rr_v0469_campaign_demo.gd
## 录像：
##   xvfb-run -a godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 360 \
##     --write-movie /tmp/rr_v0469_campaign_demo.avi -s tools/rr_v0469_campaign_demo.gd

var _ui = null
var _banner: Label = null
var _markers: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _stamp(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = _ui.get_viewport().get_texture().get_image()
	var path := "/tmp/%s.png" % name
	img.save_png(path)
	var gx := -1.0
	if not _markers.is_empty() and is_instance_valid(_markers[0]):
		gx = (_markers[0] as Node2D).global_position.x
	print("saved ", path, " ", img.get_width(), "x", img.get_height(),
		" phase=", _ui.state.campaign_phase,
		" drift=", _ui.state.campaign_world_drift_px_per_sec(),
		" gore_x=", gx)


func _label(text: String) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.name = "CampaignDemoBanner"
		_banner.position = Vector2(16, 8)
		_banner.size = Vector2(688, 40)
		_banner.add_theme_font_size_override("font_size", 18)
		_banner.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(_banner)
	_banner.text = text


func _clear_markers() -> void:
	_markers.clear()
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


func _plant_ground_debris() -> void:
	_ui._ensure_gore_layer()
	_clear_markers()
	var gore = _ui.get("_gore_layer")
	var gy: float = 900.0
	if _ui.has_method("_board_ground_global_y"):
		gy = _ui._board_ground_global_y()
	gore.ground_y = gy
	var xs: Array = [360.0, 410.0, 460.0, 510.0, 560.0]
	for i in xs.size():
		var node := Node2D.new()
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([
			Vector2(-20, -8), Vector2(18, -11), Vector2(16, 10), Vector2(-16, 12)
		])
		body.color = Color(0.72, 0.05, 0.08, 1)
		var shade := Polygon2D.new()
		shade.polygon = PackedVector2Array([
			Vector2(-8, -2), Vector2(8, -4), Vector2(6, 6), Vector2(-7, 5)
		])
		shade.color = Color(0.28, 0.02, 0.04, 1)
		node.add_child(body)
		node.add_child(shade)
		gore.add_child(node)
		node.global_position = Vector2(xs[i], gy - 6.0)
		node.z_index = 8
		gore._pieces.append({
			"node": node,
			"vel": Vector2.ZERO,
			"spin": 0.0,
			"rest_t": 0.0,
			"bounces": 3,
			"age": 0.0,
			"trail": Color(0.78, 0.06, 0.1, 0.95),
			"trail_t": 0.0,
		})
		_markers.append(node)
	# 同步种几块地面血迹
	if _ui.has_method("_spawn_blood_stain"):
		for i in 4:
			_ui._spawn_blood_stain(Vector2(390.0 + i * 40.0, gy - 8.0), Color(0.7, 0.05, 0.08, 0.85), 1.0)


func _hold_rest() -> void:
	# 演示期间不要淡出，方便对照位置
	var gore = _ui.get("_gore_layer")
	if gore == null:
		return
	for p in gore._pieces:
		p["rest_t"] = 0.0
		var n: Node = p.get("node")
		if n != null and is_instance_valid(n):
			n.modulate.a = 1.0


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

	if _ui.state.campaign_offer_pending:
		_ui.state.campaign_pick_opening(0)
	_ui.state.campaign_instant_transitions = false
	_ui.state.campaign_skip_walk()
	_ui._refresh()
	_plant_ground_debris()
	_ui._apply_campaign_presentation()
	var cat = _ui.get("_skel_player")
	if cat != null:
		cat.set_walk_tempo(_ui.state.campaign_walk_tempo())
		cat.set_walking(true)
		cat.play_shoot()
	_label("v0.4.69 战斗慢走 · 地上碎块往后（背景静止）")
	for _w in 8:
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_combat_a")

	for _k in 36:
		_hold_rest()
		if cat != null and int(_k) % 10 == 0:
			cat.play_shoot()
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_combat_b")

	# 进商店快走，碎块还是同一批，位移应更快
	_ui.state.enemies.clear()
	_ui.state.reward_pending = false
	_ui.state.pending_levelups = 0
	if _ui.state.has_method("_clear_reward_state"):
		_ui.state._clear_reward_state()
	_ui.state.shop_touch_pending = false
	_ui.state.shop_hold = false
	_ui.state.campaign_instant_transitions = false
	_ui.state.campaign_transition_lock = true
	_ui.state.campaign_phase = 4  # PHASE_WALK_SHOP，避免工具脚本编译期绑 CombatState
	_ui.state.campaign_walk_left = 3.0
	_ui.state.encounter_kind = 0
	if _ui.has_method("_set_reward_open"):
		_ui._set_reward_open(false)
	_ui._refresh()
	_ui._apply_campaign_presentation()
	if cat != null:
		cat.set_walk_tempo(_ui.state.campaign_walk_tempo())
		cat.set_walking(true)
	_label("v0.4.69 进店快走 · 地上碎块退得更快（背景静止）")
	for _s in 8:
		_hold_rest()
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_shop_a")
	for _s2 in 24:
		_hold_rest()
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_shop_b")

	# 停步：选奖励/开店时碎块不再移动
	_ui.state.reward_pending = true
	_ui._apply_campaign_presentation()
	_label("v0.4.69 暂停选择 · 地上碎块停住（背景静止）")
	for _p in 8:
		_hold_rest()
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_pause_a")
	for _p2 in 24:
		_hold_rest()
		await process_frame
	_hold_rest()
	await _stamp("rr_v0469_pause_b")
	print("demo done")
	quit(0)
