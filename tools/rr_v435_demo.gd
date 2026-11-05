extends SceneTree
## v0.4.35：几只燃烧怪 + Boss，展示一团大火焰。

var _ui
var _title: Label

func _initialize() -> void:
	call_deferred("_run")

func _banner(text: String) -> void:
	if _title == null:
		_title = Label.new()
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.add_theme_font_size_override("font_size", 22)
		_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
		_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_title.add_theme_constant_override("outline_size", 8)
		_title.z_index = 200
		_title.position = Vector2(10, 52)
		_title.size = Vector2(700, 100)
		_ui.add_child(_title)
	_title.text = text

func _ignite(e) -> void:
	if e == null:
		return
	e.burn_stacks = 8
	e.burn_peak = 8
	e.walking = true
	if e.pos_x < -100.0:
		e.pos_x = float(e.cell)

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
	if _ui._dev_open:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	_banner("燃烧：一团大火焰盖住全身（含 Boss）+ 黑烟")
	# 普通怪 + Boss
	st.sandbox_spawn_dummy(200, 4)
	st.sandbox_spawn_dummy(200, 6)
	st.sandbox_spawn_enemy(5, 8)  # SUPER_ZOMBIE boss
	await create_timer(0.2).timeout
	_ui._refresh()
	await create_timer(0.15).timeout
	for e in st.enemies:
		_ignite(e)
	_ui._refresh()
	_ui._update_burn_vfx()
	await create_timer(0.4).timeout
	for k in 150:
		for e in st.enemies:
			if e != null and is_instance_valid(e) and e.is_alive():
				e.burn_stacks = 8
				e.walking = true
				e.pos_x = maxf(1.5, e.pos_x - 0.012)
		_ui._update_enemy_animal_motion()
		_ui._update_burn_vfx()
		await process_frame
	await create_timer(0.5).timeout
	print("DEMO_DONE v0.4.35")
	quit(0)
