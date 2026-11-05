extends GutTest
## v0.4.34：小石头逐步合成石头；燃烧全身 VFX。

const PEBBLE := FireResolver.ID_PEBBLE
const STONE := FireResolver.ID_STONE
const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 43401) -> CombatState:
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


func test_version_is_0_4_34() -> void:
	assert_eq(GameVersion.STRING, "0.4.34")
	assert_true("0.4.34" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_pebble_merge_step_by_step_leaves_stone() -> void:
	var cs := _rush(43410)
	cs.dev_force_load([PEBBLE, PEBBLE, PEBBLE, WHITE, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	assert_eq(cs.peek_pebble_merge_run(), 3)
	var s1: Dictionary = cs.apply_pebble_merge_step(1)
	assert_true(bool(s1.get("ok", false)))
	assert_eq(cs.magazine.slots[0], STONE)
	assert_eq(cs.magazine.slots[1], Magazine.EMPTY)
	assert_eq(cs.magazine.slots[2], PEBBLE)
	var s2: Dictionary = cs.apply_pebble_merge_step(2)
	assert_true(bool(s2.get("ok", false)))
	assert_eq(cs.magazine.slots[0], STONE)
	assert_eq(cs.magazine.slots[2], Magazine.EMPTY)
	assert_true(WHITE in cs.magazine.slots)


func test_pebble_chain_fires_as_stone_damage_max_base_or_run() -> void:
	var cs := _rush(43411)
	cs.dev_force_load([PEBBLE, PEBBLE, PEBBLE, WHITE, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	assert_eq(dealt, 3)
	assert_eq(cs.last_shot_ammo_id, STONE)
	var peb_left := 0
	for id in cs.magazine.slots:
		if int(id) == PEBBLE:
			peb_left += 1
	assert_eq(peb_left, 0)
	assert_true(WHITE in cs.magazine.slots)


func test_two_pebbles_merge_deals_stone_base() -> void:
	## 2 颗合成石头 → 伤害至少石头基础 3
	var cs := _rush(43412)
	cs.dev_force_load([PEBBLE, PEBBLE, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 3)
	assert_eq(cs.last_shot_ammo_id, STONE)


func test_gap_still_breaks_merge() -> void:
	var cs := _rush(43413)
	cs.dev_force_load([PEBBLE, Magazine.EMPTY, PEBBLE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY] as Array[int])
	cs.magazine.set_start(0)
	assert_eq(cs.peek_pebble_merge_run(), 1)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_eq(hp0 - cs.enemies[0].hp, 1)
	assert_eq(cs.last_shot_ammo_id, PEBBLE)
	assert_true(PEBBLE in cs.magazine.slots)


func test_pebble_text_mentions_step_merge() -> void:
	var peb: Dictionary = DataRegistry.get_ammo(PEBBLE)
	assert_true("逐步" in str(peb.get("special", "")) or "合成石头" in str(peb.get("special", "")))
	assert_true("合成" in str(peb.get("blurb", "")))


func test_burn_vfx_script_has_full_body_api() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/burn_vfx.gd")
	assert_true("configure" in src)
	assert_true("set_burn_active" in src)
	assert_true("黑烟" in src or "smoke" in src.to_lower() or "烟" in src)
	var fx = load("res://scripts/combat/burn_vfx.gd").new()
	assert_not_null(fx)
	fx.configure(56, 100, 1.55)
	assert_gt(fx.body_h, 90.0)
	fx.free()


func test_combat_ui_pools_burn_vfx() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true("_burn_vfx_pool" in src)
	assert_true("_acquire_burn_vfx" in src)
	assert_true("_play_pebble_merge_sequence" in src)
