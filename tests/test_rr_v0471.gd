extends GutTest
## v0.4.71：袋重置改到全部打光之后；闯关开局 5 白板再选 1 发。


const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	CampaignRules.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func after_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false
	CombatState.boot_campaign = false


func test_version_is_at_least_0_4_71() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.71") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.71" in log)
	assert_true("5 发" in log or "5 白板" in log)


func _rush(seed: int) -> CombatState:
	var cs := CombatState.new()
	cs.start_rush(seed, FireResolver.ID_WRATH)
	cs.spawn_paused = true
	cs.auto_enemy_advance = true
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _circulation(cs: CombatState) -> int:
	var n: int = cs.bag.size() + cs.hand.size() + cs.discard.size()
	if cs.magazine != null:
		n += cs.magazine.loaded_count()
	return n


func _permanent_circulation(cs: CombatState) -> int:
	return cs.count_permanent_owned() + _hand_permanents(cs)


func _hand_permanents(cs: CombatState) -> int:
	var n := 0
	cs._sync_hand_arrays()
	for i in cs.hand.size():
		var tv = cs.hand_temp[i] if i < cs.hand_temp.size() else 0.0
		if cs._counts_as_permanent(int(cs.hand[i]), tv):
			n += 1
	return n


func test_campaign_opening_is_five_whites_then_one_choice() -> void:
	assert_eq(CampaignRules.opening_white_count(), 5)
	assert_eq(CombatConstants.STARTER_WHITE_COUNT, 6, "rush 开局白板数量不变")
	var cs := CombatState.new()
	cs.start_campaign(47101)
	assert_eq(cs.bag.size(), 5)
	assert_eq(_count(cs.bag, WHITE), 5)
	assert_eq(cs._combat_bag_baseline.size(), 5)
	assert_true(cs.campaign_offer_pending)
	var picked: int = int(cs.campaign_offer_choices[0])
	assert_ne(picked, WHITE)
	assert_true(cs.campaign_pick_opening(0))
	assert_eq(cs.bag.size(), 6)
	assert_eq(_count(cs.bag, WHITE), 5)
	assert_eq(_count(cs.bag, picked), 1)
	assert_eq(cs._combat_bag_baseline.size(), 6)

	# 重新开始：先 5 白板，不能留下上次选的弹。
	cs.start_campaign(47102)
	assert_eq(cs.bag.size(), 5)
	assert_eq(_count(cs.bag, WHITE), 5)
	assert_eq(_count(cs.bag, picked), 0)
	assert_eq(cs._combat_bag_baseline.size(), 5)
	assert_true(cs.campaign_offer_pending)
	assert_false(cs.campaign_opening_resolved)
	assert_eq(cs.hand.size(), 0)
	assert_true(cs.magazine == null or cs.magazine.is_empty())


func test_rush_and_sandbox_starters_unchanged() -> void:
	var rush := _rush(47111)
	assert_eq(rush.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(_count(rush.bag, WHITE), CombatConstants.STARTER_WHITE_COUNT)
	var box := CombatState.new()
	box.start_sandbox(47112, FireResolver.ID_WRATH, true)
	assert_true(box.sandbox_mode)
	assert_eq(box.bag.size(), 0)
	assert_false(box.ensure_bag_refilled_if_empty())
	assert_eq(box.bag.size(), 0)


func test_pour_exhausted_pool_does_not_duplicate_hand_or_cylinder() -> void:
	var cs := _rush(47121)
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	for _i in 5:
		cs._bag_append(WHITE, false)
	cs._snapshot_combat_bag_baseline()
	assert_eq(cs.dump_to_hand(), 5)
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.hand.size(), 5)
	assert_false(cs.ensure_bag_refilled_if_empty(), "最后一发倒进手里时不重置")
	assert_eq(cs.bag_reset_count, 0)
	var mid: int = _circulation(cs)
	assert_eq(mid, 5)
	# 没有可回收的子弹：保留手牌，不能凭空补到6。
	assert_eq(cs.dump_to_hand(), 0)
	assert_eq(_circulation(cs), 5, "反复倒出空袋不得复制子弹")
	assert_eq(cs.bag_reset_count, 0)
	_load_hand_into_mag(cs)
	assert_eq(cs.hand.size(), 0)
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.magazine.loaded_count(), 5)
	assert_false(cs.ensure_bag_refilled_if_empty(), "部分转轮有弹时不重置")
	assert_false(cs.can_dump_to_hand(), "全部永久弹已在转轮中，无可回收弹")
	assert_eq(cs.bag_reset_count, 0)
	assert_eq(_circulation(cs), 5)


