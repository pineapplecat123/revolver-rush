extends GutTest
## v0.4.56：加速弹节奏不再封顶；袋内圆形子弹下落更快。


const WHITE := CombatConstants.WHITE_AMMO_ID
const JIASU := CombatConstants.JIASU_AMMO_ID
const OLD_SACK_GRAVITY := 1400.0


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_56() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.56") >= 0)
	assert_true("0.4.56" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("4 倍" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_jiasu_stacks_uncapped_2x_3x_4x_cadence() -> void:
	assert_almost_eq(CombatConstants.JIASU_SPEED_PER_STACK, 1.0, 0.0001)
	var cs := _ready_fight(45601)
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, JIASU)
	cs.magazine.set_slot(2, JIASU)
	cs.magazine.set_slot(3, WHITE)
	var base: float = CombatState.volley_wait_before_next_sec()
	assert_almost_eq(cs.volley_speed_mult(), 1.0, 0.0001)
	cs.fire_tap(false)
	assert_almost_eq(cs.volley_speed_mult(), 2.0, 0.0001)
	assert_almost_eq(cs.volley_wait_scaled_sec(), base / 2.0, 0.0001)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_almost_eq(cs.volley_speed_mult(), 3.0, 0.0001)
	assert_almost_eq(cs.volley_wait_scaled_sec(), base / 3.0, 0.0001)
	assert_lt(cs.volley_wait_scaled_sec(), CombatConstants.MIN_FIRE_INTERVAL_SEC)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_almost_eq(cs.volley_speed_mult(), 4.0, 0.0001, "三层应为 4 倍，不再停在 2.5")
	assert_almost_eq(cs.volley_wait_scaled_sec(), base / 4.0, 0.0001)
	assert_lt(cs.volley_wait_scaled_sec(), base / 2.5, "实际节奏必须快过旧 2.5 倍封顶")


func test_ui_paced_cadence_goes_above_old_cap() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, JIASU)
	cs.magazine.set_slot(2, JIASU)
	cs.magazine.set_slot(3, WHITE)
	cs.pace_after_fire = false
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_almost_eq(cs.volley_speed_mult(), 3.0, 0.0001)
	ui._combat_speed = 1.0
	ui._volley_stepping = true
	var base: float = CombatState.volley_wait_before_next_sec()
	var paced: float = ui._paced(base, true)
	assert_almost_eq(paced, base / 3.0, 0.0001)
	assert_lt(paced, CombatConstants.MIN_FIRE_INTERVAL_SEC)
	assert_lt(paced, base / 2.5)
	# 仍是逐发：连射待发，不会一次打光
	assert_true(cs.is_volley_pending())
	assert_eq(cs.magazine.loaded_count(), 2)
	CombatState.boot_sandbox = false


func test_sack_gravity_is_clearly_faster() -> void:
	assert_almost_eq(BagPhysicsBox.GRAVITY, 2100.0, 0.1)
	assert_gt(BagPhysicsBox.GRAVITY, OLD_SACK_GRAVITY * 1.4)
	var box: BagPhysicsBox = BagPhysicsBox.new()
	box.size = Vector2(350, 370)
	add_child_autofree(box)
	box.sync_ammo_ids([WHITE])
	assert_eq(box.ball_count(), 1)
	var aabb: Rect2 = box._sack_interior_aabb()
	var b: Dictionary = box._balls[0]
	b["pos"] = Vector2(aabb.get_center().x, aabb.position.y + 40.0)
	b["vel"] = Vector2.ZERO
	b["asleep"] = false
	b["omega"] = 0.0
	var y0: float = float(b["pos"].y)
	var frames := 12
	var dt := 1.0 / 60.0
	for _i in frames:
		box._physics_process(dt)
	var drop: float = float(box._balls[0]["pos"].y) - y0
	var t: float = dt * float(frames)
	var old_free: float = 0.5 * OLD_SACK_GRAVITY * t * t
	assert_gt(drop, old_free * 1.25, "同样时间内应明显快过旧重力 1400")
	assert_gt(drop, 1.0)
	# 短时间内还在袋里，没有穿墙飞出
	assert_false(bool(box._balls[0].get("exited", false)))
	var poly: PackedVector2Array = box._sack_walls_world()
	assert_true(Geometry2D.is_point_in_polygon(box._balls[0]["pos"], poly))


func test_pour_still_drops_exactly_six_across_seeds() -> void:
	# 含重力调高前会偶发只掉 5 发的种子（trial 32 → seed 547）
	for trial in [0, 3, 32, 47]:
		seed(trial * 17 + 3)
		var box: BagPhysicsBox = BagPhysicsBox.new()
		box.size = Vector2(360, 400)
		add_child_autofree(box)
		var ids: Array = []
		for i in 12:
			ids.append(40 + (i % 6))
		box.sync_ammo_ids(ids)
		for _i in 90:
			box._physics_process(1.0 / 60.0)
		box.pour_cap = 6
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
			if not closed and box.fallen_count() >= 6:
				box.mouth_open = false
				closed = true
		if box.mouth_open:
			box.mouth_open = false
		for _k in 60:
			box._physics_process(1.0 / 60.0)
		assert_eq(box.fallen_count(), 6, "trial %s still pours six" % trial)
		assert_eq(box.sack_remaining_count(), 6)
		var r: Rect2 = box.hand_catch_rect.grow(8.0)
		for b in box._balls:
			if bool(b.get("exited", false)):
				assert_true(r.has_point(b["pos"]))
		box.queue_free()


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
	return cs
