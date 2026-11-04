extends GutTest
## v0.4.16 倾泻节奏：~0.06s/发 UI 步进；异步延后收束；可中断。

const WHITE := CombatConstants.WHITE_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 41601) -> CombatState:
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


func test_changelog_still_has_0_4_16() -> void:
	## 版本号会继续递增；此处只断言 0.4.16 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.16"' in text or '"version":"0.4.16"' in text)