func test_reset_once_after_full_depletion_conserves_permanents() -> void:
	var cs := _rush(47131)
	# 人为缩成 4 发永久白，方便打完整轮。
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	for _i in 4:
		cs._bag_append(WHITE, false)
	cs._snapshot_combat_bag_baseline()
	assert_eq(cs._combat_bag_baseline.size(), 4)
	var resets := 0
	for cycle in 3:
		assert_eq(cs.bag.size(), 4, "第 %d 轮开始袋里应是 4 发基线" % cycle)
		assert_eq(cs.dump_to_hand(), 4)
		assert_eq(cs.bag.size(), 0)
		assert_eq(cs.hand.size(), 4)
		assert_false(cs.ensure_bag_refilled_if_empty())
		_load_hand_into_mag(cs)
		assert_eq(cs.magazine.loaded_count(), 4)
		assert_false(cs.ensure_bag_refilled_if_empty())
		# 当作全部打出：进弃牌，转轮清空（不走完整弹道，只验证重置时机与计数）。
		for s in cs.magazine.slots.size():
			var id: int = int(cs.magazine.slots[s])
			if id != Magazine.EMPTY:
				cs.discard.append(id)
				cs.discard_temp.append(0.0)
		cs.magazine.clear()
		assert_eq(cs.bag.size(), 0)
		assert_eq(cs.hand.size(), 0)
		assert_eq(cs.magazine.loaded_count(), 0)
		assert_true(cs.bag_cycle_ready_to_reset())
		assert_true(cs.ensure_bag_refilled_if_empty())
		resets += 1
		assert_eq(cs.bag_reset_count, resets)
		assert_eq(cs.bag.size(), 4)
		assert_eq(_count(cs.bag, WHITE), 4)
		assert_eq(cs.discard.size(), 0)
		assert_false(cs.ensure_bag_refilled_if_empty(), "同一轮不得再重置")
	assert_eq(resets, 3)
	assert_eq(cs.bag.size(), 4)


func test_temporary_fire_once_not_resurrected_and_reward_kept() -> void:
	var cs := _rush(47141)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.hand.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs._bag_append(WHITE, false)
	cs._bag_append(QISHI, false)
	cs._snapshot_combat_bag_baseline()
	# 奖励/购买的永久弹进基线。
	cs._bag_append(WHITE, false)
	cs._note_baseline_add(WHITE, false)
	assert_eq(cs._combat_bag_baseline.size(), 3)
	# 打出即毁的临时复制体：打出后不进弃牌，重置不得把它变出来。
	cs._bag_append(WHITE, CombatConstants.FIRE_ONCE_TEMP, true)
	assert_eq(cs.bag.size(), 4)
	cs.dump_to_hand()
	_load_hand_into_mag(cs)
	# 清掉膛内：永久进弃牌，临时复制体直接销毁。
	for s in cs.magazine.slots.size():
		var id: int = int(cs.magazine.slots[s])
		if id == Magazine.EMPTY:
			continue
		if cs.magazine.is_slot_temporary(s) or cs.magazine.is_slot_envy_copy(s):
			continue
		cs.discard.append(id)
		cs.discard_temp.append(0.0)
	cs.magazine.clear()
	assert_true(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 3, "只还永久基线，不复活打出即毁弹")
	assert_eq(_count(cs.bag, WHITE), 2)
	assert_eq(_count(cs.bag, QISHI), 1)
	assert_eq(_temp_count(cs), 0)


func test_deferred_impact_delays_reset_then_resets_once() -> void:
	var cs := _rush(47151)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.hand.clear()
	cs.discard.clear()
	cs.magazine.clear()
	cs._bag_append(WHITE, false)
	cs._bag_append(WHITE, false)
	cs._snapshot_combat_bag_baseline()
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	# 两发都已打出，弹道未落地。
	cs._pending_impacts[7] = {"hits": [], "ammo_id": WHITE, "resolved_total": 0}
	cs._pending_impacts[8] = {"hits": [], "ammo_id": WHITE, "resolved_total": 0}
	assert_true(cs.has_pending_impacts())
	assert_false(cs.bag_cycle_ready_to_reset())
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.bag_reset_count, 0)
	cs.finalize_pending_impact(7)
	assert_eq(cs.bag.size(), 0, "还有一发未落地，不得重置")
	assert_eq(cs.bag_reset_count, 0)
	cs.finalize_pending_impact(8)
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), 2)
	assert_false(cs.has_pending_impacts())
	assert_false(cs.ensure_bag_refilled_if_empty())


func test_sandbox_never_auto_refills() -> void:
	var cs := CombatState.new()
	cs.start_sandbox(47161, FireResolver.ID_WRATH, false)
	cs._bag_append(WHITE, false)
	cs._snapshot_combat_bag_baseline()
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.hand.clear()
	cs.magazine.clear()
	cs.discard.clear()
	assert_true(cs.sandbox_mode)
	assert_false(cs.bag_cycle_ready_to_reset())
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag.size(), 0)
	# 生成器仍可直接入袋。
	cs._bag_append(WHITE, CombatConstants.FIRE_ONCE_TEMP, true)
	assert_eq(cs.bag.size(), 1)


func _count(arr: Array, ammo_id: int) -> int:
	var n := 0
	for x in arr:
		if int(x) == ammo_id:
			n += 1
	return n


func _temp_count(cs: CombatState) -> int:
	var n := 0
	cs._sync_temp_arrays()
	for t in cs.bag_temp:
		if Magazine.temp_value(t) > 0.0:
			n += 1
	for t in cs.hand_temp:
		if Magazine.temp_value(t) > 0.0:
			n += 1
	for t in cs.discard_temp:
		if Magazine.temp_value(t) > 0.0:
			n += 1
	if cs.magazine != null:
		for s in cs.magazine.slots.size():
			if cs.magazine.is_slot_temporary(s):
				n += 1
	return n


func _load_hand_into_mag(cs: CombatState) -> void:
	while not cs.hand.is_empty() and cs.magazine.loaded_count() < CombatConstants.MAGAZINE_SIZE:
		var n: int = cs.auto_load_from_hand()
		if n <= 0:
			break
