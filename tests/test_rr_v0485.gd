extends GutTest
## t658 + t661-t666: approved flame mechanics. t668: 总伤二分 uses actual prior totals; 传递/爆穿 keep planned post-flame rounding.
const WHITE := 49
const EMPTY := Magazine.EMPTY

func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false

func _flat(id: String, n: int, amount: float) -> Dictionary:
	return {"id": id, "effect_kind": "damage_flat", "remaining": n, "total": n, "amount": amount}

func _cs(ids: Array[int], paced: bool = false) -> CombatState:
	var cs := CombatState.new(485)
	cs.start_rush(485, FireResolver.ID_WRATH)
	cs.pace_after_fire = paced
	cs.defer_impacts = paced
	cs.auto_enemy_advance = true
	cs.enemies.clear()
	for cell in [3, 5, 7]:
		cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, cell)
		var e: EnemyInstance = cs.enemies[-1]
		e.hp = 10000
		e.max_hp = 10000
		e.atk = 0
	cs.dev_clear_bag()
	cs.magazine.clear()
	cs.magazine.start_index = 0
	for i in ids.size():
		cs.magazine.slots[i] = ids[i]
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs

func _settle(cs: CombatState, shots: Array) -> void:
	for shot in shots:
		if int(shot.get("impact_id", -1)) >= 0:
			cs.finalize_pending_impact(int(shot["impact_id"]))

func test_eight_rows_preserve_original_values_and_blank_explosion() -> void:
	assert_eq(DataRegistry.all_ammo().size(), 28)
	for id in range(60, 68):
		assert_true(DataRegistry.is_ammo_reward_eligible(id))
		assert_eq(str(DataRegistry.get_ammo(id)["rarity"]), "")
	assert_eq(float(DataRegistry.get_ammo(60)["base_damage"]), 1.0)
	assert_eq(float(DataRegistry.get_ammo(63)["base_damage"]), 1.0)
	assert_null(DataRegistry.get_ammo(64)["base_damage"])

func test_total_transfer_requires_self_actual_not_prediction() -> void:
	var p := FireResolver.compute_volley_details([WHITE, 60, WHITE], [], [20, null])
	assert_true(p["after"][1].is_empty())
	var d := FireResolver.compute_volley_details([WHITE, 60, WHITE], [], [20, 10])
	var f: Dictionary = d["after"][1][0]
	assert_eq(int(f["remaining"]), 3)
	assert_almost_eq(float(f["amount"]), 10.0, 0.0001)
	assert_almost_eq(float(d["damages"][2]), 33.0, 0.0001)
	var next := FireResolver.compute_volley_details([WHITE, WHITE, WHITE], [], [], d["after"][1])
	assert_eq(next["damages"], [33.0, 23.0, 13.0])

func test_total_transfer_live_snapshot_denominator_no_empty_or_previous_volley() -> void:
	var d := FireResolver.compute_volley_details([WHITE, EMPTY, 60, EMPTY], [], [5, null, 1])
	assert_eq(int(d["after"][2][0]["remaining"]), 2)
	assert_almost_eq(float(d["after"][2][0]["amount"]), 3.0, 0.0001)
	var current := FireResolver.compute_volley_details([60], [], [1], d["after"][2])
	assert_almost_eq(float(current["after"][0][-1]["amount"]), 1.0, 0.0001)

func test_double_layers_preserves_groups_values_no_application_no_consumption() -> void:
	var a := _flat("a", 2, 3.5)
	var b := _flat("b", 3, 1.0)
	var d := FireResolver.compute_volley_details([61, WHITE], [], [], [a,b])
	assert_eq(float(d["damages"][0]), 0.0)
	assert_eq(int(d["consumed"][0]), 0)
	assert_eq(int(d["after"][0][0]["remaining"]), 4)
	assert_eq(int(d["after"][0][1]["remaining"]), 6)
	assert_eq(float(d["after"][0][0]["amount"]), 3.5)
	# A copied doubling skill must also bypass flames despite mimic's own base 3.
	var copied := FireResolver.compute_volley_details([61, 53], [], [], [a])
	assert_eq(float(copied["damages"][1]), 3.0)
	assert_eq(int(copied["consumed"][1]), 0)
	assert_eq(int(copied["after"][1][0]["remaining"]), 8)

