extends GutTest
## v0.3.6：战斗内袋重置不复制膛内弹（罪孽不再暴涨到 8+）；查询不改状态；补袋幂等。

const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 3601) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	for e in cs.enemies:
		e.hp = 99999
		e.max_hp = 99999
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _total_temp(cs: CombatState) -> int:
	var n: int = cs.count_temporary_in_bag()
	for t in cs.discard_temp:
		if Magazine.temp_value(t) != 0.0:
			n += 1
	for i in cs.magazine.slots.size():
		if cs.magazine.is_slot_temporary(i):
			n += 1
	return n


func _total_ammo(cs: CombatState) -> int:
	return cs.bag.size() + cs.discard.size() + cs.magazine.loaded_count()


func _load_full(cs: CombatState) -> void:
	var guard := 12
	while guard > 0 and cs.can_manual_load() and cs.magazine.loaded_count() < 6:
		guard -= 1
		if not cs.is_busy_loading():
			if not cs.begin_load():
				break
			if not cs.is_busy_loading():
				continue
		var r: Dictionary = cs.load_next_chamber()
		if not bool(r.get("ok", false)):
			break
		if not bool(r.get("done", false)):
			cs.apply_load_rotate()
	cs.commit_load_session_if_active()


func test_sin_total_matches_design_after_every_reset() -> void:
	## 设计（v0.3.8 起）：重置后整池 = 10 平庸 + 5 罪孽 + 惩罚产生的临时罪孽（袋+膛+弃合计）。
	## 旧 bug：重置时膛内弹再被整份基线复制一次 → 第 3 次重置时罪孽合计 12（设计 8）。
	var cs := _rush()
	assert_eq(cs.total_ammo_count(W), 0)
	assert_eq(cs.total_ammo_count(WHITE), CombatConstants.STARTER_BAG_TOTAL)
	var seen := 0
	for _cycle in 60:
		_load_full(cs)
		if cs.bag_reset_count != seen:
			seen = cs.bag_reset_count
			var temps_now: int = _total_temp(cs)
			assert_eq(cs.total_ammo_count(WHITE), CombatConstants.STARTER_BAG_TOTAL + temps_now, "第 %d 次重置：平庸基础池 + 现存临时" % seen)
			assert_eq(_total_ammo(cs), CombatConstants.STARTER_BAG_TOTAL + temps_now, "整池不复制膛内弹")
			assert_lte(temps_now, cs.load_temp_sins_spawned)
			assert_eq(cs.penalty_temp_sins_spawned, 0)
		while cs.can_fire():
			var fired: Array = cs.fire_tap()
			if fired.is_empty():
				if cs.player_fire_gate_remaining > 0.0:
					cs.player_fire_gate_remaining = 0.0
					continue
				break
		if seen >= 5:
			break
	assert_gte(seen, 3, "模拟期间至少重置 3 次")


func test_reset_with_full_magazine_does_not_duplicate() -> void:
	var cs := _rush(3602)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	for i in 6:
		cs.magazine.set_slot(i, W if i < 3 else WHITE)
	assert_true(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL - 3, "基线里的 3 发平庸已在膛，不重复补")
	assert_eq(cs.total_ammo_count(WHITE), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(cs.total_ammo_count(W), 3, "塞进膛的非基线弹不会被复制进袋")


func test_temp_sin_in_magazine_counts_toward_next_reset() -> void:
	## v0.3.8：膛内临时罪孽不属于基础池 → 重置不扣基础罪孽，也不新增临时；它按自己的寿命走。
	var cs := _rush(3603)
	cs.bag_reset_count = 1
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs.magazine.set_slot(0, WHITE, true)
	assert_true(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag_reset_count, 2)
	assert_eq(_total_temp(cs), 1)
	assert_eq(cs.total_ammo_count(WHITE), CombatConstants.STARTER_BAG_TOTAL + 1)


func test_can_manual_load_is_pure_query() -> void:
	var cs := _rush(3604)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	for _i in 10:
		assert_true(cs.can_manual_load())
	assert_eq(cs.bag_reset_count, 0, "反复查询不触发重置")
	assert_true(cs.bag.is_empty())
	assert_true(cs.can_refill_bag())
	assert_true(cs.bag.is_empty())


func test_refill_is_idempotent_per_empty_bag() -> void:
	var cs := _rush(3605)
	cs.bag.clear()
	cs.bag_temp.clear()
	assert_true(cs.ensure_bag_refilled_if_empty())
	var size1: int = cs.bag.size()
	assert_false(cs.ensure_bag_refilled_if_empty(), "袋非空不再补")
	assert_false(cs.ensure_bag_refilled_if_empty())
	cs.tick_enemy_auto_step()
	assert_eq(cs.bag_reset_count, 1)
	assert_eq(cs.bag.size(), size1)


func test_no_reset_when_magazine_holds_whole_pool() -> void:
	## 基线很小且全在膛内：重置不出任何弹 → 不计次数、不加罪孽（防止反复触发叠加）。
	var cs := _rush(3606)
	cs._combat_bag_baseline = [WHITE, WHITE] as Array[int]
	cs.selected_sin_ammo_id = W
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.magazine.clear()
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(2, W, true)
	assert_false(cs.can_refill_bag())
	assert_false(cs.ensure_bag_refilled_if_empty())
	assert_eq(cs.bag_reset_count, 0)
	assert_false(cs.can_manual_load())


func test_changelog_has_0_3_6() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/changelog.json"))
	var found := false
	for e in d["entries"]:
		if str(e["version"]) == "0.3.6":
			found = true
	assert_true(found)
