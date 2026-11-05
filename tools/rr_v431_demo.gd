extends SceneTree
## v0.4.31：枪线无 AA 演示。
var _ui
var _title: Label

func _initialize() -> void:
	call_deferred("_run")

func _wait_volley(max_sec: float) -> void:
	var t := 0.0
	await create_timer(0.08).timeout
	while t < max_sec and (_ui._volley_ui_running or _ui.state.is_volley_pending()):
		await process_frame
		t += 1.0 / 30.0

func _run() -> void:
	RrAa.apply_project_defaults()
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.2).timeout
	RrAa.apply_to_viewport(root.get_viewport())
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(99999, 3)
	st.sandbox_spawn_dummy(99999, 6)
	_title = Label.new()
	_title.text = "v0.4.31 枪线/弹道 Line2D 无抗锯齿（RrAa.ENABLED=false）· 多弹齐飞"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.z_index = 200
	_title.position = Vector2(10, 64)
	_title.size = Vector2(700, 80)
	_ui.add_child(_title)
	st.dev_force_load([1, 16, 1, 17, 1, 18] as Array[int])
	_ui._combat_speed = 1.2
	_ui._refresh()
	await create_timer(0.6).timeout
	_ui._on_fire()
	await _wait_volley(10.0)
	await create_timer(0.4).timeout
	st.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_ui._refresh()
	await create_timer(0.4).timeout
	_ui._on_fire()
	await _wait_volley(8.0)
	await create_timer(0.5).timeout
	print("DEMO_DONE v0.4.31 aa_off=%s" % str(not RrAa.ENABLED))
	quit(0)
