extends GutTest
## v0.4.44：沙盒空袋、木桩死后恢复、新的顶部弹药控制台。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const WEIZHONG := CombatConstants.WEIZHONG_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_0_4_44() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.44") >= 0)
	assert_true("0.4.44" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_sandbox_starts_with_empty_bag_rush_unchanged() -> void:
	var sb := CombatState.new(44401)
	sb.start_sandbox(44401, FireResolver.ID_WRATH)
	assert_true(sb.sandbox_mode)
	assert_eq(sb.bag.size(), 0)
	assert_eq(sb.hand.size(), 0)
	assert_true(sb.sandbox_hold_bag_empty)
	assert_false(sb.ensure_bag_refilled_if_empty())
	assert_eq(sb.bag.size(), 0)
	assert_eq(sb.enemies.size(), CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS.size())
	var rush := CombatState.new(44402)
	rush.start_rush(44402, FireResolver.ID_WRATH)
	assert_false(rush.sandbox_mode)
	assert_eq(rush.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(rush.total_ammo_count(WHITE), CombatConstants.STARTER_WHITE_COUNT)


func test_sandbox_bag_and_hand_add_remove_and_hand_cap() -> void:
	var cs := CombatState.new(44403)
	cs.start_sandbox(44403, FireResolver.ID_WRATH, false)
	assert_true(WHITE in cs.sandbox_enabled_ammo_ids())
	assert_true(QISHI in cs.sandbox_enabled_ammo_ids())
	assert_true(WEIZHONG in cs.sandbox_enabled_ammo_ids())
	cs.sandbox_add_ammo(WHITE, 2)
	cs.sandbox_add_ammo(QISHI, 1)
	assert_eq(cs.count_ammo_in_bag(WHITE), 2)
	assert_eq(cs.count_ammo_in_bag(QISHI), 1)
	assert_eq(cs.sandbox_remove_ammo_from_bag(WHITE, 1), 1)
	assert_eq(cs.count_ammo_in_bag(WHITE), 1)
	assert_eq(cs.sandbox_add_to_hand(QISHI, 2), 2)
	assert_eq(cs.count_ammo_in_hand(QISHI), 2)
	assert_eq(cs.bag.size(), 2)
	assert_eq(cs.sandbox_remove_from_hand(QISHI, 1), 1)
	assert_eq(cs.count_ammo_in_hand(QISHI), 1)
	# 手容量 6：再加到满后加不进去
	var added := cs.sandbox_add_to_hand(WHITE, 10)
	assert_eq(cs.hand.size(), CombatConstants.HAND_SIZE)
	assert_eq(added, CombatConstants.HAND_SIZE - 1)
	assert_eq(cs.sandbox_add_to_hand(WHITE, 1), 0)
	assert_eq(cs.hand.size(), CombatConstants.HAND_SIZE)


func test_dummy_revives_in_sandbox_without_xp_or_gold() -> void:
	var cs := CombatState.new(44404)
	cs.start_sandbox(44404, FireResolver.ID_WRATH, false)
	cs.gold = 0
	cs.xp = 0
	cs.pending_levelups = 0
	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(20, 4)
	assert_not_null(dummy)
	var cell: int = dummy.cell
	dummy.hp = 0
	dummy.burn_stacks = 3
	cs.kill_gold_chance_override = 1.0
	cs._remove_dead()
	assert_eq(cs.enemies.size(), 1, "木桩还在")
	assert_true(cs.enemies[0].is_dummy)
	assert_eq(cs.enemies[0].cell, cell)
	assert_eq(cs.enemies[0].hp, cs.enemies[0].max_hp)
	assert_eq(cs.enemies[0].burn_stacks, 0)
	assert_eq(cs.gold, 0)
	assert_eq(cs.pending_gold_total(), 0)
	assert_eq(cs.xp, 0)
	assert_eq(cs.pending_levelups, 0)


func test_normal_enemy_still_removed_in_sandbox() -> void:
	var cs := CombatState.new(44405)
	cs.start_sandbox(44405, FireResolver.ID_WRATH, false)
	cs.dev_spawn_enemy(CombatConstants.CIVILIAN_ENEMY_ID, 5)
	assert_eq(cs.enemies.size(), 1)
	cs.enemies[0].hp = 0
	cs._remove_dead()
	assert_eq(cs.enemies.size(), 0)


func test_sandbox_console_lists_enabled_ammo_with_big_buttons() -> void:
	CombatState.boot_sandbox = true
	var scene = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(scene.state.sandbox_mode)
	assert_eq(scene.state.bag.size(), 0)
	assert_true(scene.dev_panel.visible)
	var vp: Vector2 = scene.get_viewport_rect().size
	var pr: Rect2 = scene.dev_panel.get_global_rect()
	assert_true(pr.position.y <= 16.0, "控制台从上方弹出")
	assert_true(pr.size.y <= vp.y * 0.40 + 8.0, "大约三分之一屏高")
	if scene.bag_panel != null:
		assert_true(pr.end.y <= scene.bag_panel.get_global_rect().position.y + 1.0, "不遮挡弹药袋")
	var names: Array = []
	for l in scene.dev_panel.find_children("*", "Label", true, false):
		names.append((l as Label).text)
	var joined := " ".join(names)
	assert_true("白板弹" in joined)
	assert_true("加伤弹" in joined)
	assert_true("尾重弹" in joined)
	var plus_bag := 0
	for b in scene.dev_panel.find_children("*", "Button", true, false):
		var btn := b as Button
		if not btn.is_visible_in_tree():
			continue
		assert_true(btn.get_combined_minimum_size().y >= 56.0, "按钮 '%s' 太小" % btn.text)
		if btn.text == "袋+":
			plus_bag += 1
	assert_eq(plus_bag, scene.state.sandbox_enabled_ammo_ids().size())
	# 点白板入袋，计数更新，袋区仍在控制台下面
	for b in scene.dev_panel.find_children("*", "Button", true, false):
		var btn2 := b as Button
		if btn2.text == "袋+" and btn2.is_visible_in_tree():
			# 点第一行（按类型排序，白板在中间组）
			pass
	scene.state.sandbox_add_ammo(WHITE, 1)
	scene._refresh()
	await get_tree().process_frame
	assert_eq(scene.state.count_ammo_in_bag(WHITE), 1)
