class_name SkeletonPlayer
extends Node2D
## v0.4.21 骨骼动画玩家（纯表现，不碰任何玩法/数值）。
## Skeleton2D + Bone2D 搭的抽象小人（警长帽 + 蓝外套 + 左轮），原点 = 脚底中心，面朝右。
## 动画：idle（呼吸循环）/ shoot（后坐+枪口焰，可连点打断）/ reload（装弹）/ hurt（受击）/ death（倒地）。
## 用法：bind_state(cs) 后自动订阅 —— on_shot→shoot，on_chamber_loaded→reload，
##       player_damaged→hurt，phase_changed(LOST)→death，离开 LOST→revive。

const ANIM_IDLE := &"idle"
const ANIM_SHOOT := &"shoot"
const ANIM_RELOAD := &"reload"
const ANIM_HURT := &"hurt"
const ANIM_DEATH := &"death"
const ANIM_RESET := &"RESET"

## 配色：沿用棋盘玩家块的蓝 + 地面米色 + 描边浅蓝
const COL_COAT := Color(0.2, 0.48, 0.92)
const COL_COAT_BACK := Color(0.14, 0.33, 0.66)
const COL_OUTLINE := Color(0.65, 0.88, 1.0, 0.95)
const COL_PANTS := Color(0.15, 0.2, 0.36)
const COL_PANTS_BACK := Color(0.11, 0.15, 0.27)
const COL_SKIN := Color(0.95, 0.9, 0.82)
const COL_HAT := Color(0.45, 0.3, 0.19)
const COL_BAND := Color(0.78, 0.72, 0.55)
const COL_BOOT := Color(0.32, 0.21, 0.13)
const COL_STEEL := Color(0.62, 0.66, 0.74)
const COL_STEEL_DARK := Color(0.36, 0.39, 0.46)
const COL_GRIP := Color(0.5, 0.32, 0.18)
const COL_BADGE := Color(1.0, 0.88, 0.2)
const COL_FLASH := Color(1.0, 0.93, 0.55)
const COL_EYE := Color(0.08, 0.09, 0.12)

## 静止姿态：骨骼名 -> [position, rotation]
const REST := {
	"Hip": [Vector2(0, -45), 0.0],
	"Torso": [Vector2(0, -2), 0.0],
	"Head": [Vector2(1, -30), 0.0],
	"UpperArmF": [Vector2(3, -26), 0.08],
	"ForearmF": [Vector2(13, 0), -0.08],
	"HandF": [Vector2(12, 0), 0.0],
	"UpperArmB": [Vector2(-3, -26), 1.25],
	"ForearmB": [Vector2(12, 0), -0.7],
	"HandB": [Vector2(11, 0), 0.0],
	"ThighF": [Vector2(4, 0), -0.14],
	"ShinF": [Vector2(0, 20), 0.06],
	"ThighB": [Vector2(-4, 0), 0.16],
	"ShinB": [Vector2(0, 20), -0.04],
}

var rig: Node2D
var skeleton: Skeleton2D
var anim: AnimationPlayer
var muzzle: Marker2D
var flash: Polygon2D
var cylinder: Polygon2D
var bones: Dictionary = {}  ## name -> Bone2D
var is_dead: bool = false
var _state = null
var _hp_label: Label
var _hp_fill: ColorRect
## 头顶锚点（跟着 Head 骨走，帽顶上方）：给以后玩家状态圆环/飘字定位用
var head_anchor: Marker2D
## 状态圆环锚点（固定在血条正上方，不随动画抖）：v0.4.22 玩家头顶状态环挂这里
var status_anchor: Marker2D

func _init() -> void:
	name = "SkeletonPlayer"
	_build_rig()
	_build_hp_badge()
	_build_animations()


func _ready() -> void:
	anim.play(ANIM_IDLE)


# ---------------------------------------------------------------- 外部接口

func bind_state(cs) -> void:
	if _state != null:
		_unbind()
	_state = cs
	if cs == null:
		return
	cs.hooks.hooked.connect(_on_hook)
	cs.player_damaged.connect(_on_player_damaged)
	cs.phase_changed.connect(_on_phase_changed)
	set_hp(int(cs.player_hp), int(cs.player_max_hp))
	if int(cs.phase) == CombatState.Phase.LOST:
		play_death()


