class_name SkeletonPlayer
extends Node2D
## v0.4.21 骨骼动画玩家（纯表现，不碰任何玩法/数值）。
## Skeleton2D + Bone2D 搭的站立 Q 版小橘猫（大头二头身半、猫耳胡须大眼、三节尾巴、肉垫爪握大左轮），原点 = 脚底中心，面朝右。
## 动画：idle（呼吸循环）/ shoot（后坐+枪口焰，可连点打断）/ reload（装弹）/ hurt（受击）/ death（倒地）。
## 用法：bind_state(cs) 后自动订阅 —— on_shot→shoot，on_chamber_loaded→reload，
##       player_damaged→hurt，phase_changed(LOST)→death，离开 LOST→revive。

const ANIM_IDLE := &"idle"
const ANIM_SHOOT := &"shoot"
const ANIM_RELOAD := &"reload"
const ANIM_HURT := &"hurt"
const ANIM_DEATH := &"death"
const ANIM_RESET := &"RESET"

## 配色：橘猫（暖橘毛 + 奶油肚皮/口鼻 + 深褐描边），红色小领巾，在深蓝底上很醒目
const COL_FUR := Color(1.0, 0.64, 0.28)
const COL_FUR_BACK := Color(0.86, 0.5, 0.2)
const COL_STRIPE := Color(0.82, 0.42, 0.15)
const COL_CREAM := Color(1.0, 0.94, 0.82)
const COL_OUTLINE := Color(0.33, 0.18, 0.08, 1.0)
const COL_EAR_IN := Color(1.0, 0.68, 0.72)
const COL_NOSE := Color(0.95, 0.45, 0.55)
const COL_BLUSH := Color(1.0, 0.5, 0.55, 0.55)
const COL_SCARF := Color(0.86, 0.2, 0.22)
const COL_WHISKER := Color(1.0, 0.97, 0.9, 0.95)
const COL_STEEL := Color(0.66, 0.7, 0.78)
const COL_STEEL_DARK := Color(0.36, 0.39, 0.46)
const COL_GRIP := Color(0.5, 0.32, 0.18)
const COL_FLASH := Color(1.0, 0.93, 0.55)
const COL_EYE := Color(0.08, 0.09, 0.12)
const GUN_SCALE := 1.75  ## 左轮比旧版大约 1.75 倍

## 静止姿态：骨骼名 -> [position, rotation]。二头身多一点：腿 ~23、身 ~20、头 ~40（含耳）
const REST := {
	"Hip": [Vector2(0, -24), 0.0],
	"Torso": [Vector2(0, -1), 0.0],
	"Head": [Vector2(1, -19), 0.0],
	"UpperArmF": [Vector2(3, -14), 0.1],
	"ForearmF": [Vector2(7, 0), -0.1],
	"HandF": [Vector2(7, 0), 0.0],
	"UpperArmB": [Vector2(-3, -14), 1.35],
	"ForearmB": [Vector2(7, 0), -0.4],
	"HandB": [Vector2(6, 0), 0.0],
	"ThighF": [Vector2(4, 0), -0.08],
	"ShinF": [Vector2(0, 11), 0.08],
	"ThighB": [Vector2(-4, 0), 0.1],
	"ShinB": [Vector2(0, 11), -0.06],
	"Tail1": [Vector2(-7, -2), -2.3],
	"Tail2": [Vector2(9, 0), 0.45],
	"Tail3": [Vector2(8, 0), 0.5],
}

