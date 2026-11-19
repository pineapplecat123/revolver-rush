extends GutTest
## v0.4.57：平庸全部换成白板；沙盒袋+一次加 2 发；打光后空袋不再自动补回。


const WHITE := CombatConstants.WHITE_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const RETIRED := CombatConstants.RETIRED_PINGYONG_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_0_4_57() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.57") >= 0)
	assert_true("0.4.57" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("白板弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_pingyong_replaced_by_single_baiban() -> void:
	assert_eq(WHITE, BAIBAN)
	assert_eq(WHITE, 49)
	assert_eq(RETIRED, 1)
	assert_eq(CombatConstants.migrate_ammo_id(1), BAIBAN)
	assert_eq(CombatConstants.migrate_ammo_id(49), BAIBAN)
	assert_eq(CombatConstants.migrate_ammo_id(40), 40)
	var names: Array = []
	var ids: Array = []
	for item in DataRegistry.all_ammo():
		ids.append(int(item.get("id", 0)))
		names.append(str(item.get("name", "")))
	assert_false(1 in ids, "平庸行已从弹药表删除")
	assert_eq(ids.count(BAIBAN), 1, "只有一条白板定义")
	assert_false("平庸子弹" in names)
	assert_true("白板弹" in names)
	assert_eq(DataRegistry.all_ammo().size(), 15)
	var def: Dictionary = DataRegistry.get_ammo(BAIBAN)
	assert_eq(str(def.get("name")), "白板弹")
	assert_eq(int(def.get("base_damage")), 3)
	assert_eq(FireResolver.type_tag(BAIBAN), "中间")
	# 旧 id 读取时也指向白板，不另开一套
	assert_eq(str(DataRegistry.get_ammo(RETIRED).get("name")), "白板弹")
	assert_eq(int(DataRegistry.get_ammo(RETIRED).get("id")), BAIBAN)
	assert_true(DataRegistry.is_ammo_runtime_visible(BAIBAN))
	assert_false(ids.has(RETIRED))


func test_starter_bag_and_legacy_instances_become_baiban() -> void:
	var ids: Array[int] = CombatConstants.starter_ammo_ids()
	assert_eq(ids.count(WHITE), CombatConstants.STARTER_WHITE_COUNT)
	assert_eq(ids.count(1), 0)
	var cs := CombatState.new(45701)
	cs.start_rush(45701, FireResolver.ID_WRATH)
	assert_eq(cs.count_ammo_in_bag(BAIBAN), CombatConstants.STARTER_WHITE_COUNT)
	assert_eq(cs.count_ammo_in_bag(RETIRED), 0)
	# 旧平庸实例写入袋/手/仓后变成白板，数量与临时标记保留
	cs.dev_clear_bag()
	cs.sandbox_mode = true
	cs._bag_append(RETIRED, 0.0)
	cs._bag_append(RETIRED, 4.5)
	assert_eq(cs.bag.size(), 2)
	assert_eq(int(cs.bag[0]), BAIBAN)
	assert_eq(int(cs.bag[1]), BAIBAN)
	assert_almost_eq(float(cs.bag_temp[1]), 4.5, 0.0001)
	cs._hand_append(RETIRED, false)
	assert_eq(int(cs.hand[0]), BAIBAN)
	cs.magazine.set_slot(0, RETIRED, false)
	assert_eq(int(cs.magazine.slots[0]), BAIBAN)


func test_sandbox_lists_baiban_not_pingyong() -> void:
	var cs := CombatState.new(45702)
	cs.start_sandbox(45702)
	var ids: Array[int] = cs.sandbox_enabled_ammo_ids()
	assert_true(BAIBAN in ids)
	assert_false(RETIRED in ids)
	assert_eq(ids.count(BAIBAN), 1)


func test_sandbox_bag_plus_tap_adds_exactly_two_even_with_duplicate_events() -> void:
	assert_eq(CombatConstants.SANDBOX_BAG_ADD_PER_TAP, 2)
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	assert_true(ui.state.sandbox_mode)
	assert_eq(ui.state.bag.size(), 0)
	var btn: Button = _find_bag_plus_for(ui, BAIBAN)
	assert_not_null(btn)
	# 一次点按同时送鼠标和触屏 down/up，不能加成 4 发
	_emit_pointer(btn, "mouse", true)
	_emit_pointer(btn, "touch", true)
	_emit_pointer(btn, "mouse", false)
	_emit_pointer(btn, "touch", false)
	await wait_process_frames(1)
	assert_eq(ui.state.count_ammo_in_bag(BAIBAN), 2, "一次袋+应加 2 发，事件重复也不再加倍")
	assert_eq(ui.state.bag.size(), 2)
	# 再点一次仍是 +2
	_emit_pointer(btn, "mouse", true)
	_emit_pointer(btn, "touch", true)
	_emit_pointer(btn, "mouse", false)
	_emit_pointer(btn, "touch", false)
	await wait_process_frames(1)
	assert_eq(ui.state.bag.size(), 4)
	CombatState.boot_sandbox = false


func test_sandbox_firing_all_baiban_leaves_bag_empty() -> void:
	var cs := _sandbox_fight(45703)
	cs.sandbox_add_ammo(BAIBAN, 2)
	assert_eq(cs.bag.size(), 2)
	assert_eq(cs._combat_bag_baseline.size(), 2)
	assert_true(cs.begin_load())
	var loaded := 0
	for _i in 8:
		var rec: Dictionary = cs.load_next_chamber()
		if bool(rec.get("done", false)) or not bool(rec.get("ok", true)):
			if int(rec.get("ammo_id", Magazine.EMPTY)) != Magazine.EMPTY:
				loaded += 1
			break
		if int(rec.get("ammo_id", Magazine.EMPTY)) != Magazine.EMPTY:
			loaded += 1
	assert_eq(loaded, 2)
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(cs.bag.size(), 0, "装完后袋应空，且不被基线补回")
	var shots: Array = cs.fire_tap(false)
	# 第一发已打出；余下用连射步进打完（含结束时的敌方回合/补袋检查）
	var guard := 8
	while guard > 0 and cs.is_volley_pending():
		guard -= 1
		cs.player_fire_gate_remaining = 0.0
		var more: Array = cs.take_volley_shot()
		shots.append_array(more)
	assert_gte(shots.size(), 2)
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_eq(cs.bag.size(), 0, "打光白板后袋应保持空，不能多出一发")
	assert_eq(cs.hand.size(), 0)
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 0)
	# 弹药守恒：用掉的永久弹不能凭空再出现在袋/手/仓
	assert_eq(cs.count_ammo_in_bag(BAIBAN), 0)
	assert_eq(cs.count_ammo_in_hand(BAIBAN), 0)


func test_sandbox_add_two_dump_and_refresh_does_not_spawn_extra() -> void:
	var cs := _sandbox_fight(45704)
	cs.sandbox_add_ammo(BAIBAN, CombatConstants.SANDBOX_BAG_ADD_PER_TAP)
	assert_eq(cs.bag.size(), 2)
	assert_eq(cs.dump_to_hand(), 2)
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.hand.size(), 2)
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 0, "倒出手后空袋不应再补出弹药")