func _unbind() -> void:
	if _state == null:
		return
	if _state.hooks.hooked.is_connected(_on_hook):
		_state.hooks.hooked.disconnect(_on_hook)
	if _state.player_damaged.is_connected(_on_player_damaged):
		_state.player_damaged.disconnect(_on_player_damaged)
	if _state.phase_changed.is_connected(_on_phase_changed):
		_state.phase_changed.disconnect(_on_phase_changed)
	_state = null


func muzzle_global_position() -> Vector2:
	return muzzle.global_position


## 帽顶上方一点（随头动）。全局坐标。
func head_top_global_position() -> Vector2:
	return head_anchor.global_position


## 状态圆环应放的位置（血条正上方，稳定不抖）。全局坐标。
func status_anchor_global_position() -> Vector2:
	return status_anchor.global_position


func current_animation() -> StringName:
	return StringName(anim.current_animation)


func set_hp(hp: int, max_hp: int) -> void:
	_hp_label.text = str(maxi(hp, 0))
	var r := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	_hp_fill.size.x = 30.0 * r


func play_shoot() -> void:
	if is_dead:
		return
	## 连点：已在 shoot 中就从头再来（打断），否则从任意动作快速切入
	if anim.current_animation == ANIM_SHOOT:
		anim.seek(0.0, true)
	else:
		anim.play(ANIM_SHOOT, 0.03)


func play_reload() -> void:
	if is_dead:
		return
	if anim.current_animation == ANIM_SHOOT and anim.current_animation_position < 0.07:
		return  ## 刚开枪的那一下先让后坐打完，避免装弹把后坐吃掉
	if anim.current_animation == ANIM_RELOAD:
		anim.seek(0.0, true)
	else:
		anim.play(ANIM_RELOAD, 0.05)


func play_hurt() -> void:
	if is_dead:
		return
	if anim.current_animation == ANIM_HURT:
		anim.seek(0.0, true)
	else:
		anim.play(ANIM_HURT, 0.02)


func play_death() -> void:
	if is_dead:
		return
	is_dead = true
	anim.play(ANIM_DEATH, 0.05)


func revive() -> void:
	is_dead = false
	anim.play(ANIM_RESET)
	anim.advance(0.0)
	anim.play(ANIM_IDLE)


# ---------------------------------------------------------------- 信号

func _on_hook(event: StringName, _payload: Dictionary) -> void:
	match event:
		&"on_shot":
			play_shoot()
		&"on_chamber_loaded":
			play_reload()


func _on_player_damaged(_amount: int, _kind: String) -> void:
	if _state != null:
		set_hp(int(_state.player_hp), int(_state.player_max_hp))
		if int(_state.player_hp) <= 0:
			play_death()
			return
	play_hurt()


func _on_phase_changed(p: int) -> void:
	if p == CombatState.Phase.LOST:
		play_death()
	elif is_dead:
		revive()
	if _state != null:
		set_hp(int(_state.player_hp), int(_state.player_max_hp))


func _on_anim_finished(n: StringName) -> void:
	if n == ANIM_SHOOT or n == ANIM_RELOAD or n == ANIM_HURT:
		anim.play(ANIM_IDLE, 0.1)


# ---------------------------------------------------------------- 搭骨架