var rig: Node2D
var skeleton: Skeleton2D
var anim: AnimationPlayer
var muzzle: Marker2D
var flash: Polygon2D
var cylinder: Polygon2D
var eyes: Node2D
var xeyes: Node2D
var bones: Dictionary = {}  ## name -> Bone2D
var is_dead: bool = false
var _state = null
## —— 自动瞄准（纯表现）：持枪大臂每帧叠加一个偏转，让枪口对准最近的活怪 ——
const AIM_MIN := -0.9  ## 最多往上抬（弧度，负=上）
const AIM_MAX := 0.75  ## 最多往下压
const AIM_LERP := 12.0  ## 跟随平滑（越大越跟手）
const HEAD_TILT_K := 0.3  ## 脑袋跟着歪一点
## 返回最近目标全局坐标（Vector2）或 null；combat_ui 注入
var aim_target_provider: Callable = Callable()
var aim_angle: float = 0.0  ## 当前叠加在 UpperArmF 上的偏转（平滑后）
var aim_target_angle: float = 0.0  ## 本帧想要的偏转（已夹角）
var _aim_override = null  ## set_aim_target() 手动指定（测试/演示）
var _aim_weight: float = 1.0
var _applied_arm: float = 0.0
var _applied_head: float = 0.0
var _rest_muzzle_angle: float = 0.0  ## 静止姿态下 肩→枪口 的角度（本节点局部）；瞄准以此为基准，后坐不会被瞄准抵消
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
	var sh := _xform_to_self(bones["UpperArmF"]).origin
	var mz := _xform_to_self(muzzle).origin
	_rest_muzzle_angle = (mz - sh).angle()


func _ready() -> void:
	anim.play(ANIM_IDLE)


func _process(delta: float) -> void:
	## 动画手动推进 → 再把瞄准偏转叠上去（后坐等动画姿态在下层，瞄准在上层叠加）
	_unapply_aim()
	anim.advance(delta)
	update_aim(delta)


## 手动指定瞄准点（全局坐标）；传 null 恢复由 provider 决定
func set_aim_target(global_pos) -> void:
	_aim_override = global_pos


func _current_target():
	if _aim_override != null:
		return _aim_override
	if aim_target_provider.is_valid():
		return aim_target_provider.call()
	return null


func _xform_to_self(n: Node) -> Transform2D:
	var t := Transform2D.IDENTITY
	var cur := n
	while cur != null and cur != self:
		if cur is Node2D:
			t = (cur as Node2D).transform * t
		cur = cur.get_parent()
	return t


func _unapply_aim() -> void:
	var ua: Bone2D = bones["UpperArmF"]
	var hd: Bone2D = bones["Head"]
	ua.rotation -= _applied_arm
	hd.rotation -= _applied_head
	_applied_arm = 0.0
	_applied_head = 0.0


