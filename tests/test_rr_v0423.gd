extends GutTest
## v0.4.23：Q 版小橘猫玩家 + 小动物敌人（纯表现）。

func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_0_4_23() -> void:
	assert_true(GameVersion.STRING >= "0.4.23")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.23"' in text)
	assert_true('"version": "0.4.22"' in text)


func test_skeleton_scenes_exist() -> void:
	assert_true(ResourceLoader.exists("res://scenes/player/skeleton_player.tscn"))
	assert_true(ResourceLoader.exists("res://scenes/enemy/skeleton_enemy.tscn"))
	var player = (load("res://scenes/player/skeleton_player.tscn") as PackedScene).instantiate()
	assert_true(player != null)
	assert_true(player is SkeletonPlayer)
	player.free()
	var enemy = (load("res://scenes/enemy/skeleton_enemy.tscn") as PackedScene).instantiate()
	assert_true(enemy != null)
	assert_true(enemy is SkeletonEnemy)
	enemy.free()
