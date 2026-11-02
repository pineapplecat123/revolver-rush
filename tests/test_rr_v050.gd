extends GutTest
## v0.4.10 金币弹药：伤=3+⌊金×20%⌋；每发金≥1则−1。

const GOLD := FireResolver.ID_GOLD
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 5010) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
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


func test_changelog_has_0_4_10_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.10"' in text or '"version":"0.4.10"' in text)


func test_gold_ammo_def() -> void:
	var def: Dictionary = DataRegistry.get_ammo(GOLD)
	assert_eq(str(def.get("name", "")), "金币弹药")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(GOLD))


func test_gold_damage_formula_and_spend() -> void:
	var cs := _rush(5011)
	cs.gold = 25
	cs.dev_force_load([GOLD, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	var expect: int = 3 + int(25 * 0.20)  # 3+5=8
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, expect)
	assert_eq(cs.gold, 24)
	assert_eq(cs.pending_gold_autofires(), 0)


func test_gold_no_spend_when_broke() -> void:
	var cs := _rush(5012)
	cs.gold = 0
	cs.dev_force_load([GOLD, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
	assert_eq(cs.gold, 0)


func test_shop_still_spends_gold() -> void:
	## 商店金币消费旧逻辑仍可用（买弹扣金）。
	var shop := ShopState.new()
	shop.begin(50, [WHITE, WHITE] as Array, 1, 42)
	assert_true(shop.can_buy(0) or shop.stock.size() > 0)
	if shop.stock.is_empty():
		return
	var before: int = shop.gold
	if shop.can_buy(0):
		assert_true(shop.buy(0))
		assert_lt(shop.gold, before)
