extends GutTest
## t640: all layers apply, each effect loses one layer per own-positive shot.
const HUD := preload("res://scripts/combat/muzzle_status_hud.gd")
const WHITE := CombatConstants.BAIBAN_AMMO_ID
const EMPTY := Magazine.EMPTY

func before_each() -> void:
	DataRegistry.reload()

func _flame(id: String, kind: String, layers: int, value: float) -> Dictionary:
	return {"id": id, "effect_kind": kind, "remaining": layers, "total": layers, "effect_per_stack": value, "amount": value, "color": Color.RED}

func test_t640_canonical_all_layers_then_independent_type_decay() -> void:
	var flames: Array = [_flame("add", "damage_pct", 3, 0.5), _flame("double", "damage_mult", 2, 2.0)]
	var expected := [40.5, 13.5, 4.5, 3.0, 3.0]
	for want in expected:
		var actual := FireResolver.apply_flames(3.0, flames)
		assert_almost_eq(actual, want, 0.0001)
		flames = FireResolver.consume_flame_layers(flames, 3.0)
	assert_eq(FireResolver.round_damage(expected[0]), 41)
	assert_eq(FireResolver.round_damage(expected[1]), 14)

func test_transfer_excess_9_three_actual_shots_full_excess_no_conservation() -> void:
	var flames: Array = [FireResolver.make_flame(52, 0, 9, 1.0)]
	for bonus in [9.0, 8.0, 7.0]:
		assert_almost_eq(FireResolver.apply_flames(3.0, flames) - 3.0, bonus, 0.0001)
		flames = FireResolver.consume_flame_layers(flames, 3.0)

func test_transfer_excess_2_four_actual_shots_clamps_to_zero() -> void:
	var flames: Array = [FireResolver.make_flame(52, 0, 2, 1.0)]
	for bonus in [2.0, 1.0, 0.0, 0.0]:
		assert_almost_eq(FireResolver.apply_flames(3.0, flames) - 3.0, bonus, 0.0001)
		flames = FireResolver.consume_flame_layers(flames, 3.0)

func test_transfer_generation_and_empty_chambers_preserve_decay() -> void:
	# 传递 3 受 ×4 → 预计 12，加强量 9，只一层；空仓不消耗，再后面的白板不再吃到这个火焰。
	var seed: Array = [_flame("boost", "damage_mult", 1, 4.0)]
	var details := FireResolver.compute_volley_details([52, WHITE, EMPTY, WHITE, WHITE], [], [], seed)
	assert_eq(details["damages"], [12.0, 12.0, 0.0, 3.0, 3.0])
	assert_eq(int(details["after"][0][0]["remaining"]), 1)
	assert_eq(float(details["after"][0][0]["amount"]), 9.0)

func test_five_layers_all_apply_then_four_then_three() -> void:
	var flames: Array = [_flame("flat", "damage_flat", 5, 1.0)]
	assert_almost_eq(FireResolver.apply_flames(3.0, flames), 8.0, 0.001)
	flames = FireResolver.consume_flame_layers(flames, 3.0)
	assert_eq(int(flames[0]["remaining"]), 4)
	assert_almost_eq(FireResolver.apply_flames(3.0, flames), 7.0, 0.001)
	flames = FireResolver.consume_flame_layers(flames, 3.0)
	assert_eq(int(flames[0]["remaining"]), 3)

func test_zero_intrinsic_no_bootstrap_no_consumption() -> void:
	var flames: Array = [_flame("flat", "damage_flat", 5, 7.0)]
	assert_almost_eq(FireResolver.apply_flames(0.0, flames), 0.0, 0.001)
	assert_eq(FireResolver.consume_flame_layers(flames, 0.0), flames)
	var details := FireResolver.compute_volley_details([41, WHITE], [], [], flames)
	assert_almost_eq(float(details["damages"][0]), 0.0, 0.001)
	assert_eq(int(details["after"][0][0]["remaining"]), 5)

func test_start_type_positive_formula_is_not_exempt() -> void:
	assert_true(FireResolver.is_start_type(47))
	var details := FireResolver.compute_volley_details([47, WHITE], [], [], [_flame("flat", "damage_flat", 5, 1.0)])
	assert_almost_eq(float(details["damages"][0]), 8.0, 0.001)
	assert_eq(int(details["after"][0][0]["remaining"]), 4)

func test_alternate_zero_stored_damage_formula_qualifies() -> void:
	assert_eq(int(DataRegistry.get_ammo(57)["base_damage"]), 0)
	var details := FireResolver.compute_volley_details([WHITE, 57], [], [], [_flame("flat", "damage_flat", 5, 1.0)])
	assert_almost_eq(float(details["intrinsic"][1]), 4.0, 0.001) # first shot 3+5=8
	assert_almost_eq(float(details["damages"][1]), 8.0, 0.001) # formula4 + remaining4
	assert_eq(int(details["after"][1][0]["remaining"]), 3)

