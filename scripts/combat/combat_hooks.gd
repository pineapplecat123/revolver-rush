class_name CombatHooks
## v0.4.0 战斗生命周期钩子总线（涌现式连携流派预留）。
## 订阅方 presently 可空；弹药/机制在既有路径上 emit。
##
## 钩子一览（payload 均为 Dictionary，至少含 "cs" = CombatState）：
##   on_fire              — 玩家点射/开火链开始（含连发窗免费弹、倾泻续射之前的主发）
##   on_shot              — 任意一发实际击发结算后（含虚拟幽灵/连发免费弹）；ammo_id, virtual, dealt
##   on_chamber_loaded    — 弹药装入转轮仓；ammo_id, slot, temporary
##   on_bag_enter         — 弹药进入袋；ammo_id, temporary/temp_life
##   on_bag_leave         — 弹药离开袋（抽装/取出/到期/倾泻幽灵）；ammo_id, reason
##   on_three_sin         — 三罪孽惩罚触发；sin_id, count
##   on_muzzle_apply      — 枪口层挂上；kind (wrath/pride/greed/pierce/…), stacks_after
##   on_kill              — 敌人死亡移除时；enemy_id, cell, def_id
##   on_shop_enter        — 地图商店触碰打开；shop_cell
##   on_dump_start/end    — 倾泻开始/结束（interrupted=是否被点射打断）
##   on_burst_window      — 连发窗开启或刷新；remaining
##   on_temp_sin_spawn    — 临时罪孽入袋；sin_id, source ("load33"|"penalty_legacy")
##   on_dot_tick          — DoT 跳（燃烧/流血）；kind
##   on_insurance_swap    — 保险挡住第3罪孽装填；sin_id
##   on_stone_shatter     — 石头命中碎裂产小石头；dealt, pebbles
##   on_pebble_fuse       — 小石头相邻融合点射；count, damage
##   on_justice_strip     — 正义卸除已装罪孽；stripped, bonus_after
##   on_gold_ammo_spend   — 金币弹扣金；gold_after
##   on_confuse           — 敌人被加混乱；enemy_id, remaining
##   on_confuse_attack    — 混乱怪攻击邻近怪；attacker_id, victim_id, dealt
##   on_player_confuse    — 色欲三罪玩家自混乱；remaining
##   on_self_hit          — 自混乱期间攻击打自己；ammo_id, dealt
##   on_envy_copy         — 嫉妒击杀复制非罪 TTL；ammo_id
##   on_envy_discard      — 嫉妒三罪弃永久非罪；moved
##   on_gluttony_heal     — 暴食击杀回血；amount
##   on_gluttony_self_dot — 暴食三罪自 DoT 挂上；remaining
##   on_slow              — 懒惰命中减速；enemy_id, stacks
##   on_sloth_fire_penalty— 懒惰三罪射速窗；remaining
##
## 用法：cs.hooks.subscribe("on_shot", callable) / cs.hooks.emit_hook("on_shot", {...})

signal hooked(event: StringName, payload: Dictionary)

var _subs: Dictionary = {}  ## StringName -> Array[Callable]


func subscribe(event: StringName, cb: Callable) -> void:
	if not _subs.has(event):
		_subs[event] = []
	var arr: Array = _subs[event]
	if cb in arr:
		return
	arr.append(cb)


func unsubscribe(event: StringName, cb: Callable) -> void:
	if not _subs.has(event):
		return
	var arr: Array = _subs[event]
	var i := arr.find(cb)
	if i >= 0:
		arr.remove_at(i)


func clear() -> void:
	_subs.clear()


func emit_hook(event: StringName, payload: Dictionary = {}) -> void:
	var p: Dictionary = payload.duplicate()
	hooked.emit(event, p)
	if not _subs.has(event):
		return
	for cb in _subs[event]:
		if cb.is_valid():
			cb.call(p)