func test_end_share_only_remaining_ends_equal_share_not_layer_sum() -> void:
	var d := FireResolver.compute_volley_details([51, 62, WHITE, 51, 56], [], [3, 9])
	assert_eq(int(d["after"][1][0]["remaining"]), 2)
	assert_eq(float(d["after"][1][0]["amount"]), 4.5)
	assert_eq(float(d["damages"][2]), 3.0) # middle unaffected, does not consume
	assert_eq(float(d["damages"][3]), 7.5)
	assert_eq(float(d["damages"][4]), 10.5) # Encourage own rebase 6 + same4.5
	var none := FireResolver.compute_volley_details([51, 62, WHITE], [], [3,9])
	assert_true(none["after"][1].is_empty())

func test_drain_counts_consumed_not_applied_layers_and_no_self_recursion() -> void:
	# Five layers applied but only two actually consumed -> own base1 x4.
	var d := FireResolver.compute_volley_details([WHITE, 63], [], [], [_flat("a", 3, 1), _flat("b", 2, 1)])
	assert_eq(int(d["consumed"][0]), 2)
	assert_eq(float(d["intrinsic"][1]), 4.0)
	assert_eq(float(d["damages"][1]), 7.0)
	assert_eq(float(d["intrinsic"][0]), 3.0)
	var repeated := FireResolver.compute_volley_details([WHITE, 63], [], [], [_flat("a", 2,1),_flat("a",3,1)])
	assert_eq(int(repeated["consumed"][0]), 1)
	assert_eq(float(repeated["intrinsic"][1]), 2.0)

func test_detonation_consumes_every_layer_and_feeds_later_drain() -> void:
	var d := FireResolver.compute_volley_details([64,63], [], [], [_flat("a", 3,100),_flat("b",2,100)])
	assert_eq(float(d["damages"][0]), 20.0) # no +500, no extra ordinary shot
	assert_eq(int(d["consumed"][0]), 5)
	assert_true(d["after"][0].is_empty())
	assert_eq(float(d["intrinsic"][1]), 32.0)

func test_detonation_every_enemy_sync_and_paced_no_extra_normal_shot() -> void:
	for paced in [false,true]:
		var cs := _cs([64], paced)
		cs._volley_muzzle_buffs = [_flat("a",3,100)]
		var shots := cs.fire_tap(not paced)
		_settle(cs, shots)
		for e in cs.enemies:
			assert_eq(e.hp, 9988)
		assert_true(cs.volley_muzzle_buffs().is_empty())

func test_split_uses_previous_actual_total_boost_once_ceil_per_target() -> void:
	var d := FireResolver.compute_volley_details([WHITE,65], [], [5], [_flat("a",2,1.5)])
	assert_eq(float(d["intrinsic"][1]), 5.0)
	assert_eq(float(d["damages"][1]), 6.5)
	assert_eq(int(d["consumed"][1]), 1)
	var prediction := FireResolver.compute_volley_details([WHITE,65])
	assert_eq(float(prediction["intrinsic"][1]), 0.0)
	# Actual previous shot pierces: 3+2+1 = 6; split6/3 ->2 each.
	for paced in [false,true]:
		var cs := _cs([51,65], paced)
		var first := cs.fire_tap(false)
		_settle(cs,first)
		# Instead use the actual total recorded by the first real hit (3), then split(3)/3=1.
		var hp: Array = []
		for e in cs.enemies: hp.append(e.hp)
		var second := cs.take_volley_shot()
		_settle(cs,second)
		for i in cs.enemies.size(): assert_eq(cs.enemies[i].hp, int(hp[i])-1)

