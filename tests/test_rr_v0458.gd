extends GutTest
## v0.4.58：连射前转轮落在最先的开始弹；撤退弹临时复制体入手/上膛保持半透明且不会被寿命清仓。


const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const CHETUI := CombatConstants.CHETUI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const EMPTY := Magazine.EMPTY
const FIRE_ONCE := CombatConstants.FIRE_ONCE_TEMP


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_58() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.58") >= 0)
	assert_true("0.4.58" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("开始弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _ready_fight(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs


func _ready_next_action(cs: CombatState) -> void:
	cs._volley_pending = false
	cs._volley_followup_pending = false
	cs._volley_session = false
	cs.player_fire_gate_remaining = 0.0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)


func test_spin_multiple_starts_always_lands_on_first() -> void:
	var cs := CombatState.new(45801)
	cs.start_rush(45801, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 5
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.set_slot(3, WHITE)
	cs.magazine.set_slot(4, XULI)
	cs.magazine.set_slot(5, WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	for i in 20:
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0)
		assert_eq(cs.magazine.chamber_at_fire_port(), 1, "多发开始弹必须停在下标最小的那发")
		assert_eq(cs.magazine.slots[cs.magazine.chamber_at_fire_port()], QISHI)


func test_spin_single_start_always_lands_there() -> void:
	var cs := CombatState.new(45802)
	cs.start_rush(45802, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(2, DIZENG)
	cs.magazine.set_slot(4, QISHI)
	cs.magazine.set_slot(5, WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	for i in 12:
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0)
		assert_eq(cs.magazine.chamber_at_fire_port(), 4)


func test_spin_already_on_first_start_still_turns_full_circle() -> void:
	var cs := CombatState.new(45803)
	cs.start_rush(45803, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 1
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(4, XULI)
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(2, WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var steps: int = cs.spin_cylinder_for_volley()
	assert_eq(steps, cs.magazine.size(), "已在最先开始仓时画面仍整圈转")
	assert_eq(cs.magazine.chamber_at_fire_port(), 1)
	assert_eq(cs.magazine.start_index, 1)


func test_spin_without_start_keeps_loaded_fallback() -> void:
	var cs := CombatState.new(45804)
	cs.start_rush(45804, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(2, DIZENG)
	cs.magazine.set_slot(4, ZHONGSHEN)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	for i in 16:
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0)
		var port: int = cs.magazine.chamber_at_fire_port()
		assert_ne(cs.magazine.slots[port], EMPTY, "无开始弹时仍不得停在空仓")
		assert_true(port == 0 or port == 2 or port == 4)


func test_spin_ui_ring_matches_first_start() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.set_slot(3, WHITE)
	cs.magazine.set_slot(4, XULI)
	cs.magazine.set_slot(5, WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	ui._snap_disk_to_logic()
	ui._refresh()
	assert_eq(ui.ring_slot_from_disk(), 0)
	# 与真实开火路径一致：预转期间 is_shooting，_refresh 不得提前把盘面对齐到落点。
	ui._volley_ui_running = true
	var steps: int = cs.spin_cylinder_for_volley()
	assert_gt(steps, 0)
	assert_eq(cs.magazine.chamber_at_fire_port(), 1)
	assert_eq(ui.ring_slot_from_disk(), 0, "预转动画开始前击发圈应仍在转前锤位")
	await ui._play_roll_spin_visual(steps)
	assert_eq(ui.ring_slot_from_disk(), 1, "银白击发圈应对准最先的开始弹仓")
	assert_eq(ui.displayed_ammo_at(ui.ring_slot_from_disk()), QISHI)
	ui._volley_ui_running = false
	CombatState.boot_sandbox = false


func test_fire_once_temp_survives_magazine_lifetime_tick() -> void:
	var cs := CombatState.new(45820)
	cs.start_sandbox(45820, FireResolver.ID_WRATH, false)
	cs.magazine.clear()
	cs.magazine.set_slot(0, BAIBAN, FIRE_ONCE, true)
	cs.magazine.set_slot(1, BAIBAN, 0.2, false)
	assert_true(cs.tick_temp_sin_lifetimes(0.25))
	assert_eq(cs.magazine.slots[0], BAIBAN, "打出即毁复制体不能被寿命结算清仓")
	assert_true(cs.magazine.is_slot_fire_once(0))
	assert_true(cs.magazine.is_slot_envy_copy(0))
	assert_eq(cs.magazine.slots[1], EMPTY, "带正数寿命的临时弹到期仍应消失")
	assert_true(cs.tick_temp_sin_lifetimes(2.0) == false or cs.magazine.slots[0] == BAIBAN)
	assert_eq(cs.magazine.slots[0], BAIBAN)


func test_chetui_generated_temp_pour_hand_load_fire() -> void:
	var cs := _ready_fight(45830)
	cs.dev_clear_bag()
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, BAIBAN)
	var shots: Array = cs.fire_tap(true)
	assert_gt(shots.size(), 0)
	var temps: int = 0
	for i in cs.bag.size():
		if cs.is_bag_index_temporary(i):
			temps += 1
			assert_eq(float(cs.bag_temp[i]), FIRE_ONCE)
			assert_true(bool(cs.bag_envy_copy[i]))
	assert_gt(temps, 0, "撤退弹开火后应生成打出即毁临时复制体进袋")
	var recs: Array = []
	for i in cs.bag.size():
		recs.append({
			"id": int(cs.bag[i]),
			"temp": cs.is_bag_index_temporary(i),
			"envy": bool(cs.bag_envy_copy[i]) if i < cs.bag_envy_copy.size() else false,
		})
	_ready_next_action(cs)
	cs.magazine.clear()
	var n: int = cs.dump_to_hand_items(recs)
	assert_gt(n, 0, "生成的临时复制体应能按倒出记录入手")
	assert_eq(cs.hand.size(), n)
	for i in cs.hand.size():
		assert_eq(float(cs.hand_temp[i]), FIRE_ONCE)
		assert_true(bool(cs.hand_envy_copy[i]))
		assert_true(cs.is_hand_index_temporary(i))
	var hid: int = int(cs.hand[0])
	assert_true(cs.load_hand_index_into_chamber(0, 0))
	assert_eq(cs.magazine.slots[0], hid)
	assert_true(cs.magazine.is_slot_temporary(0))
	assert_true(cs.magazine.is_slot_fire_once(0))
	assert_true(cs.magazine.is_slot_envy_copy(0))
	assert_eq(cs.magazine.slot_temp_life(0), FIRE_ONCE)
	cs.tick_temp_sin_lifetimes(0.5)
	cs.tick_temp_sin_lifetimes(1.5)
	assert_eq(cs.magazine.slots[0], hid, "装进转轮仓后不得因寿命结算消失")
	assert_true(cs.magazine.is_slot_fire_once(0))
	var disc0: int = cs.discard.size()
	cs.magazine.start_index = 0
	_ready_next_action(cs)
	var fired: Array = cs.fire_tap(true)
	assert_gt(fired.size(), 0)
	assert_eq(cs.magazine.slots[0], EMPTY)
	assert_lte(cs.discard.size(), disc0, "打出即毁临时弹不增加弃牌；空袋重洗可减少弃牌")


func test_temp_copy_hand_and_chamber_stay_translucent() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.dev_clear_bag()
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.magazine.clear()
	cs._bag_append(BAIBAN, FIRE_ONCE, true)
	var recs: Array = [{"id": BAIBAN, "temp": true, "envy": true}]
	_ready_next_action(cs)
	assert_eq(cs.dump_to_hand_items(recs), 1)
	ui._refresh()
	await wait_process_frames(1)
	assert_gt(ui._hand_slot_panels.size(), 0)
	var hp: Control = ui._hand_slot_panels[0]
	assert_true(hp is HandBulletView)
	assert_almost_eq((hp as HandBulletView).modulate.a, 0.48, 0.001, "入手后仍应半透明")
	assert_true((hp as HandBulletView).temporary)
	assert_true(cs.load_hand_index_into_chamber(0, 2))
	ui._refresh()
	# 真实战斗心跳：修之前会在第一次寿命结算后把仓打空。
	for _i in 8:
		cs.tick_combat_time(1.0 / 60.0)
		await wait_process_frames(1)
	assert_eq(cs.magazine.slots[2], BAIBAN, "装进转轮仓后经过心跳仍在")
	assert_true(cs.magazine.is_slot_fire_once(2))
	ui._refresh()
	assert_true(2 < ui._chamber_panels.size())
	var panel: Control = ui._chamber_panels[2]
	assert_almost_eq(panel.modulate.a, 0.48, 0.001, "转轮仓内临时复制体应半透明")
	CombatState.boot_sandbox = false


func test_temp_copy_physics_pour_keeps_identity_flags() -> void:
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(360, 400)
	add_child_autofree(box)
	box.sync_ammo_ids([BAIBAN, BAIBAN], [true, true], [true, true])
	for _i in 90:
		box._physics_process(1.0 / 60.0)
	box.pour_cap = 2
	box.hand_catch_rect = Rect2(40, 520, 280, 180)
	box.hand_catch_active = true
	for k in 36:
		box.sack_tilt = -PI * float(k + 1) / 36.0
		box._physics_process(1.0 / 60.0)
	box.mouth_open = true
	box.impulse_pour_balls()
	var closed := false
	for _j in 300:
		box._physics_process(1.0 / 60.0)
		if not closed and box.fallen_count() >= 2:
			box.mouth_open = false
			closed = true
	if box.mouth_open:
		box.mouth_open = false
	for _k in 60:
		box._physics_process(1.0 / 60.0)
	assert_eq(box.fallen_count(), 2)
	var fallen: Array = box.take_fallen_balls()
	assert_eq(fallen.size(), 2)
	for rec in fallen:
		assert_eq(int(rec.get("id", -1)), BAIBAN)
		assert_true(bool(rec.get("temp", false)), "倒出记录应带临时标记")
		assert_true(bool(rec.get("envy", false)), "倒出记录应带复制标记")
	var cs := CombatState.new(45840)
	cs.start_sandbox(45840, FireResolver.ID_WRATH, false)
	cs.dev_clear_bag()
	cs._bag_append(BAIBAN, FIRE_ONCE, true)
	cs._bag_append(BAIBAN, FIRE_ONCE, true)
	_ready_next_action(cs)
	assert_eq(cs.dump_to_hand_items(fallen), 2)
	for i in cs.hand.size():
		assert_eq(float(cs.hand_temp[i]), FIRE_ONCE)
		assert_true(bool(cs.hand_envy_copy[i]))
		assert_true(cs.is_hand_index_temporary(i))
	assert_true(cs.load_hand_index_into_chamber(0, 0))
	cs.tick_temp_sin_lifetimes(1.0)
	assert_eq(cs.magazine.slots[0], BAIBAN)
	assert_true(cs.magazine.is_slot_fire_once(0))
