extends GutTest
## v0.4.90: small-icon ×N, flame layer cap, session logs.
const HUD := preload("res://scripts/combat/muzzle_status_hud.gd")
const WHITE := CombatConstants.BAIBAN_AMMO_ID
const DOUBLE := FireResolver.ID_DOUBLE_LAYERS
const CHUANDI := FireResolver.ID_CHUANDI

func before_each() -> void:
	DataRegistry.reload()
	SessionLogService.DIR = SessionLogService.DIR_GUT

func _flame(id: String, kind: String, layers: int, value: float) -> Dictionary:
	return {"id": id, "effect_kind": kind, "remaining": layers, "total": layers, "effect_per_stack": value, "amount": value, "color": Color.RED, "name": id}

func test_version_is_at_least_0_4_90() -> void:
	assert_true(GameVersion.STRING.begins_with("0.4."))
	var minor := int(GameVersion.STRING.split(".")[2])
	assert_gte(minor, 90)

func test_same_type_icons_collapse_and_omit_times_one() -> void:
	var a := _flame("boost", "damage_mult", 3, 1.5)
	var b := _flame("add", "damage_flat", 1, 1.0)
	b["color"] = Color.BLUE
	var c := _flame("boost-again", "damage_mult", 2, 1.5)
	c["color"] = Color.GREEN
	var icons := HUD.layer_icon_entries([a, b, c])
	assert_eq(icons.size(), 2)
	assert_eq(int(icons[0]["stack"]), 5)
	assert_eq(str(icons[0]["effect_kind"]), "damage_mult")
	assert_eq(int(icons[1]["stack"]), 1)
	assert_eq(icons[1]["color"], Color.BLUE)
	# Non-adjacent same types merge; first-seen color/order is kept.
	assert_eq(icons[0]["color"], Color.RED)
	assert_eq(HUD.icon_count_mark(5), "×5")
	assert_eq(HUD.icon_count_mark(1), "")
	assert_eq(HUD.icon_count_mark(0), "")

func test_hundreds_of_layers_make_one_icon_not_hundreds_of_controls() -> void:
	var cs := CombatState.new(49001)
	var hud = HUD.new()
	add_child_autofree(hud)
	hud.setup(cs, func() -> Vector2: return Vector2(120, 160))
	cs._volley_muzzle_buffs = [_flame("boost", "damage_mult", 240, 1.5), _flame("add", "damage_flat", 80, 1.0)]
	hud._process(0.0)
	assert_eq(hud._icons.size(), 2)
	assert_eq(int(hud._icons[0].stack_count), 240)
	assert_eq(hud._icons[0].count_text(), "×240")
	assert_eq(int(hud._icons[1].stack_count), 80)

func test_large_flame_envelope_is_not_collapsed_by_icon_stacking() -> void:
	var many := HUD.flame_envelope([{"remaining": 5}, {"remaining": 5}])
	var one := HUD.flame_envelope([{"remaining": 10}])
	assert_almost_eq(many.x, one.x, 0.05)
	assert_almost_eq(many.y, one.y, 0.05)
	var twelve := HUD.flame_envelope([{"remaining": 12}])
	var capped := HUD.flame_envelope([{"remaining": 99}])
	assert_almost_eq(twelve.x, capped.x, 0.05)
	assert_almost_eq(twelve.y, capped.y, 0.05)

func test_approved_twelve_layer_double_is_unchanged_under_the_cap() -> void:
	var seed := [_flame("boost", "damage_mult", 12, 1.5)]
	var d := FireResolver.compute_volley_details([DOUBLE, WHITE], [], [], seed)
	assert_eq(int(d["after"][0][0]["remaining"]), 24)
	assert_eq(FireResolver.flame_layer_count(d["after"][0]), 24)
	# The double shot itself does not consume.
	assert_eq(int(d["consumed"][0]), 0)

func test_double_layers_cap_at_99_instead_of_exponential_runaway() -> void:
	var seed := [_flame("boost", "damage_mult", 80, 1.5)]
	var once := FireResolver.compute_volley_details([DOUBLE], [], [], seed)
	assert_eq(int(once["after"][0][0]["remaining"]), 99)
	assert_ne(int(once["after"][0][0]["remaining"]), 160)
	var again := FireResolver.compute_volley_details([DOUBLE], [], [], once["after"][0])
	assert_eq(int(again["after"][0][0]["remaining"]), 99)

func test_huge_transfer_grant_is_capped_not_rejected() -> void:
	var granted := FireResolver.make_flame(CHUANDI, 0, 1000, 1.0)
	assert_false(granted.is_empty())
	assert_eq(int(granted["remaining"]), 99)
	assert_lte(int(granted["remaining"]), FireResolver.FLAME_LAYER_CAP)

func test_session_log_records_cap_and_export_text() -> void:
	var path := SessionLogService.begin_session("test", {"seed": 49010})
	SessionLogService.flame_event("cap", {"context": "double", "wanted": 160, "capped": 99, "source": "boost"})
	SessionLogService.flame_snapshot("after_shot", [_flame("boost", "damage_mult", 99, 1.5)], {"ammo_id": DOUBLE, "consumed": 0})
	SessionLogService.flush()
	var bundle := SessionLogService.export_bundle()
	var body := str(bundle.get("text", ""))
	assert_true(bundle.get("ok", false))
	assert_gt(body.find("SESSION"), -1)
	assert_gt(body.find("\"kind\":\"cap\""), -1)
	assert_gt(body.find("\"wanted\":160"), -1)
	assert_gt(body.find("\"total\":99"), -1)
	assert_gt(body.find("FLAME"), -1)
	assert_true(FileAccess.file_exists(path) or FileAccess.file_exists(str(bundle.get("path", ""))))
	assert_true(str(bundle.get("dir", "")).ends_with("session_logs_gut") or str(bundle.get("path", "")).contains("session_logs_gut"))