func _build_rig() -> void:
	rig = Node2D.new()
	rig.name = "Rig"
	add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	rig.add_child(skeleton)

	var hip := _bone("Hip", skeleton, 10)
	var torso := _bone("Torso", hip, 30)
	var head := _bone("Head", torso, 20)
	var ua_f := _bone("UpperArmF", torso, 13)
	var fa_f := _bone("ForearmF", ua_f, 12)
	var hand_f := _bone("HandF", fa_f, 4)
	var ua_b := _bone("UpperArmB", torso, 12)
	var fa_b := _bone("ForearmB", ua_b, 11)
	var hand_b := _bone("HandB", fa_b, 4)
	var th_f := _bone("ThighF", hip, 20)
	var sh_f := _bone("ShinF", th_f, 21)
	var th_b := _bone("ThighB", hip, 20)
	var sh_b := _bone("ShinB", th_b, 21)

	# 后侧肢体（z 0）
	_part(ua_b, _capsule(Vector2.ZERO, Vector2(12, 0), 3.4), COL_COAT_BACK, 0)
	_part(fa_b, _capsule(Vector2.ZERO, Vector2(11, 0), 3.0), COL_COAT_BACK, 0)
	_part(hand_b, _circle(Vector2(1, 0), 3.2), COL_SKIN.darkened(0.15), 0)
	_part(th_b, _capsule(Vector2.ZERO, Vector2(0, 20), 4.2), COL_PANTS_BACK, 0)
	_part(sh_b, _capsule(Vector2.ZERO, Vector2(0, 19), 3.6), COL_PANTS_BACK, 0)
	_part(sh_b, _boot(), COL_BOOT.darkened(0.2), 0)
	# 前腿（z 1）
	_part(th_f, _capsule(Vector2.ZERO, Vector2(0, 20), 4.2), COL_PANTS, 1)
	_part(sh_f, _capsule(Vector2.ZERO, Vector2(0, 19), 3.6), COL_PANTS, 1)
	_part(sh_f, _boot(), COL_BOOT, 1)
	# 躯干（z 2）：外套梯形 + 腰带 + 警长星
	var coat := PackedVector2Array([
		Vector2(-8, 3), Vector2(8, 3), Vector2(9.5, -24), Vector2(7, -30),
		Vector2(-7, -30), Vector2(-9.5, -24)])
	_part(torso, _grow(coat, 1.6), COL_OUTLINE, 2)
	_part(torso, coat, COL_COAT, 2)
	_part(torso, _rect(Vector2(-8.4, -2), Vector2(8.4, 1.5)), COL_BAND, 2)
	_part(torso, _star(Vector2(3.5, -19), 3.6, 1.6), COL_BADGE, 2)
	# 头（z 2）：圆脑袋 + 眼睛 + 牛仔帽
	_part(head, _circle(Vector2(0, -10), 11.2), COL_OUTLINE, 2)
	_part(head, _circle(Vector2(0, -10), 10.0), COL_SKIN, 2)
	_part(head, _rect(Vector2(4, -12.5), Vector2(6.4, -8.5)), COL_EYE, 2)
	_part(head, PackedVector2Array([Vector2(-15, -16), Vector2(15, -16), Vector2(13, -19.5), Vector2(-13, -19.5)]), COL_HAT, 2)
	_part(head, PackedVector2Array([Vector2(-8, -19), Vector2(8, -19), Vector2(6, -29), Vector2(0, -27), Vector2(-6, -29)]), COL_HAT, 2)
	_part(head, _rect(Vector2(-7.6, -22), Vector2(7.6, -19.4)), COL_BAND, 2)
	# 持枪手臂（z 3）
	_part(ua_f, _capsule(Vector2.ZERO, Vector2(13, 0), 4.6), COL_OUTLINE, 3)
	_part(ua_f, _capsule(Vector2.ZERO, Vector2(13, 0), 3.4), COL_COAT, 3)
	_part(fa_f, _capsule(Vector2.ZERO, Vector2(12, 0), 4.2), COL_OUTLINE, 3)
	_part(fa_f, _capsule(Vector2.ZERO, Vector2(12, 0), 3.0), COL_COAT, 3)
	# 左轮（挂在持枪手骨上）
	var gun := Node2D.new()
	gun.name = "Revolver"
	hand_f.add_child(gun)
	_part(gun, PackedVector2Array([Vector2(-1.5, -1), Vector2(3, -1), Vector2(1.5, 8), Vector2(-3.5, 7)]), COL_GRIP, 3)
	_part(gun, _rect(Vector2(0, -5.5), Vector2(9, 0.5)), COL_STEEL_DARK, 3)
	_part(gun, _rect(Vector2(8, -5), Vector2(22, -2)), COL_STEEL, 3)
	_part(gun, _rect(Vector2(20, -6.5), Vector2(21.5, -5)), COL_STEEL, 3)
	_part(gun, PackedVector2Array([Vector2(-1, -5.5), Vector2(1.5, -5.5), Vector2(-1.5, -8.5)]), COL_STEEL_DARK, 3)
	cylinder = _part(gun, _circle(Vector2.ZERO, 3.6, 6), COL_STEEL, 3)
	cylinder.name = "Cylinder"
	cylinder.position = Vector2(4.5, -2.5)
	_part(hand_f, _circle(Vector2(0.5, 0.5), 3.4), COL_SKIN, 3)
	muzzle = Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector2(23, -3.5)
	gun.add_child(muzzle)
	flash = _part(muzzle, _star(Vector2.ZERO, 9.0, 3.5, 5), COL_FLASH, 4)
	flash.name = "Flash"
	flash.position = Vector2(5, 0)
	flash.scale = Vector2(1.4, 0.8)
	flash.visible = false
	head_anchor = Marker2D.new()
	head_anchor.name = "HeadAnchor"
	head_anchor.position = Vector2(0, -32)
	head.add_child(head_anchor)


