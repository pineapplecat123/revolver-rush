extends GutTest
## v0.4.16 倾泻节奏：~0.06s/发 UI 步进；异步延后收束；可中断。

const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41601) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func test_version_is_0_4_16() -> void:
	assert_eq(GameVersion.STRING, "0.4.16")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.16"' in text or '"version":"0.4.16"' in text)


func test_dump_shot_interval_is_006() -> void:
	assert_eq(CombatConstants.DUMP_SHOT_INTERVAL_SEC, 0.06)


func test_ui_uses_async_dump_and_interval() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true("fire_tap(false)" in src, "UI must pace dump via fire_tap(false)")
	assert_true("_run_dump_autofire" in src)
	assert_true("DUMP_SHOT_INTERVAL_SEC" in src)
	assert_true("take_dump_shot()" in src)
	assert_true("interrupt_dump" in src)


func test_async_dump_steps_one_chamber_at_a_time() -> void:
	var cs := _rush(41610)
	cs.dev_force_load([
		FireResolver.ID_DUMP, WHITE, WHITE, WHITE,
		Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var hp0: int = cs.enemies[0].hp
	var shots: Array = cs.fire_tap(false)
	assert_true(cs.is_dump_pending())
	assert_eq(shots.size(), 1, "primary dump only before paced steps")
	assert_eq(cs.magazine.loaded_count(), 3)
	assert_eq(hp0 - cs.enemies[0].hp, 2)

	var more1: Array = cs.take_dump_shot()
	assert_eq(more1.size(), 1)
	assert_true(cs.is_dump_pending())
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_eq(hp0 - cs.enemies[0].hp, 2 + 3)

	var more2: Array = cs.take_dump_shot()
	assert_eq(more2.size(), 1)
	assert_eq(cs.magazine.loaded_count(), 1)

	var more3: Array = cs.take_dump_shot()
	assert_eq(more3.size(), 1)
	assert_eq(cs.magazine.loaded_count(), 0)
	assert_false(cs.is_dump_pending(), "dump ends when mag empty")
	assert_eq(hp0 - cs.enemies[0].hp, 2 + 3 + 3 + 3)


func test_async_dump_interrupt_keeps_remaining() -> void:
	var cs := _rush(41611)
	cs.dev_force_load([
		FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE, WHITE,
	] as Array[int])
	cs.fire_tap(false)
	assert_true(cs.is_dump_pending())
	cs.take_dump_shot()
	assert_eq(cs.magazine.loaded_count(), 4)
	assert_true(cs.interrupt_dump())
	assert_false(cs.is_dump_pending())
	assert_eq(cs.magazine.loaded_count(), 4)
	var empty: Array = cs.take_dump_shot()
	assert_true(empty.is_empty())
