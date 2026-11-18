extends GutTest
## v0.4.55：沙盒一键清空弹药袋（只清袋）；加减按钮加大。


const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const CombatUIScript = preload("res://scripts/combat/combat_ui.gd")


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_55() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.55") >= 0)
	assert_true("0.4.55" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("清空弹药袋" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_ammo_add_remove_buttons_are_enlarged() -> void:
	assert_almost_eq(CombatUIScript.SB_AMMO_BTN_H, 96.0, 0.001)
	assert_almost_eq(CombatUIScript.SB_AMMO_BTN_MIN_W, 100.0, 0.001)
	assert_eq(CombatUIScript.SB_AMMO_BTN_FONT, 30)
	assert_gt(CombatUIScript.SB_AMMO_BTN_H, CombatUIScript.SB_TOUCH_H)
	CombatState.boot_sandbox = true
	var scene = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var counted := 0
	for b in scene.dev_panel.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn.text in ["袋+", "袋-", "手+", "手-"] and btn.is_visible_in_tree():
			assert_gte(btn.custom_minimum_size.y, 96.0, "加减按钮高度 %s" % btn.text)
			assert_gte(btn.custom_minimum_size.x, 100.0, "加减按钮宽度 %s" % btn.text)
			counted += 1
	assert_eq(counted, scene.state.sandbox_enabled_ammo_ids().size() * 4)
	CombatState.boot_sandbox = false


func test_dev_clear_bag_keeps_hand_and_chambers_and_stays_empty() -> void:
	var cs := CombatState.new(45501)
	cs.start_sandbox(45501, FireResolver.ID_WRATH, false)
	cs.sandbox_add_ammo(WHITE, 3)
	cs.sandbox_add_to_hand(QISHI, 2)
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, QISHI)
	var hand0: Array = cs.hand.duplicate()
	var slots0: Array = cs.magazine.slots.duplicate()
	cs.dev_clear_bag()
	assert_eq(cs.bag.size(), 0)
	assert_true(cs.sandbox_hold_bag_empty)
	assert_eq(cs.hand, hand0, "手里的子弹应保留")
	assert_eq(cs.magazine.slots, slots0, "弹仓应保留")
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.hand, hand0)
	assert_eq(cs.magazine.slots, slots0)


func test_sandbox_clear_bag_button_empties_sack_only() -> void:
	CombatState.boot_sandbox = true
	var scene = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var clear := scene.dev_panel.get_node_or_null("DevMargin/DevVBox/SandboxClearBag") as Button
	assert_not_null(clear, "控制台应有清空弹药袋按钮")
	assert_eq(clear.text, "清空弹药袋")
	assert_gte(clear.custom_minimum_size.y, 96.0)
	scene.state.sandbox_add_ammo(WHITE, 4)
	scene.state.sandbox_add_to_hand(QISHI, 1)
	scene.state.magazine.set_slot(0, WHITE)
	scene._refresh()
	await wait_process_frames(2)
	assert_eq(scene.state.bag.size(), 4)
	assert_false(clear.disabled)
	if scene._bag_physics != null:
		assert_eq(scene._bag_physics.ball_count(), 4)
	var hand_n: int = scene.state.hand.size()
	var mag_n: int = scene.state.magazine.loaded_count()
	clear.pressed.emit()
	await wait_process_frames(2)
	assert_eq(scene.state.bag.size(), 0)
	assert_true(scene.state.sandbox_hold_bag_empty)
	assert_eq(scene.state.hand.size(), hand_n)
	assert_eq(scene.state.magazine.loaded_count(), mag_n)
	if scene._bag_physics != null:
		assert_eq(scene._bag_physics.ball_count(), 0, "袋画面应同步变空")
	assert_true(clear.disabled)
	assert_false(scene.state.ensure_bag_refilled_if_empty())
	assert_eq(scene.state.bag.size(), 0)
	CombatState.boot_sandbox = false