func _bone(bname: String, parent: Node, length: float) -> Bone2D:
	var b := Bone2D.new()
	b.name = bname
	var r: Array = REST[bname]
	b.position = r[0]
	b.rotation = r[1]
	b.set_autocalculate_length_and_angle(false)
	b.set_length(length)
	b.set_bone_angle(0.0)
	parent.add_child(b)
	b.rest = b.transform
	bones[bname] = b
	return b


func _part(parent: Node, pts: PackedVector2Array, col: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	p.z_index = z
	parent.add_child(p)
	return p


func _build_hp_badge() -> void:
	## 头顶小血条 + 数字（替代旧“玩家 / HP”方块文字）
	var box := Node2D.new()
	box.name = "HpBadge"
	box.position = Vector2(-15, -126)
	box.z_index = 4
	add_child(box)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.85)
	bg.position = Vector2(-1, 13)
	bg.size = Vector2(32, 6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.name = "HpFill"
	_hp_fill.color = Color(0.35, 0.85, 0.45)
	_hp_fill.position = Vector2(0, 14)
	_hp_fill.size = Vector2(30, 4)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_hp_fill)
	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.position = Vector2(-5, -6)
	_hp_label.size = Vector2(40, 18)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hp_label.add_theme_constant_override("outline_size", 4)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.text = "20"
	box.add_child(_hp_label)
	status_anchor = Marker2D.new()
	status_anchor.name = "StatusAnchor"
	status_anchor.position = Vector2(0, -136)
	add_child(status_anchor)


# ---------------------------------------------------------------- 几何

static func _circle(c: Vector2, r: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _capsule(a: Vector2, b: Vector2, r: float, n: int = 6) -> PackedVector2Array:
	var d := (b - a)
	var ang := d.angle()
	var out := PackedVector2Array()
	for i in n + 1:
		var t := ang - PI * 0.5 + PI * float(i) / float(n)
		out.append(b + Vector2(cos(t), sin(t)) * r)
	for i in n + 1:
		var t := ang + PI * 0.5 + PI * float(i) / float(n)
		out.append(a + Vector2(cos(t), sin(t)) * r)
	return out


static func _rect(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


static func _star(c: Vector2, r_out: float, r_in: float, n: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n * 2:
		var a := -PI * 0.5 + PI * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return out


static func _boot() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-4, 16), Vector2(4, 16), Vector2(5, 19), Vector2(9, 20.5), Vector2(9, 23), Vector2(-4.5, 23)])


