extends GutTest
## v0.4.25：连射前恢复随机转轮；空仓先推进让锤位/红圈对准下一发实弹。

const WHITE := CombatConstants.WHITE_AMMO_ID
const W := FireResolver.ID_WRATH


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _rush(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func test_version_0_4_25() -> void:
	assert_true(GameVersion.STRING >= "0.4.25")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.25"' in text)
	assert_true('"version": "0.4.24"' in text)


func test_pre_volley_spin_restored() -> void:
	var cs := _rush(42501)
	cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
	cs.magazine.set_start(0)
	var steps: int = cs.spin_cylinder_for_volley()
	assert_gte(steps, 1, "两发以上必转")
	assert_eq(cs.magazine.start_index, steps % CombatConstants.MAGAZINE_SIZE)
	assert_eq(cs.magazine.loaded_count(), 6, "转轮不耗弹")
	var shots: Array = cs.fire_tap(false)
	assert_eq(shots.size(), 1)
	assert_eq(int(shots[0].get("start_before", -1)), steps % CombatConstants.MAGAZINE_SIZE, "转完后从新锤位开打")


func test_spin_noop_when_one_loaded() -> void:
	var cs := _rush(42502)
	cs.magazine.clear()
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.start_index = 2
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	assert_eq(cs.spin_cylinder_for_volley(), 0)


func test_advance_empty_chambers_aligns_hammer() -> void:
	var cs := _rush(42503)
	cs.magazine.clear()
	cs.magazine.set_slot(3, WHITE)
	cs.magazine.set_slot(5, WHITE)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var skipped: int = cs.advance_empty_chambers()
	assert_eq(skipped, 3)
	assert_eq(cs.magazine.start_index, 3)
	assert_eq(cs.magazine.chamber_at_fire_port(), 3)
	assert_eq(cs.magazine.slots[3], WHITE)
	assert_eq(cs.advance_empty_chambers(), 0, "已对准实弹不再跳")


func test_paced_interval_unchanged() -> void:
	assert_almost_eq(CombatConstants.VOLLEY_SHOT_INTERVAL_SEC, 0.25, 0.0001)
	assert_almost_eq(CombatState.volley_wait_before_next_sec(), CombatState.volley_shot_interval_sec(), 0.0001)
	assert_false(CombatConstants.LOAD_FULL_RANDOM_SPIN)


func test_fire_without_spin_still_from_current_when_caller_skips() -> void:
	## fire_tap 本身不转；转轮由 UI/spin_cylinder_for_volley 负责。
	var cs := _rush(42504)
	cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
	cs.magazine.set_start(4)
	var shots: Array = cs.fire_tap(false)
	assert_eq(int(shots[0].get("start_before", -1)), 4)
