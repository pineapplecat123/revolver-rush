extends GutTest
const WHITE := 49
func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false

func _cs(pool_count: int = 8) -> CombatState:
	var cs := CombatState.new(489)
	cs.start_rush(489)
	cs.enemies.clear()
	cs.dev_spawn_enemy(900, 8)
	cs.spawn_paused = true
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.hand_uid.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs._combat_bag_baseline.clear()
	for i in pool_count: cs._combat_bag_baseline.append(WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs

func test_partial_pour_consumes_remainder_then_refills_and_continues() -> void:
	var cs := _cs()
	for i in 2: cs._bag_append(WHITE, false)
	for i in 6: cs._discard_append(WHITE, false)
	var resets := cs.bag_reset_count
	assert_eq(cs.dump_to_hand(), 6)
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.bag.size(), 2)
	assert_eq(cs.bag_reset_count, resets + 1)
	assert_true(cs.discard.is_empty())
	assert_eq(cs.dump_to_hand(), 0)
	assert_eq(cs.bag.size(), 2)

func test_partial_hand_and_cylinder_are_not_duplicated_into_refill() -> void:
	var cs := _cs()
	for i in 2:
		cs._hand_append(WHITE)
		cs._bag_append(WHITE)
		cs.magazine.set_slot(i, WHITE)
	var uids := cs.hand_uid.duplicate()
	assert_eq(cs.dump_to_hand(), 4)
	assert_eq(cs.hand.size(), 6)
	assert_eq(cs.hand_uid.slice(0,2), uids)
	assert_eq(cs.magazine.loaded_count(), 2)
	assert_true(cs.bag.is_empty())
	assert_eq(cs._bag_reset_pool(99).size(), 0)
	assert_false(cs.can_dump_to_hand())

func test_empty_bag_and_zero_eligible_pool_stop_without_fabrication() -> void:
	var cs := _cs(4)
	for i in 2: cs._hand_append(WHITE)
	for i in 2: cs.magazine.set_slot(i, WHITE)
	var resets := cs.bag_reset_count
	assert_false(cs.can_dump_to_hand())
	assert_eq(cs.dump_to_hand(), 0)
	assert_eq(cs.bag_reset_count, resets)
	cs.magazine.clear()
	assert_eq(cs.dump_to_hand(), 2)
	assert_eq(cs.hand.size(), 4)
	assert_false(cs.can_dump_to_hand())

func test_pending_shots_block_pour_and_refill_and_items_are_not_double_claimed() -> void:
	var cs := _cs()
	cs._bag_append(WHITE)
	cs._pending_impacts[123] = {"ammo_id":WHITE}
	assert_false(cs.can_dump_to_hand())
	assert_eq(cs.dump_to_hand(), 0)
	cs.bag.clear()
	assert_false(cs.refill_bag_for_pour())
	cs._pending_impacts.clear()
	cs._bag_append(WHITE)
	assert_eq(cs.dump_to_hand_items([{"id":WHITE,"temp":false,"envy":false}]), 1)
	assert_eq(cs.dump_to_hand_items([{"id":WHITE,"temp":false,"envy":false}]), 0)
	assert_eq(cs.hand.size(), 1)

func test_room_only_pour_preserves_unselected_bag_items() -> void:
	var cs := _cs(12)
	for i in 5: cs._hand_append(WHITE)
	for i in 7: cs._bag_append(WHITE)
	assert_eq(cs.dump_to_hand(), 1)
	assert_eq(cs.bag.size(), 6)
	assert_eq(cs.hand.size(), 6)