static func _grow(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(pts, d)
	return res[0] if res.size() > 0 else pts


# ---------------------------------------------------------------- 动画

func _track_paths() -> Array:
	var out: Array = []
	for bn in REST.keys():
		out.append(["%s:rotation" % _bone_path(bn), REST[bn][1]])
	out.append(["%s:position" % _bone_path("Hip"), REST["Hip"][0]])
	out.append(["Rig:modulate", Color(1, 1, 1, 1)])
	out.append(["Rig:position", Vector2.ZERO])
	return out


func _bone_path(bn: String) -> String:
	return String(get_path_to(bones[bn]))


## keys: track_path -> Array of [time, value]；没写到的轨在 0 和末尾钉回静止值
func _make_anim(length: float, keys: Dictionary, loop: bool = false, hold_end: bool = false) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for tp in _track_paths():
		var path: String = tp[0]
		var rest_v = tp[1]
		var ti := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(ti, NodePath(path))
		a.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC if loop else Animation.INTERPOLATION_LINEAR)
		a.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
		if keys.has(path):
			var arr: Array = keys[path]
			var has0 := false
			for k in arr:
				if is_zero_approx(float(k[0])):
					has0 = true
			if not has0:
				a.track_insert_key(ti, 0.0, rest_v)
			for k in arr:
				a.track_insert_key(ti, float(k[0]), k[1])
			if not hold_end and float(arr[arr.size() - 1][0]) < length - 0.001:
				a.track_insert_key(ti, length, rest_v)
		else:
			a.track_insert_key(ti, 0.0, rest_v)
			a.track_insert_key(ti, length, rest_v)
	return a


func _r(bn: String) -> String:
	return "%s:rotation" % _bone_path(bn)


func _flash_track(a: Animation, on_t: float, off_t: float) -> void:
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath("%s:visible" % String(get_path_to(flash))))
	a.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
	if on_t < 0.0:
		a.track_insert_key(ti, 0.0, false)
		return
	a.track_insert_key(ti, on_t, true)
	a.track_insert_key(ti, off_t, false)


func _cyl_track(a: Animation, keys: Array) -> void:
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath("%s:position" % String(get_path_to(cylinder))))
	for k in keys:
		a.track_insert_key(ti, float(k[0]), k[1])


