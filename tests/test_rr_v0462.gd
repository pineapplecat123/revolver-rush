extends GutTest
## v0.4.62：沙盒控制台顶部操作钮（清空袋/保存/还原等）按下拖动能滚列表，轻点仍只触发一次。


const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const PRESET_PATH := "user://sandbox_bag_preset_test_0462.json"


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.sandbox_bag_preset_path = PRESET_PATH
	_wipe_preset()


func after_each() -> void:
	_wipe_preset()
	CombatState.sandbox_bag_preset_path = "user://sandbox_bag_preset.json"
	CombatState.boot_sandbox = false


func _wipe_preset() -> void:
	if FileAccess.file_exists(PRESET_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PRESET_PATH))


func test_version_is_at_least_0_4_62() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.62") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.62" in log)
	assert_true("清空弹药袋" in log)


func _boot_ui():
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_true(ui.state.sandbox_mode)
	assert_true(ui.dev_panel.visible)
	CombatState.sandbox_bag_preset_path = PRESET_PATH
	return ui


func _dev_scroll(ui) -> ScrollContainer:
	var scroll: ScrollContainer = ui.dev_panel.find_child("DevScroll", true, false)
	assert_not_null(scroll)
	var inner: Control = scroll.get_child(0) as Control if scroll.get_child_count() > 0 else null
	assert_not_null(inner)
	inner.custom_minimum_size = Vector2(0, 2400)
	return scroll


func _btn_named(ui, node_name: String = "", text: String = "") -> Button:
	for b in ui.dev_panel.find_children("*", "Button", true, false):
		var btn := b as Button
		if node_name != "" and btn.name == node_name:
			return btn
		if text != "" and btn.text == text and btn.is_visible_in_tree():
			return btn
	return null


func _mouse(pressed: bool, pos: Vector2, mask: bool = false) -> InputEvent:
	if mask:
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = pos
		m.relative = Vector2.ZERO
		return m
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	return ev


func _drag_on(ui, ctrl: Control, scroll: ScrollContainer, dy: float = 0.0) -> int:
	if dy == 0.0:
		dy = ui.SB_TAP_MAX_PX + 24.0
	var before: int = scroll.scroll_vertical
	# 走按钮真实绑定的 gui_input，确认不会误触 pressed/on_tap。
	ctrl.gui_input.emit(_mouse(true, Vector2(10, 10)))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(10, 10 + dy)
	motion.relative = Vector2(0, -dy)
	ctrl.gui_input.emit(motion)
	var after: int = scroll.scroll_vertical
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = motion.position
	ctrl.gui_input.emit(rel)
	assert_gt(after, before, "%s 上拖动应滚动列表" % ctrl.name)
	return after - before


func test_drag_on_clear_save_restore_scrolls_without_acting() -> void:
	var ui = await _boot_ui()
	var scroll := _dev_scroll(ui)
	await wait_process_frames(2)
	var clear: Button = _btn_named(ui, "SandboxClearBag", "清空弹药袋")
	var save: Button = _btn_named(ui, "SandboxSaveBagPreset", "保存当前袋中配置")
	var restore: Button = _btn_named(ui, "SandboxRestoreBagPreset", "一键还原袋中配置")
	assert_not_null(clear)
	assert_not_null(save)
	assert_not_null(restore)
	assert_true(clear.disabled, "开局空袋时清空应是禁用")
	assert_true(restore.disabled, "尚未保存时还原应是禁用")
	assert_false(ui.state.has_sandbox_bag_preset())
	# 禁用的清空/还原也不能变成拖不动的死区
	_drag_on(ui, clear, scroll)
	assert_eq(ui.state.bag.size(), 0)
	scroll.scroll_vertical = 0
	_drag_on(ui, restore, scroll)
	assert_false(ui.state.has_sandbox_bag_preset())
	assert_eq(ui.state.bag.size(), 0)
	# 有弹药后，拖清空/保存不得误触
	ui.state.sandbox_add_ammo(BAIBAN, 2)
	ui._refresh()
	await wait_process_frames(1)
	assert_false(clear.disabled)
	assert_eq(ui.state.bag.size(), 2)
	scroll.scroll_vertical = 0
	_drag_on(ui, clear, scroll)
	assert_eq(ui.state.bag.size(), 2, "在清空钮上拖动不得清袋")
	scroll.scroll_vertical = 0
	_drag_on(ui, save, scroll)
	assert_false(ui.state.has_sandbox_bag_preset(), "在保存钮上拖动不得保存")
	CombatState.boot_sandbox = false


