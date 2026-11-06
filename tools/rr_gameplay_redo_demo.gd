extends SceneTree
## feat/gameplay-redo：倒出→手→自动装入 / 仓对调 / 再倒出。
##   godot --path . --resolution 720x1280 --write-movie /workspace/rr-demo-vids/raw/gameplay_redo_hand.avi --fixed-fps 30 -s tools/rr_gameplay_redo_demo.gd

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
	# 保证袋里有足量平庸
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
	_banner("1 缩小弹药袋 + 「手」区（仅平庸弹）")
	await create_timer(1.4).timeout
	_banner("2 倒出：袋 → 手（随机最多 6）")
	_ui._on_manual_load()
	_ui._refresh()
	await create_timer(1.5).timeout
	_banner("3 自动装入：手 → 空仓")
	_ui._on_auto_load()
	_ui._refresh()
	await create_timer(1.5).timeout
	_banner("4 弹仓拖拽对调（0 ↔ 3）")
	st.swap_magazine_slots(0, 3)
	_ui._refresh()
	await create_timer(1.3).timeout
	_banner("5 再倒出（手非空：先退回袋再抽）")
	st.magazine.clear()
	_ui._refresh()
	_ui._on_manual_load()
	_ui._refresh()
	await create_timer(1.3).timeout
	_banner("6 手→指定空仓（拖装 API）")
	if st.hand.size() >= 2:
		st.load_hand_index_into_chamber(0, 1)
		st.load_hand_index_into_chamber(0, 4)
	_ui._refresh()
	await create_timer(1.6).timeout
	_banner("DEMO_DONE gameplay-redo hand")
	print("DEMO_DONE gameplay-redo")
	await create_timer(0.5).timeout
	quit(0)