func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	var hip_p := "%s:position" % _bone_path("Hip")
	var hip0: Vector2 = REST["Hip"][0]
	var cyl0 := Vector2(4.5, -2.5)

	# RESET：全部回静止
	var reset := _make_anim(0.001, {})
	_flash_track(reset, 0.0005, 0.0006)
	_cyl_track(reset, [[0.0, cyl0]])
	lib.add_animation(ANIM_RESET, reset)

	# idle：1.6s 呼吸（胯微沉、上身/头微晃、枪口轻轻起伏）
	var idle := _make_anim(1.6, {
		hip_p: [[0.0, hip0], [0.8, hip0 + Vector2(0, 1.2)], [1.6, hip0]],
		_r("Torso"): [[0.0, 0.0], [0.8, -0.035], [1.6, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.8, 0.05], [1.6, 0.0]],
		_r("UpperArmF"): [[0.0, 0.08], [0.8, 0.12], [1.6, 0.08]],
		_r("UpperArmB"): [[0.0, 1.25], [0.8, 1.32], [1.6, 1.25]],
	}, true)
	_flash_track(idle, -1.0, -1.0)
	_cyl_track(idle, [[0.0, cyl0]])
	lib.add_animation(ANIM_IDLE, idle)

	# shoot：0.16s 后坐——手臂上扬、上身后仰、头一顿；枪口焰 0~0.05s
	var shoot := _make_anim(0.16, {
		_r("UpperArmF"): [[0.0, 0.08], [0.03, -0.14], [0.16, 0.08]],
		_r("ForearmF"): [[0.0, -0.08], [0.03, -0.18], [0.16, -0.08]],
		_r("HandF"): [[0.0, 0.0], [0.03, -0.24], [0.16, 0.0]],
		_r("Torso"): [[0.0, 0.0], [0.03, -0.09], [0.16, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.04, -0.08], [0.16, 0.0]],
		hip_p: [[0.0, hip0], [0.03, hip0 + Vector2(-1.5, 0)], [0.16, hip0]],
	})
	_flash_track(shoot, 0.0, 0.05)
	_cyl_track(shoot, [[0.0, cyl0]])
	lib.add_animation(ANIM_SHOOT, shoot)

	# reload：0.34s 枪收到胸前、转轮甩出、后手拍弹、甩回
	var reload := _make_anim(0.34, {
		_r("UpperArmF"): [[0.0, 0.08], [0.08, 0.95], [0.26, 0.95], [0.34, 0.08]],
		_r("ForearmF"): [[0.0, -0.08], [0.08, -1.35], [0.26, -1.35], [0.34, -0.08]],
		_r("HandF"): [[0.0, 0.0], [0.08, 0.95], [0.26, 0.95], [0.34, 0.0]],
		_r("UpperArmB"): [[0.0, 1.25], [0.1, 0.75], [0.16, 0.9], [0.22, 0.75], [0.34, 1.25]],
		_r("ForearmB"): [[0.0, -0.7], [0.1, -1.1], [0.16, -0.9], [0.22, -1.1], [0.34, -0.7]],
		_r("Head"): [[0.0, 0.0], [0.08, 0.32], [0.26, 0.32], [0.34, 0.0]],
		_r("Torso"): [[0.0, 0.0], [0.08, 0.07], [0.26, 0.07], [0.34, 0.0]],
	})
	_flash_track(reload, -1.0, -1.0)
	_cyl_track(reload, [[0.0, cyl0], [0.08, cyl0], [0.11, cyl0 + Vector2(0, 4.5)], [0.24, cyl0 + Vector2(0, 4.5)], [0.27, cyl0]])
	lib.add_animation(ANIM_RELOAD, reload)

	# hurt：0.26s 后仰 + 闪红 + 往后一顿
	var hurt := _make_anim(0.26, {
		_r("Torso"): [[0.0, 0.0], [0.04, -0.3], [0.26, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.04, -0.35], [0.26, 0.0]],
		_r("UpperArmF"): [[0.0, 0.08], [0.04, -0.22], [0.26, 0.08]],
		_r("UpperArmB"): [[0.0, 1.25], [0.04, 0.85], [0.26, 1.25]],
		_r("ThighF"): [[0.0, -0.14], [0.04, -0.3], [0.26, -0.14]],
		"Rig:position": [[0.0, Vector2.ZERO], [0.04, Vector2(-4, 0)], [0.26, Vector2.ZERO]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.03, Color(1.45, 0.6, 0.6)], [0.18, Color(1, 1, 1)]],
	})
	_flash_track(hurt, -1.0, -1.0)
	_cyl_track(hurt, [[0.0, cyl0]])
	lib.add_animation(ANIM_HURT, hurt)

	# death：0.9s 中弹后仰 → 跪倒 → 前扑趴下，枪垂下，整体变暗（停在最后一帧）
	var death := _make_anim(0.9, {
		_r("Torso"): [[0.0, 0.0], [0.1, -0.4], [0.45, 0.35], [0.9, 1.38]],
		_r("Head"): [[0.0, 0.0], [0.1, -0.45], [0.45, 0.25], [0.9, 0.15]],
		_r("UpperArmF"): [[0.0, 0.08], [0.1, -0.9], [0.45, 0.6], [0.9, -1.2]],
		_r("ForearmF"): [[0.0, -0.08], [0.45, 0.3], [0.9, 0.05]],
		_r("HandF"): [[0.0, 0.0], [0.9, 0.5]],
		_r("UpperArmB"): [[0.0, 1.25], [0.1, 0.3], [0.45, 0.9], [0.9, -0.95]],
		_r("ForearmB"): [[0.0, -0.7], [0.9, -0.2]],
		_r("ThighF"): [[0.0, -0.14], [0.45, -1.35], [0.9, 1.3]],
		_r("ShinF"): [[0.0, 0.06], [0.45, 1.5], [0.9, 0.15]],
		_r("ThighB"): [[0.0, 0.16], [0.45, -0.9], [0.9, 1.45]],
		_r("ShinB"): [[0.0, -0.04], [0.45, 1.75], [0.9, 0.05]],
		hip_p: [[0.0, hip0], [0.1, hip0 + Vector2(-3, 0)], [0.45, hip0 + Vector2(-2, 16)], [0.9, hip0 + Vector2(-4, 39)]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.05, Color(1.45, 0.6, 0.6)], [0.3, Color(1, 1, 1)], [0.9, Color(0.55, 0.55, 0.62, 1)]],
	}, false, true)
	_flash_track(death, -1.0, -1.0)
	_cyl_track(death, [[0.0, cyl0]])
	lib.add_animation(ANIM_DEATH, death)

	anim.add_animation_library(&"", lib)
	anim.animation_finished.connect(_on_anim_finished)
