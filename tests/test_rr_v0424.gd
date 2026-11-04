extends GutTest
## v0.4.24：连射不再随机转轮；打一发 → 转一格 → 下一发，间隔 VOLLEY_SHOT_INTERVAL_SEC。

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


func test_version_0_4_24() -> void:
	assert_true(GameVersion.STRING >= "0.4.24")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.24"' in text)


func test_volley_interval_constants() -> void:
	assert_almost_eq(CombatConstants.VOLLEY_SHOT_INTERVAL_SEC, 0.25, 0.0001)
	assert_gte(CombatState.volley_shot_interval_sec(), CombatConstants.MIN_FIRE_INTERVAL_SEC, "射速帽是下限")
	assert_gt(CombatState.volley_rotate_sec(), 0.1, "转一格要看得清")
	assert_lte(CombatState.volley_rotate_sec(), CombatState.volley_shot_interval_sec(), "转一格放在间隔内")
	assert_lt(CombatConstants.VOLLEY_EMPTY_SKIP_SEC, CombatState.volley_shot_interval_sec(), "空仓快转，不等整格")
	assert_false(CombatConstants.LOAD_FULL_RANDOM_SPIN)


func test_pre_volley_spin_api_exists_again() -> void:
	## v0.4.25 起又加回；本文件保留间隔/装满不转等断言。
	var cs := _rush(42401)
	assert_true(cs.has_method("spin_cylinder_for_volley"))


func test_fire_starts_from_current_chamber() -> void:
	for seed_v in [42402, 42403, 42404, 42405]:
		var cs := _rush(seed_v)
		cs.dev_force_load([WHITE, WHITE, WHITE, WHITE, WHITE, WHITE] as Array[int])
		cs.magazine.set_start(3)
		var shots: Array = cs.fire_tap(false)
		assert_eq(shots.size(), 1, "第一发立刻打出")
		assert_eq(int(shots[0].get("start_before", -1)), 3, "从当前击发仓开打，不先转")
		assert_true(cs.is_volley_pending())
		assert_eq(cs.fire_tap(false).size(), 0, "连射中再按忽略")
		var starts: Array[int] = [int(shots[0].get("start_after", -1))]
		var guard := 8
		while cs.is_volley_pending() and guard > 0:
			guard -= 1
			var more: Array = cs.take_volley_shot()
			if more.is_empty():
				break
			starts.append(int(more[0].get("start_after", -1)))
		assert_eq(cs.magazine.loaded_count(), 0)
		# 每发只转一格：4,5,0,1,2,(3)
		for i in range(starts.size() - 1):
			assert_eq(starts[i], (3 + 1 + i) % CombatConstants.MAGAZINE_SIZE)


func test_full_load_does_not_spin() -> void:
	var expect_start: int = (CombatConstants.LOAD_SESSION_INITIAL_START + CombatConstants.MAGAZINE_SIZE - 1) % CombatConstants.MAGAZINE_SIZE
	for seed_v in [7, 11, 99, 4242]:
		var cs := CombatState.new(seed_v)
		cs.start_rush(seed_v)
		assert_true(cs.do_load())
		assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)
		assert_eq(cs.magazine.start_index, expect_start, "装满后停在会话末仓，不随机转")


func test_empty_chambers_wait_is_plain_interval() -> void:
	## v0.4.25：空仓由 advance_empty_chambers 快跳，等待本身不再加空仓时间。
	var cs := _rush(42406)
	cs.magazine.clear()
	cs.magazine.set_slot(3, WHITE)
	cs.magazine.start_index = 0
	assert_eq(cs.volley_next_empty_skips(), 3)
	assert_almost_eq(cs.volley_wait_before_next_sec(), CombatState.volley_shot_interval_sec(), 0.0001)
	cs.magazine.start_index = 3
	assert_eq(cs.volley_next_empty_skips(), 0)
	assert_almost_eq(cs.volley_wait_before_next_sec(), CombatState.volley_shot_interval_sec(), 0.0001)