func test_sandbox_still_allows_effect_generated_ammo() -> void:
	# 撤退弹打出后仍可往袋里放临时复制体，不被「沙盒不补袋」拦住。
	var cs := _sandbox_fight(45705)
	var chetui := CombatConstants.CHETUI_AMMO_ID
	cs.sandbox_add_ammo(BAIBAN, 1)
	cs.sandbox_add_ammo(chetui, 1)
	assert_true(cs.begin_load())
	for _i in 8:
		var rec: Dictionary = cs.load_next_chamber()
		if bool(rec.get("done", false)):
			break
	var before: int = cs.bag.size()
	cs.fire_tap(false)
	var guard := 8
	while guard > 0 and cs.is_volley_pending():
		guard -= 1
		cs.player_fire_gate_remaining = 0.0
		cs.take_volley_shot()
	# 撤退应生成临时复制体入袋；这是效果本身，不是空袋自动补回。
	var temps := 0
	for tv in cs.bag_temp:
		if Magazine.temp_value(tv) > 0.0:
			temps += 1
	assert_gt(cs.bag.size() + temps, before - 1)
	assert_gt(cs.bag.size(), 0)


func _sandbox_fight(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH, true)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	# 保留默认自动推进：打完连射会走敌方回合里的补袋检查
	return cs


func _find_bag_plus_for(ui, ammo_id: int) -> Button:
	for pair in ui._sb_count_nodes.keys():
		if int(pair) == int(ammo_id):
			return ui._sb_count_nodes[pair].get("bag_plus") as Button
	# 退回：按行上的白板名称找邻近袋+
	for b in ui.dev_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "袋+" and (b as Button).is_visible_in_tree():
			return b as Button
	return null


func _emit_pointer(btn: Control, kind: String, pressed: bool) -> void:
	var ev: InputEvent
	if kind == "touch":
		var t := InputEventScreenTouch.new()
		t.position = Vector2(8, 8)
		t.pressed = pressed
		t.index = 0
		ev = t
	else:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = Vector2(8, 8)
		m.pressed = pressed
		ev = m
	btn.gui_input.emit(ev)