func test_campaign_doubled_count_all_arrive_and_node_waits_for_reserves() -> void:
	var cs := CombatState.new(4891)
	cs.start_campaign(4891)
	cs.campaign_instant_transitions = true
	cs.campaign_pick_opening(0)
	cs.campaign_skip_walk()
	assert_eq(cs.alive_enemies().size(), 3)
	assert_eq(cs.campaign_wave_reserve.size(), 1)
	cs.enemies.clear()
	cs.campaign_try_advance()
	assert_eq(cs.alive_enemies().size(), 1)
	assert_eq(cs.campaign_node_clears, 0)
	assert_false(cs.alley_active())
	cs.enemies.clear()
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 1)
	assert_eq(cs.alive_enemies().size() + cs.campaign_wave_reserve.size(), 4)
	for floor_index in range(1,10):
		for seg in range(1,4):
			for wave in range(1,3):
				var count := 0
				for rec in CampaignRules.wave_spawns(floor_index,seg,wave):count += int(rec["count"])
				assert_true(count in [4,6,8,10])

func test_encourage_counts_consumed_not_applied_layers_with_additive_base() -> void:
	var a := {"id":"flat","effect_kind":"damage_flat","remaining":5,"total":5,"amount":1.0}
	var same := a.duplicate(true)
	same["remaining"] = 3
	var speed := {"id":"speed","effect_kind":"fire_rate_mult","remaining":2,"total":2,"effect_per_stack":1.5}
	var p := FireResolver.compute_volley_details([56],[],[],[a,same,speed])
	assert_eq(int(p["consumed"][0]),2)
	assert_eq(float(p["intrinsic"][0]),9.0)
	assert_eq(float(p["damages"][0]),17.0)
	var plain := FireResolver.compute_volley_details([56])
	assert_eq(float(plain["damages"][0]),3.0)
	var copy := FireResolver.compute_volley_details([56,53],[],[],[a,speed])
	assert_eq(float(copy["intrinsic"][1]),9.0)

func test_encourage_runtime_damage_rounding_and_consumption() -> void:
	var cs := _cs()
	cs.auto_enemy_advance = false
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, 56)
	var enemy = cs.enemies[0]
	enemy.hp = 100
	enemy.max_hp = 100
	cs._volley_muzzle_buffs = [
		{"id":"a","effect_kind":"damage_flat","remaining":1,"total":1,"amount":0.25},
		{"id":"b","effect_kind":"damage_flat","remaining":1,"total":1,"amount":0.25},
	]
	var shots: Array = cs.fire_tap(false)
	assert_eq(shots.size(), 1)
	assert_eq(enemy.hp, 90, "3×(1+2)+0.25+0.25 = 9.5，最后四舍五入为10")
	assert_eq(cs.volley_muzzle_buffs().size(), 0)

func test_second_pour_preserves_prior_cards_without_covering_them() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	ui._fit_combat_viewport(Vector2(720,1280))
	ui.size = Vector2(720,1280)
	await wait_process_frames(2)
	ui.set_process(false)
	ui._bag_physics.set_physics_process(false)
	ui.state.start_rush(4892)
	ui.state.dev_clear_bag()
	for i in 8: ui.state.sandbox_add_ammo(WHITE, 1, 0.0)
	ui.hand_slots.size = Vector2(400,180)
	var origin: Vector2 = ui.hand_slots.global_position
	var first: Array = []
	for i in 2:first.append({"id":WHITE,"temp":false,"envy":false,"h":48.0,"world_pos":origin+Vector2(38+78*i,55)})
	assert_eq(ui.state.dump_to_hand_items(first),2)
	ui._apply_fallen_hand_layout(first)
	ui._refresh()
	ui._layout_hand_scatter()
	var prior: Array = ui._hand_scatter_positions.duplicate()
	var second: Array = []
	for i in 4:second.append(first[i%2].duplicate())
	assert_eq(ui.state.dump_to_hand_items(second),4)
	ui._apply_fallen_hand_layout(second)
	ui._refresh()
	ui._layout_hand_scatter()
	assert_eq(ui._hand_slot_panels.size(),6)
	for i in 2:assert_eq(ui._hand_scatter_positions[i],prior[i])
	for i in 6:
		for j in range(i+1,6):
			assert_false(ui._hand_slot_panels[i].get_rect().grow(-2).intersects(ui._hand_slot_panels[j].get_rect().grow(-2)),"all six cards stay visible: %s %s" % [ui._hand_slot_panels[i].get_rect(),ui._hand_slot_panels[j].get_rect()])
