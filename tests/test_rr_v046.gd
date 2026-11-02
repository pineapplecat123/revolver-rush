extends GutTest
## v0.4.6 保险弹药：挡住第 3 颗同种罪孽装填。

const W := FireResolver.ID_WRATH
const INS := FireResolver.ID_INSURANCE
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func test_version_is_0_4_6() -> void:
	assert_eq(GameVersion.STRING, "0.4.6")


func test_insurance_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(INS)
	assert_eq(str(def.get("name", "")), "保险弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(INS))
	assert_eq(FireResolver.base_damage_for(INS, [INS], 0, 0), 1)


func test_insurance_swap_helper_blocks_third() -> void:
	var cs := CombatState.new(4610)
	cs.start_rush(4610, W)
	cs.player_hp = 20
	cs.dev_force_load([W, W, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(INS, false)
	assert_eq(cs.sin_count_in_cylinder(W), 2)
	var swap: Dictionary = cs._try_insurance_swap_third_sin(W, 0.0)
	assert_true(bool(swap.get("swapped", false)))
	assert_eq(int(swap.get("ammo_id", -1)), INS)
	assert_true(cs._bag_has_ammo(W), "sin returned to bag")
	assert_false(cs._bag_has_ammo(INS), "insurance taken from bag")


func test_insurance_swap_load_path() -> void:
	## 袋里只有保险+1愤怒：强制先抽出愤怒（袋序固定后用多次 begin 不稳定），
	## 改为：膛 2 怒，袋仅保险，手动 set 第三发前走 swap 再装入。
	var cs := CombatState.new(4611)
	cs.start_rush(4611, W)
	cs.player_hp = 20
	cs.dev_force_load([W, W, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.bag.clear()
	cs.bag_temp.clear()
	cs._bag_append(INS, false)
	var swap: Dictionary = cs._try_insurance_swap_third_sin(W, 0.0)
	assert_true(bool(swap.get("swapped", false)))
	# 写入保险到空仓
	cs.magazine.set_slot(cs.magazine.chamber_at_load_port(), int(swap["ammo_id"]), swap.get("temp", 0.0))
	cs._check_sin_threshold_after_insert(int(swap["ammo_id"]))
	assert_eq(cs.sin_count_in_cylinder(W), 2)
	assert_eq(cs.player_hp, 20)


func test_third_sin_without_insurance_penalizes() -> void:
	var cs := CombatState.new(4612)
	cs.start_rush(4612, W)
	cs.player_hp = 20
	cs.dev_force_load([W, W, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	assert_eq(cs.sin_count_in_cylinder(W), 2)
	# 直接插入第三发愤怒（无保险）
	var slot: int = -1
	for i in cs.magazine.slots.size():
		if cs.magazine.slots[i] == Magazine.EMPTY:
			slot = i
			break
	assert_gte(slot, 0)
	cs.magazine.set_slot(slot, W, false)
	cs._check_sin_threshold_after_insert(W)
	assert_eq(cs.sin_count_in_cylinder(W), 3)
	assert_eq(cs.player_hp, 14)