func test_split_fraction_kept_until_division_and_target_snapshot() -> void:
	var cs := _cs([WHITE,65], true)
	_settle(cs,cs.fire_tap(false))
	cs._volley_seed_flames = [_flat("a",2,0.75)]
	cs._recompute_volley_plan_flats()
	# prior actual3, split total3.75/3 -> ceil1.25=2, not rounded-total rules
	var shots := cs.take_volley_shot()
	assert_eq(shots[0]["hit_cells"].size(),3)
	var id := int(shots[0]["impact_id"])
	var plan: Dictionary = cs._pending_impacts[id]
	assert_eq(int(plan["hits"][0]["dmg"]),2)
	cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID,9)
	var late: EnemyInstance = cs.enemies[-1]
	var hp := late.hp
	_settle(cs,shots)
	assert_eq(late.hp,hp) # not in the shot's frozen target list

func test_empty_neighbors_are_circular_and_use_firestart_snapshot() -> void:
	assert_eq(FireResolver.compute_volley_damages([66,WHITE,EMPTY])[0],6.0)
	assert_eq(FireResolver.compute_volley_damages([EMPTY,66,EMPTY])[1],9.0)
	var d := FireResolver.compute_volley_details([WHITE,66,WHITE],[],[3])
	assert_eq(float(d["intrinsic"][1]),3.0) # fired first slot is not a new empty

func test_black_sight_from_firestart_only_virtual_empty_counts() -> void:
	var d := FireResolver.compute_volley_details([59,66,WHITE,67])
	assert_eq(int(d["after"][0][0]["remaining"]),4)
	assert_eq(float(d["intrinsic"][1]),9.0) # both neighboring slots virtually empty
	assert_eq(float(d["damages"][1]),144.0)
	assert_eq(float(d["damages"][2]),24.0) # white still fires and consumes
	assert_eq(FireResolver.compute_volley_details([42,67])["intrinsic"][0],2.75)
	assert_eq(FireResolver.compute_volley_details([46,67])["intrinsic"][0],1.5)

func test_tail_generated_at_last_turn_and_only_tail_expires() -> void:
	var d := FireResolver.compute_volley_details([55,WHITE,40])
	assert_true(d["after"][0].is_empty())
	assert_true(d["before"][1].is_empty())
	assert_eq(str(d["before"][2][0]["id"]),"weijiabei")
	var cs := _cs([55,40])
	cs._volley_muzzle_buffs = [_flat("persist",5,2)]
	cs.fire_tap(true)
	for f in cs.volley_muzzle_buffs():
		assert_ne(str(f["id"]),"weijiabei")
	assert_eq(int(cs.volley_muzzle_buffs()[0]["remaining"]),5)

func test_actual_grant_finishes_after_last_deferred_impact_and_carries() -> void:
	var cs := _cs([WHITE,60],true)
	_settle(cs,cs.fire_tap(false))
	var shots := cs.take_volley_shot()
	assert_true(cs._volley_reset_after_impacts)
	assert_eq(cs._volley_seq_snapshot.size(),6)
	_settle(cs,shots)
	assert_false(cs._volley_reset_after_impacts)
	assert_eq(cs.volley_muzzle_buffs().size(),1)
	assert_eq(int(cs.volley_muzzle_buffs()[0]["remaining"]),2)
	assert_eq(float(cs.volley_muzzle_buffs()[0]["amount"]),2.0) # actual3+1=4, N2

func test_rounding_at_end_and_encouragement_counts_one_consumed_type() -> void:
	var mul := {"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":1.5}
	var d := FireResolver.compute_volley_details([EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,42],[],[],[mul])
	assert_eq(float(d["damages"][5]),9.75) # not round6.5 ->7 then x1.5
	assert_eq(FireResolver.round_damage(float(d["damages"][5])),10)
	var boost := mul.duplicate()
	boost["remaining"]=3
	assert_eq(FireResolver.compute_volley_details([56],[],[],[boost])["intrinsic"][0],6.0)

