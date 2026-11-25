extends GutTest

func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false

func _campaign() -> CombatState:
	var cs := CombatState.new(488)
	cs.start_campaign(488)
	cs.campaign_instant_transitions = true
	cs.campaign_pick_opening(0)
	cs.campaign_skip_walk()
	return cs

func _clear(cs: CombatState) -> void:
	cs.enemies.clear()
	cs.reward_pending = false
	cs.pending_levelups = 0
	cs.campaign_try_advance()

func test_three_combat_clears_per_node_eighteen_before_third_shop_boss() -> void:
	var cs := _campaign()
	var clears := 0
	for node in 6:
		for wave in 3:
			assert_eq(cs.campaign_phase, CampaignRules.PHASE_COMBAT)
			assert_gt(cs.alive_enemies().size(), 0)
			_clear(cs)
			clears += 1
			if wave < 2:
				assert_false(cs.alley_active())
				assert_eq(cs.shop_house_seq, CombatState.SHOP_HOUSE_NONE)
				assert_eq(cs.campaign_shops_this_floor, node / 2)
		if node % 2 == 0:
			assert_true(cs.alley_active())
			assert_true(cs.campaign_simulate_alley_skip())
		else:
			assert_true(cs.campaign_simulate_shop_cycle())
		assert_eq(cs.campaign_node_clears, 0)
		if node < 5:
			assert_ne(cs.campaign_phase, CampaignRules.PHASE_BOSS)
	assert_eq(clears, 18)
	assert_eq(cs.campaign_shops_this_floor, 3)
	assert_eq(cs.campaign_phase, CampaignRules.PHASE_BOSS)

func test_pending_hit_reward_and_enemy_do_not_count_as_cleared_wave() -> void:
	var cs := _campaign()
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 0)
	cs.enemies.clear()
	cs._volley_pending = true
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 0)
	cs._volley_pending = false
	cs.reward_pending = true
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 0)
	cs.reward_pending = false
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 1)
	cs.campaign_try_advance()
	assert_eq(cs.campaign_node_clears, 1)
	cs.start_campaign(489)
	assert_eq(cs.campaign_node_clears, 0)

func test_silhouette_keeps_parallax_and_pause_semantics() -> void:
	var bg := CampaignBackdrop.new()
	bg.advance(1.0, -80.0)
	assert_almost_eq(bg.shift_for(bg.DEPTH_FAR), -17.6, 0.0001)
	assert_almost_eq(bg.shift_for(bg.DEPTH_MID), -38.4, 0.0001)
	assert_eq(bg.shift_for(bg.DEPTH_NEAR), -80.0)
	bg.advance(0.0, -80.0)
	assert_eq(bg.scroll, -80.0)
	bg.free()

func test_trash_xp_picker_is_top_canvas_blocks_background_and_selects_once() -> void:
	CombatState.boot_campaign = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(4)
	CombatState.boot_campaign = false
	var cs: CombatState = ui.state
	cs.campaign_instant_transitions = true
	cs.campaign_pick_opening(0)
	cs.campaign_skip_walk()
	cs.enemies.clear()
	cs.alley_force_kind = CampaignRules.ALLEY_TRASH
	cs._begin_alley_approach()
	cs.campaign_skip_walk()
	ui._ensure_alley_panel()
	cs.alley_force_trash_u = 0.95
	assert_true(cs.alley_try_rummage())
	ui._refresh()
	ui._open_reward_panel_now()
	await wait_process_frames(3)
	assert_true(ui._reward_open)
	assert_true(ui.is_combat_frozen())
	assert_eq(ui.reward_panel.get_canvas_layer_node().layer, 100)
	assert_eq(ui.dimmer.get_canvas_layer_node(), ui.reward_panel.get_canvas_layer_node())
	assert_gt(ui.reward_panel.z_index, ui._alley_panel.z_index)
	assert_eq(ui.dimmer.mouse_filter, Control.MOUSE_FILTER_STOP)
	var bag_before := cs.bag.size()
	var hand_before := cs.hand.duplicate()
	# A click outside the reward card must land on the modal dimmer, not the load button.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = ui.btn_manual_load.get_global_rect().get_center()
	Input.parse_input_event(click)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await wait_process_frames(2)
	assert_eq(cs.hand, hand_before)
	assert_eq(cs.bag.size(), bag_before)
	ui._on_reward_pick(0)
	assert_eq(cs.bag.size(), bag_before + 1)
	ui._on_reward_pick(0)
	assert_eq(cs.bag.size(), bag_before + 1)
	assert_false(ui._reward_open)
	assert_false(ui.is_combat_frozen())

func test_rarity_appearance_disabled_data_and_sin_unchanged() -> void:
	assert_false(RarityFx.RARITY_APPEARANCE_ENABLED)
	for row in DataRegistry.all_ammo():
		var id := int(row["id"])
		if DataRegistry.is_sin_ammo(id):
			assert_eq(RarityFx.tier_for_ammo(id), RarityFx.TIER_SIN)
		else:
			assert_eq(RarityFx.tier_for_ammo(id), RarityFx.TIER_COMMON)
	assert_eq(RarityFx.epic_text_outline(1.0, 2.0), Color.TRANSPARENT)
	var host := Label.new()
	add_child_autofree(host)
	var stale := RarityFx.new()
	stale.name = RarityFx.NODE_NAME
	host.add_child(stale)
	stale._text_targets = [host]
	host.add_theme_color_override("font_outline_color", Color.RED)
	host.add_theme_constant_override("outline_size", 5)
	assert_null(RarityFx.attach(host, CombatConstants.WHITE_AMMO_ID))
	assert_false(host.has_theme_color_override("font_outline_color"))
	assert_false(host.has_theme_constant_override("outline_size"))