func test_mixed_flat_multiply_order_matters() -> void:
	var flat := _flame("flat", "damage_flat", 1, 2.0)
	var mult := _flame("mult", "damage_mult", 1, 2.0)
	assert_almost_eq(FireResolver.apply_flames(3.0, [flat, mult]), 10.0, 0.001)
	assert_almost_eq(FireResolver.apply_flames(3.0, [mult, flat]), 8.0, 0.001)

func test_same_type_grants_decay_one_oldest_layer_not_each_group() -> void:
	var flames: Array = [_flame("flat", "damage_flat", 2, 1.0), _flame("double", "damage_mult", 2, 2.0), _flame("flat", "damage_flat", 3, 1.0)]
	var after := FireResolver.consume_flame_layers(flames, 3.0)
	assert_eq(int(after[0]["remaining"]), 1)
	assert_eq(int(after[1]["remaining"]), 1)
	assert_eq(int(after[2]["remaining"]), 3)

func test_layer_icons_merge_same_type_with_count_and_keep_order() -> void:
	var a := _flame("a", "damage_flat", 5, 1.0)
	var b := _flame("b", "damage_mult", 2, 2.0)
	b["color"] = Color.BLUE
	var icons := HUD.layer_icon_entries([a, b])
	assert_eq(icons.size(), 2)
	assert_eq(int(icons[0]["stack"]), 5)
	assert_eq(int(icons[1]["stack"]), 2)
	assert_eq(icons[0]["color"], Color.RED)
	assert_eq(icons[1]["color"], Color.BLUE)
	assert_eq(HUD.icon_count_mark(5), "×5")
	assert_eq(HUD.icon_count_mark(1), "")

func test_wait_does_not_decay_flames() -> void:
	var cs := CombatState.new(48000)
	cs._volley_muzzle_buffs = [_flame("a", "damage_flat", 5, 1.0)]
	cs.tick_muzzle_durations(600.0)
	assert_eq(int(cs.volley_muzzle_buffs()[0]["remaining"]), 5)

func test_new_formulas_and_actual_previous_damage() -> void:
	var half := FireResolver.compute_volley_details([WHITE, 57], [], [5, null])
	assert_almost_eq(float(half["damages"][1]), 3.0, 0.001)
	var twice := FireResolver.compute_volley_details([WHITE, 58], [], [5, null])
	assert_almost_eq(float(twice["damages"][1]), 10.0, 0.001)
	var miss := FireResolver.compute_volley_details([WHITE, 58], [], [0, null])
	assert_almost_eq(float(miss["damages"][1]), 0.0, 0.001)

func test_hopper_uses_two_spatial_clip_windows_not_body_visibility_toggle() -> void:
	var cu := GumballCloseup.new()
	add_child_autofree(cu)
	assert_true(cu.casing_top_y() < cu.outlet_reveal_y())
	assert_true(cu.outlet_reveal_y() < cu.outlet_point().y)
	assert_true(cu._hopper_ball_clip.clip_contents)
	assert_true(cu._outlet_ball_clip.clip_contents)
	assert_true(cu._hopper_ball_clip.get_parent() == cu._ball_view)
	assert_true(cu.machine.physics_drop)
	assert_true(cu.machine.hide_interior_balls)

func test_immediate_copy_effect_does_not_create_phantom_flame_layers() -> void:
	var details := FireResolver.compute_volley_details([45, WHITE])
	assert_true(details["after"][0].is_empty())

func test_encouragement_doubles_own_base_before_flames() -> void:
	var plain := FireResolver.compute_volley_damages([56])
	assert_almost_eq(plain[0], 3.0, 0.001)
	var boosted := FireResolver.compute_volley_details([56], [], [], [_flame("boost", "damage_mult", 1, 1.5)])
	assert_almost_eq(float(boosted["intrinsic"][0]), 6.0, 0.001)
	assert_almost_eq(float(boosted["damages"][0]), 9.0, 0.001)

func test_empty_beat_generates_snapshot_empty_count_layers() -> void:
	var details := FireResolver.compute_volley_details([59, WHITE, EMPTY, EMPTY])
	assert_eq(int(details["after"][0][0]["remaining"]), 2)
	assert_almost_eq(float(details["damages"][1]), 12.0, 0.001)
	assert_eq(int(details["after"][1][0]["remaining"]), 1)

func test_four_clear_new_bullets_are_reward_eligible() -> void:
	for id in [56, 57, 58, 59]:
		assert_true(DataRegistry.is_ammo_reward_eligible(id))
		assert_false(DataRegistry.ammo_game_description(id).is_empty())