## 计算并叠加瞄准偏转。要求调用前骨骼处于"纯动画姿态"（_process 里已先 _unapply_aim）。
func update_aim(delta: float) -> void:
	var tgt = null if is_dead else _current_target()
	var want_w := 1.0
	match StringName(anim.current_animation):
		ANIM_RELOAD:
			want_w = 0.0
		ANIM_HURT:
			want_w = 0.5
	if is_dead:
		want_w = 0.0
	var k := clampf(delta * AIM_LERP, 0.0, 1.0)
	_aim_weight = lerpf(_aim_weight, want_w, k)
	aim_target_angle = 0.0
	if tgt is Vector2:
		var ua: Bone2D = bones["UpperArmF"]
		# 绕肩转：需要的偏转 = 肩→目标 的角度 − 肩→枪口 的角度（均在本节点局部坐标里算，兼容缩放）
		var sh := to_local(ua.global_position)
		var tg := to_local(tgt)
		if sh.distance_to(tg) > 20.0:
			aim_target_angle = clampf(angle_difference(_rest_muzzle_angle, (tg - sh).angle()), AIM_MIN, AIM_MAX)
	aim_angle = lerpf(aim_angle, aim_target_angle, k)
	_applied_arm = aim_angle * _aim_weight
	_applied_head = aim_angle * HEAD_TILT_K * _aim_weight
	bones["UpperArmF"].rotation += _applied_arm
	bones["Head"].rotation += _applied_head


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
	rig.z_index = 1  ## 尾巴用 z -1 → 相对后实际 0，不会被棋盘底板盖住
	add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	rig.add_child(skeleton)

	var hip := _bone("Hip", skeleton, 6)
	var torso := _bone("Torso", hip, 19)
	var head := _bone("Head", torso, 36)
	var ua_f := _bone("UpperArmF", torso, 7)
	var fa_f := _bone("ForearmF", ua_f, 7)
	var hand_f := _bone("HandF", fa_f, 4)
	var ua_b := _bone("UpperArmB", torso, 7)
	var fa_b := _bone("ForearmB", ua_b, 6)
	var hand_b := _bone("HandB", fa_b, 4)
	var th_f := _bone("ThighF", hip, 11)
	var sh_f := _bone("ShinF", th_f, 11)
	var th_b := _bone("ThighB", hip, 11)
	var sh_b := _bone("ShinB", th_b, 11)
	var t1 := _bone("Tail1", hip, 9)
	var t2 := _bone("Tail2", t1, 8)
	var t3 := _bone("Tail3", t2, 8)

	# 尾巴（最底层 z -1）：三节胶囊，尾尖奶油色
	_part(t1, _capsule(Vector2.ZERO, Vector2(9, 0), 4.4), COL_OUTLINE, -1)
	_part(t1, _capsule(Vector2.ZERO, Vector2(9, 0), 3.4), COL_FUR, -1)
	_part(t2, _capsule(Vector2.ZERO, Vector2(8, 0), 4.2), COL_OUTLINE, -1)
	_part(t2, _capsule(Vector2.ZERO, Vector2(8, 0), 3.2), COL_FUR, -1)
	_part(t2, _rect(Vector2(3, -3.2), Vector2(5, 3.2)), COL_STRIPE, -1)
	_part(t3, _capsule(Vector2.ZERO, Vector2(7, 0), 4.0), COL_OUTLINE, -1)
	_part(t3, _capsule(Vector2.ZERO, Vector2(7, 0), 3.0), COL_FUR, -1)
	_part(t3, _capsule(Vector2(5, 0), Vector2(7.5, 0), 3.0), COL_CREAM, -1)
	# 后侧肢体（z 0）
	_part(ua_b, _capsule(Vector2.ZERO, Vector2(7, 0), 4.0), COL_OUTLINE, 0)
	_part(ua_b, _capsule(Vector2.ZERO, Vector2(7, 0), 3.0), COL_FUR_BACK, 0)
	_part(fa_b, _capsule(Vector2.ZERO, Vector2(6, 0), 3.8), COL_OUTLINE, 0)
	_part(fa_b, _capsule(Vector2.ZERO, Vector2(6, 0), 2.8), COL_FUR_BACK, 0)
	_part(hand_b, _circle(Vector2(1, 0), 4.0), COL_OUTLINE, 0)
	_part(hand_b, _circle(Vector2(1, 0), 3.1), COL_CREAM.darkened(0.12), 0)
	_part(th_b, _capsule(Vector2.ZERO, Vector2(0, 11), 5.0), COL_OUTLINE, 0)
	_part(th_b, _capsule(Vector2.ZERO, Vector2(0, 11), 4.0), COL_FUR_BACK, 0)
	_part(sh_b, _capsule(Vector2.ZERO, Vector2(0, 9), 4.6), COL_OUTLINE, 0)
	_part(sh_b, _capsule(Vector2.ZERO, Vector2(0, 9), 3.6), COL_FUR_BACK, 0)
	_part(sh_b, _ellipse(Vector2(2, 10), 6.4, 3.8), COL_OUTLINE, 0)
	_part(sh_b, _ellipse(Vector2(2, 10), 5.4, 2.8), COL_CREAM.darkened(0.12), 0)
	# 前腿（z 1）
	_part(th_f, _capsule(Vector2.ZERO, Vector2(0, 11), 5.0), COL_OUTLINE, 1)
	_part(th_f, _capsule(Vector2.ZERO, Vector2(0, 11), 4.0), COL_FUR, 1)
	_part(sh_f, _capsule(Vector2.ZERO, Vector2(0, 9), 4.6), COL_OUTLINE, 1)
	_part(sh_f, _capsule(Vector2.ZERO, Vector2(0, 9), 3.6), COL_FUR, 1)
	_part(sh_f, _ellipse(Vector2(2, 10), 6.4, 3.8), COL_OUTLINE, 1)
	_part(sh_f, _ellipse(Vector2(2, 10), 5.4, 2.8), COL_CREAM, 1)
	# 身子（z 2）：小圆梨形 + 奶油肚皮 + 红领巾
	var body := PackedVector2Array([
		Vector2(-9, 2), Vector2(-10.5, -4), Vector2(-9, -13), Vector2(-6, -19),
		Vector2(6, -19), Vector2(9, -13), Vector2(10.5, -4), Vector2(9, 2), Vector2(0, 4)])
	_part(torso, _grow(body, 1.2), COL_OUTLINE, 2)
	_part(torso, body, COL_FUR, 2)
	_part(torso, _ellipse(Vector2(2.5, -5), 5.5, 7.0), COL_CREAM, 2)
	_part(torso, _rect(Vector2(-8.5, -9), Vector2(-5.5, -7.5)), COL_STRIPE, 2)
	_part(torso, _rect(Vector2(-9.5, -4), Vector2(-6.5, -2.5)), COL_STRIPE, 2)
	_part(torso, PackedVector2Array([Vector2(-7.5, -19.5), Vector2(8, -19.5), Vector2(7, -16), Vector2(-6.5, -16)]), COL_SCARF, 2)
	_part(torso, PackedVector2Array([Vector2(2, -17), Vector2(8, -17), Vector2(5, -11)]), COL_SCARF.darkened(0.15), 2)
	# 头（z 2）：大圆脑袋（r 16）+ 两只尖耳 + 条纹 + 大眼睛 + 粉鼻 + 腮红 + 胡须
	var hc := Vector2(0, -16)
	for ear in [[Vector2(-14, -22), Vector2(-11, -39), Vector2(-1, -30)], [Vector2(2, -31), Vector2(12, -39), Vector2(15, -21)]]:
		var e := PackedVector2Array(ear)
		_part(head, _grow(e, 1.3), COL_OUTLINE, 2)
		_part(head, e, COL_FUR, 2)
		var cen: Vector2 = (ear[0] + ear[1] + ear[2]) / 3.0
		var inner := PackedVector2Array()
		for v in ear:
			inner.append(cen + (v - cen) * 0.55 + Vector2(0, 1.5))
		_part(head, inner, COL_EAR_IN, 2)
	_part(head, _ellipse(hc, 17.3, 15.8), COL_OUTLINE, 2)
	_part(head, _ellipse(hc, 16.0, 14.5), COL_FUR, 2)
	# 额头三道虎斑
	_part(head, _rect(Vector2(-1.2, -30), Vector2(1.2, -25)), COL_STRIPE, 2)
	_part(head, PackedVector2Array([Vector2(-6, -29), Vector2(-4, -29.5), Vector2(-3.5, -25.5), Vector2(-5.2, -25)]), COL_STRIPE, 2)
	_part(head, PackedVector2Array([Vector2(4, -29.5), Vector2(6, -29), Vector2(5.2, -25), Vector2(3.5, -25.5)]), COL_STRIPE, 2)
	_part(head, _rect(Vector2(-16, -19), Vector2(-12, -17.4)), COL_STRIPE, 2)
	_part(head, _rect(Vector2(-15.6, -14.5), Vector2(-12, -13)), COL_STRIPE, 2)
	# 口鼻奶油区（偏右，脸朝右）
	_part(head, _ellipse(Vector2(8, -9), 7.5, 5.2), COL_CREAM, 2)
	_part(head, _ellipse(Vector2(-2.5, -9.5), 3.2, 2.0), COL_BLUSH, 2)
	_part(head, _ellipse(Vector2(14.2, -10), 1.8, 1.6), COL_BLUSH, 2)
	_part(head, PackedVector2Array([Vector2(9, -12.5), Vector2(12.4, -12.5), Vector2(10.7, -10.6)]), COL_NOSE, 3)
	# "ω" 小嘴
	_part(head, _capsule(Vector2(10.7, -10.6), Vector2(9.0, -8.6), 0.55, 3), COL_OUTLINE, 3)
	_part(head, _capsule(Vector2(10.7, -10.6), Vector2(12.4, -8.6), 0.55, 3), COL_OUTLINE, 3)
	# 胡须：右侧伸出脸外，左侧两根短的
	for w in [[Vector2(13, -11), Vector2(24, -13.5)], [Vector2(13, -9.5), Vector2(24, -8.5)], [Vector2(12.5, -8), Vector2(22, -4.5)],
			[Vector2(4, -10.5), Vector2(-4, -12.5)], [Vector2(4, -9), Vector2(-4, -7.5)]]:
		_part(head, _capsule(w[0], w[1], 0.5, 2), COL_WHISKER, 3)
	# 大眼睛（可眨眼，死亡时换成 ><）
	eyes = Node2D.new()
	eyes.name = "Eyes"
	eyes.position = Vector2(0, -17)
	eyes.z_index = 3
	head.add_child(eyes)
	for ex in [1.5, 10.5]:
		_part(eyes, _ellipse(Vector2(ex, 0), 3.3, 4.2), COL_EYE, 0)
		_part(eyes, _circle(Vector2(ex + 1.1, -1.6), 1.4, 10), Color(1, 1, 1), 0)
		_part(eyes, _circle(Vector2(ex - 1.0, 1.6), 0.6, 8), Color(1, 1, 1, 0.8), 0)
	xeyes = Node2D.new()
	xeyes.name = "XEyes"
	xeyes.position = Vector2(0, -17)
	xeyes.z_index = 3
	xeyes.visible = false
	head.add_child(xeyes)
	for xe in [[1.5, 1.0], [10.5, -1.0]]:  # 左眼 ">"、右眼 "<"
		var ex: float = xe[0]
		var d: float = xe[1]
		_part(xeyes, _capsule(Vector2(ex - 2.4 * d, -2.6), Vector2(ex + 2.2 * d, 0), 0.9, 3), COL_EYE, 0)
		_part(xeyes, _capsule(Vector2(ex + 2.2 * d, 0), Vector2(ex - 2.4 * d, 2.6), 0.9, 3), COL_EYE, 0)
	# 持枪前臂（z 3）
	_part(ua_f, _capsule(Vector2.ZERO, Vector2(7, 0), 4.2), COL_OUTLINE, 3)
	_part(ua_f, _capsule(Vector2.ZERO, Vector2(7, 0), 3.2), COL_FUR, 3)
	_part(fa_f, _capsule(Vector2.ZERO, Vector2(7, 0), 4.0), COL_OUTLINE, 3)
	_part(fa_f, _capsule(Vector2.ZERO, Vector2(7, 0), 3.0), COL_FUR, 3)
	_part(fa_f, _rect(Vector2(3, -3), Vector2(4.5, 3)), COL_STRIPE, 3)
	# 左轮（挂在持枪爪骨上，放大 GUN_SCALE 倍；枪口/枪口焰跟着放大）
	var gun := Node2D.new()
	gun.name = "Revolver"
	gun.scale = Vector2(GUN_SCALE, GUN_SCALE)
	gun.position = Vector2(1, 0)
	hand_f.add_child(gun)
	_part(gun, _grow(PackedVector2Array([Vector2(-1.5, -1), Vector2(3, -1), Vector2(1.5, 8), Vector2(-3.5, 7)]), 0.6), COL_OUTLINE, 3)
	_part(gun, PackedVector2Array([Vector2(-1.5, -1), Vector2(3, -1), Vector2(1.5, 8), Vector2(-3.5, 7)]), COL_GRIP, 3)
	_part(gun, _grow(_rect(Vector2(0, -5.5), Vector2(22, 0.5)), 0.6), COL_OUTLINE, 3)
	_part(gun, _rect(Vector2(0, -5.5), Vector2(9, 0.5)), COL_STEEL_DARK, 3)
	_part(gun, _rect(Vector2(8, -5), Vector2(22, -2)), COL_STEEL, 3)
	_part(gun, _rect(Vector2(20, -6.5), Vector2(21.5, -5)), COL_STEEL, 3)
	_part(gun, PackedVector2Array([Vector2(-1, -5.5), Vector2(1.5, -5.5), Vector2(-1.5, -8.5)]), COL_STEEL_DARK, 3)
	cylinder = _part(gun, _circle(Vector2.ZERO, 3.6, 6), COL_STEEL, 3)
	cylinder.name = "Cylinder"
	cylinder.position = Vector2(4.5, -2.5)
	# 肉垫小爪包住枪柄
	_part(hand_f, _circle(Vector2(1, 0.5), 4.4), COL_OUTLINE, 4)
	_part(hand_f, _circle(Vector2(1, 0.5), 3.5), COL_CREAM, 4)
	_part(hand_f, _circle(Vector2(2.6, 1.6), 1.0, 8), COL_EAR_IN, 4)
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
	head_anchor.position = Vector2(0, -42)
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
	box.position = Vector2(-14, -110)
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
	status_anchor.position = Vector2(0, -124)
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


