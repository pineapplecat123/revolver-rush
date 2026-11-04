extends GutTest
## v0.4.1 回声弹药：挂枪口【回声】4s（最多1层刷新）；窗内每发结算两次。

const WHITE := CombatConstants.WHITE_AMMO_ID
const ECHO := FireResolver.ID_ECHO


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4101) -> CombatState:
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
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	return cs


func _shot_one(cs: CombatState) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		cs._post_fire_enemy_pending = false


func _log_has(cs: CombatState, needle: String) -> bool:
	for line in cs.last_log:
		if needle in str(line):
			return true
	return false


func test_changelog_has_0_4_1_entry() -> void:
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.1"' in text or '"version":"0.4.1"' in text)


func test_echo_ammo_def_and_flags() -> void:
	var def: Dictionary = DataRegistry.get_ammo(ECHO)
	assert_eq(str(def.get("name", "")), "回声弹药")
	assert_eq(int(def.get("base_damage", 0)), 1)
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(ECHO))
	assert_false(DataRegistry.is_ammo_ephemeral(ECHO))
	assert_eq(FireResolver.base_damage_for(ECHO, [ECHO], 0), 1)
	var flags := FireResolver.inherits_from(ECHO)
	assert_true(bool(flags.get("echo", false)))
	assert_false(bool(flags.get("pierce", false)))
	# 玩家文案不含「回合」
	assert_false("回合" in str(def.get("special", "")))
	assert_false("回合" in str(def.get("blurb", "")))


func test_echo_mounts_muzzle_and_doubles_own_shot() -> void:
	## 回声本发即双结算：底伤1 → 实际扣血2。
	var cs := _rush(4110)
	cs.dev_force_load([
		ECHO, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	assert_true(cs._muzzle_echo)
	assert_true("回声" in cs.muzzle_status_parts())
	assert_true(_log_has(cs, "枪口【回声】"))
	assert_eq(hp0 - cs.enemies[0].hp, 2)
	assert_true(cs.last_shot_was_echoed)
	assert_gt(cs._muzzle_echo_t, 0.0)


func test_echo_muzzle_doubles_later_white() -> void:
	var cs := _rush(4111)
	cs.dev_force_load([
		ECHO, WHITE, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	_shot_one(cs)  # echo 1+1
	assert_true(cs._muzzle_echo)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)  # white 3+3
	assert_eq(hp0 - cs.enemies[0].hp, 6)


func test_echo_muzzle_max_one_layer_refresh() -> void:
	var cs := _rush(4112)
	cs.dev_force_load([
		ECHO, ECHO, WHITE, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	_shot_one(cs)
	assert_eq(cs._muzzle_echo_layers.size(), 1)
	cs.tick_muzzle_durations(1.5)
	var left: float = cs._muzzle_echo_t
	assert_lt(left, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC - 1.0)
	_shot_one(cs)  # refresh
	assert_eq(cs._muzzle_echo_layers.size(), 1)
	assert_almost_eq(cs._muzzle_echo_t, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC, 0.001)


func test_echo_expires_after_duration() -> void:
	var cs := _rush(4113)
	cs.dev_force_load([
		ECHO, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	assert_true(cs.do_fire())
	assert_true(cs._muzzle_echo)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_ELEMENT_SEC + 0.01)
	assert_false(cs._muzzle_echo)


func test_echo_fire_tap_emits_twin_record_and_hooks() -> void:
	var cs := _rush(4114)
	cs.pace_after_fire = true
	cs.dev_force_load([
		ECHO, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var seen_echo_hook := {"n": 0, "shot": 0}
	cs.hooks.subscribe(&"on_muzzle_apply", func(p):
		if str(p.get("kind", "")) == "echo":
			seen_echo_hook["n"] = int(seen_echo_hook["n"]) + 1
	)
	cs.hooks.subscribe(&"on_shot", func(_p):
		seen_echo_hook["shot"] = int(seen_echo_hook["shot"]) + 1
	)
	var hp0: int = cs.enemies[0].hp
	var shots: Array = cs.fire_tap()
	assert_eq(hp0 - cs.enemies[0].hp, 2)
	assert_gte(shots.size(), 2)
	assert_true(bool(shots[1].get("echo", false)) or bool(shots[0].get("echo", false)) or shots.size() >= 2)
	var echo_recs := 0
	for s in shots:
		if bool(s.get("echo", false)):
			echo_recs += 1
	assert_gte(echo_recs, 1)
	assert_gte(int(seen_echo_hook["n"]), 1)
	assert_gte(int(seen_echo_hook["shot"]), 2)


func test_echo_tip_and_entries_no_turn_wording() -> void:
	var cs := _rush(4115)
	cs._muzzle_echo = true
	cs._muzzle_echo_t = 3.5
	var tip := cs.muzzle_damage_tip_text()
	assert_true("回声" in tip)
	assert_false("回合" in tip)
	var entries: Array = cs.muzzle_status_entries()
	var names: PackedStringArray = PackedStringArray()
	for e in entries:
		names.append(str(e.get("name", "")))
	assert_true("回声" in names)