func test_real_piercing_actual_total_feeds_split_not_single_target_damage() -> void:
	for paced in [false,true]:
		var cs := _cs([51,65],paced)
		cs._volley_muzzle_buffs = [_flat("a",2,2.5)]
		_settle(cs,cs.fire_tap(false))
		# boosted8 pierces as8+7+6 -> actual21; one remaining flat2.5 ->23.5; /3 ceil8.
		assert_eq(int(cs._volley_actuals[0]),21)
		var hp: Array = []
		for e in cs.enemies: hp.append(e.hp)
		_settle(cs,cs.take_volley_shot())
		for i in cs.enemies.size(): assert_eq(cs.enemies[i].hp,int(hp[i])-8)

func test_real_total_transfer_miss_and_end_share_use_actual_not_forecast() -> void:
	var cs := _cs([60],true)
	var shots := cs.fire_tap(false)
	# The shot was planned for1, but its frozen target dies before arrival.
	cs.enemies[0].hp=0
	_settle(cs,shots)
	assert_eq(float(cs.volley_muzzle_buffs()[0]["amount"]),0.0)
	var tail := _cs([62,51,51],true)
	_settle(tail,tail.fire_tap(false))
	assert_eq(float(tail.volley_muzzle_buffs()[0]["amount"]),1.5)
	_settle(tail,tail.take_volley_shot())
	assert_eq(tail.last_shot_planned_damage,5) # 3+1.5 ->5
	_settle(tail,tail.take_volley_shot())
	assert_eq(tail.last_shot_planned_damage,5) # equal second share, not diminishing
	assert_true(tail.volley_muzzle_buffs().is_empty())

func test_full_physical_snapshot_empty_counts_and_black_clear_between_volleys() -> void:
	var cs := _cs([66,67])
	cs.fire_tap(false)
	assert_eq(cs.last_shot_planned_damage,9)
	cs.take_volley_shot()
	cs.magazine.clear()
	cs.magazine.start_index=0
	cs.magazine.set_slot(0,66)
	cs.magazine.set_slot(1,WHITE)
	cs.player_fire_gate_remaining=0.0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap(false)
	assert_eq(cs.last_shot_planned_damage,6) # physical last slot empty, right neighbor loaded, no black

func test_tail_no_early_generation_to_double_and_last_zero_never_carries() -> void:
	var d := FireResolver.compute_volley_details([55,61,WHITE])
	assert_eq(float(d["damages"][2]),4.5) # not doubled before existing
	var cs := _cs([55,61],true)
	cs._volley_muzzle_buffs=[_flat("persist",3,1)]
	_settle(cs,cs.fire_tap(false))
	_settle(cs,cs.take_volley_shot())
	assert_eq(cs.volley_muzzle_buffs().size(),1)
	assert_eq(str(cs.volley_muzzle_buffs()[0]["id"]),"persist")
	assert_eq(int(cs.volley_muzzle_buffs()[0]["remaining"]),6)

func test_explosion_never_adds_element_chain_echo_or_normal_boost() -> void:
	var cs := _cs([64],true)
	cs._volley_muzzle_buffs=[_flat("a",2,99)]
	cs._muzzle_thunder=1
	cs._muzzle_echo=true
	for e in cs.enemies: e.wet_stacks=5
	var shots := cs.fire_tap(false)
	assert_eq(shots.size(),1)
	_settle(cs,shots)
	for e in cs.enemies: assert_eq(e.hp,9992)
	assert_true(cs.last_shot_buff_outlines.is_empty())

func test_zhongshen_uses_actual_prior_total_not_planned_and_keeps_half_float() -> void:
	assert_true(FireResolver.effect_replaces_own_base(43))
	var miss := FireResolver.compute_volley_details([WHITE, 43], [], [0])
	assert_eq(float(miss["intrinsic"][1]), 0.0)
	var empty := FireResolver.compute_volley_details([WHITE, EMPTY, 43], [], [6, null])
	assert_eq(float(empty["intrinsic"][2]), 3.0)
	# Actual pierce total 21, half 10.5 stays float; two ×1.5 layers so one remains after the first shot.
	var mul := {"id": "m", "effect_kind": "damage_mult", "remaining": 2, "effect_per_stack": 1.5}
	var half := FireResolver.compute_volley_details([WHITE, 43], [], [21], [mul])
	assert_eq(float(half["intrinsic"][1]), 10.5)
	assert_almost_eq(float(half["damages"][1]), 15.75, 0.0001)
	assert_eq(FireResolver.round_damage(15.75), 16)
	var copied := FireResolver.compute_volley_details([WHITE, 43, 53], [], [8, 4])
	assert_eq(FireResolver.resolve_shot_effect_id([WHITE, 43, 53], 2), 43)
	assert_eq(float(copied["intrinsic"][2]), 6.0)

