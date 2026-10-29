extends GutTest
## v0.3.7：枪口每层独立计时；傲慢也计时（12s）；UI 显示最短层剩余。

const W := FireResolver.ID_WRATH
const P := FireResolver.ID_PRIDE
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3701, sin_id: int = W) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, sin_id)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	cs.enemies[0].hp = 9999
	cs.enemies[0].max_hp = 9999
	return cs


func test_duration_table() -> void:
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_WRATH_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_GREED_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 4.0, 0.001)
	assert_almost_eq(CombatConstants.MUZZLE_DURATION_PRIDE_SEC, 12.0, 0.001)


func test_each_wrath_layer_expires_independently() -> void:
	var cs := _rush()
	cs._mount_sin_muzzle_from({"wrath": true})
	cs.tick_muzzle_durations(1.5)
	cs._mount_sin_muzzle_from({"wrath": true})
	assert_eq(cs._muzzle_wrath, 2)
	assert_almost_eq(cs._muzzle_wrath_t, 4.0 - 1.5, 0.01, "最短=旧层")
	assert_almost_eq(float(cs._muzzle_wrath_layers[1]), 4.0, 0.01)
	# 旧层再 2.6s 到期 → 剩 1 层
	cs.tick_muzzle_durations(2.6)
	assert_eq(cs._muzzle_wrath, 1)
	assert_almost_eq(cs._muzzle_wrath_t, 4.0 - 2.6, 0.05)
	# 新层再到期
	cs.tick_muzzle_durations(2.0)
	assert_eq(cs._muzzle_wrath, 0)


func test_pride_is_timed_not_permanent() -> void:
	var cs := _rush(3702, P)
	cs._mount_sin_muzzle_from({"pride": true})
	assert_eq(cs._muzzle_pride, 1)
	assert_almost_eq(cs._muzzle_pride_t, 12.0, 0.01)
	cs.tick_muzzle_durations(11.9)
	assert_eq(cs._muzzle_pride, 1)
	cs.tick_muzzle_durations(0.2)
	assert_eq(cs._muzzle_pride, 0, "傲慢到期清零")


func test_pride_layers_independent_and_longer_than_wrath() -> void:
	var cs := _rush(3703, P)
	cs._mount_sin_muzzle_from({"pride": true})
	cs.tick_muzzle_durations(3.0)
	cs._mount_sin_muzzle_from({"pride": true})
	assert_eq(cs._muzzle_pride, 2)
	assert_almost_eq(cs._muzzle_pride_t, 9.0, 0.01)
	# 愤怒 4s 整段过去，傲慢仍在
	cs._mount_sin_muzzle_from({"wrath": true})
	cs.tick_muzzle_durations(4.1)
	assert_eq(cs._muzzle_wrath, 0)
	assert_eq(cs._muzzle_pride, 2)
	cs.tick_muzzle_durations(5.0)  # 旧傲慢层 9-4.1-5 < 0
	assert_eq(cs._muzzle_pride, 1)
	assert_gt(cs._muzzle_pride_t, 0.0)


func test_stack_count_drives_damage_mult() -> void:
	var cs := _rush(3704)
	cs._mount_sin_muzzle_from({"wrath": true})
	cs._mount_sin_muzzle_from({"wrath": true})
	assert_eq(cs._muzzle_wrath, 2)
	assert_almost_eq(cs.muzzle_outgoing_multiplier(), 3.0, 0.001)  # ×(1+2)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_WRATH_SEC + 0.01)
	# 两层同龄几乎同时到期
	assert_eq(cs._muzzle_wrath, 0)
	assert_almost_eq(cs.muzzle_outgoing_multiplier(), 1.0, 0.001)


func test_ui_shows_soonest_and_stack() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var cs: CombatState = ui.state
	cs._muzzle_wrath_layers = [1.2, 3.5]
	cs._muzzle_pride_layers = [8.0]
	ui._refresh_muzzle_hud()
	assert_eq(ui._muzzle_chip_nodes.size(), 2)
	assert_eq((ui._muzzle_chip_nodes[0]["label"] as Label).text, "愤怒×2 1.2s")
	assert_eq((ui._muzzle_chip_nodes[1]["label"] as Label).text, "傲慢 8.0s")
	# 旧层到期 → 层数掉、最短变
	cs.tick_muzzle_durations(1.3)
	ui._update_muzzle_countdowns()
	# 集合变了会重建
	assert_eq(cs._muzzle_wrath, 1)
	assert_eq((ui._muzzle_chip_nodes[0]["label"] as Label).text, "愤怒 %.1fs" % cs._muzzle_wrath_t)


func test_element_max_one_refreshes_single_layer() -> void:
	var cs := _rush(3705)
	cs._mount_muzzle_from({"pierce": true})
	cs.tick_muzzle_durations(2.0)
	assert_almost_eq(cs._muzzle_pierce_t, 2.0, 0.01)
	cs._mount_muzzle_from({"pierce": true})
	assert_eq(cs._muzzle_pierce_layers.size(), 1)
	assert_almost_eq(cs._muzzle_pierce_t, 4.0, 0.01)


func test_entries_no_infinity() -> void:
	var cs := _rush(3706, P)
	cs._muzzle_pride = 1
	var e: Dictionary = cs.muzzle_status_entries()[0]
	assert_gt(float(e["total"]), 0.0)
	assert_false(CombatState.format_muzzle_countdown(e).contains("∞"))


func test_game_version_0_3_7() -> void:
	assert_eq(GameVersion.STRING, "0.3.7")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_eq(str(d["entries"][0]["version"]), "0.3.7")
