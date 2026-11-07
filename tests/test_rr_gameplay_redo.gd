extends GutTest
## feat/gameplay-redo：倒出→手→拖装 / 仓对调（自动装入仅保留状态 API）；PLAIN_ONLY 开局。


func before_each() -> void:
	CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY = true
	DataRegistry.reload()


func after_each() -> void:
	CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY = false


func test_plain_only_starter_bag() -> void:
	var cs := CombatState.new()
	cs.start_rush(1, FireResolver.ID_WRATH)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT)
	for id in cs.bag:
		assert_eq(int(id), CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.hand.is_empty())


func test_dump_to_hand_draws_up_to_six() -> void:
	var cs := CombatState.new()
	cs.start_rush(2, FireResolver.ID_WRATH)
	assert_true(cs.can_dump_to_hand())
	var n: int = cs.dump_to_hand()
	assert_eq(n, CombatConstants.HAND_SIZE)
	assert_eq(cs.hand.size(), CombatConstants.HAND_SIZE)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT - CombatConstants.HAND_SIZE)


func test_dump_returns_hand_then_redraws() -> void:
	var cs := CombatState.new()
	cs.start_rush(3, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	var first: Array = cs.hand.duplicate()
	assert_eq(first.size(), 6)
	var bag_before_second: int = cs.bag.size()
	var n2: int = cs.dump_to_hand()
	assert_eq(n2, 6)
	# 手非空先退回再抽：袋数量应回到「总数-6」
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_PLAIN_ONLY_COUNT - 6)
	assert_eq(bag_before_second + first.size() - 6, cs.bag.size())


func test_auto_load_from_hand() -> void:
	var cs := CombatState.new()
	cs.start_rush(4, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	var loaded: int = cs.auto_load_from_hand()
	assert_eq(loaded, 6)
	assert_true(cs.hand.is_empty())
	assert_eq(cs.magazine.loaded_count(), 6)


func test_load_hand_into_specific_chamber() -> void:
	var cs := CombatState.new()
	cs.start_rush(5, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	assert_true(cs.load_hand_index_into_chamber(0, 2))
	assert_eq(cs.hand.size(), 5)
	assert_ne(cs.magazine.slots[2], Magazine.EMPTY)
	assert_eq(cs.magazine.slots[0], Magazine.EMPTY)


func test_swap_magazine_slots() -> void:
	var cs := CombatState.new()
	cs.start_rush(6, FireResolver.ID_WRATH)
	cs.dump_to_hand()
	cs.auto_load_from_hand()
	var a: int = cs.magazine.slots[0]
	var b: int = cs.magazine.slots[3]
	assert_true(cs.swap_magazine_slots(0, 3))
	assert_eq(cs.magazine.slots[0], b)
	assert_eq(cs.magazine.slots[3], a)


func test_do_load_still_works_for_tests() -> void:
	## 旧 API 保留：测试/金色额外轮仍可直接袋→匣。
	var cs := CombatState.new()
	cs.start_rush(7, FireResolver.ID_WRATH)
	assert_true(cs.do_load())
	assert_eq(cs.magazine.loaded_count(), 6)


func test_reward_pool_plain_only() -> void:
	var cs := CombatState.new()
	cs.start_rush(8, FireResolver.ID_WRATH)
	var choices: Array[int] = cs.generate_reward_choices()
	assert_eq(choices.size(), CombatConstants.REWARD_CHOICE_COUNT)
	for id in choices:
		assert_eq(int(id), CombatConstants.WHITE_AMMO_ID)


func test_ui_no_autoload_button_and_hand_scatter() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_null(ui.get_node_or_null("%BtnAutoLoad"))
	ui.state.dump_to_hand()
	ui._refresh()
	await wait_process_frames(2)
	assert_gt(ui._hand_slot_panels.size(), 0)
	# 散落：至少两颗位置不完全相同
	if ui._hand_slot_panels.size() >= 2:
		var a: Vector2 = ui._hand_slot_panels[0].position
		var b: Vector2 = ui._hand_slot_panels[1].position
		assert_ne(a, b, "hand balls should scatter")
