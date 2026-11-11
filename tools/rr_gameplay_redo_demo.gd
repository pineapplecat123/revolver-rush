extends SceneTree
## Bag visible, hand scatter, 射击 returns leftovers, load → rotate → load snap.
##   godot --path . --resolution 720x1280 --write-movie /tmp/rr-demo/redo_fix.avi --fixed-fps 30 -s tools/rr_gameplay_redo_demo.gd

var _ui
var _title: Label
var _cursor: ColorRect


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
		_title.z_index = 220
		_title.position = Vector2(12, 8)
		_title.size = Vector2(696, 78)
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(_title)
	_title.text = text
	print("DEMO: ", text)


func _move_cursor(global_pos: Vector2) -> void:
	if _cursor == null:
		_cursor = ColorRect.new()
		_cursor.color = Color(1.0, 0.25, 0.2, 0.95)
		_cursor.size = Vector2(14, 14)
		_cursor.z_index = 240
		_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(_cursor)
	_cursor.visible = true
	_cursor.global_position = global_pos - _cursor.size * 0.5


func _hide_cursor() -> void:
	if _cursor != null:
		_cursor.visible = false


func _drag_onto(hand_index: int, slot: int) -> void:
	var center: Vector2 = _ui.chamber_visual_center(slot)
	var start: Vector2 = center + Vector2(150, 110)
	_ui._drag_begin("hand", hand_index, start)
	_move_cursor(start)
	for i in 14:
		var p: Vector2 = start.lerp(center, float(i) / 13.0)
		_ui._drag_move(p)
		_move_cursor(p)
		await process_frame
	await create_timer(0.55).timeout
	_ui._drag_end(center)
	_hide_cursor()
	await process_frame


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
	_banner("1 弹药袋：24 发全部可见，不上下滚动")
	await create_timer(1.6).timeout
	_banner("2 倒出后手区散开，子弹互不重叠")
	_ui._on_manual_load()
	await create_timer(0.15).timeout
	_ui._layout_hand_scatter()
	await create_timer(1.5).timeout
	_banner("3 拖进空仓（吸附在仓上）")
	if st.hand.size() > 0:
		await _drag_onto(0, 0)
	await create_timer(0.4).timeout
	_hide_cursor()
	_banner("4 转轮转两格，再拖一发，吸附仍对准那一仓")
	var from_s := float(_ui._wheel_visual_steps)
	var to_s := from_s + 2.0
	for i in 16:
		_ui._apply_disk_rotation(lerpf(from_s, to_s, float(i) / 15.0))
		await process_frame
	st.magazine.start_index = int(round(fposmod(to_s, 6.0))) % 6
	_ui._apply_disk_rotation(float(st.magazine.start_index))
	await create_timer(0.25).timeout
	if st.hand.size() > 0:
		await _drag_onto(0, 3)
	await create_timer(0.45).timeout
	var leftover: int = st.hand.size()
	var bag_before: int = st.bag.size()
	_banner("5 按射击：剩余 %d 发自动回袋，再打已装弹" % leftover)
	_ui._combat_speed = 2.0
	_ui._on_fire()
	await create_timer(0.35).timeout
	_banner("5 手已空（回袋 %d），袋 %d。已装的留下开火" % [leftover, st.bag.size()])
	print("DEMO_HANDOFF leftover=%d bag %d -> %d hand=%d" % [leftover, bag_before, st.bag.size(), st.hand.size()])
	await create_timer(2.2).timeout
	_banner("DEMO_DONE bag / hand / snap")
	print("DEMO_DONE gameplay-redo fix")
	await create_timer(0.4).timeout
	quit(0)