func test_zhongshen_runtime_waits_and_uses_pierce_actual_total() -> void:
	var wait_cs := _cs([WHITE, 43], true)
	wait_cs._ensure_volley_plan()
	assert_true(wait_cs.volley_waits_for_actual_damage())
	var mimic_only := _cs([WHITE, 53], true)
	mimic_only._ensure_volley_plan()
	assert_false(mimic_only.volley_waits_for_actual_damage())
	var copied := _cs([43, 53], true)
	copied._ensure_volley_plan()
	assert_true(copied.volley_waits_for_actual_damage())
	# 爆穿计划 8，实际 8+7+6=21；剩余一层 +2.5，二分 10.5+2.5=13
	for paced in [false, true]:
		var cs := _cs([51, 43], paced)
		cs._volley_muzzle_buffs = [_flat("a", 2, 2.5)]
		if paced:
			_settle(cs, cs.fire_tap(false))
			assert_eq(int(cs._volley_actuals[0]), 21)
			_settle(cs, cs.take_volley_shot())
		else:
			cs.fire_tap(true)
		assert_eq(cs.last_shot_planned_damage, 13)
		assert_eq(cs.last_shot_dealt, 13)

func test_zhongshen_miss_and_copy_formula_at_runtime() -> void:
	var cs := _cs([WHITE, 43, 53], true)
	_settle(cs, cs.fire_tap(false))
	_settle(cs, cs.take_volley_shot())
	assert_eq(cs.last_shot_dealt, 2) # half of 3 -> 1.5 -> 2
	_settle(cs, cs.take_volley_shot())
	assert_eq(cs.last_shot_planned_damage, 3) # actual 3+2, half 2.5 -> 3
	assert_eq(cs.last_shot_dealt, 3)

func test_transfer_uses_planned_rounded_not_actual_multitarget_and_no_bootstrap() -> void:
	var d := FireResolver.compute_volley_details([52, WHITE], [], [], [{"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":1.5}])
	assert_eq(FireResolver.round_damage(float(d["damages"][0])), 5)
	# 预览无结算时用预计伤害 5−3=2，只一层。
	assert_eq(int(d["after"][0][0]["remaining"]), 1)
	assert_eq(float(d["after"][0][0]["amount"]), 2.0)
	var after := FireResolver.compute_volley_details([52, WHITE], [], [12], [{"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":1.5}])
	# 有实际伤害时用 12−3=9，仍然只一层，不按穿透总伤以外的其它口径。
	assert_eq(int(after["after"][0][0]["remaining"]), 1)
	assert_eq(float(after["after"][0][0]["amount"]), 9.0)
	# 倍伤加强传递是合法的（传递自身伤害为3）；零伤不能靠平面火焰抬起来再挂传递层
	var boosted := FireResolver.compute_volley_details([41, 52])
	assert_eq(float(boosted["damages"][0]), 0.0)
	assert_eq(FireResolver.round_damage(float(boosted["damages"][1])), 5)
	assert_eq(int(boosted["after"][1][-1]["remaining"]), 1)
	assert_eq(float(boosted["after"][1][-1]["amount"]), 2.0)
	var speed := FireResolver.compute_volley_details([52], [], [], [{"id":"s","effect_kind":"speed_pct","remaining":3,"effect_per_stack":1.0}])
	assert_true(speed["after"][0].filter(func(f): return str(f.get("id",""))=="chuandi").is_empty())
	var empties := FireResolver.compute_volley_details([52, EMPTY, WHITE], [], [], [{"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":1.5}])
	assert_eq(int(empties["after"][0][0]["remaining"]), 1)
	assert_eq(float(empties["after"][0][0]["amount"]), 2.0)
	assert_eq(float(empties["damages"][1]), 0.0)
	assert_eq(float(empties["damages"][2]), 5.0)

