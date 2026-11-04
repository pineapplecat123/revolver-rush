extends SceneTree
## v0.4.29 演示（~20s）：空仓也算一拍；打死后不在空中喷血；袋里 80 球照样顺；商店删除列出弃牌堆。
var _ui = null
var _title: Label = null
var _perf: Label = null
var _last_draw := 0
var _last_phys := 0

func _initialize() -> void:
	call_deferred("_run")

func _wait_volley(max_sec: float) -> void:
	var t := 0.0
	await create_timer(0.1).timeout
	while t < max_sec and (_ui._volley_ui_running or _ui.state.is_volley_pending()):
		await process_frame
		t += 1.0 / 30.0

func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.3).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.player_max_hp = 99999
	st.sandbox_clear_muzzle()
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(3, 3)
	st.sandbox_spawn_dummy(99999, 6)
	_show_title("1 空仓也算一拍（红圈停一下再转）· 前面木桩打死后，后面的子弹不再在空中喷血")
	# 只装 1 颗在第 4 仓、锤位在第 1 仓：空、空、空、打（不快跳）
	st.dev_force_load([-1, -1, -1, 1, -1, -1] as Array[int])
	st.magazine.set_start(0)
	_ui._combat_speed = 1.0
	_ui._refresh()
	await create_timer(0.9).timeout
	_ui._on_fire()
	await _wait_volley(10.0)
	await create_timer(0.5).timeout
	# 隔仓装：打、空、打、空、打
	st.dev_force_load([1, -1, 1, -1, 1, -1] as Array[int])
	_ui._refresh()
	await create_timer(0.6).timeout
	_ui._on_fire()
	await _wait_volley(10.0)
	await create_timer(1.0).timeout
	# 2 大袋子
	_title.text = "2 袋里 80 颗球（各稀有度+罪孽）照样顺：每帧最多画一次，同种特效只算一次"
	var pool := [1, 8, 16, 17, 18, 19, 22, 24, 25, 26, 27, 28, 30, 33, 34, 35, 36, 37]
	for k in 80:
		st.dev_add_ammo(int(pool[k % pool.size()]), 1)
	_ui._refresh()
	_perf = Label.new()
	_perf.add_theme_font_size_override("font_size", 22)
	_perf.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_perf.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_perf.add_theme_constant_override("outline_size", 6)
	_perf.z_index = 200
	_perf.position = Vector2(10, 140)
	_ui.add_child(_perf)
	var bs = load("res://scripts/combat/bag_physics_box.gd")
	for f in 150:
		if f % 45 == 0 and _ui._bag_physics != null:
			for b in _ui._bag_physics._balls:
				b["vel"] = Vector2(randf_range(-400, 400), randf_range(-800, -250))
				b["asleep"] = false
		var d: int = int(bs.prof_draw_usec) - _last_draw
		var p: int = int(bs.prof_phys_usec) - _last_phys
		_last_draw = int(bs.prof_draw_usec)
		_last_phys = int(bs.prof_phys_usec)
		if f % 6 == 0:
			_perf.text = "袋内 %d 球 · 本帧袋子绘制 %.2f ms + 物理 %.2f ms" % [_ui._bag_physics.ball_count() if _ui._bag_physics != null else 0, d / 1000.0, p / 1000.0]
		await process_frame
	_perf.queue_free()
	# 3 商店
	_title.text = "3 商店「移除」：袋内 [袋] 和弃牌堆 [弃] 一起列出，删哪堆扣哪堆"
	st.gold = 999
	_ui._open_rush_shop()
	await create_timer(2.6).timeout
	var removed := false
	for r in _ui.shop_remove_rows():
		if r["pile"] == "discard":
			_ui._on_rush_shop_remove(int(r["id"]), "discard")
			removed = true
			break
	await create_timer(2.6).timeout
	_ui._on_rush_shop_leave()
	await create_timer(0.5).timeout
	print("DEMO_DONE blanks=%d shots=%d air_skipped=%d removed=%s" % [_ui.blank_audit.size(), _ui.shot_audit.size(), _ui.air_blood_skipped, str(removed)])
	quit(0)

func _show_title(text: String) -> void:
	_title = Label.new()
	_title.text = text
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.z_index = 200
	_title.position = Vector2(10, 64)
	_title.size = Vector2(700, 70)
	_ui.add_child(_title)