static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
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


func _vis_track(a: Animation, node: Node, keys: Array) -> void:
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath("%s:visible" % String(get_path_to(node))))
	a.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
	for k in keys:
		a.track_insert_key(ti, float(k[0]), k[1])


func _eyes_track(a: Animation, keys: Array) -> void:
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath("%s:scale" % String(get_path_to(eyes))))
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
	var e1 := Vector2.ONE
	var t1r: float = REST["Tail1"][1]
	var t2r: float = REST["Tail2"][1]
	var t3r: float = REST["Tail3"][1]

	# RESET：全部回静止
	var reset := _make_anim(0.001, {})
	_flash_track(reset, 0.0005, 0.0006)
	_cyl_track(reset, [[0.0, cyl0]])
	_vis_track(reset, eyes, [[0.0, true]])
	_vis_track(reset, xeyes, [[0.0, false]])
	_eyes_track(reset, [[0.0, e1]])
	lib.add_animation(ANIM_RESET, reset)

	# idle：2.0s 呼吸（身子微沉、脑袋轻晃、尾巴左右摇、中途眨一下眼）
	var idle := _make_anim(2.0, {
		hip_p: [[0.0, hip0], [1.0, hip0 + Vector2(0, 1.0)], [2.0, hip0]],
		_r("Torso"): [[0.0, 0.0], [1.0, -0.03], [2.0, 0.0]],
		_r("Head"): [[0.0, 0.0], [1.0, 0.06], [2.0, 0.0]],
		_r("UpperArmF"): [[0.0, 0.1], [1.0, 0.14], [2.0, 0.1]],
		_r("UpperArmB"): [[0.0, 1.35], [1.0, 1.45], [2.0, 1.35]],
		_r("Tail1"): [[0.0, t1r], [0.5, t1r + 0.18], [1.0, t1r], [1.5, t1r - 0.12], [2.0, t1r]],
		_r("Tail2"): [[0.0, t2r], [0.5, t2r + 0.25], [1.0, t2r - 0.1], [1.5, t2r - 0.25], [2.0, t2r]],
		_r("Tail3"): [[0.0, t3r], [0.5, t3r + 0.35], [1.0, t3r - 0.15], [1.5, t3r - 0.35], [2.0, t3r]],
	}, true)
	_flash_track(idle, -1.0, -1.0)
	_cyl_track(idle, [[0.0, cyl0]])
	_vis_track(idle, eyes, [[0.0, true]])
	_vis_track(idle, xeyes, [[0.0, false]])
	_eyes_track(idle, [[0.0, e1], [1.3, e1], [1.36, Vector2(1, 0.12)], [1.44, e1], [2.0, e1]])
	lib.add_animation(ANIM_IDLE, idle)

	# shoot：0.18s 后坐——大枪把小爪往上顶、身子后仰、脑袋一缩、尾巴一甩；枪口焰 0~0.05s
	var shoot := _make_anim(0.18, {
		_r("UpperArmF"): [[0.0, 0.1], [0.03, -0.12], [0.18, 0.1]],
		_r("ForearmF"): [[0.0, -0.1], [0.03, -0.22], [0.18, -0.1]],
		_r("HandF"): [[0.0, 0.0], [0.03, -0.24], [0.18, 0.0]],
		_r("Torso"): [[0.0, 0.0], [0.03, -0.08], [0.18, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.04, -0.12], [0.18, 0.0]],
		_r("Tail2"): [[0.0, t2r], [0.04, t2r - 0.5], [0.18, t2r]],
		_r("Tail3"): [[0.0, t3r], [0.05, t3r - 0.8], [0.18, t3r]],
		hip_p: [[0.0, hip0], [0.03, hip0 + Vector2(-2, 0)], [0.18, hip0]],
	})
	_flash_track(shoot, 0.0, 0.05)
	_cyl_track(shoot, [[0.0, cyl0]])
	_vis_track(shoot, eyes, [[0.0, true]])
	_vis_track(shoot, xeyes, [[0.0, false]])
	_eyes_track(shoot, [[0.0, Vector2(1, 0.55)], [0.08, e1]])
	lib.add_animation(ANIM_SHOOT, shoot)

	# reload：0.36s 枪抱到胸前、转轮甩出、后爪拍弹、甩回；脑袋低头看
	var reload := _make_anim(0.36, {
		_r("UpperArmF"): [[0.0, 0.1], [0.08, 1.1], [0.27, 1.1], [0.36, 0.1]],
		_r("ForearmF"): [[0.0, -0.1], [0.08, -1.6], [0.27, -1.6], [0.36, -0.1]],
		_r("HandF"): [[0.0, 0.0], [0.08, 0.6], [0.27, 0.6], [0.36, 0.0]],
		_r("UpperArmB"): [[0.0, 1.35], [0.1, 0.55], [0.16, 0.8], [0.22, 0.55], [0.36, 1.35]],
		_r("ForearmB"): [[0.0, -0.4], [0.1, -0.9], [0.16, -0.6], [0.22, -0.9], [0.36, -0.4]],
		_r("Head"): [[0.0, 0.0], [0.08, 0.22], [0.27, 0.22], [0.36, 0.0]],
		_r("Torso"): [[0.0, 0.0], [0.08, 0.06], [0.27, 0.06], [0.36, 0.0]],
		_r("Tail3"): [[0.0, t3r], [0.12, t3r + 0.4], [0.24, t3r - 0.2], [0.36, t3r]],
	})
	_flash_track(reload, -1.0, -1.0)
	_cyl_track(reload, [[0.0, cyl0], [0.08, cyl0], [0.11, cyl0 + Vector2(0, 4.5)], [0.25, cyl0 + Vector2(0, 4.5)], [0.28, cyl0]])
	_vis_track(reload, eyes, [[0.0, true]])
	_vis_track(reload, xeyes, [[0.0, false]])
	_eyes_track(reload, [[0.0, e1]])
	lib.add_animation(ANIM_RELOAD, reload)

	# hurt：0.28s 后仰 + 闪红 + 往后一顿 + 眯眼 + 尾巴炸起
	var hurt := _make_anim(0.28, {
		_r("Torso"): [[0.0, 0.0], [0.04, -0.28], [0.28, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.04, -0.3], [0.28, 0.0]],
		_r("UpperArmF"): [[0.0, 0.1], [0.04, -0.3], [0.28, 0.1]],
		_r("UpperArmB"): [[0.0, 1.35], [0.04, 0.7], [0.28, 1.35]],
		_r("ThighF"): [[0.0, -0.08], [0.04, -0.3], [0.28, -0.08]],
		_r("Tail1"): [[0.0, t1r], [0.04, t1r + 0.45], [0.28, t1r]],
		_r("Tail2"): [[0.0, t2r], [0.04, t2r - 0.4], [0.28, t2r]],
		_r("Tail3"): [[0.0, t3r], [0.05, t3r - 0.5], [0.28, t3r]],
		"Rig:position": [[0.0, Vector2.ZERO], [0.04, Vector2(-4, 0)], [0.28, Vector2.ZERO]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.03, Color(1.45, 0.6, 0.6)], [0.18, Color(1, 1, 1)]],
	})
	_flash_track(hurt, -1.0, -1.0)
	_cyl_track(hurt, [[0.0, cyl0]])
	_vis_track(hurt, eyes, [[0.0, true]])
	_vis_track(hurt, xeyes, [[0.0, false]])
	_eyes_track(hurt, [[0.0, e1], [0.03, Vector2(1, 0.15)], [0.2, Vector2(1, 0.15)], [0.26, e1]])
	lib.add_animation(ANIM_HURT, hurt)

	# death：1.0s 中弹一颤 → 腿一软 → 往前"啪叽"趴倒（脑袋朝右、小短腿往后翘、尾巴竖起再耷拉），眼睛变 ><，整体变暗（停在最后一帧）
	var death := _make_anim(1.0, {
		_r("Torso"): [[0.0, 0.0], [0.1, -0.3], [0.4, 0.25], [0.75, 1.62], [0.85, 1.48], [1.0, 1.52]],
		_r("Head"): [[0.0, 0.0], [0.1, -0.3], [0.4, 0.15], [0.75, -0.95], [1.0, -0.9]],
		_r("UpperArmF"): [[0.0, 0.1], [0.1, -0.8], [0.4, 0.3], [0.75, -0.95], [1.0, -0.9]],
		_r("ForearmF"): [[0.0, -0.1], [1.0, 0.1]],
		_r("HandF"): [[0.0, 0.0], [0.75, -0.5], [1.0, -0.6]],
		_r("UpperArmB"): [[0.0, 1.35], [0.1, 0.4], [0.75, -1.1], [1.0, -1.0]],
		_r("ForearmB"): [[0.0, -0.4], [1.0, -0.3]],
		_r("ThighF"): [[0.0, -0.08], [0.4, -0.6], [0.75, 1.45], [0.85, 1.75], [1.0, 1.65]],
		_r("ShinF"): [[0.0, 0.08], [0.4, 0.6], [0.75, -0.2], [1.0, -0.55]],
		_r("ThighB"): [[0.0, 0.1], [0.4, -0.4], [0.75, 1.35], [0.85, 1.6], [1.0, 1.5]],
		_r("ShinB"): [[0.0, -0.06], [0.4, 0.5], [0.75, -0.3], [1.0, -0.8]],
		_r("Tail1"): [[0.0, t1r], [0.4, -2.0], [0.8, -1.5], [1.0, -1.85]],
		_r("Tail2"): [[0.0, t2r], [0.8, -0.6], [1.0, 0.3]],
		_r("Tail3"): [[0.0, t3r], [0.8, -0.5], [1.0, 0.6]],
		hip_p: [[0.0, hip0], [0.1, hip0 + Vector2(-2, 0)], [0.4, hip0 + Vector2(-4, 6)], [0.75, hip0 + Vector2(-8, 12)], [0.85, hip0 + Vector2(-8, 10)], [1.0, hip0 + Vector2(-8, 11)]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.05, Color(1.45, 0.6, 0.6)], [0.3, Color(1, 1, 1)], [1.0, Color(0.7, 0.68, 0.72, 1)]],
	}, false, true)
	_flash_track(death, -1.0, -1.0)
	_cyl_track(death, [[0.0, cyl0]])
	_vis_track(death, eyes, [[0.0, true], [0.1, false]])
	_vis_track(death, xeyes, [[0.0, false], [0.1, true]])
	_eyes_track(death, [[0.0, e1]])
	lib.add_animation(ANIM_DEATH, death)

	anim.add_animation_library(&"", lib)
	anim.animation_finished.connect(_on_anim_finished)
	## 由本节点 _process 手动推进，保证"先动画、后叠加瞄准"的顺序
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
