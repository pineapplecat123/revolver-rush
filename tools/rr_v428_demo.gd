extends SceneTree
## v0.4.28 演示（~20s）：视野外走进来/速度不同/重叠；慢放命中才掉血；罪孽危险特效（转轮+飞行）；火药加亮；肢体血迹。
var _ui = null
var _title: Label = null

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
	st.auto_enemy_advance = true
	st.spawn_paused = true
	_show_title("1 敌人从画面外走进来 · 速度各不相同 · 可以挤在一起")
	# 罪孽+普通混装，转轮里先看危险特效
	st.dev_force_load([16, 1, 34, 27, 17, 1] as Array[int])
	st.magazine.set_start(0)
	_ui._combat_speed = 2.0
	for k in 6:
		st._spawn_enemy_at_lane([1, 2, 3, 4, 1, 2][k])
	for e in st.enemies:
		e.hp = 4
		e.max_hp = 4
		e.atk = 0
	_ui._refresh()
	await create_timer(6.0).timeout
	_ui._combat_speed = 0.5
	_title.text = "2 慢放 0.5×：子弹打到才掉血 · 罪孽弹黑红危险光 · 炸药火药屑 · 碎块拖血"
	_ui._on_fire()
	await _wait_volley(14.0)
	await create_timer(0.6).timeout
	st.dev_force_load([18, 35, 27, 1, 36, 1] as Array[int])
	_ui._refresh()
	await create_timer(0.8).timeout
	_ui._on_fire()
	await _wait_volley(14.0)
	await create_timer(1.5).timeout
	print("DEMO_DONE audit=%d" % _ui.shot_audit.size())
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
