extends GutTest
## RR v0.3.0：唯一模式 rush! + 竖屏三等分 + 操作区两颗大按钮 + 无战斗日志。

const CombatScene := preload("res://scenes/combat.tscn")


func test_project_is_portrait_mobile() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 720)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 1280)
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	assert_eq(int(ProjectSettings.get_setting("display/window/handheld/orientation")), 1, "portrait")
	assert_false(ProjectSettings.has_setting("autoload/RunState"), "map run state removed")


func test_combat_scene_thirds_two_buttons_no_log() -> void:
	var ui = add_child_autofree(CombatScene.instantiate())
	await wait_process_frames(2)
	assert_null(ui.get_node_or_null("%LogBox"), "combat log removed")
	assert_null(ui.find_child("LogPanel", true, false), "log panel removed")
	assert_null(ui.find_child("LogTitle", true, false), "log title removed")
	for gone in ["%BtnLoad", "%BtnRoll", "%BtnUnload"]:
		assert_null(ui.get_node_or_null(gone), "%s removed" % gone)
	var sections := ["Margin/RootVBox/TopPanel", "Margin/RootVBox/MidPanel", "Margin/RootVBox/BottomPanel"]
	for p in sections:
		var c: Control = ui.get_node(p)
		assert_eq(c.size_flags_vertical & Control.SIZE_EXPAND, Control.SIZE_EXPAND, "%s expands" % p)
		assert_almost_eq(c.size_flags_stretch_ratio, 1.0, 0.001)
	assert_true(ui.get_node("Margin/RootVBox/TopPanel").is_ancestor_of(ui.get_node("%BoardRow")), "board in top third")
	var mid: Node = ui.get_node("Margin/RootVBox/MidPanel")
	assert_true(mid.is_ancestor_of(ui.get_node("%MagWheel")), "cylinder in middle third")
	assert_true(mid.is_ancestor_of(ui.get_node("%BagPanel")), "ammo bag in middle third")
	var row: Node = ui.get_node("%ActionRow")
	assert_true(ui.get_node("Margin/RootVBox/BottomPanel").is_ancestor_of(row), "controls in bottom third")
	var btns: Array = []
	for ch in row.get_children():
		if ch is Button:
			btns.append(ch)
	assert_eq(btns.size(), 2, "exactly two control buttons")
	assert_eq(btns[0].text, "手动装弹")
	assert_eq(btns[1].text, "射击")


func test_manual_load_adds_one_then_fire_empties() -> void:
	var cs := CombatState.new(3001)
	cs.start_rush(3001)
	assert_true(cs.can_manual_load())
	assert_false(cs.can_fire(), "nothing loaded yet")
	var bag0 := cs.bag.size()
	assert_true(cs.begin_load())
	var r: Dictionary = cs.load_next_chamber()
	assert_true(bool(r.get("ok", false)))
	assert_eq(cs.magazine.loaded_count(), 1)
	assert_eq(cs.bag.size(), bag0 - 1)
	assert_true(cs.can_fire(), "partial load can fire")
	assert_true(cs.do_fire())
	assert_true(cs.magazine.is_empty())


func test_rush_is_only_mode() -> void:
	var cs := CombatState.new(3002)
	cs.start_rush(3002)
	assert_false("endless_mode" in cs)
	assert_false("from_map_run" in cs)
	assert_false(cs.has_method("start_graybox"))
	assert_false(cs.has_method("start_from_run"))
	assert_eq(cs.enemies.size(), 2)
