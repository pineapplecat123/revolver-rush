extends GutTest

var ui
var old_emulation: bool

func before_each() -> void:
	old_emulation = bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = true
	ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	if ui._dev_open:
		ui._toggle_dev()
	ui.set_process(false)
	ui._bag_physics.set_physics_process(false)
	ui.state.magazine.set_slot(0, CombatConstants.WHITE_AMMO_ID)
	ui._paint_mag_chambers()

func after_each() -> void:
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", old_emulation)
	CombatState.boot_sandbox = false

func mouse(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e

func motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e

func chamber_press() -> Vector2:
	var p: Vector2 = ui.chamber_visual_center(0)
	ui._on_chamber_gui_input(mouse(true, p), 0)
	return p

func test_chamber_waits_for_threshold_and_release_is_consumed() -> void:
	var p := chamber_press()
	ui._tick_bullet_hold(0.44)
	assert_false(ui._detail_open)
	assert_false(ui._drag_active)
	ui._tick_bullet_hold(0.02)
	assert_true(ui._detail_open)
	assert_eq(ui._ammo_detail_title.text, DataRegistry.get_ammo(CombatConstants.WHITE_AMMO_ID)["name"])
	assert_true(ui._bullet_hold_input(mouse(false, p)))
	assert_false(ui._detail_open)
	assert_false(ui._ammo_detail_panel.visible)

func test_short_tap_does_not_show_and_does_not_drag() -> void:
	var p := chamber_press()
	ui._tick_bullet_hold(0.2)
	ui._input(mouse(false, p))
	ui._tick_bullet_hold(1.0)
	assert_false(ui._detail_open)
	assert_false(ui._drag_active)

func test_jitter_is_allowed_but_drag_never_rearms() -> void:
	var p := chamber_press()
	ui._bullet_hold_input(motion(p + Vector2(6, 4)))
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)
	assert_true(ui._bullet_hold_input(motion(p + Vector2(11, 0))))
	assert_false(ui._detail_open)
	assert_true(ui._drag_active)
	ui._input(motion(p))
	ui._tick_bullet_hold(1.0)
	assert_false(ui._detail_open)
	ui._input(mouse(false, p))
	assert_false(ui._drag_active)

func test_drag_before_threshold_preserves_chamber_swap() -> void:
	var p := chamber_press()
	var other := FireResolver.ID_WRATH
	ui.state.magazine.set_slot(1, other)
	var target: Vector2 = ui.chamber_visual_center(1)
	ui._input(motion(target))
	assert_true(ui._drag_active)
	assert_false(ui._detail_open)
	ui._input(mouse(false, target))
	assert_eq(ui.state.magazine.slots[1], CombatConstants.WHITE_AMMO_ID)
	assert_eq(ui.state.magazine.slots[0], other)

func test_hover_only_never_opens_legacy_bag_tip() -> void:
	ui._on_bag_physics_hover(CombatConstants.WHITE_AMMO_ID)
	ui._on_bag_physics_press(CombatConstants.WHITE_AMMO_ID)
	ui._tick_bullet_hold(1.0)
	assert_false(ui._detail_open)

func bag_press() -> Dictionary:
	var bag = ui._bag_physics
	bag.clear_balls()
	bag._spawn_ball(CombatConstants.WHITE_AMMO_ID)
	bag._spawn_ball(CombatConstants.WHITE_AMMO_ID)
	bag._balls[0]["pos"] = Vector2(80, 90)
	bag._balls[1]["pos"] = Vector2(180, 190)
	var ball: Dictionary = bag._balls[0]
	var p: Vector2 = bag.get_global_transform() * Vector2(ball["pos"])
	ui._on_bag_detail_press(int(ball["id"]), int(ball["detail_uid"]), mouse(true, p))
	return ball

func test_bag_tracks_instance_through_motion_not_ball_under_finger() -> void:
	var ball := bag_press()
	var uid: int = ball["detail_uid"]
	ball["pos"] = Vector2(130, 130)
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)
	assert_eq(ui._bullet_hold_key, uid)
	assert_eq(ui._detail_ammo_id, CombatConstants.WHITE_AMMO_ID)
	ui._bag_physics._balls.remove_at(0)
	ui._tick_bullet_hold(0.01)
	assert_false(ui._detail_open, "Duplicate ammo does not keep removed instance's popup alive")
	assert_eq(ui._bullet_hold_kind, "")

func test_bag_drag_before_threshold_never_opens_or_rearms() -> void:
	bag_press()
	var p: Vector2 = ui._bullet_hold_origin
	ui._input(motion(p + Vector2(30, 0)))
	ui._input(motion(p))
	ui._tick_bullet_hold(1.0)
	assert_false(ui._detail_open)
	assert_false(ui._drag_active)

func test_bag_release_outside_hides_immediately() -> void:
	bag_press()
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)
	assert_true(ui._bullet_hold_input(mouse(false, Vector2(-100, -100))))
	assert_false(ui._detail_open)

func test_removed_chamber_bullet_cancels() -> void:
	chamber_press()
	ui._tick_bullet_hold(0.46)
	ui.state.magazine.set_slot(0, Magazine.EMPTY)
	ui._tick_bullet_hold(0.01)
	assert_false(ui._detail_open)

