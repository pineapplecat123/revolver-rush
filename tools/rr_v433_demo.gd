extends SceneTree
## v0.4.33：图鉴从方格上拖动滚动，再轻点开详情。
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	var menu
	for _i in 60:
		await process_frame
		menu = current_scene
		if menu != null and menu.has_method("_on_codex_pressed"):
			break
	await create_timer(0.3).timeout
	var title := Label.new()
	title.text = "图鉴：手指按在方格上拖动也能滚 → 轻点开详情"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	title.z_index = 200
	title.position = Vector2(10, 48)
	title.size = Vector2(700, 70)
	menu.add_child(title)
	menu._on_codex_pressed()
	await create_timer(0.5).timeout
	var scroll: ScrollContainer = menu.get_node("%CodexScroll")
	var list = menu.get_node("%CodexList")
	var ammo_id := 1
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			ammo_id = int(str(c.name).get_slice("_", 1))
			break
	# drag on cell
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(40, 40)
	menu._on_codex_cell_gui_input(press, ammo_id)
	for k in 28:
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.relative = Vector2(0, -16)
		motion.position = Vector2(40, 40 - k * 16)
		menu._on_codex_cell_gui_input(motion, ammo_id)
		await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(40, 40 - 28 * 16)
	menu._on_codex_cell_gui_input(release, ammo_id)
	await create_timer(0.7).timeout
	# coast inertia briefly
	await create_timer(0.5).timeout
	# tap another cell
	var ammo2 := ammo_id
	var n := 0
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			n += 1
			if n == 4:
				ammo2 = int(str(c.name).get_slice("_", 1))
				break
	var p2 := InputEventMouseButton.new()
	p2.button_index = MOUSE_BUTTON_LEFT
	p2.pressed = true
	p2.position = Vector2(12, 12)
	menu._on_codex_cell_gui_input(p2, ammo2)
	var r2 := InputEventMouseButton.new()
	r2.button_index = MOUSE_BUTTON_LEFT
	r2.pressed = false
	r2.position = Vector2(12, 12)
	menu._on_codex_cell_gui_input(r2, ammo2)
	await create_timer(1.4).timeout
	menu._on_codex_detail_close_pressed()
	await create_timer(0.3).timeout
	print("DEMO_DONE v0.4.33 scroll=", scroll.scroll_vertical)
	quit(0)
