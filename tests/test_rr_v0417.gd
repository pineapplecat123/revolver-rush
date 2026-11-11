extends GutTest
## v0.4.17 沙盒模式：自定义枪口/袋 TTL/木桩/状态；暂停刷怪与地图商店。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_0_4_17() -> void:
	## 版本号会继续递增；此处只断言 0.4.17 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.17"' in text or '"version":"0.4.17"' in text)


func test_main_menu_has_sandbox_button() -> void:
	var MainScene := load("res://scenes/main.tscn")
	var main = add_child_autofree(MainScene.instantiate())
	await get_tree().process_frame
	var btn: Button = main.get_node("%BtnSandbox")
	assert_not_null(btn)
	assert_eq(btn.text, "沙盒")


func test_start_sandbox_pauses_spawn_and_shop() -> void:
	var cs := CombatState.new(41701)
	cs.start_sandbox(41701, FireResolver.ID_WRATH)
	assert_true(cs.sandbox_mode)
	assert_true(cs.spawn_paused)
	assert_true(cs.map_shop_disabled)
	# v0.4.20：沙盒开局只有默认 3 个木桩，没有普通怪
	assert_eq(cs.enemies.size(), CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS.size())
	for e in cs.enemies:
		assert_true(e.is_dummy)
	assert_true(cs.bag.size() > 0)
	# 时间推进不应刷怪 / 出商店
	cs.tick_combat_time(50.0)
	assert_eq(cs.enemies.size(), CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS.size())
	assert_eq(cs.shop_cell, -1)
	assert_false(cs.shop_touch_pending)


func test_sandbox_set_muzzle_custom_duration_and_stacks() -> void:
	var cs := CombatState.new(41702)
	cs.start_sandbox(41702)
	assert_true(cs.sandbox_set_muzzle("wrath", 3, 7.5))
	assert_eq(cs._muzzle_wrath, 3)
	assert_eq(cs._muzzle_wrath_t, 7.5)
	assert_true(cs.sandbox_set_muzzle("echo", 5, 2.0))  # 元素最多 1 层
	assert_eq(cs._muzzle_echo_layers.size(), 1)
	assert_eq(cs._muzzle_echo_t, 2.0)
	cs.sandbox_clear_muzzle("wrath")
	assert_eq(cs._muzzle_wrath, 0)
	cs.sandbox_clear_muzzle()
	assert_false(cs._muzzle_echo)


func test_sandbox_bag_inject_with_temp_ttl() -> void:
	var cs := CombatState.new(41703)
	cs.start_sandbox(41703)
	cs.dev_clear_bag()
	cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 2, 9.0)
	assert_eq(cs.bag.size(), 2)
	assert_eq(Magazine.temp_value(cs.bag_temp[0]), 9.0)
	assert_eq(Magazine.temp_value(cs.bag_temp[1]), 9.0)
	assert_true(cs.sandbox_set_bag_temp(0, 3.5))
	assert_eq(Magazine.temp_value(cs.bag_temp[0]), 3.5)
	cs.tick_temp_sin_lifetimes(4.0)
	# 下标 0 到期消失；下标 1 剩 5s
	assert_eq(cs.bag.size(), 1)
	assert_eq(Magazine.temp_value(cs.bag_temp[0]), 5.0)


func test_sandbox_dummy_is_immobile_and_does_not_attack() -> void:
	var cs := CombatState.new(41704)
	cs.start_sandbox(41704, FireResolver.ID_WRATH, false)  # v0.4.20：不摆默认木桩，空场测手动生成
	var dummy: EnemyInstance = cs.sandbox_spawn_dummy(500, 3)
	assert_not_null(dummy)
	assert_true(dummy.is_dummy)
	assert_eq(dummy.hp, 500)
	assert_eq(dummy.cell, 3)
	assert_eq(dummy.mobility, 0)
	assert_eq(dummy.atk, 0)
	var movers: Dictionary = cs.compute_enemy_movers()
	assert_false(movers.has(dummy.get_instance_id()), "dummy must not move")
	assert_false(cs.can_attack_player(dummy))
	# 即便邻接也不攻
	dummy.cell = 1
	assert_false(cs.can_attack_player(dummy))
	var hp0: int = cs.player_hp
	cs.auto_enemy_advance = true
	cs.tick_enemy_auto_step()
	assert_eq(cs.player_hp, hp0)
	assert_eq(dummy.cell, 1)


func test_sandbox_enemy_status_and_player_timer() -> void:
	var cs := CombatState.new(41705)
	cs.start_sandbox(41705)
	cs.sandbox_spawn_enemy(1, 5)
	assert_true(cs.sandbox_set_enemy_status({"burn": 4, "confuse": 2.5, "slow_stacks": 2, "slow_sec": 3.0}))
	var e: EnemyInstance = cs.front_enemy()
	assert_eq(e.burn_stacks, 4)
	assert_eq(e.confuse_remaining, 2.5)
	assert_eq(e.slow_stacks(), 2)


func test_dummy_enemy_def_registered() -> void:
	var def: Dictionary = DataRegistry.get_enemy(CombatConstants.DUMMY_ENEMY_ID)
	assert_false(def.is_empty())
	assert_eq(str(def.get("name", "")), "木桩")
	assert_true(bool(def.get("dummy", false)) or "木桩" in def.get("tags", []))
