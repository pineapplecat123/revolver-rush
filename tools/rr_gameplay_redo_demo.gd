extends SceneTree
## feat/gameplay-redo UI2：左轮右袋+手、倒出/射击、散落手区、空仓吸附。
##   godot --path . --resolution 720x1280 --write-movie /workspace/rr-demo-vids/raw/gameplay_redo_ui2.avi --fixed-fps 30 -s tools/rr_gameplay_redo_demo.gd

var _ui
var _title: Label


func _initialize() -> void:
	CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY = true
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
		_title.size = Vector2(700, 110)
		_ui.add_child(_title)
	_title.text = text
	print("DEMO: ", text)


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
	CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY = true
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(200, 5)
	st.bag.clear()
	st.bag_temp.clear()
	st.bag_envy_copy.clear()
	st.hand.clear()
	st.hand_temp.clear()
	st.hand_envy_copy.clear()
	st.magazine.clear()
	for _i in 24:
		st._bag_append(CombatConstants.WHITE_AMMO_ID, false)
	_ui._refresh()
	_banner("1 左=转轮 · 右上=袋 · 右下=手（无自动装入）")
	await create_timer(1.5).timeout
	_banner("2 倒出 → 手区散落")
	_ui._on_manual_load()
	_ui._refresh()
	await create_timer(0.2).timeout
	_ui._layout_hand_scatter()
	await create_timer(1.6).timeout
	_banner("3 空仓吸附装入（手→仓 0/2/4）")
	if st.hand.size() >= 3:
		st.load_hand_index_into_chamber(0, 0)
		st.load_hand_index_into_chamber(0, 2)
		st.load_hand_index_into_chamber(0, 4)
	_ui._refresh()
	await create_timer(1.4).timeout
	_banner("4 弹仓对调 0↔2")
	st.swap_magazine_slots(0, 2)
	_ui._refresh()
	await create_timer(1.3).timeout
	_banner("5 再倒出 · 手区继续散落")
	_ui._on_manual_load()
	_ui._refresh()
	await create_timer(0.15).timeout
	_ui._layout_hand_scatter()
	await create_timer(1.5).timeout
	_banner("DEMO_DONE gameplay-redo ui2")
	print("DEMO_DONE gameplay-redo ui2")
	await create_timer(0.5).timeout
	quit(0)
