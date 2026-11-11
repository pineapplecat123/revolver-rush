extends GutTest
## v0.4.33：图鉴方格上拖动能滚；轻点开详情。

func before_each() -> void:
	DataRegistry.reload()


func test_version_0_4_33() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.33") >= 0)
	assert_true('"version": "0.4.33"' in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_codex_drag_starting_on_cell_scrolls() -> void:
	var menu = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_process_frames(2)
	menu._on_codex_pressed()
	await wait_process_frames(2)
	var scroll: ScrollContainer = menu.get_node("%CodexScroll")
	var list: GridContainer = menu.get_node("%CodexList")
	assert_gt(list.get_child_count(), 0)
	var cell: Control = null
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			cell = c as Control
			break
	assert_not_null(cell)
	assert_false(cell is Button, "方格不应再是 Button")
	list.custom_minimum_size = Vector2(0, 2400)
	await wait_process_frames(2)
	var before: int = scroll.scroll_vertical
	# 模拟从方格起手的拖拽（超过 tap 阈值）
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 20)
	menu._on_codex_cell_gui_input(press, 1)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(20, 20 + menu.CODEX_TAP_MAX_PX + 20)
	motion.relative = Vector2(0, -(menu.CODEX_TAP_MAX_PX + 20))
	menu._on_codex_cell_gui_input(motion, 1)
	assert_gt(scroll.scroll_vertical, before, "从方格起手拖应改变 scroll")
	assert_true(menu._codex_moved)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	menu._on_codex_cell_gui_input(release, 1)
	# 拖过阈值松手不应开详情
	assert_false(menu.get_node("%CodexDetailPanel").visible)


func test_codex_tap_on_cell_opens_detail() -> void:
	var menu = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_process_frames(2)
	menu._on_codex_pressed()
	await wait_process_frames(2)
	var list: GridContainer = menu.get_node("%CodexList")
	var ammo_id := -1
	for c in list.get_children():
		if str(c.name).begins_with("CodexCell_"):
			ammo_id = int(str(c.name).get_slice("_", 1))
			break
	assert_gt(ammo_id, 0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	menu._on_codex_cell_gui_input(press, ammo_id)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(10, 10)
	menu._on_codex_cell_gui_input(release, ammo_id)
	await wait_process_frames(1)
	assert_true(menu.get_node("%CodexDetailPanel").visible)
