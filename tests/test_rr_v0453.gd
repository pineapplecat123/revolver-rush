extends GutTest
## v0.4.53：弹药袋改成束口皮袋，倒出时子弹从袋口掉进手里。


func test_version_0_4_53() -> void:
	assert_eq(GameVersion.STRING, "0.4.53")
	assert_true("0.4.53" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("束口皮袋" in FileAccess.get_file_as_string("res://data/changelog.json"))
