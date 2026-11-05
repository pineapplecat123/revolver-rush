extends SceneTree
## v0.4.32 演示：预转花式转枪→出膛姿势；致死碎块无趴地；图鉴网格+详情。
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

func _banner(text: String) -> void:
	if _title == null:
		_title = Label.new()
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.add_theme_font_size_override("font_size", 24)
		_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
		_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_title.add_theme_constant_override("outline_size", 8)
		_title.z_index = 200
		_title.position = Vector2(10, 56)
		_title.size = Vector2(700, 90)
		_ui.add_child(_title)
	_title.text = text

func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.2).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(5, 3)
	st.sandbox_spawn_dummy(8, 6)
	_banner("1 开火：预转时花式转枪 → 转完才播开枪姿势")
	st.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_ui._combat_speed = 1.15
	_ui._refresh()
	await create_timer(0.5).timeout
	_ui._on_fire()
	await _wait_volley(12.0)
	await create_timer(0.4).timeout

	_banner("2 灼烧/爆炸致死：当场碎块，无趴地尸体")
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(2, 4)
	st.sandbox_spawn_dummy(2, 6)
	_ui._refresh()
	await create_timer(0.35).timeout
	# burn kill
	var e0 = st.enemies[0]
	e0.hp = 0
	st.last_damaged_enemy = e0
	st.last_damage_lethal = true
	_ui._on_enemy_damaged(e0.cell, 4, "burn")
	_ui._refresh()
	await create_timer(0.55).timeout
	# explosion-style sync kill
	if st.enemies.size() > 0:
		st.enemies[0].hp = 0
		_ui._refresh()
	await create_timer(0.7).timeout

	_banner("3 图鉴：方格网格 → 点开详情")
	change_scene_to_file("res://scenes/main.tscn")
	for _i in 60:
		await process_frame
		if current_scene != null and current_scene.has_method("_on_codex_pressed"):
			break
	await create_timer(0.35).timeout
	var menu = current_scene
	menu._on_codex_pressed()
	await create_timer(1.2).timeout
	# scroll a bit
	if menu.has_node("%CodexScroll"):
		for k in 18:
			menu.get_node("%CodexScroll").scroll_vertical += 18
			await process_frame
	await create_timer(0.4).timeout
	var list = menu.get_node("%CodexList")
	var aid := 1
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			aid = int(str(c.name).get_slice("_", 1))
			break
	menu._on_codex_cell_pressed(aid)
	await create_timer(1.6).timeout
	menu._on_codex_detail_close_pressed()
	await create_timer(0.35).timeout
	print("DEMO_DONE v0.4.32")
	quit(0)