func test_modal_cancels_pending_without_timeout_resurrection() -> void:
	chamber_press()
	ui._shop_open = true
	ui._update_dimmer()
	ui._shop_open = false
	ui._tick_bullet_hold(1.0)
	assert_false(ui._detail_open)
	assert_eq(ui._bullet_hold_kind, "")

func test_freeze_or_focus_loss_dismisses_open_tip() -> void:
	chamber_press()
	ui._tick_bullet_hold(0.46)
	ui._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(ui._detail_open)
	chamber_press()
	ui._tick_bullet_hold(0.46)
	ui._set_combat_frozen(true)
	assert_false(ui._detail_open)
	ui._set_combat_frozen(false)

func test_native_touch_ignores_other_finger_and_cancels() -> void:
	var host: Control = ui._chamber_panels[0]
	var down := InputEventScreenTouch.new()
	down.index = 7
	down.pressed = true
	down.position = host.size * 0.5
	ui._on_chamber_gui_input(down, 0)
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)
	var up := InputEventScreenTouch.new()
	up.index = 8
	assert_false(ui._bullet_hold_input(up))
	assert_true(ui._detail_open)
	up.index = 7
	up.canceled = true
	assert_true(ui._bullet_hold_input(up))
	assert_false(ui._detail_open)

func test_popup_is_rounded_noninteractive_inside_viewport_and_real_content() -> void:
	chamber_press()
	ui._tick_bullet_hold(0.46)
	var panel: PanelContainer = ui._ammo_detail_panel
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(ui._ammo_detail_body.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(ui._ammo_detail_title.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	assert_gt(style.corner_radius_top_left, 0)
	ui._position_bullet_hold_detail(Vector2(1, 1))
	var viewport_rect: Rect2 = ui.get_viewport().get_visible_rect()
	assert_true(viewport_rect.encloses(panel.get_global_rect()))
	var def: Dictionary = DataRegistry.get_ammo(CombatConstants.WHITE_AMMO_ID)
	assert_true(ui._ammo_detail_body.text.contains(str(def["game_description"])))
	assert_true(ui._ammo_detail_body.text.contains(str(def["special"])))
	assert_true(ui._ammo_detail_body.text.contains("基础伤害：3"))
	assert_false(ui._ammo_detail_body.text.contains("稀有度"))

func test_bag_real_gui_press_uses_stable_uid_and_keeps_physics_wakeup() -> void:
	var bag = ui._bag_physics
	bag.clear_balls()
	bag._spawn_ball(CombatConstants.WHITE_AMMO_ID)
	var ball: Dictionary = bag._balls[0]
	ball["pos"] = Vector2(80, 90)
	ball["asleep"] = true
	var event := mouse(true, Vector2(80, 90))
	event.global_position = bag.get_global_transform() * event.position
	bag._gui_input(event)
	assert_eq(ui._bullet_hold_kind, "bag")
	assert_eq(ui._bullet_hold_key, int(ball["detail_uid"]))
	assert_false(bool(ball["asleep"]))
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)

func test_touch_emulation_has_one_canonical_press_path() -> void:
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", true)
	var bag = ui._bag_physics
	bag.clear_balls()
	bag._spawn_ball(CombatConstants.WHITE_AMMO_ID)
	bag._balls[0]["pos"] = Vector2(80, 90)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(80, 90)
	bag._gui_input(touch)
	assert_eq(ui._bullet_hold_kind, "")
	var emulated := mouse(true, touch.position)
	emulated.global_position = bag.get_global_transform() * touch.position
	bag._gui_input(emulated)
	assert_eq(ui._bullet_hold_kind, "bag")
	ui._tick_bullet_hold(0.46)
	assert_true(ui._detail_open)
	ui._input(mouse(false, emulated.global_position))
	assert_false(ui._detail_open)

func test_modal_aborts_chamber_drag_without_dropping_or_swapping() -> void:
	var p := chamber_press()
	ui._input(motion(p + Vector2(30, 0)))
	assert_true(ui._drag_active)
	ui._shop_open = true
	ui._update_dimmer()
	assert_false(ui._drag_active)
	assert_eq(ui.state.magazine.slots[0], CombatConstants.WHITE_AMMO_ID)

func test_empty_chamber_and_formula_damage_have_no_fabricated_data() -> void:
	ui.state.magazine.set_slot(0, Magazine.EMPTY)
	chamber_press()
	ui._tick_bullet_hold(0.46)
	assert_false(ui._detail_open)
	for def in DataRegistry.all_ammo():
		if str(def.get("base_damage_mode", "")) == "previous_actual":
			assert_true(ui._bullet_hold_detail_text(int(def["id"])).contains("基础伤害：X"))

func test_effect_only_blank_damage_stays_blank_and_null_formula_is_x() -> void:
	for def in DataRegistry.all_ammo():
		if def.get("base_damage", 0) != null:
			continue
		var first: String = ui._bullet_hold_detail_text(int(def["id"])).split("\n")[0]
		if str(def.get("base_damage_mode", "")) == "effect":
			assert_eq(first, "基础伤害：")
		elif str(def.get("base_damage_mode", "")) == "formula":
			assert_eq(first, "基础伤害：X")
