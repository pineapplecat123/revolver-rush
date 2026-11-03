extends GutTest
## v0.4.9 正义弹药：装入卸已装罪孽；每卸 +2 本战斗永久伤。

const JUSTICE := FireResolver.ID_JUSTICE
const W := FireResolver.ID_WRATH
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4901) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, W)
	while cs.enemies.size() > 1:
		cs.enemies.pop_back()
	if cs.enemies.is_empty():
		cs.dev_spawn_enemy(1, 5)
	for e in cs.enemies:
		e.hp = 999
		e.max_hp = 999
		e.atk = 0
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func _count_bag(cs: CombatState, ammo_id: int) -> int:
	var n := 0
	for x in cs.bag:
		if int(x) == ammo_id:
			n += 1
	return n


func test_version_is_0_4_9() -> void:
	assert_true("0.4.9" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_justice_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(JUSTICE)
	assert_eq(str(def.get("name", "")), "正义弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(JUSTICE))
	assert_eq(FireResolver.base_damage_for(JUSTICE, [JUSTICE], 0), 3)


func test_justice_strips_loaded_sins_back_to_bag() -> void:
	var cs := _rush(4910)
	cs.dev_force_load([W, W, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	var bag_w0: int = _count_bag(cs, W)
	# 手动把正义装入空仓并触发卸罪
	var slot := -1
	for i in cs.magazine.slots.size():
		if cs.magazine.slots[i] == Magazine.EMPTY:
			slot = i
			break
	assert_gte(slot, 0)
	cs.magazine.set_slot(slot, JUSTICE, false)
	var stripped: int = cs._apply_justice_strip_on_load(JUSTICE)
	assert_eq(stripped, 2)
	assert_eq(cs.justice_damage_bonus, 4)
	assert_eq(cs.sin_count_in_cylinder(W), 0)
	assert_eq(_count_bag(cs, W), bag_w0 + 2)
	# 正义仍在匣
	assert_true(JUSTICE in cs.magazine.slots)


func test_justice_bonus_applies_to_outgoing() -> void:
	var cs := _rush(4911)
	cs.justice_damage_bonus = 4
	cs.dev_force_load([WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	# 平庸3 + 正义4
	assert_eq(hp0 - cs.enemies[0].hp, 7)


func test_force_load_with_justice_strips() -> void:
	var cs := _rush(4912)
	var bag_w0: int = _count_bag(cs, W)
	cs.dev_force_load([W, JUSTICE, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	assert_eq(cs.sin_count_in_cylinder(W), 0)
	assert_eq(cs.justice_damage_bonus, 2)
	assert_eq(_count_bag(cs, W), bag_w0 + 1)