func test_tap_clear_and_save_once_mouse_touch_dedup() -> void:
	var ui = await _boot_ui()
	_dev_scroll(ui)
	var clear: Button = _btn_named(ui, "SandboxClearBag")
	var save: Button = _btn_named(ui, "SandboxSaveBagPreset")
	assert_not_null(clear)
	assert_not_null(save)
	ui.state.sandbox_add_ammo(BAIBAN, 2)
	ui._refresh()
	await wait_process_frames(1)
	# 走共享手势处理：同一次按下同时来鼠标和触屏，只触发一次
	var n := [0]
	var tap := func(): n[0] = int(n[0]) + 1
	ui._sb_on_scroll_gui_input(clear, _mouse(true, Vector2(8, 8)), tap)
	var tdown := InputEventScreenTouch.new()
	tdown.position = Vector2(8, 8)
	tdown.pressed = true
	tdown.index = 0
	ui._sb_on_scroll_gui_input(clear, tdown, tap)
	ui._sb_on_scroll_gui_input(clear, _mouse(false, Vector2(8, 8)), tap)
	var tup := InputEventScreenTouch.new()
	tup.position = Vector2(8, 8)
	tup.pressed = false
	tup.index = 0
	ui._sb_on_scroll_gui_input(clear, tup, tap)
	assert_eq(int(n[0]), 1, "清空钮鼠标+触屏同一次只能点一下")
	# 真实绑定：轻点清空清袋，且只清一次
	clear.gui_input.emit(_mouse(true, Vector2(8, 8)))
	clear.gui_input.emit(_mouse(false, Vector2(8, 8)))
	await wait_process_frames(1)
	assert_eq(ui.state.bag.size(), 0, "轻点清空弹药袋应清袋")
	ui.state.sandbox_add_ammo(BAIBAN, 2)
	ui._refresh()
	await wait_process_frames(1)
	save.gui_input.emit(_mouse(true, Vector2(8, 8)))
	save.gui_input.emit(_mouse(false, Vector2(8, 8)))
	await wait_process_frames(1)
	assert_true(ui.state.has_sandbox_bag_preset(), "轻点保存应写出配置")
	assert_eq(ui.state.bag.size(), 2)
	CombatState.boot_sandbox = false


func test_ammo_row_plus_swipe_and_tap_unchanged() -> void:
	var ui = await _boot_ui()
	var scroll := _dev_scroll(ui)
	await wait_process_frames(2)
	var plus: Button = null
	for b in ui.dev_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "袋+" and (b as Button).is_visible_in_tree():
			plus = b
			break
	assert_not_null(plus)
	var bag0: int = ui.state.bag.size()
	var before: int = scroll.scroll_vertical
	var add := func(): ui.state.sandbox_add_ammo(BAIBAN, 1)
	ui._sb_on_scroll_gui_input(plus, _mouse(true, Vector2(10, 10)), add)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(10, 10 + ui.SB_TAP_MAX_PX + 24)
	motion.relative = Vector2(0, -(ui.SB_TAP_MAX_PX + 24))
	ui._sb_on_scroll_gui_input(plus, motion, add)
	assert_gt(scroll.scroll_vertical, before)
	assert_eq(ui.state.bag.size(), bag0, "子弹行上滑动仍不得加弹")
	ui._sb_on_scroll_gui_input(plus, _mouse(false, motion.position), add)
	assert_eq(ui.state.bag.size(), bag0)
	ui._sb_on_scroll_gui_input(plus, _mouse(true, Vector2(8, 8)), add)
	ui._sb_on_scroll_gui_input(plus, _mouse(false, Vector2(8, 8)), add)
	assert_eq(ui.state.bag.size(), bag0 + 1, "子弹行轻点仍加弹")
	CombatState.boot_sandbox = false