func test_transfer_runtime_stays_on_planned_shot_not_actual_total() -> void:
	var cs := _cs([52, WHITE], true)
	cs._volley_muzzle_buffs = [{"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":4.0,"total":1}]
	# planned/actual 12 → 一个加强量 9 的火焰，不是 9 层。
	var first := cs.fire_tap(false)
	assert_eq(int(first[0]["planned_damage"]), 12)
	_settle(cs, first)
	assert_eq(int(cs._volley_actuals[0]), 12)
	assert_eq(int(cs.volley_muzzle_buffs()[0]["remaining"]), 1)
	assert_eq(float(cs.volley_muzzle_buffs()[0]["amount"]), 9.0)
	_settle(cs, cs.take_volley_shot())
	assert_eq(cs.last_shot_planned_damage, 12) # 3+9

func test_baochuan_threshold_7_vs_8_and_decay_to_zero() -> void:
	assert_false(FireResolver.shot_self_pierce(51, 7))
	assert_true(FireResolver.shot_self_pierce(51, 8))
	assert_eq(FireResolver.compute_shot_damages([51])[0], 3)
	var one := {"id":"m","effect_kind":"damage_mult","remaining":1,"effect_per_stack":1.5}
	var two := {"id":"m","effect_kind":"damage_mult","remaining":2,"effect_per_stack":1.5}
	var three := {"id":"m","effect_kind":"damage_mult","remaining":3,"effect_per_stack":1.5}
	assert_eq(FireResolver.round_damage(float(FireResolver.compute_volley_details([51], [], [], [one])["damages"][0])), 5)
	assert_eq(FireResolver.round_damage(float(FireResolver.compute_volley_details([51], [], [], [two])["damages"][0])), 7)
	assert_false(FireResolver.shot_self_pierce(51, 7))
	assert_eq(FireResolver.round_damage(float(FireResolver.compute_volley_details([51], [], [], [three])["damages"][0])), 10)
	assert_true(FireResolver.shot_self_pierce(51, 10))
	assert_eq(FireResolver.resolve_shot_effect_id([51, 53], 1), 51)
	var cs_no := _cs([51], false)
	cs_no.fire_tap(true)
	assert_false(cs_no.last_shot_was_pierce)
	assert_eq(cs_no.last_shot_hit_amounts, [3])
	var cs := _cs([51], false)
	cs._volley_muzzle_buffs = [_flat("a", 5, 1)]
	cs.fire_tap(true)
	assert_true(cs.last_shot_was_pierce)
	assert_eq(cs.last_shot_hit_amounts, [8, 7, 6])
	assert_false(cs._muzzle_pierce)
	var delayed := _cs([51], true)
	delayed._volley_muzzle_buffs = [_flat("a", 5, 1)]
	var shots := delayed.fire_tap(false)
	assert_true(bool(shots[0]["pierce"]))
	_settle(delayed, shots)
	assert_eq(delayed.last_shot_hit_amounts, [8, 7, 6])
	assert_false(FireResolver.shot_self_pierce(51, FireResolver.compute_shot_damages([41, EMPTY, 51])[2]))

func test_baochuan_copied_by_mimic_uses_effect_id_threshold() -> void:
	var cs := _cs([40, 40, 40, 51, 53], false)
	cs.fire_tap(true)
	assert_eq(cs.last_shot_ammo_id, 53)
	assert_true(cs.last_shot_was_pierce)
	assert_gt(cs.last_shot_planned_damage, 7)
	assert_eq(cs.last_shot_hit_amounts[1], cs.last_shot_hit_amounts[0] - 1)
