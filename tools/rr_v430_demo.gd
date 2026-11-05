extends SceneTree
## v0.4.30 演示（~22s）：出膛必有姿势+弹道（穿过）；致死即碎；嫉妒命中复制；图鉴；沙盒空袋。
var _ui = null
var _title: Label = null

func _initialize() -> void:
	call_deferred("_run")

func _wait_volley(max_sec: float) -> void:
	var t := 0.0
	await create_timer(0.08).timeout
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
	await create_timer(0.25).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.player_max_hp = 99999
	st.sandbox_clear_muzzle()
	st.sandbox_clear_enemies()
	_show_title("1 出膛必有姿势+弹道：木桩死后子弹仍飞穿（不再缺姿势/缺拖尾）")
	st.sandbox_spawn_dummy(2, 3)
	st.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_ui._combat_speed = 1.35
	_ui._refresh()
	await create_timer(0.7).timeout
	_ui._on_fire()
	await _wait_volley(12.0)
	await create_timer(0.6).timeout

	_title.text = "2 致死瞬间碎块飞出（无 0.9s 尸体滞留）"
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(1, 4)
	st.dev_force_load([1, -1, -1, -1, -1, -1] as Array[int])
	_ui._refresh()
	await create_timer(0.5).timeout
	_ui._on_fire()
	await _wait_volley(6.0)
	await create_timer(0.8).timeout

	_title.text = "3 嫉妒：命中约 25% 复制一次性临时弹（绿菱）· 打出即毁"
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(99999, 3)
	st.sandbox_spawn_dummy(99999, 6)
	st.sandbox_clear_muzzle()
	st._muzzle_envy = 3
	st.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_ui._refresh()
	await create_timer(0.5).timeout
	_ui._on_fire()
	await _wait_volley(10.0)
	await create_timer(0.7).timeout

	_title.text = "4 沙盒清空袋子后保持空（直到再加弹）"
	st.dev_clear_bag()
	_ui._refresh()
	await create_timer(1.4).timeout
	st.dev_add_ammo(1, 3)
	_ui._refresh()
	await create_timer(1.0).timeout

	# 图鉴：回主菜单展示
	_title.text = "5 主菜单「图鉴」：全部实装弹药（稀有度/价格/数值/效果）"
	change_scene_to_file("res://scenes/main.tscn")
	for _i in 60:
		await process_frame
		if current_scene != null and current_scene.has_method("_on_codex_pressed"):
			break
	await create_timer(0.4).timeout
	var menu = current_scene
	if menu != null and menu.has_method("_on_codex_pressed"):
		menu._on_codex_pressed()
	await create_timer(3.2).timeout
	if menu != null and menu.has_method("_on_codex_close_pressed"):
		menu._on_codex_close_pressed()
	await create_timer(0.4).timeout
	print("DEMO_DONE v0.4.30")
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
