extends GutTest
## v0.4.46: web loading page uses a spinning cylinder instead of the Godot logo.


func test_version_is_at_least_0_4_46() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.46") >= 0)
	assert_true("0.4.46" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_web_shell_spins_cylinder_and_keeps_progress() -> void:
	var shell := FileAccess.get_file_as_string("res://misc/web_shell.html")
	assert_false(shell.is_empty(), "custom html shell must exist")
	assert_true("rr-cylinder-spin" in shell)
	assert_true("@keyframes rr-cylinder-spin" in shell)
	assert_true('id="status-progress"' in shell)
	assert_true("$GODOT_CONFIG" in shell)
	assert_true("$GODOT_URL" in shell)
	# Must not show the exported Godot / boot splash bitmap as the loading logo.
	assert_false('<img' in shell, "loading overlay should not use an <img> Godot logo")
	# Six empty chambers in the inline cylinder SVG.
	assert_gte(shell.count('r="20" fill="#141418"'), 6)


func test_export_preset_and_boot_splash_use_cylinder() -> void:
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_true('html/custom_html_shell="res://misc/web_shell.html"' in preset)
	var project := FileAccess.get_file_as_string("res://project.godot")
	assert_true('boot_splash/image="res://assets/boot/loading_cylinder.png"' in project)
	assert_true("boot_splash/show_image=true" in project)
	assert_true(FileAccess.file_exists("res://assets/boot/loading_cylinder.png"))
