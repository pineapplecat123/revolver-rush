extends GutTest
## v0.4.31：全局关 AA。

func test_version_and_aa_toggle() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.31") >= 0)
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.31"' in text)
	assert_false(RrAa.ENABLED)
	assert_false(RrAa.line())
	assert_false(RrAa.poly())

func test_shot_streak_line_has_aa_off() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var line: Line2D = ui._make_shot_streak(8.0, Color.WHITE, 1.0, 0.1)
	assert_false(line.antialiased)
	line.free()
