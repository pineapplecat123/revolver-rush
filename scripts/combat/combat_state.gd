class_name CombatState
## 战斗状态机（rush!）：清场后奖励三选一，结算后再下一波。
## 随时装弹；开火一次先随机转轮，再按射速帽打光已装弹。装弹不倾倒已上膛子弹，可在有空仓时随时补弹。

enum Phase {
	AWAIT_LOAD,
	AWAIT_ACTION,
	FIRING,
	ENEMY_TURN,
	WON,
	LOST,
}

enum LoseReason {
	NONE,
	HP,
	AMMO_EXHAUSTED,
}

enum EncounterKind {
	NORMAL,
	BOSS,
}

signal phase_changed(phase: int)
signal log_line(text: String)
signal state_changed
## UI：敌人实际扣血时抛出（cell + 伤害 + 状态标签；直伤 kind 为空），用于飘字
signal enemy_damaged(cell: int, amount: int, kind: String)
signal explosive_detonated(cell: int, n_side: int)
## 玩家实际扣血（怪物普攻、愤怒自伤等）；UI 抖玩家格 + 飘字。
signal player_damaged(amount: int, kind: String)
## UI 表现用：敌人出手（打玩家或混乱打怪）时发一次。
signal enemy_attacked(enemy: EnemyInstance, kind: String)
signal player_healed(amount: int, kind: String)
## UI：金币入账时抛出（拾取或贪婪），用于金色飘字
signal gold_gained(cell: int, amount: int)
## 击杀掉落：金币先飞出来，碰到玩家才入账
signal gold_drop_spawned(drop_id: int, cell: int, amount: int)
## 击杀经验：数值已入账，UI 只播飞向经验条的粒子
signal xp_orb_spawned(cell: int, amount: int)

## v0.4.0 连携钩子总线（见 combat_hooks.gd）
var hooks: CombatHooks = CombatHooks.new()

## 主菜单 → 战斗：true=沙盒开局（combat_ui 读取后清回 false）
static var boot_sandbox: bool = false
## 沙盒：可自定义枪口/袋/怪；默认暂停连续刷怪与地图商店
var sandbox_mode: bool = false
var spawn_paused: bool = false
var map_shop_disabled: bool = false

var phase: int = Phase.AWAIT_LOAD
var player_hp: int = CombatConstants.PLAYER_MAX_HP
var player_max_hp: int = CombatConstants.PLAYER_MAX_HP
var bag: Array[int] = []
## 与 bag 平行：战斗内额外罪孽（半透明）
var bag_temp: Array = []  ## v0.3.8：临时罪孽剩余寿命秒（0=永久）
var discard: Array[int] = []
var discard_temp: Array = []
var magazine: Magazine = Magazine.new()
var enemies: Array = []
var turn_index: int = 0
var needs_reshuffle_next_load: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_log: PackedStringArray = PackedStringArray()
var lose_reason: int = LoseReason.NONE
var gold: int = 0
var wave_index: int = 1  ## v0.3.8 起无波次：保留字段兼容，UI 不显示

## v0.3.8 经验值 / 连续刷怪
var xp: int = 0
var level: int = 1
var pending_levelups: int = 0
var elapsed_sec: float = 0.0
## v0.4.20 伤害统计（沙盒 DPS 面板）：每次对敌伤害结算记一条 {t, amount}；时间轴=战斗秒 elapsed_sec。
var dmg_stats_events: Array = []
var dmg_stats_total: int = 0
var dmg_stats_peak_hit: int = 0
var dmg_stats_hits: int = 0
var dmg_stats_start_t: float = 0.0
var _spawn_timer: float = 0.0
var _boss_spawned: int = 0
var penalty_temp_sins_spawned: int = 0
## UI 用：最近到期消失的临时罪孽 [{where:"bag"/"discard"/"mag", slot, id}]（UI 取走后清空）
var expired_temp_events: Array = []

## 战斗胜利奖励（灰盒：基础金币 + 弹药三选一；可放弃换额外金）
var reward_pending: bool = false
var reward_resolved: bool = false
var reward_choices: Array[int] = []
## 预留钩子：本波是否受伤、本波玩家回合数（无伤/三回合奖励灰盒先不做）
var wave_took_damage: bool = false
var wave_player_turns: int = 0

## rush!（唯一模式）：一波接一波；胜利保留构筑。本波奖励后若需进店，false 表示还没逛完
var rush_shop_done: bool = true
## 遭遇类型：普通 / Boss（rush! 每 10 波超级僵尸）
var encounter_kind: int = EncounterKind.NORMAL
## 本波实际发放的基础金币（供 UI 显示）
var last_reward_base_gold: int = 0

## 弹药跨回合状态
var player_fire_gate_remaining: float = 0.0
## <0 用常量表击杀掉金概率；测试可写成 0 或 1。
var kill_gold_chance_override: float = -1.0
## 正义：本战斗永久平坦加伤（每卸除1罪孽 +2）。
var justice_damage_bonus: int = 0

## 逐步射击会话
var _fire_queue: Array[int] = []
var _fire_damages: Array[int] = []
var _fire_index: int = 0
var _fire_total_damage: int = 0
## v0.3.7：每层枪口独立计时（数组元素 = 该层剩余秒）；层数 = size；UI 显示最短剩余。
var _muzzle_pierce_layers: Array = []
var _muzzle_gas_layers: Array = []
var _muzzle_fire_layers: Array = []
var _muzzle_water_layers: Array = []
var _muzzle_thunder_layers: Array = []
var _muzzle_echo_layers: Array = []
var _muzzle_explosive_layers: Array = []
var _muzzle_lifesteal_layers: Array = []
var _muzzle_wrath_layers: Array = []
var _muzzle_pride_layers: Array = []
var _muzzle_greed_layers: Array = []
var _muzzle_lust_layers: Array = []
var _muzzle_envy_layers: Array = []
var _muzzle_gluttony_layers: Array = []
var _muzzle_sloth_layers: Array = []


func _muzzle_soonest(layers: Array) -> float:
	if layers.is_empty():
		return 0.0
	var m: float = float(layers[0])
	for x in layers:
		m = minf(m, float(x))
	return m


func _muzzle_set_stack_count(layers: Array, count: int, default_dur: float) -> void:
	## 测试/旧代码直接写层数：裁剪或补满时长层。
	count = maxi(0, count)
	while layers.size() > count:
		layers.pop_back()
	while layers.size() < count:
		layers.append(default_dur)


func _muzzle_set_soonest_or_all(layers: Array, remaining: float, default_dur: float) -> void:
	## 测试写 _muzzle_*_t：若无层且 remaining>0 补 1 层；否则把所有层设为 remaining（便于整段到期断言）。
	if remaining <= 0.0:
		layers.clear()
		return
	if layers.is_empty():
		layers.append(remaining)
		return
	for i in layers.size():
		layers[i] = remaining


func _muzzle_set_flag(layers: Array, on: bool, dur: float) -> void:
	if on:
		if layers.is_empty():
			layers.append(dur)
	else:
		layers.clear()


func _muzzle_add_layer(layers: Array, dur: float, max_layers: int = 99) -> void:
	## 叠层：追加新层（满时长）；max_layers=1 时改为刷新唯一层。
	if max_layers <= 1:
		layers.clear()
		layers.append(dur)
		return
	layers.append(dur)


func _muzzle_tick_layers(layers: Array, delta_sec: float) -> int:
	## 扣减每层；返回到期移除的层数。
	var expired := 0
	var i := 0
	while i < layers.size():
		var left: float = maxf(0.0, float(layers[i]) - delta_sec)
		if left <= 0.0:
			layers.remove_at(i)
			expired += 1
		else:
			layers[i] = left
			i += 1
	return expired


var _muzzle_pierce: bool:
	get:
		return not _muzzle_pierce_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_pierce_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_gas: bool:
	get:
		return not _muzzle_gas_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_gas_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_fire: bool:
	get:
		return not _muzzle_fire_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_fire_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_water: bool:
	get:
		return not _muzzle_water_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_water_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_thunder: bool:
	get:
		return not _muzzle_thunder_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_thunder_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_echo: bool:
	get:
		return not _muzzle_echo_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_echo_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_explosive: bool:
	get:
		return not _muzzle_explosive_layers.is_empty()
	set(v):
		_muzzle_set_flag(_muzzle_explosive_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_lifesteal: int:
	get:
		return _muzzle_lifesteal_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_lifesteal_layers, v, CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC)

var _muzzle_wrath: int:
	get:
		return _muzzle_wrath_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_wrath_layers, v, CombatConstants.MUZZLE_DURATION_WRATH_SEC)

var _muzzle_pride: int:
	get:
		return _muzzle_pride_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_pride_layers, v, CombatConstants.MUZZLE_DURATION_PRIDE_SEC)

var _muzzle_greed: int:
	get:
		return _muzzle_greed_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_greed_layers, v, CombatConstants.MUZZLE_DURATION_GREED_SEC)

var _muzzle_lust: int:
	get:
		return _muzzle_lust_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_lust_layers, v, CombatConstants.MUZZLE_DURATION_LUST_SEC)

var _muzzle_envy: int:
	get:
		return _muzzle_envy_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_envy_layers, v, CombatConstants.MUZZLE_DURATION_ENVY_SEC)

var _muzzle_gluttony: int:
	get:
		return _muzzle_gluttony_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_gluttony_layers, v, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC)

var _muzzle_sloth: int:
	get:
		return _muzzle_sloth_layers.size()
	set(v):
		_muzzle_set_stack_count(_muzzle_sloth_layers, v, CombatConstants.MUZZLE_DURATION_SLOTH_SEC)

var _muzzle_wrath_t: float:
	get:
		return _muzzle_soonest(_muzzle_wrath_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_wrath_layers, v, CombatConstants.MUZZLE_DURATION_WRATH_SEC)

var _muzzle_pride_t: float:
	get:
		return _muzzle_soonest(_muzzle_pride_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_pride_layers, v, CombatConstants.MUZZLE_DURATION_PRIDE_SEC)

var _muzzle_greed_t: float:
	get:
		return _muzzle_soonest(_muzzle_greed_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_greed_layers, v, CombatConstants.MUZZLE_DURATION_GREED_SEC)

var _muzzle_lust_t: float:
	get:
		return _muzzle_soonest(_muzzle_lust_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_lust_layers, v, CombatConstants.MUZZLE_DURATION_LUST_SEC)

var _muzzle_envy_t: float:
	get:
		return _muzzle_soonest(_muzzle_envy_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_envy_layers, v, CombatConstants.MUZZLE_DURATION_ENVY_SEC)

var _muzzle_gluttony_t: float:
	get:
		return _muzzle_soonest(_muzzle_gluttony_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_gluttony_layers, v, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC)

var _muzzle_sloth_t: float:
	get:
		return _muzzle_soonest(_muzzle_sloth_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_sloth_layers, v, CombatConstants.MUZZLE_DURATION_SLOTH_SEC)

var _muzzle_pierce_t: float:
	get:
		return _muzzle_soonest(_muzzle_pierce_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_pierce_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_gas_t: float:
	get:
		return _muzzle_soonest(_muzzle_gas_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_gas_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_fire_t: float:
	get:
		return _muzzle_soonest(_muzzle_fire_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_fire_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_water_t: float:
	get:
		return _muzzle_soonest(_muzzle_water_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_water_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_thunder_t: float:
	get:
		return _muzzle_soonest(_muzzle_thunder_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_thunder_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_echo_t: float:
	get:
		return _muzzle_soonest(_muzzle_echo_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_echo_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_explosive_t: float:
	get:
		return _muzzle_soonest(_muzzle_explosive_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_explosive_layers, v, CombatConstants.MUZZLE_DURATION_ELEMENT_SEC)

var _muzzle_lifesteal_t: float:
	get:
		return _muzzle_soonest(_muzzle_lifesteal_layers)
	set(v):
		_muzzle_set_soonest_or_all(_muzzle_lifesteal_layers, v, CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC)

## 本局所选罪孽弹药 id（愤怒/傲慢/贪婪之一）
var selected_sin_ammo_id: int = FireResolver.ID_WRATH
## 本场战斗内袋重置次数；每次重置灌袋 = 构筑基线 + 本计数发额外临时罪孽。开局/波末/下场清零。
var bag_reset_count: int = 0
## 本波构筑基线（非 ephemeral、非临时额外罪孽）；战斗内袋重置按此恢复，保留墓碑等永久弹。
var _combat_bag_baseline: Array[int] = []
var _pending_gold_autofires: int = 0
## v0.4.0 连发窗剩余秒（>0 时点射=免费平庸伤）；刷新不叠加。
var burst_window_remaining: float = 0.0
## v0.4.11 色欲：玩家自混乱剩余秒（期间攻击打自己）。
var player_confuse_remaining: float = 0.0
## v0.4.12 嫉妒：上一发非罪孽弹药 id（-1=尚无）。
var last_non_sin_ammo_id: int = -1
## v0.4.13 暴食：击杀回血预算（每秒按层数回复上限）。
var _gluttony_heal_budget: float = 0.0
## v0.4.13 暴食三罪：持续自伤 DoT 剩余秒（与 DoT 同频跳）。
var gluttony_self_dot_remaining: float = 0.0
## v0.4.14 懒惰三罪：射速惩罚窗 / 开火锁。
var sloth_fire_penalty_remaining: float = 0.0
var fire_lock_remaining: float = 0.0
## 本装填周期已击发的聚能发数（聚能伤害递增）。
var _focus_shots_fired: int = 0
## 本发小石头融合段长（≥2 时一次清空多仓）。
var _pebble_fuse_count: int = 0
## v0.4.0 倾泻：击发倾泻后待自动打出的剩余仓。v0.4.22 连射期间再按开火是忽略，不再用点射打断。
var _dump_pending: bool = false
var _dump_interrupted: bool = false
## UI 异步倾泻：跳过 fire_tap 末尾金色/收束，等倾泻结束（含中断）再补。
var _dump_followup_pending: bool = false
## v0.4.22：一次开火打光已装弹。异步时剩余仓由 take_volley_shot 步进。
var _volley_pending: bool = false
var _volley_followup_pending: bool = false
## 地图商店打开：逻辑时钟（怪、枪口、TTL、刷怪、射速帽）全部停。
var shop_hold: bool = false
## 尚未飞到玩家手里的金币。{id, cell, remaining, total}
var gold_drops: Array = []
var _gold_drop_seq: int = 0
## v0.4.0 DoT 独立计时。
var _dot_timer: float = 0.0
## v0.4.0 地图商店实体（格位；-1=不在场）。碰到玩家（cell<=1）打开商店。
var shop_cell: int = -1
var shop_spawn_count: int = 0
var shop_touch_pending: bool = false
var _shop_move_prog: float = 0.0
var load_temp_sins_spawned: int = 0
var _pending_tombstone_ghost_shots: Array = []
## 本玩家开火链已累计授予的额外轮数（含主匣与嵌套）；达上限后不再叠加。
var _extra_autofires_granted_this_chain: int = 0
## UI 逐步表现：为 true 时整匣结束后不立刻跑金色额外轮/怪回合，由 UI 消费。
var pace_after_fire: bool = false
## rush!：敌人按计时器自动向左走，不因玩家每发射击才推进一步。
var auto_enemy_advance: bool = false
## rush! 连续滑行：当前这一格走了多少（0..1）。满 1 → 逻辑格 -1 并结算一拍。
var enemy_step_progress: float = 0.0
## 本拍开始时锁定的「会移动」敌人（instance_id → true），保证视觉滑行与落格一致。
var _glide_movers: Dictionary = {}
var _glide_movers_valid: bool = false
## 兼容旧字段：v0.3.4 枪口改持续时间后不再用于清愤怒/贪婪。
var _turn_sin_clear_pending: bool = false
var _post_fire_enemy_pending: bool = false
var _in_gold_extra_round: bool = false

## 逐步装填会话（UI：装一发→转 60°→再装；do_load 仍可一次装满）
var _load_session_active: bool = false
var _load_next_slot: int = 0
var _load_raw_ids: Array[int] = []
var _load_resolved_ids: Array[int] = []
## UI：上一发实际对准的仓位（锤位）；空仓也会记下
var last_fired_slot: int = -1
## UI：上一发是否空仓（无效果、无黄闪，仍推进一格）
var last_shot_was_blank: bool = false
## 本发开火前快跳过的空仓步数（供 UI 快转）
var last_blank_skip_steps: int = 0
## UI 射击特效：本发弹药 id / 主命中格 / 主命中伤害 / 枪口描边=开火前枪口贡献色（怒→傲→贪→穿甲；不含本发刚挂罪孽）
var last_shot_ammo_id: int = -1
var last_shot_hit_cell: int = -1
var last_shot_dealt: int = 0
var last_shot_muzzle_outline_ids: Array[int] = []
## 本发命中格（前→后）；穿透时多格，弹点飞到末格；每格可飚血
var last_shot_hit_cells: Array[int] = []
var last_shot_hit_amounts: Array[int] = []
var last_shot_was_pierce: bool = false
## 本发是否因【回声】做了第二次结算；供 fire_tap 追加回声分录。
var last_shot_was_echoed: bool = false
var last_echo_hit_cells: Array[int] = []
var last_echo_hit_amounts: Array[int] = []
## pace：本发已规划、待视觉命中时再结算的命中（空=无待结算）
var _paced_shot: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## rush!：开局（唯一模式）。第 1 波按 rush 刷怪表；胜利后领奖 → 下一波，逢 5 波进店。
func start_rush(seed_value: int = 0, sin_ammo_id: int = FireResolver.ID_WRATH) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	BulletEffectRegistry.ensure_defaults()
	player_max_hp = CombatConstants.PLAYER_MAX_HP
	player_hp = player_max_hp
	bag.clear()
	bag_temp.clear()
	discard.clear()
	discard_temp.clear()
	bag_reset_count = 0
	_apply_sin_choice(sin_ammo_id, false)
	_fill_starter_bag()
	_shuffle_bag()
	_snapshot_combat_bag_baseline()
	magazine = Magazine.new()
	enemies.clear()
	wave_index = 1
	turn_index = 0
	needs_reshuffle_next_load = false
	last_log.clear()
	lose_reason = LoseReason.NONE
	gold = 0
	justice_damage_bonus = 0
	player_fire_gate_remaining = 0.0
	kill_gold_chance_override = -1.0
	_reset_fire_session()
	_reset_muzzle()
	_pending_gold_autofires = 0
	_extra_autofires_granted_this_chain = 0
	_post_fire_enemy_pending = false
	_in_gold_extra_round = false
	_reset_load_session()
	_clear_reward_state()
	wave_took_damage = false
	wave_player_turns = 0
	rush_shop_done = false
	burst_window_remaining = 0.0
	player_confuse_remaining = 0.0
	last_non_sin_ammo_id = -1
	_gluttony_heal_budget = 0.0
	gluttony_self_dot_remaining = 0.0
	sloth_fire_penalty_remaining = 0.0
	fire_lock_remaining = 0.0
	player_fire_gate_remaining = 0.0
	_reset_focus_shot_counter()
	_pebble_fuse_count = 0
	_dump_pending = false
	_dump_interrupted = false
	_dump_followup_pending = false
	_volley_pending = false
	_volley_followup_pending = false
	shop_hold = false
	gold_drops.clear()
	_gold_drop_seq = 0
	_dot_timer = CombatConstants.DOT_TICK_SEC
	shop_cell = -1
	shop_spawn_count = 0
	shop_touch_pending = false
	_shop_move_prog = 0.0
	load_temp_sins_spawned = 0
	hooks.clear()
	encounter_kind = EncounterKind.NORMAL
	last_reward_base_gold = 0
	pace_after_fire = true
	auto_enemy_advance = true
	sandbox_mode = false
	spawn_paused = false
	map_shop_disabled = false
	reset_enemy_glide()
	xp = 0
	level = 1
	pending_levelups = 0
	elapsed_sec = 0.0
	damage_stats_reset()
	_boss_spawned = 0
	penalty_temp_sins_spawned = 0
	expired_temp_events.clear()
	encounter_kind = EncounterKind.NORMAL
	_clear_all_sin_muzzle(true)
	# v0.3.8：无波次，开局按连续刷怪规则先刷满存活上限（t=0 → 2 只，同旧第 1 波 ×1.5）
	_spawn_up_to_cap()
	_spawn_timer = spawn_interval_now()
	_set_phase(Phase.AWAIT_LOAD)
	_log("rush!：平庸 ×%d + %s ×%d · 第 %d 波。" % [
		CombatConstants.STARTER_WHITE_COUNT,
		_ammo_name(selected_sin_ammo_id), CombatConstants.STARTER_SIN_COUNT, wave_index
	])
	_emit()


## 沙盒：同 rush 开局构筑，但清场、暂停刷怪与地图商店，保留装弹/射击。
func start_sandbox(seed_value: int = 0, sin_ammo_id: int = FireResolver.ID_WRATH, default_dummies: bool = true) -> void:
	start_rush(seed_value, sin_ammo_id)
	sandbox_mode = true
	spawn_paused = true
	map_shop_disabled = true
	enemies.clear()
	shop_cell = -1
	shop_touch_pending = false
	_shop_move_prog = 0.0
	_spawn_timer = 99999.0
	if default_dummies:
		sandbox_spawn_default_dummies()
	damage_stats_reset()
	_log("沙盒模式：刷怪与地图商店已暂停；用沙盒面板自定义枪口/袋/怪。")
	_emit()


func sandbox_spawn_default_dummies() -> int:
	## v0.4.20：默认 3 个木桩（SANDBOX_DEFAULT_DUMMY_CELLS），格被占则跳过。返回实际摆了几个。
	var n := 0
	for c in CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS:
		if occupied_cells().has(int(c)):
			continue
		if sandbox_spawn_dummy(-1, int(c)) != null:
			n += 1
	return n


func _consolidate_ammo_into_bag() -> void:
	if not magazine.is_empty():
		for entry in magazine.unload_all_entries():
			_bag_append(int(entry.get("id", Magazine.EMPTY)), entry.get("temp", 0.0))
	if not discard.is_empty():
		_sync_temp_arrays()
		for i in discard.size():
			_bag_append(discard[i], discard_temp[i] if i < discard_temp.size() else 0.0)
		discard.clear()
		discard_temp.clear()



func _reset_fire_session() -> void:
	## 仅清射击队列；枪口效果跨金色额外轮保留，胜败/新波由 _reset_muzzle 清；平时靠持续时间到期。
	## 保留 last_shot_* / last_fired_slot / last_blank_skip_steps 供 UI 播完末发；下一发开火时会重写。
	_fire_queue.clear()
	_fire_damages.clear()
	_fire_index = 0
	_fire_total_damage = 0
	_paced_shot.clear()



func muzzle_status_parts() -> PackedStringArray:
	## UI 用：当前枪口已挂效果（中文短名）。
	var parts: PackedStringArray = PackedStringArray()
	if _muzzle_pierce:
		parts.append("穿甲")
	if _muzzle_gas:
		parts.append("汽油")
	if _muzzle_fire:
		parts.append("火焰")
	if _muzzle_water:
		parts.append("水")
	if _muzzle_thunder:
		parts.append("雷")
	if _muzzle_echo:
		parts.append("回声")
	if _muzzle_explosive:
		parts.append("炸药")
	if _muzzle_lifesteal > 0:
		parts.append("吸血")
	if _muzzle_wrath > 0:
		parts.append("愤怒")
	if _muzzle_pride > 0:
		parts.append("傲慢")
	if _muzzle_greed > 0:
		parts.append("贪婪")
	if _muzzle_lust > 0:
		parts.append("色欲")
	if _muzzle_envy > 0:
		parts.append("嫉妒")
	if _muzzle_gluttony > 0:
		parts.append("暴食")
	if _muzzle_sloth > 0:
		parts.append("懒惰")
	return parts


func muzzle_status_entries() -> Array:
	## UI 倒计时：[{name, remaining(最短层), total, stacks, layers(各层剩余，升序)}]。
	var out: Array = []
	var el: float = CombatConstants.MUZZLE_DURATION_ELEMENT_SEC
	var defs: Array = [
		["穿甲", _muzzle_pierce_layers, el],
		["汽油", _muzzle_gas_layers, el],
		["火焰", _muzzle_fire_layers, el],
		["水", _muzzle_water_layers, el],
		["雷", _muzzle_thunder_layers, el],
		["回声", _muzzle_echo_layers, el],
		["炸药", _muzzle_explosive_layers, el],
		["吸血", _muzzle_lifesteal_layers, CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC],
		["愤怒", _muzzle_wrath_layers, CombatConstants.MUZZLE_DURATION_WRATH_SEC],
		["傲慢", _muzzle_pride_layers, CombatConstants.MUZZLE_DURATION_PRIDE_SEC],
		["贪婪", _muzzle_greed_layers, CombatConstants.MUZZLE_DURATION_GREED_SEC],
		["色欲", _muzzle_lust_layers, CombatConstants.MUZZLE_DURATION_LUST_SEC],
		["嫉妒", _muzzle_envy_layers, CombatConstants.MUZZLE_DURATION_ENVY_SEC],
		["暴食", _muzzle_gluttony_layers, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC],
		["懒惰", _muzzle_sloth_layers, CombatConstants.MUZZLE_DURATION_SLOTH_SEC],
	]
	for d in defs:
		var layers: Array = d[1]
		if layers.is_empty():
			continue
		var sorted: Array = layers.duplicate()
		sorted.sort()
		out.append({"name": d[0], "remaining": float(sorted[0]), "total": float(d[2]), "stacks": layers.size(), "layers": sorted})
	return out


static func format_muzzle_countdown(entry: Dictionary) -> String:
	## 芯片文字：「愤怒×2 2.1s」——层数>1 显示 ×N，秒数取最短层。
	var s: String = str(entry.get("name", ""))
	var stacks: int = int(entry.get("stacks", 0))
	if stacks > 1:
		s += "×%d" % stacks
	return s + " %.1fs" % maxf(0.0, float(entry.get("remaining", 0.0)))


func muzzle_status_text() -> String:
	var parts := muzzle_status_parts()
	if parts.is_empty():
		return ""
	return "枪口：" + " · ".join(parts)



func _muzzle_outline_ammo_ids_for_shot() -> Array[int]:
	## 开火前已在枪口的贡献色（罪孽 + 穿甲）；供射线描边。须在本发罪孽入枪口之前取样。
	var out: Array[int] = []
	if _muzzle_wrath > 0:
		out.append(FireResolver.ID_WRATH)
	if _muzzle_pride > 0:
		out.append(FireResolver.ID_PRIDE)
	if _muzzle_greed > 0:
		out.append(FireResolver.ID_GREED)
	if _muzzle_lust > 0:
		out.append(FireResolver.ID_LUST)
	if _muzzle_envy > 0:
		out.append(FireResolver.ID_ENVY)
	if _muzzle_gluttony > 0:
		out.append(FireResolver.ID_GLUTTONY)
	if _muzzle_sloth > 0:
		out.append(FireResolver.ID_SLOTH)
	if _muzzle_pierce:
		out.append(FireResolver.ID_ARMOR_PIERCE)
	if _muzzle_echo:
		out.append(FireResolver.ID_ECHO)
	if _muzzle_explosive:
		out.append(FireResolver.ID_EXPLOSIVE)
	if _muzzle_lifesteal > 0:
		out.append(FireResolver.ID_LIFESTEAL)
	return out


func muzzle_outgoing_multiplier() -> float:
	## UI / 测试：当前输出罪孽倍率（愤怒×傲慢相乘）。
	return _outgoing_sin_multiplier()


func muzzle_incoming_multiplier() -> float:
	## UI / 测试：傲慢抬高的受伤倍率。
	return _incoming_pride_multiplier()


static func _format_damage_mult(m: float) -> String:
	var r := snappedf(m, 0.01)
	if is_equal_approx(r, float(int(round(r)))):
		return "×%d" % int(round(r))
	return "×%.2f" % r


func muzzle_damage_tip_text() -> String:
	## 枪口悬停/长按：玩家可读的伤害修正说明；结算侧四舍五入。
	var lines: PackedStringArray = PackedStringArray()
	lines.append("枪口伤害修正")
	var wrath := _muzzle_wrath
	var pride := _muzzle_pride
	var greed := _muzzle_greed
	var out_m := _outgoing_sin_multiplier()
	var in_m := _incoming_pride_multiplier()
	var has_dmg_mod := wrath > 0 or pride > 0
	if wrath > 0:
		var wm := float(1 + wrath)
		lines.append("愤怒×%d：输出 %s（每层 +100%%）" % [wrath, _format_damage_mult(wm)])
	if pride > 0:
		lines.append("傲慢×%d：输出 %s（每层 +25%%；受伤同乘）" % [pride, _format_damage_mult(in_m)])
	if has_dmg_mod:
		lines.append("合成输出倍率：%s" % _format_damage_mult(out_m))
		lines.append("结算：底伤×倍率后四舍五入为整数")
		var sample_raw := 3
		var sample := _scale_outgoing_damage(sample_raw)
		lines.append("例：底伤 %d → 实际 %d" % [sample_raw, sample])
	else:
		lines.append("当前无修正（×1）")
		lines.append("结算：无倍率，底伤不变")
	if greed > 0:
		lines.append("贪婪×%d：造成伤害时每层 30%% 掉等额金（不改倍率）· 最短层剩余 %.1f 秒" % [greed, _muzzle_greed_t])
	if wrath > 0:
		lines.append("愤怒最短层剩余 %.1f 秒" % _muzzle_wrath_t)
	if pride > 0:
		lines.append("傲慢剩余 %.1f 秒（每层独立，满时长 %.0f 秒）" % [_muzzle_pride_t, CombatConstants.MUZZLE_DURATION_PRIDE_SEC])
	var elems: PackedStringArray = PackedStringArray()
	if _muzzle_pierce:
		elems.append("穿甲%.1fs" % _muzzle_pierce_t)
	if _muzzle_gas:
		elems.append("汽油%.1fs" % _muzzle_gas_t)
	if _muzzle_fire:
		elems.append("火焰%.1fs" % _muzzle_fire_t)
	if _muzzle_water:
		elems.append("水%.1fs" % _muzzle_water_t)
	if _muzzle_thunder:
		elems.append("雷%.1fs" % _muzzle_thunder_t)
	if _muzzle_echo:
		elems.append("回声%.1fs" % _muzzle_echo_t)
	if _muzzle_explosive:
		elems.append("炸药%.1fs" % _muzzle_explosive_t)
	if not elems.is_empty():
		lines.append("元素附带：%s（不改倍率）" % " · ".join(elems))
	if _muzzle_pierce:
		lines.append("穿甲：击穿怪物；首个全伤，之后每穿一个 -1，减到 0 为止")
	if _muzzle_echo:
		lines.append("回声：每发弹药结算两次（双发，均吃当前枪口）· 剩余 %.1f 秒" % _muzzle_echo_t)
	if _muzzle_explosive:
		lines.append("炸药：打已燃烧目标 → 目标及左右各 N 格 3 倍伤（N=底伤-2，至少1）· 剩余 %.1f 秒" % _muzzle_explosive_t)
	if _muzzle_lifesteal > 0:
		var chance: float = minf(1.0, float(_muzzle_lifesteal) * CombatConstants.LIFESTEAL_CHANCE_PER_STACK)
		lines.append("吸血×%d：每击 %.0f%% 概率恢复本次伤害的 %.0f%% · 最短层剩余 %.1f 秒" % [
			_muzzle_lifesteal, chance * 100.0, CombatConstants.LIFESTEAL_HEAL_RATIO * 100.0, _muzzle_lifesteal_t
		])
	return "\n".join(lines)


func _reset_muzzle() -> void:
	## 清全部元素枪口层（胜/败/新波/新开）；平时靠每层计时自然到期。
	_muzzle_pierce_layers.clear()
	_muzzle_gas_layers.clear()
	_muzzle_fire_layers.clear()
	_muzzle_water_layers.clear()
	_muzzle_thunder_layers.clear()
	_muzzle_echo_layers.clear()
	_muzzle_explosive_layers.clear()
	_muzzle_lifesteal_layers.clear()


func _clear_turn_sin_muzzle() -> void:
	## 兼容旧调用名：立即清愤怒/贪婪层；傲慢保留。通常由 tick_muzzle_durations 逐层到期。
	if _muzzle_wrath > 0 or _muzzle_greed > 0:
		_log("枪口：愤怒/贪婪清除（傲慢×%d 保留）。" % _muzzle_pride)
	_muzzle_wrath_layers.clear()
	_muzzle_greed_layers.clear()


func _clear_all_sin_muzzle(include_pride: bool = true) -> void:
	## 战斗结束/新开/下一波：清全部罪孽枪口层。include_pride 保留兼容；始终清零。
	_muzzle_wrath_layers.clear()
	_muzzle_greed_layers.clear()
	_muzzle_pride_layers.clear()
	_muzzle_lust_layers.clear()
	_muzzle_envy_layers.clear()
	_muzzle_gluttony_layers.clear()
	_muzzle_sloth_layers.clear()
	player_confuse_remaining = 0.0
	gluttony_self_dot_remaining = 0.0
	sloth_fire_penalty_remaining = 0.0
	fire_lock_remaining = 0.0
	_gluttony_heal_budget = 0.0
	last_non_sin_ammo_id = -1
	if not include_pride:
		pass


func tick_muzzle_durations(delta_sec: float) -> bool:
	## v0.3.7：每层独立扣减；到期只掉那一层，其它层继续。返回是否有层数/状态变化。
	if delta_sec <= 0.0 or reward_pending:
		return false
	if phase == Phase.WON or phase == Phase.LOST:
		return false
	var changed := false
	changed = _tick_muzzle_named_layers(_muzzle_pierce_layers, delta_sec, "穿甲") or changed
	changed = _tick_muzzle_named_layers(_muzzle_gas_layers, delta_sec, "汽油") or changed
	changed = _tick_muzzle_named_layers(_muzzle_fire_layers, delta_sec, "火焰") or changed
	changed = _tick_muzzle_named_layers(_muzzle_water_layers, delta_sec, "水") or changed
	changed = _tick_muzzle_named_layers(_muzzle_thunder_layers, delta_sec, "雷") or changed
	changed = _tick_muzzle_named_layers(_muzzle_echo_layers, delta_sec, "回声") or changed
	changed = _tick_muzzle_named_layers(_muzzle_explosive_layers, delta_sec, "炸药") or changed
	changed = _tick_muzzle_named_layers(_muzzle_lifesteal_layers, delta_sec, "吸血") or changed
	changed = _tick_muzzle_named_layers(_muzzle_wrath_layers, delta_sec, "愤怒") or changed
	changed = _tick_muzzle_named_layers(_muzzle_pride_layers, delta_sec, "傲慢") or changed
	changed = _tick_muzzle_named_layers(_muzzle_greed_layers, delta_sec, "贪婪") or changed
	changed = _tick_muzzle_named_layers(_muzzle_lust_layers, delta_sec, "色欲") or changed
	changed = _tick_muzzle_named_layers(_muzzle_envy_layers, delta_sec, "嫉妒") or changed
	changed = _tick_muzzle_named_layers(_muzzle_gluttony_layers, delta_sec, "暴食") or changed
	changed = _tick_muzzle_named_layers(_muzzle_sloth_layers, delta_sec, "懒惰") or changed
	return changed


func _tick_muzzle_named_layers(layers: Array, delta_sec: float, label: String) -> bool:
	if layers.is_empty():
		return false
	var before: int = layers.size()
	var expired: int = _muzzle_tick_layers(layers, delta_sec)
	if expired <= 0:
		return false
	if layers.is_empty():
		_log("枪口【%s】全部层到期（曾 ×%d）。" % [label, before])
	else:
		_log("枪口【%s】%d 层到期 → 剩余 ×%d。" % [label, expired, layers.size()])
	return true


func _apply_sin_choice(sin_ammo_id: int, refill_bag: bool = true) -> void:
	if not _is_opening_sin_id(sin_ammo_id):
		sin_ammo_id = FireResolver.ID_WRATH
	selected_sin_ammo_id = sin_ammo_id
	if refill_bag:
		# 开局选罪孽：基准 10+5，不计入战斗内重置加成
		bag_reset_count = 0
		_fill_starter_bag()
		_shuffle_bag()
		_snapshot_combat_bag_baseline()
		_emit()


static func _normalize_temp_for(ammo_id: int, temporary) -> float:
	## v0.4.20：幽灵永远是临时弹——任何路径传入「永久/0」都改成整段 GHOST_TTL，不会变永久。
	var tv: float = Magazine.temp_value(temporary)
	if ammo_id == FireResolver.ID_GHOST and tv <= 0.0:
		tv = CombatConstants.GHOST_TTL_SEC
	return tv


func _bag_append(ammo_id: int, temporary = false) -> void:
	bag.append(ammo_id)
	var tv: float = _normalize_temp_for(ammo_id, temporary)
	bag_temp.append(tv)
	hooks.emit_hook(&"on_bag_enter", {"cs": self, "ammo_id": ammo_id, "temp_life": tv, "temporary": tv > 0.0})


func _discard_append(ammo_id: int, temporary = false) -> void:
	discard.append(ammo_id)
	discard_temp.append(_normalize_temp_for(ammo_id, temporary))


func _sync_temp_arrays() -> void:
	## 兜底：保证 temp 数组与 bag/discard 等长（旧路径漏标时当永久弹）。
	while bag_temp.size() < bag.size():
		bag_temp.append(_normalize_temp_for(int(bag[bag_temp.size()]), false))
	while bag_temp.size() > bag.size():
		bag_temp.pop_back()
	while discard_temp.size() < discard.size():
		discard_temp.append(_normalize_temp_for(int(discard[discard_temp.size()]), false))
	while discard_temp.size() > discard.size():
		discard_temp.pop_back()


func _fill_starter_bag(extra_sin: int = 0) -> void:
	## 灌入 10 平庸 + 5 本局罪孽 + extra_sin 发临时额外罪孽（半透明）。
	bag.clear()
	bag_temp.clear()
	for _i in CombatConstants.STARTER_WHITE_COUNT:
		_bag_append(CombatConstants.WHITE_AMMO_ID, false)
	for _i in CombatConstants.STARTER_SIN_COUNT:
		_bag_append(selected_sin_ammo_id, false)
	for _i in maxi(extra_sin, 0):
		_bag_append(selected_sin_ammo_id, true)


func _counts_as_permanent(ammo_id: int, temporary) -> bool:
	## 永久拥有：非空、非衍生物、没有剩余 TTL。
	if ammo_id == Magazine.EMPTY:
		return false
	if DataRegistry.is_ammo_ephemeral(ammo_id):
		return false
	return Magazine.temp_value(temporary) <= 0.0


func _note_baseline_add(ammo_id: int, temporary) -> void:
	if _counts_as_permanent(ammo_id, temporary):
		_combat_bag_baseline.append(ammo_id)


func _baseline_remove_one(ammo_id: int) -> void:
	var k: int = _combat_bag_baseline.find(ammo_id)
	if k >= 0:
		_combat_bag_baseline.remove_at(k)


func _snapshot_combat_bag_baseline() -> void:
	## 永久构筑 = 袋 + 膛 + 弃牌里的永久弹（跳过 ephemeral 与带 TTL 的临时弹）。
	## 只拍袋会把正在膛里/弃牌堆里的永久弹从基线抹掉，下次袋空重置就把它们丢了。
	_combat_bag_baseline.clear()
	_sync_temp_arrays()
	for i in bag.size():
		var id: int = int(bag[i])
		var tv = bag_temp[i] if i < bag_temp.size() else 0.0
		if _counts_as_permanent(id, tv):
			_combat_bag_baseline.append(id)
	if magazine != null:
		for s in magazine.slots.size():
			var mid: int = int(magazine.slots[s])
			if _counts_as_permanent(mid, magazine.slot_temp_life(s)):
				_combat_bag_baseline.append(mid)
	for i in discard.size():
		var did: int = int(discard[i])
		var dv = discard_temp[i] if i < discard_temp.size() else 0.0
		if _counts_as_permanent(did, dv):
			_combat_bag_baseline.append(did)


func _strip_temporary_ammo_from_bag() -> void:
	## 去掉袋内临时额外罪孽（半透明），保留永久弹。
	_sync_temp_arrays()
	var i := bag.size() - 1
	while i >= 0:
		if Magazine.temp_value(bag_temp[i]) > 0.0:
			bag.remove_at(i)
			bag_temp.remove_at(i)
		i -= 1


func _extract_ghosts_from_bag_and_discard() -> Array:
	## 从袋/弃牌取出幽灵（不碰弹夹），供战斗内重置后放回袋。
	## v0.4.20：返回各自剩余 TTL（秒）；已到期（≤0）的直接丢掉，不再「只数个数→放回成永久弹」。
	var lives: Array = []
	_sync_temp_arrays()
	var i := bag.size() - 1
	while i >= 0:
		if int(bag[i]) == FireResolver.ID_GHOST:
			var tv: float = Magazine.temp_value(bag_temp[i]) if i < bag_temp.size() else 0.0
			bag.remove_at(i)
			if i < bag_temp.size():
				bag_temp.remove_at(i)
			if tv > 0.0:
				lives.append(tv)
		i -= 1
	i = discard.size() - 1
	while i >= 0:
		if int(discard[i]) == FireResolver.ID_GHOST:
			var dv: float = Magazine.temp_value(discard_temp[i]) if i < discard_temp.size() else 0.0
			discard.remove_at(i)
			if i < discard_temp.size():
				discard_temp.remove_at(i)
			if dv > 0.0:
				lives.append(dv)
		i -= 1
	return lives


func _shuffle_bag() -> void:
	_sync_temp_arrays()
	# Fisher–Yates 同步打乱 bag 与 bag_temp
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp_id := bag[i]
		bag[i] = bag[j]
		bag[j] = tmp_id
		var tmp_t = bag_temp[i]
		bag_temp[i] = bag_temp[j]
		bag_temp[j] = tmp_t


func _bag_reset_pool(next_reset_count: int) -> Array:
	## v0.3.6 纯函数：第 next_reset_count 次战斗内重置后「袋里应有」的弹 [{id,temp}]（不改状态）。
	## 整个弹药池 = 构筑基线 + N 临时罪孽（N=重置次数）；**转轮里还在膛的弹算作已从新池抽出**，
	## 从袋里扣掉，避免膛内弹被复制一份（旧 bug：膛内 6 发 + 整份基线 → 罪孽最多多出 6 颗）。
	var pool: Array = []
	if _combat_bag_baseline.is_empty():
		for _i in CombatConstants.STARTER_WHITE_COUNT:
			pool.append({"id": CombatConstants.WHITE_AMMO_ID, "temp": false})
		for _i in CombatConstants.STARTER_SIN_COUNT:
			pool.append({"id": selected_sin_ammo_id, "temp": false})
	else:
		for id in _combat_bag_baseline:
			pool.append({"id": int(id), "temp": false})
	# v0.3.8：袋重置只还基础池；临时罪孽改为「每吃一次三罪孽惩罚 +1」（见 _spawn_penalty_temp_sin），不再随重置次数加。
	if magazine != null:
		for i in magazine.slots.size():
			var mid: int = int(magazine.slots[i])
			if mid == Magazine.EMPTY or mid == FireResolver.ID_GHOST:
				continue
			var mt: bool = magazine.is_slot_temporary(i)
			if mt:
				continue  # 临时罪孽不属于基础池
			var k: int = _pool_find(pool, mid, mt)
			if k < 0:
				k = _pool_find(pool, mid, not mt)
			if k >= 0:
				pool.remove_at(k)
	return pool


func _pool_find(pool: Array, id: int, temp: bool) -> int:
	for k in pool.size():
		if int(pool[k]["id"]) == id and bool(pool[k]["temp"]) == temp:
			return k
	return -1


func _count_ghosts_bag_and_discard() -> int:
	var n := 0
	for x in bag:
		if int(x) == FireResolver.ID_GHOST:
			n += 1
	for x in discard:
		if int(x) == FireResolver.ID_GHOST:
			n += 1
	return n


func can_refill_bag() -> bool:
	## 纯查询：袋空时能否战斗内重置出至少 1 发（不改任何状态）。
	if not bag.is_empty():
		return true
	return (not _bag_reset_pool(bag_reset_count + 1).is_empty()) or _count_ghosts_bag_and_discard() > 0 or count_temporary_in_discard() > 0


func count_temporary_in_discard() -> int:
	var n := 0
	for x in discard_temp:
		if Magazine.temp_value(x) > 0.0:
			n += 1
	return n


func _reset_bag_in_combat() -> bool:
	## 战斗内袋重置：次数 +1；整池 = 构筑基线 + N 临时罪孽（扣除仍在膛内的弹）；幽灵保留至波/战斗结束。
	## 重置后袋若仍为空（膛内已占满整池）则不重置、不计次数，防止反复触发叠罪孽。
	var pool: Array = _bag_reset_pool(bag_reset_count + 1)
	if pool.is_empty() and _count_ghosts_bag_and_discard() == 0 and count_temporary_in_discard() == 0:
		return false
	bag_reset_count += 1
	var ghost_lives: Array = _extract_ghosts_from_bag_and_discard()
	# v0.3.8：弃牌里仍在寿命内的临时罪孽带回新袋（各自计时继续）
	var live_temps: Array = []
	_sync_temp_arrays()
	for i in discard.size():
		var tv: float = Magazine.temp_value(discard_temp[i])
		if tv > 0.0:
			live_temps.append({"id": int(discard[i]), "temp": tv})
	bag.clear()
	bag_temp.clear()
	discard.clear()
	discard_temp.clear()
	for entry in pool:
		_bag_append(int(entry["id"]), entry["temp"])
	for entry in live_temps:
		_bag_append(int(entry["id"]), entry["temp"])
	for gl in ghost_lives:
		_bag_append(FireResolver.ID_GHOST, float(gl))  # 各自剩余 TTL 继续倒计时
	_shuffle_bag()
	return true


func count_permanent_owned() -> int:
	## 袋 + 膛 + 弃牌里的永久弹（不含幽灵/小石头/带 TTL 的临时弹）。
	var n := 0
	_sync_temp_arrays()
	for i in bag.size():
		var tv = bag_temp[i] if i < bag_temp.size() else 0.0
		if _counts_as_permanent(int(bag[i]), tv):
			n += 1
	for i in discard.size():
		var dv = discard_temp[i] if i < discard_temp.size() else 0.0
		if _counts_as_permanent(int(discard[i]), dv):
			n += 1
	if magazine != null:
		for s in magazine.slots.size():
			var mid: int = int(magazine.slots[s])
			if _counts_as_permanent(mid, magazine.slot_temp_life(s)):
				n += 1
	return n


func apply_shop_session(new_ids: Array, new_temps: Array, new_gold: int) -> void:
	## 离店写回：按商店袋的顺序还原，临时 TTL 跟着原下标走；新买的是永久弹。
	## 膛和弃牌不动。基线重拍成「袋+膛+弃」里的全部永久弹，避免重置时丢掉没在袋里的那部分。
	gold = new_gold
	bag.clear()
	bag_temp.clear()
	for i in new_ids.size():
		var tv = new_temps[i] if i < new_temps.size() else 0.0
		_bag_append(int(new_ids[i]), tv)
	_snapshot_combat_bag_baseline()
	_log("离开地图商店（金 %d，袋 %d 发，永久合计 %d）。" % [gold, bag.size(), count_permanent_owned()])
	_emit()


func total_ammo_count(ammo_id: int) -> int:
	## 测试/UI：袋+膛+弃牌中某弹总数。
	var n := 0
	for x in bag:
		if int(x) == ammo_id:
			n += 1
	for x in discard:
		if int(x) == ammo_id:
			n += 1
	if magazine != null:
		for x in magazine.slots:
			if int(x) == ammo_id:
				n += 1
	return n


func is_bag_index_temporary(index: int) -> bool:
	if index < 0 or index >= bag_temp.size() or index >= bag.size():
		return false
	return Magazine.temp_value(bag_temp[index]) > 0.0


func count_temporary_in_bag() -> int:
	var n := 0
	for t in bag_temp:
		if Magazine.temp_value(t) > 0.0:
			n += 1
	return n


func _clear_combat_bonus_ammo() -> void:
	## 失败：额外罪孽与临时标记清零，袋回 10+5。
	bag_reset_count = 0
	_fill_starter_bag(0)
	_shuffle_bag()
	discard.clear()
	discard_temp.clear()
	_snapshot_combat_bag_baseline()


func _auto_reset_bag_if_empty_at_turn_start() -> bool:
	## 兼容旧名：袋空立刻战斗内重置（见 ensure_bag_refilled_if_empty）。
	return ensure_bag_refilled_if_empty()


func ensure_bag_refilled_if_empty() -> bool:
	## 袋一空就补：立刻战斗内重置（构筑基线 + N 临时罪孽，保留幽灵）。弃牌并入重置逻辑。
	if not bag.is_empty():
		return false
	if not _reset_bag_in_combat():
		return false
	needs_reshuffle_next_load = false
	_log("弹药袋已空：立刻战斗内重置（构筑 %d + 临时罪孽 ×%d，第 %d 次）。" % [
		_combat_bag_baseline.size(), bag_reset_count, bag_reset_count
	])
	return true




func choose_sin(sin_ammo_id: int) -> void:
	## UI：开局选定罪孽后灌入 10 平庸 + 5 罪孽（不含战斗内重置加成）。
	_apply_sin_choice(sin_ammo_id, true)
	_log("选定罪孽：%s。弹药袋：平庸 ×%d + %s ×%d。" % [
		_ammo_name(selected_sin_ammo_id), CombatConstants.STARTER_WHITE_COUNT,
		_ammo_name(selected_sin_ammo_id), CombatConstants.STARTER_SIN_COUNT
	])


func _outgoing_sin_multiplier() -> float:
	## 愤怒：每层 +100% → ×(1+stacks)；傲慢：每层 +25% → ×(1+0.25*stacks)；两者相乘。
	var m := 1.0
	if _muzzle_wrath > 0:
		m *= float(1 + _muzzle_wrath)
	if _muzzle_pride > 0:
		m *= 1.0 + 0.25 * float(_muzzle_pride)
	return m


func _incoming_pride_multiplier() -> float:
	if _muzzle_pride <= 0:
		return 1.0
	return 1.0 + 0.25 * float(_muzzle_pride)


func _scale_outgoing_damage(raw: int) -> int:
	## 罪孽输出倍率后四舍五入为整数伤害（与枪口提示一致）；再加正义永久加伤。
	if raw <= 0:
		return 0
	var scaled: int = int(round(float(raw) * _outgoing_sin_multiplier()))
	scaled += justice_damage_bonus
	return maxi(scaled, 0)


func _mount_muzzle_from(flags: Dictionary) -> void:
	## 元素枪口：最多 1 层；再挂则刷新该层满时长（不叠层）。
	var dur: float = CombatConstants.MUZZLE_DURATION_ELEMENT_SEC
	if bool(flags.get("pierce", false)):
		if not _muzzle_pierce:
			_log("  → 枪口【穿甲】（最多 1 层，%.1f 秒）" % dur)
		_muzzle_add_layer(_muzzle_pierce_layers, dur, 1)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "pierce", "stacks_after": 1})
	if bool(flags.get("gas", false)):
		_muzzle_add_layer(_muzzle_gas_layers, dur, 1)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "gas", "stacks_after": 1})
	if bool(flags.get("fire", false)):
		var was_fire: bool = _muzzle_fire
		_muzzle_add_layer(_muzzle_fire_layers, dur, 1)
		if not was_fire:
			_log("  → 枪口【火焰】（最多 1 层，%.1f 秒）" % dur)
		else:
			_log("  → 枪口【火焰】刷新 %.1f 秒" % dur)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "flame", "stacks_after": 1})
	if bool(flags.get("water", false)):
		_muzzle_add_layer(_muzzle_water_layers, dur, 1)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "water", "stacks_after": 1})
	if bool(flags.get("thunder", false)):
		_muzzle_add_layer(_muzzle_thunder_layers, dur, 1)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "thunder", "stacks_after": 1})
	if bool(flags.get("echo", false)):
		var was: bool = _muzzle_echo
		_muzzle_add_layer(_muzzle_echo_layers, dur, 1)
		if not was:
			_log("  → 枪口【回声】（最多 1 层，%.1f 秒；窗内每发结算两次）" % dur)
		else:
			_log("  → 枪口【回声】刷新 %.1f 秒" % dur)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "echo", "stacks_after": 1})
	if bool(flags.get("explosive", false)):
		var was_x: bool = _muzzle_explosive
		_muzzle_add_layer(_muzzle_explosive_layers, dur, 1)
		if not was_x:
			_log("  → 枪口【炸药】（最多 1 层，%.1f 秒；打燃烧目标 3 倍溅射）" % dur)
		else:
			_log("  → 枪口【炸药】刷新 %.1f 秒" % dur)
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "explosive", "stacks_after": 1})
	if bool(flags.get("lifesteal", false)):
		_muzzle_add_layer(_muzzle_lifesteal_layers, CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC)
		_log("  → 枪口【吸血】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_lifesteal, CombatConstants.MUZZLE_DURATION_LIFESTEAL_SEC, _muzzle_lifesteal_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "lifesteal", "stacks_after": _muzzle_lifesteal})


func _mount_sin_muzzle_from(flags: Dictionary) -> void:
	## v0.3.7：每层独立计时；再挂追加新层（旧层不刷新）。傲慢也计时（12 秒）。
	if bool(flags.get("wrath", false)):
		_muzzle_add_layer(_muzzle_wrath_layers, CombatConstants.MUZZLE_DURATION_WRATH_SEC)
		_log("  → 枪口【愤怒】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_wrath, CombatConstants.MUZZLE_DURATION_WRATH_SEC, _muzzle_wrath_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "wrath", "stacks_after": _muzzle_wrath})
	if bool(flags.get("pride", false)):
		_muzzle_add_layer(_muzzle_pride_layers, CombatConstants.MUZZLE_DURATION_PRIDE_SEC)
		_log("  → 枪口【傲慢】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_pride, CombatConstants.MUZZLE_DURATION_PRIDE_SEC, _muzzle_pride_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "pride", "stacks_after": _muzzle_pride})
	if bool(flags.get("greed", false)):
		_muzzle_add_layer(_muzzle_greed_layers, CombatConstants.MUZZLE_DURATION_GREED_SEC)
		_log("  → 枪口【贪婪】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_greed, CombatConstants.MUZZLE_DURATION_GREED_SEC, _muzzle_greed_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "greed", "stacks_after": _muzzle_greed})
	if bool(flags.get("lust", false)):
		_muzzle_add_layer(_muzzle_lust_layers, CombatConstants.MUZZLE_DURATION_LUST_SEC)
		_log("  → 枪口【色欲】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_lust, CombatConstants.MUZZLE_DURATION_LUST_SEC, _muzzle_lust_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "lust", "stacks_after": _muzzle_lust})
	if bool(flags.get("envy", false)):
		_muzzle_add_layer(_muzzle_envy_layers, CombatConstants.MUZZLE_DURATION_ENVY_SEC)
		_log("  → 枪口【嫉妒】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_envy, CombatConstants.MUZZLE_DURATION_ENVY_SEC, _muzzle_envy_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "envy", "stacks_after": _muzzle_envy})
	if bool(flags.get("gluttony", false)):
		_muzzle_add_layer(_muzzle_gluttony_layers, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC)
		_log("  → 枪口【暴食】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_gluttony, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC, _muzzle_gluttony_t
		])
		_seed_gluttony_heal_budget()
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "gluttony", "stacks_after": _muzzle_gluttony})
	if bool(flags.get("sloth", false)):
		_muzzle_add_layer(_muzzle_sloth_layers, CombatConstants.MUZZLE_DURATION_SLOTH_SEC)
		_log("  → 枪口【懒惰】+1（现 %d，新层 %.1f 秒，最短 %.1f）" % [
			_muzzle_sloth, CombatConstants.MUZZLE_DURATION_SLOTH_SEC, _muzzle_sloth_t
		])
		hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": "sloth", "stacks_after": _muzzle_sloth})


func _count_ammo_in(ids: Array, ammo_id: int) -> int:
	var n := 0
	for x in ids:
		if int(x) == ammo_id:
			n += 1
	return n


func _resolve_sin_pack_on_load(loaded: Array) -> void:
	## 一次装填同种罪孽 ≥3 发 → 触发负面（口头：3 个或以上；含手装提交/整匣装完）。
	var wrath_n := _count_ammo_in(loaded, FireResolver.ID_WRATH)
	var pride_n := _count_ammo_in(loaded, FireResolver.ID_PRIDE)
	var greed_n := _count_ammo_in(loaded, FireResolver.ID_GREED)
	var lust_n := _count_ammo_in(loaded, FireResolver.ID_LUST)
	var envy_n := _count_ammo_in(loaded, FireResolver.ID_ENVY)
	var glut_n := _count_ammo_in(loaded, FireResolver.ID_GLUTTONY)
	var sloth_n := _count_ammo_in(loaded, FireResolver.ID_SLOTH)
	if wrath_n >= 3:
		_apply_player_damage(6, "愤怒")
		_log("罪孽[愤怒]：本匣愤怒 ×%d（≥3）→ 玩家自伤 6（HP %d/%d）。" % [wrath_n, player_hp, player_max_hp])
		if player_hp <= 0:
			_lose_hp()
	if pride_n >= 3:
		_pull_enemies_to_face(pride_n)
	if greed_n >= 3:
		gold -= 6
		_log("罪孽[贪婪]：本匣贪婪 ×%d（≥3）→ 金币 -6（现 %d）。" % [greed_n, gold])
	if lust_n >= 3:
		player_confuse_remaining = maxf(player_confuse_remaining, CombatConstants.LUST_SELF_CONFUSE_SEC)
		_log("罪孽[色欲]：本匣色欲 ×%d（≥3）→ 玩家混乱 %.1fs（期间攻击打自己）。" % [
			lust_n, player_confuse_remaining
		])
		hooks.emit_hook(&"on_player_confuse", {"cs": self, "remaining": player_confuse_remaining})
	if envy_n >= 3:
		_envy_discard_permanent_nonsin(CombatConstants.ENVY_THREE_SIN_DISCARD)
	if glut_n >= 3:
		# 持续掉血：挂一段自伤 DoT（与 tick_dot 同频）
		gluttony_self_dot_remaining = maxf(gluttony_self_dot_remaining, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC)
		_log("罪孽[暴食]：本匣暴食 ×%d（≥3）→ 持续掉血 %.1fs。" % [glut_n, gluttony_self_dot_remaining])
		hooks.emit_hook(&"on_gluttony_self_dot", {"cs": self, "remaining": gluttony_self_dot_remaining})
	if sloth_n >= 3:
		sloth_fire_penalty_remaining = maxf(sloth_fire_penalty_remaining, CombatConstants.SLOTH_FIRE_PENALTY_SEC)
		_log("罪孽[懒惰]：本匣懒惰 ×%d（≥3）→ 射速−50%% 窗 %.1fs。" % [
			sloth_n, sloth_fire_penalty_remaining
		])
		hooks.emit_hook(&"on_sloth_fire_penalty", {"cs": self, "remaining": sloth_fire_penalty_remaining})
	# v0.4.0：三罪孽惩罚不再加临时罪孽；临时罪只走「装入时 20%」。


func _spawn_penalty_temp_sin(sin_id: int) -> void:
	_bag_append(sin_id, CombatConstants.TEMP_SIN_LIFETIME_SEC)
	penalty_temp_sins_spawned += 1
	_log("罪孽惩罚：袋内 +1 颗临时%s（%.0f 秒后消失）。" % [_ammo_name(sin_id), CombatConstants.TEMP_SIN_LIFETIME_SEC])



func _is_opening_sin_id(ammo_id: int) -> bool:
	## 开局可选七罪。
	return ammo_id in [
		FireResolver.ID_WRATH, FireResolver.ID_PRIDE, FireResolver.ID_GREED,
		FireResolver.ID_LUST, FireResolver.ID_ENVY, FireResolver.ID_GLUTTONY, FireResolver.ID_SLOTH,
	]


func _is_sin_ammo_id(ammo_id: int) -> bool:
	return DataRegistry.is_sin_ammo(ammo_id)


func _apply_justice_strip_on_load(resolved: int) -> int:
	## 装填正义：卸除转轮内已装罪孽（退回袋，保留临时寿命）；每颗本战斗伤害+2。返回卸除数。
	if resolved != FireResolver.ID_JUSTICE or magazine == null:
		return 0
	var stripped := 0
	for i in magazine.slots.size():
		var aid: int = int(magazine.slots[i])
		if aid == Magazine.EMPTY or not _is_sin_ammo_id(aid):
			continue
		var tv: float = magazine.slot_temp_life(i)
		magazine.set_slot(i, Magazine.EMPTY, false)
		_bag_append(aid, tv)
		justice_damage_bonus += 2
		stripped += 1
	if stripped > 0:
		_log("正义弹药：卸除已装罪孽 ×%d → 本战斗伤害 +%d（现 +%d）。" % [
			stripped, stripped * 2, justice_damage_bonus
		])
		hooks.emit_hook(&"on_justice_strip", {
			"cs": self, "stripped": stripped, "bonus_after": justice_damage_bonus
		})
	return stripped


func _try_spawn_temp_sin_on_load(resolved: int) -> void:
	## v0.4.0：装入罪孽时 LOAD_TEMP_SIN_CHANCE（v0.4.20 起 20%）袋内 +1 同种临时罪孽（三罪孽惩罚不再加）。
	if not _is_opening_sin_id(resolved):
		return
	if rng.randf() >= CombatConstants.LOAD_TEMP_SIN_CHANCE:
		return
	_bag_append(resolved, CombatConstants.TEMP_SIN_LIFETIME_SEC)
	load_temp_sins_spawned += 1
	_log("装入%s：%d%% 触发 → 袋内 +1 临时（%.0fs）。" % [_ammo_name(resolved), int(round(CombatConstants.LOAD_TEMP_SIN_CHANCE * 100.0)), CombatConstants.TEMP_SIN_LIFETIME_SEC])
	hooks.emit_hook(&"on_temp_sin_spawn", {"cs": self, "sin_id": resolved, "source": "load33"})


const SIN_PENALTY_THRESHOLD := 3


func _bag_has_ammo(ammo_id: int) -> bool:
	for x in bag:
		if int(x) == ammo_id:
			return true
	return false


func _take_one_ammo_from_bag_by_id(ammo_id: int) -> Dictionary:
	## 从袋中取出指定 id 一发；返回 {ok, id, temp}。
	_sync_temp_arrays()
	for i in bag.size():
		if int(bag[i]) != ammo_id:
			continue
		var tv = bag_temp[i] if i < bag_temp.size() else 0.0
		bag.remove_at(i)
		if i < bag_temp.size():
			bag_temp.remove_at(i)
		hooks.emit_hook(&"on_bag_leave", {"cs": self, "ammo_id": ammo_id, "reason": "insurance_swap"})
		return {"ok": true, "id": ammo_id, "temp": Magazine.temp_value(tv)}
	return {"ok": false, "id": -1, "temp": 0.0}


func _try_insurance_swap_third_sin(resolved: int, raw_temp) -> Dictionary:
	## 若装入 resolved 会使同种罪孽达到 3，且袋中有保险：罪孽退回袋，改装保险。
	## 返回 {ammo_id, temp, swapped}。
	var out := {"ammo_id": resolved, "temp": raw_temp, "swapped": false}
	if not _is_opening_sin_id(resolved):
		return out
	if magazine == null:
		return out
	var already: int = _count_ammo_in(magazine.slots, resolved)
	if already != SIN_PENALTY_THRESHOLD - 1:
		return out
	if not _bag_has_ammo(FireResolver.ID_INSURANCE):
		return out
	var taken: Dictionary = _take_one_ammo_from_bag_by_id(FireResolver.ID_INSURANCE)
	if not bool(taken.get("ok", false)):
		return out
	# 罪孽退回袋（刚抽出来的那发）
	_bag_append(resolved, Magazine.temp_value(raw_temp))
	_log("保险弹药：挡住第 3 颗%s，改装保险（罪孽退回袋）。" % _ammo_name(resolved))
	hooks.emit_hook(&"on_insurance_swap", {"cs": self, "sin_id": resolved})
	return {"ammo_id": FireResolver.ID_INSURANCE, "temp": taken.get("temp", 0.0), "swapped": true}


func _check_sin_threshold_after_insert(resolved: int) -> void:
	## v0.3.5 rush!：每装入 1 发罪孽后数转轮内同种罪孽；数量刚达到 3（2→3）立刻触发三罪孽惩罚。
	## 打掉一些后再装回 3 会再触发；第 4、5 发不重复触发（与旧「一次装填 ≥3 触发一次」一致）。
	if not _is_opening_sin_id(resolved):
		return
	if magazine == null:
		return
	var n: int = _count_ammo_in(magazine.slots, resolved)
	if n != SIN_PENALTY_THRESHOLD:
		return
	_log("罪孽：转轮内 %s 达到 %d 颗 → 触发惩罚。" % [_ammo_name(resolved), n])
	var arr: Array[int] = []
	for _i in n:
		arr.append(resolved)
	_resolve_sin_pack_on_load(arr)
	hooks.emit_hook(&"on_three_sin", {"cs": self, "sin_id": resolved, "count": n})


func sin_count_in_cylinder(ammo_id: int) -> int:
	if magazine == null:
		return 0
	return _count_ammo_in(magazine.slots, ammo_id)


func _pull_enemies_to_face(pride_n: int = 3) -> void:
	## 傲慢装 ≥3：全体敌人尽量贴到玩家面前（格 1、2、3…）。
	var alive: Array = alive_enemies()
	alive.sort_custom(func(a, b): return a.cell < b.cell)
	var next_cell: int = CombatConstants.PLAYER_CELL + 1
	for e in alive:
		if next_cell >= CombatConstants.BOARD_SIZE:
			break
		e.cell = next_cell
		next_cell += 1
		_log("罪孽[傲慢]：%s 被拉至格 %d。" % [e.name_zh, e.cell])
	_log("罪孽[傲慢]：本匣傲慢 ×%d（≥3）→ 敌人拉至面前。" % pride_n)


func _envy_discard_permanent_nonsin(n: int) -> int:
	## 嫉妒三罪：从袋中随机弃掉最多 n 发非罪孽永久弹到弃牌堆。
	_sync_temp_arrays()
	var candidates: Array[int] = []
	for i in bag.size():
		var aid: int = int(bag[i])
		var tv: float = Magazine.temp_value(bag_temp[i] if i < bag_temp.size() else 0.0)
		if tv > 0.0:
			continue
		if _is_sin_ammo_id(aid):
			continue
		candidates.append(i)
	candidates.shuffle()
	var moved := 0
	# 从高下标删，避免打乱未选中的下标：先收集 id 再按 index 降序删
	var pick: Array[int] = []
	for i in mini(n, candidates.size()):
		pick.append(candidates[i])
	pick.sort()
	pick.reverse()
	for i in pick:
		var aid: int = int(bag[i])
		bag.remove_at(i)
		if i < bag_temp.size():
			bag_temp.remove_at(i)
		_discard_append(aid, 0.0)
		hooks.emit_hook(&"on_bag_leave", {"cs": self, "ammo_id": aid, "reason": "envy_discard"})
		moved += 1
	if moved > 0:
		_log("罪孽[嫉妒]：随机弃掉非罪永久弹 ×%d 入弃牌。" % moved)
		hooks.emit_hook(&"on_envy_discard", {"cs": self, "moved": moved})
	else:
		_log("罪孽[嫉妒]：袋中无可弃的非罪永久弹。")
	return moved


func _try_lust_confuse_on_hit(e: EnemyInstance) -> void:
	if e == null or not e.is_alive() or _muzzle_lust <= 0:
		return
	var chance: float = minf(1.0, float(_muzzle_lust) * CombatConstants.LUST_CONFUSE_CHANCE_PER_STACK)
	if rng.randf() >= chance:
		return
	e.apply_confuse(CombatConstants.LUST_CONFUSE_SEC)
	_log("  → 色欲：%s 混乱 %.1fs" % [e.name_zh, e.confuse_remaining])
	hooks.emit_hook(&"on_confuse", {"cs": self, "enemy_id": e.get_instance_id(), "remaining": e.confuse_remaining})


func _try_sloth_slow_on_hit(e: EnemyInstance) -> void:
	if e == null or not e.is_alive() or _muzzle_sloth <= 0:
		return
	e.add_slow_layer(CombatConstants.SLOTH_SLOW_LAYER_SEC)
	_log("  → 懒惰：%s 减速层 ×%d" % [e.name_zh, e.slow_stacks()])
	hooks.emit_hook(&"on_slow", {"cs": self, "enemy_id": e.get_instance_id(), "stacks": e.slow_stacks()})


func _try_envy_copy_on_kill() -> void:
	if _muzzle_envy <= 0 or last_non_sin_ammo_id < 0:
		return
	var chance: float = minf(1.0, float(_muzzle_envy) * CombatConstants.ENVY_COPY_CHANCE_PER_STACK)
	if rng.randf() >= chance:
		return
	var aid: int = last_non_sin_ammo_id
	_bag_append(aid, CombatConstants.ENVY_COPY_TTL_SEC)
	_log("  → 嫉妒：复制上一发非罪[%s] TTL 入袋。" % _ammo_name(aid))
	hooks.emit_hook(&"on_envy_copy", {"cs": self, "ammo_id": aid})


func _try_gluttony_heal_on_kill() -> void:
	if _muzzle_gluttony <= 0:
		return
	if _gluttony_heal_budget < 1.0:
		return
	_gluttony_heal_budget -= 1.0
	_apply_player_heal(CombatConstants.GLUTTONY_HEAL_ON_KILL, "暴食")
	hooks.emit_hook(&"on_gluttony_heal", {"cs": self, "amount": CombatConstants.GLUTTONY_HEAL_ON_KILL})


func _seed_gluttony_heal_budget() -> void:
	## 挂上/沙盒设暴食时立刻给满 1 秒预算（层数×每秒次数），无需先推进战斗时间。
	if _muzzle_gluttony <= 0:
		_gluttony_heal_budget = 0.0
		return
	var cap: float = float(_muzzle_gluttony) * CombatConstants.GLUTTONY_PROCS_PER_SEC_PER_LAYER
	_gluttony_heal_budget = maxf(_gluttony_heal_budget, cap)


func _note_last_non_sin_ammo(ammo_id: int) -> void:
	if ammo_id < 0 or _is_sin_ammo_id(ammo_id):
		return
	last_non_sin_ammo_id = ammo_id


func _enemy_attack_or_confuse(e: EnemyInstance) -> void:
	## 进入射程时：混乱则打邻近怪，否则打玩家。
	if e == null or not e.is_alive():
		return
	if e.confuse_remaining > 0.0:
		var victim: EnemyInstance = _nearest_other_enemy(e)
		if victim != null:
			var dmg: int = maxi(1, int(e.atk))
			var dealt: int = victim.apply_hit(dmg)
			_notify_enemy_damage(victim, dealt, "混乱")
			_log("%s 混乱攻击 %s，造成 %d（HP %d/%d）" % [
				e.name_zh, victim.name_zh, dealt, victim.hp, victim.max_hp
			])
			hooks.emit_hook(&"on_confuse_attack", {
				"cs": self, "attacker_id": e.get_instance_id(), "victim_id": victim.get_instance_id(), "dealt": dealt
			})
			enemy_attacked.emit(e, "confuse")
			return
		_log("%s 混乱但无邻近目标，跳过攻击。" % e.name_zh)
		return
	var incoming: int = int(round(float(e.atk) * _incoming_pride_multiplier()))
	_apply_player_damage(incoming, "")
	enemy_attacked.emit(e, "player")
	_log("%s 攻击玩家，造成 %d（玩家 HP %d/%d · 射程 %d%s）" % [
		e.name_zh, incoming, player_hp, player_max_hp, e.attack_range,
		(" · 傲慢×%d" % _muzzle_pride) if _muzzle_pride > 0 else ""
	])


func _nearest_other_enemy(origin: EnemyInstance) -> EnemyInstance:
	var best: EnemyInstance = null
	var best_d := 9999
	for e in alive_enemies():
		if e == origin:
			continue
		var d: int = absi(e.cell - origin.cell)
		if d < best_d:
			best_d = d
			best = e
	return best


func dot_tick_remaining() -> float:
	return maxf(_dot_timer, 0.0)


func _try_kill_gold_drop(e: EnemyInstance) -> int:
	## 击杀掉金币进现有钱包。木桩不掉。Boss 用更高的必掉额度。
	if e == null or e.is_dummy:
		return 0
	var boss := int(e.def_id) == CombatConstants.SUPER_ZOMBIE_ENEMY_ID
	var chance := CombatConstants.KILL_GOLD_BOSS_DROP_CHANCE if boss else CombatConstants.KILL_GOLD_DROP_CHANCE
	var amount := CombatConstants.KILL_GOLD_BOSS_DROP_AMOUNT if boss else CombatConstants.KILL_GOLD_DROP_AMOUNT
	if (not boss) and kill_gold_chance_override >= 0.0:
		chance = kill_gold_chance_override
	if amount <= 0 or rng.randf() >= chance:
		return 0
	_gold_drop_seq += 1
	var drop_id: int = _gold_drop_seq
	gold_drops.append({
		"id": drop_id,
		"cell": e.cell,
		"remaining": amount,
		"total": amount,
	})
	_log("击杀掉金币 %d（待拾取，钱包仍 %d）。" % [amount, gold])
	gold_drop_spawned.emit(drop_id, e.cell, amount)
	return amount


func pending_gold_total() -> int:
	var n := 0
	for d in gold_drops:
		n += int(d.get("remaining", 0))
	return n


func collect_gold_piece(drop_id: int, piece: int, cell: int = -1) -> int:
	## 金币碰到玩家：入账 piece（不超过该次掉落剩余）。战败后掉落已丢弃则返回 0。
	if piece <= 0 or phase == Phase.LOST:
		return 0
	for i in gold_drops.size():
		var rec: Dictionary = gold_drops[i]
		if int(rec.get("id", -1)) != drop_id:
			continue
		var left: int = int(rec.get("remaining", 0))
		var take: int = mini(piece, left)
		if take <= 0:
			gold_drops.remove_at(i)
			return 0
		left -= take
		rec["remaining"] = left
		gold_drops[i] = rec
		if left <= 0:
			gold_drops.remove_at(i)
		gold += take
		var at: int = cell if cell >= 0 else int(rec.get("cell", -1))
		if at >= 0:
			gold_gained.emit(at, take)
		hooks.emit_hook(&"on_gold_pickup", {"cs": self, "amount": take, "drop_id": drop_id, "cell": at})
		_log("拾取金币 +%d（现 %d）。" % [take, gold])
		_emit()
		return take
	return 0


func abandon_pending_gold() -> void:
	## 战败：没捡到的金币可以消失。
	gold_drops.clear()


func _try_greed_gold_drop(dealt: int, cell: int = -1) -> void:
	if dealt <= 0 or _muzzle_greed <= 0:
		return
	for _i in _muzzle_greed:
		if rng.randf() < 0.30:
			gold += dealt
			_log("  → 贪婪掉金 +%d（现 %d）" % [dealt, gold])
			if cell >= 0:
				gold_gained.emit(cell, dealt)


func _lifesteal_chance() -> float:
	if _muzzle_lifesteal <= 0:
		return 0.0
	return minf(1.0, float(_muzzle_lifesteal) * CombatConstants.LIFESTEAL_CHANCE_PER_STACK)


func _try_lifesteal_heal(dealt: int) -> int:
	## 按层概率触发；成功则恢复 dealt×50%（四舍五入）。返回实际恢复量。
	if dealt <= 0 or _muzzle_lifesteal <= 0:
		return 0
	var chance: float = _lifesteal_chance()
	if rng.randf() >= chance:
		return 0
	var heal: int = int(round(float(dealt) * CombatConstants.LIFESTEAL_HEAL_RATIO))
	if heal <= 0:
		return 0
	return _apply_player_heal(heal, "吸血")


func _apply_player_heal(amount: int, kind: String = "") -> int:
	if amount <= 0:
		return 0
	var before: int = player_hp
	player_hp = mini(player_max_hp, player_hp + amount)
	var gained: int = player_hp - before
	if gained <= 0:
		return 0
	_log("  → %s回复 +%d（HP %d/%d）" % [kind if kind != "" else "治疗", gained, player_hp, player_max_hp])
	player_healed.emit(gained, kind)
	return gained


func _set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(phase)


func _log(text: String) -> void:
	last_log.append(text)
	log_line.emit(text)


func _emit() -> void:
	state_changed.emit()


func _notify_enemy_damage(e: EnemyInstance, amount: int, kind: String = "") -> void:
	if e == null or amount <= 0:
		return
	_record_damage_stat(e, amount)
	enemy_damaged.emit(e.cell, amount, kind)


# ——— v0.4.20 伤害统计（所有对敌伤害都经 _notify_enemy_damage：直击/穿透/散射/爆炸/汽油/燃烧/流血/混乱/幽灵/倾泻…）———

func _record_damage_stat(e: EnemyInstance, amount: int) -> void:
	if amount <= 0:
		return
	if e != null:
		e.dmg_taken_total += amount
	dmg_stats_total += amount
	dmg_stats_hits += 1
	dmg_stats_peak_hit = maxi(dmg_stats_peak_hit, amount)
	dmg_stats_events.append({"t": elapsed_sec, "amount": amount})
	_prune_damage_stats(elapsed_sec)


func _prune_damage_stats(now: float) -> void:
	var cut: float = now - CombatConstants.SANDBOX_DPS_WINDOW_SEC
	var k := 0
	while k < dmg_stats_events.size() and float(dmg_stats_events[k]["t"]) <= cut:
		k += 1
	if k > 0:
		dmg_stats_events = dmg_stats_events.slice(k)


func damage_stats_window_sum(now: float = -1.0) -> int:
	var t_now: float = elapsed_sec if now < 0.0 else now
	var cut: float = t_now - CombatConstants.SANDBOX_DPS_WINDOW_SEC
	var s := 0
	for ev in dmg_stats_events:
		if float(ev["t"]) > cut:
			s += int(ev["amount"])
	return s


func damage_stats_dps(now: float = -1.0) -> float:
	## 最近窗口内伤害 ÷ 时间。刚清零不足一个窗口时按实际经过时间算（至少 1 秒，免得开头一发就虚高）。
	var t_now: float = elapsed_sec if now < 0.0 else now
	var span: float = clampf(t_now - dmg_stats_start_t, 1.0, CombatConstants.SANDBOX_DPS_WINDOW_SEC)
	return float(damage_stats_window_sum(t_now)) / span


func damage_stats_recent_max_hit(now: float = -1.0) -> int:
	## 最近窗口内单次结算的最大伤害。
	var t_now: float = elapsed_sec if now < 0.0 else now
	var cut: float = t_now - CombatConstants.SANDBOX_DPS_WINDOW_SEC
	var m := 0
	for ev in dmg_stats_events:
		if float(ev["t"]) > cut:
			m = maxi(m, int(ev["amount"]))
	return m


func damage_stats_reset() -> void:
	dmg_stats_events.clear()
	dmg_stats_total = 0
	dmg_stats_peak_hit = 0
	dmg_stats_hits = 0
	dmg_stats_start_t = elapsed_sec
	for e in enemies:
		if e != null:
			e.dmg_taken_total = 0


func _apply_player_damage(amount: int, kind: String = "") -> int:
	## 扣玩家 HP 并通知 UI（抖动/飘字）。amount≤0 不处理。返回申请的伤害值。
	if amount <= 0:
		return 0
	player_hp = maxi(0, player_hp - amount)
	wave_took_damage = true
	player_damaged.emit(amount, kind)
	return amount


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 检视用：按弹种汇总牌库拥有量（袋 + 膛 + 弃）。袋空时仍列出构筑内弹种。
func ammo_inventory_by_id() -> Dictionary:
	var out: Dictionary = {}
	for ammo_id in bag:
		var id: int = int(ammo_id)
		if not out.has(id):
			out[id] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
		out[id]["bag"] = int(out[id]["bag"]) + 1
		out[id]["total"] = int(out[id]["total"]) + 1
	if magazine != null:
		for ammo_id in magazine.slots:
			var id2: int = int(ammo_id)
			if id2 == Magazine.EMPTY:
				continue
			if not out.has(id2):
				out[id2] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
			out[id2]["mag"] = int(out[id2]["mag"]) + 1
			out[id2]["total"] = int(out[id2]["total"]) + 1
	for ammo_id in discard:
		var id3: int = int(ammo_id)
		if not out.has(id3):
			out[id3] = {"bag": 0, "mag": 0, "discard": 0, "total": 0}
		out[id3]["discard"] = int(out[id3]["discard"]) + 1
		out[id3]["total"] = int(out[id3]["total"]) + 1
	return out


## 弹药袋无顺序：每次从现存弹药中均匀随机抽取（数量加权=逐发随机下标），不按数组 FIFO。
## 最近一次 _draw_random_from_bag 对应的临时标记（与返回数组等长）
var _last_drawn_temps: Array = []


func _draw_random_from_bag(count: int) -> Array[int]:
	_sync_temp_arrays()
	var drawn: Array[int] = []
	_last_drawn_temps.clear()
	var n: int = mini(count, bag.size())
	for _i in n:
		var idx: int = rng.randi_range(0, bag.size() - 1)
		var aid: int = int(bag[idx])
		drawn.append(aid)
		_last_drawn_temps.append(bag_temp[idx] if idx < bag_temp.size() else 0.0)
		bag.remove_at(idx)
		if idx < bag_temp.size():
			bag_temp.remove_at(idx)
		hooks.emit_hook(&"on_bag_leave", {"cs": self, "ammo_id": aid, "reason": "draw"})
	return drawn


func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.is_alive():
			out.append(e)
	return out


func front_enemy() -> EnemyInstance:
	var best: EnemyInstance = null
	for e in alive_enemies():
		if best == null or e.cell < best.cell:
			best = e
	return best


func enemies_sorted_by_cell() -> Array:
	var out: Array = alive_enemies()
	out.sort_custom(func(a, b): return a.cell < b.cell)
	return out


func occupied_cells() -> Dictionary:
	var occ := {}
	for e in alive_enemies():
		occ[e.cell] = e
	return occ


func is_adjacent_to_player(e: EnemyInstance) -> bool:
	return e != null and e.is_alive() and e.cell == CombatConstants.PLAYER_CELL + 1


## 敌人是否在其 attack_range 内可攻击玩家（精英/Boss 可 >1）。
func can_attack_player(e: EnemyInstance) -> bool:
	if e == null or not e.is_alive() or e.is_dummy:
		return false
	var dist: int = e.cell - CombatConstants.PLAYER_CELL
	return dist >= 1 and dist <= e.attack_range


func _reset_load_session() -> void:
	_load_session_active = false
	_load_next_slot = 0
	_load_raw_ids.clear()
	_load_resolved_ids.clear()


func is_busy_loading() -> bool:
	return _load_session_active


func can_load() -> bool:
	## 可开新装填会话：玩家回合（装弹/行动）且未满匣、未在会话中。
	if _load_session_active:
		return false
	if phase != Phase.AWAIT_LOAD and phase != Phase.AWAIT_ACTION:
		return false
	if magazine != null and magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE:
		return false
	return true


func can_manual_load() -> bool:
	## 手装：随时可开新会话或在会话中继续装 1 发（袋有弹且未满匣）。
	## 不要求先打空转轮；AWAIT_ACTION 下也可补弹。袋空则立刻补后再判。
	if phase == Phase.FIRING or phase == Phase.ENEMY_TURN or phase == Phase.WON or phase == Phase.LOST:
		return false
	if reward_pending:
		return false
	# v0.3.6：查询不改状态；袋空时只判断「能否补」，真正补袋在 begin_load / 会话结束 / 怪步
	if bag.is_empty() and not can_refill_bag():
		return false
	if magazine != null and magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE:
		return false
	if _load_session_active:
		return true
	return can_load()


func _has_ammo_ready_to_act() -> bool:
	return magazine != null and not magazine.is_empty()


func _can_act_with_partial_load() -> bool:
	## 手装中途：匣内已有弹时可提交会话后开火。
	return phase == Phase.AWAIT_LOAD and _load_session_active and _has_ammo_ready_to_act()


func can_fire() -> bool:
	## 锤位有弹即可开火；连发窗内即使匣空也可点射（免费平庸）；倾泻中可点射以中断。升级三选一期间暂停。
	if reward_pending:
		return false
	if fire_lock_remaining > 0.0:
		return false
	if _dump_pending:
		return phase != Phase.WON and phase != Phase.LOST
	if burst_window_remaining > 0.0:
		return phase != Phase.WON and phase != Phase.LOST and phase != Phase.FIRING
	if not _has_ammo_ready_to_act():
		return false
	return phase == Phase.AWAIT_ACTION or phase == Phase.AWAIT_LOAD or _can_act_with_partial_load()


func can_unload() -> bool:
	if not _has_ammo_ready_to_act():
		return false
	return phase == Phase.AWAIT_ACTION or _can_act_with_partial_load()


func can_start_roll() -> bool:
	if magazine == null or magazine.loaded_count() < 1:
		return false
	return phase == Phase.AWAIT_ACTION or _can_act_with_partial_load()


## 手装中途提交：结束装填会话、保留已装弹，进入 AWAIT_ACTION。
func commit_load_session_if_active() -> bool:
	if not _load_session_active:
		return false
	_complete_load_session()
	return true


func is_busy_firing() -> bool:
	return phase == Phase.FIRING


## 一次装满（测试 / 金色额外轮 / 无动画路径）。UI 请用 begin_load + load_next_chamber + apply_load_rotate。
## v0.4.24：装满后不再随机转（LOAD_FULL_RANDOM_SPIN=false）；从当前击发仓直接开打。
func do_load() -> bool:
	if not begin_load():
		return false
	var needs_spin := false
	while _load_session_active:
		var r: Dictionary = load_next_chamber()
		needs_spin = bool(r.get("needs_spin", false))
		if not bool(r.get("done", false)) and bool(r.get("ok", false)):
			apply_load_rotate()
	if needs_spin:
		apply_roll()
	return true


## 开始逐步装填会话。成功后反复调用 load_next_chamber；每发写入后若未满，再 apply_load_rotate。
## 约定：start_index = 正上击发仓；上弹口=左上=(start+LOAD_PORT_OFFSET)%6。
## 下回合洗回：先归还膛内未耗弹（ROLL 后），再按标记/袋空把弃牌洗回袋；本回合仍能抽几发装几发。
func begin_load() -> bool:
	_reset_focus_shot_counter()
	## rush!：不倾倒已上膛弹药；空匣开局对齐上弹口，半匣则转到最近空仓对准上弹口。
	if not can_load():
		return false
	_reshuffle_if_needed_for_load()
	var topping_up := magazine != null and not magazine.is_empty()
	_load_session_active = true
	_load_next_slot = 0
	_load_raw_ids.clear()
	_load_resolved_ids.clear()
	if topping_up:
		_align_load_port_to_empty()
		_log("继续装填：匣内已有 %d 发，补空仓（上弹口=左上）。" % magazine.loaded_count())
	else:
		# 空匣：仓 0 对准左上上弹口
		magazine.start_index = CombatConstants.LOAD_SESSION_INITIAL_START
		turn_index += 1
		wave_player_turns += 1
		_log("第 %d 回合：开始装填（上弹口=左上，击发点=正上）…" % turn_index)
	_emit()
	if bag.is_empty():
		ensure_bag_refilled_if_empty()
	if bag.is_empty():
		return _finish_load_session_empty()
	return true


func _align_load_port_to_empty() -> void:
	## 顺时针把上弹口转到最近空仓；满匣则不动。
	if magazine == null or magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE:
		return
	for _i in CombatConstants.MAGAZINE_SIZE:
		if magazine.slots[magazine.chamber_at_load_port()] == Magazine.EMPTY:
			return
		magazine.start_index = (magazine.start_index + 1) % CombatConstants.MAGAZINE_SIZE


## 装入当前上弹口（左上）那一仓。不立即转盘：UI 先展示入弹，再调用 apply_load_rotate。
## 返回：ok/done/ammo_id/slot/rotate_to/exhausted/needs_spin
## rotate_to = 下一步应转到的 start_index（未满时 = 当前+1）；done 时不转。
func load_next_chamber() -> Dictionary:
	var fail := {
		"ok": false,
		"done": true,
		"ammo_id": Magazine.EMPTY,
		"slot": -1,
		"rotate_to": magazine.start_index if magazine != null else 0,
		"exhausted": false,
		"needs_spin": false,
	}
	if not _load_session_active:
		return fail
	if magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE or bag.is_empty() or _load_next_slot >= CombatConstants.MAGAZINE_SIZE:
		return _complete_load_session()
	# v0.3.3 修：上弹口只往空仓装；若上弹口对着有弹仓（半匣/随时开火后）先顺转到最近空仓，绝不覆盖。
	if magazine.slots[magazine.chamber_at_load_port()] != Magazine.EMPTY:
		_align_load_port_to_empty()
		if magazine.slots[magazine.chamber_at_load_port()] != Magazine.EMPTY:
			return _complete_load_session()
	var drawn: Array[int] = _draw_random_from_bag(1)
	var raw_id: int = drawn[0]
	var raw_temp = _last_drawn_temps[0] if not _last_drawn_temps.is_empty() else 0.0
	_load_raw_ids.append(raw_id)
	var resolved: int = raw_id
	var swap: Dictionary = _try_insurance_swap_third_sin(resolved, raw_temp)
	resolved = int(swap.get("ammo_id", resolved))
	raw_temp = swap.get("temp", raw_temp)
	_load_resolved_ids.append(resolved)
	var slot: int = magazine.chamber_at_load_port()
	assert(magazine.slots[slot] == Magazine.EMPTY)
	magazine.set_slot(slot, resolved, _normalize_temp_for(resolved, raw_temp))
	hooks.emit_hook(&"on_chamber_loaded", {"cs": self, "ammo_id": resolved, "slot": slot, "temporary": Magazine.temp_value(raw_temp) > 0.0})
	_apply_justice_strip_on_load(resolved)
	_check_sin_threshold_after_insert(resolved)
	_try_spawn_temp_sin_on_load(resolved)
	_log("装填上弹口→仓 %d：%s。" % [slot + 1, _ammo_name(resolved)])
	_load_next_slot += 1
	# 本会话袋抽空：本轮装几发是几发；会话结束/下次 can_manual_load 立刻补袋（不等怪走）。
	var more: bool = (
		_load_next_slot < CombatConstants.MAGAZINE_SIZE
		and magazine.loaded_count() < CombatConstants.MAGAZINE_SIZE
		and not bag.is_empty()
	)
	# rush! 金色/超级回合额外轮：每次只补 1 发，不一次拉满匣（避免锁控）
	if _in_gold_extra_round:
		more = false
	if more:
		var rotate_to: int = next_empty_load_start()
		_emit()
		return {
			"ok": true,
			"done": false,
			"ammo_id": resolved,
			"slot": slot,
			"rotate_to": rotate_to,
			"exhausted": false,
			"needs_spin": false,
		}
	return _complete_load_session_after_shot(resolved, slot)


## 装弹入格展示完毕后调用：整盘逻辑步进 60°（start_index+1），供下一发对准上弹口。
func apply_load_rotate() -> int:
	## v0.3.3：转到「上弹口对准下一空仓」的位置（跳过已有弹仓），不再固定 +1（旧逻辑会让下一发覆盖已有弹）。
	if magazine == null:
		return 0
	magazine.start_index = next_empty_load_start()
	_emit()
	return magazine.start_index


func align_load_port_if_occupied() -> bool:
	## UI：装填会话中下一发前若上弹口对着有弹仓，先转到最近空仓。返回是否转动。
	if magazine == null or not _load_session_active:
		return false
	if magazine.slots[magazine.chamber_at_load_port()] == Magazine.EMPTY:
		return false
	var before: int = magazine.start_index
	_align_load_port_to_empty()
	return magazine.start_index != before


func next_empty_load_start() -> int:
	## 从当前 start_index 顺时针前进 ≥1 步，返回上弹口对准空仓的 start_index；无空仓则 +1。
	var n: int = CombatConstants.MAGAZINE_SIZE
	if magazine == null:
		return 0
	for k in range(1, n + 1):
		var s: int = (magazine.start_index + k) % n
		if magazine.slots[magazine.chamber_at_load_port(s)] == Magazine.EMPTY:
			return s
	return (magazine.start_index + 1) % n


func _complete_load_session_after_shot(resolved: int, slot: int) -> Dictionary:
	var result := _complete_load_session()
	result["ammo_id"] = resolved
	result["slot"] = slot
	result["ok"] = true
	return result


func _complete_load_session() -> Dictionary:
	var n: int = _load_resolved_ids.size()
	var needs_spin: bool = (
		CombatConstants.LOAD_FULL_RANDOM_SPIN
		and n >= CombatConstants.MAGAZINE_SIZE and not magazine.is_empty()
	)
	_log("装填完成：共 %d 发%s。" % [
		n, "（将随机旋转转轮）" if needs_spin else ""
	])
	# v0.3.5：三罪孽惩罚改在每发入仓时按转轮内数量判定（_check_sin_threshold_after_insert），会话结束不再按会话计数
	var rotate_to: int = magazine.start_index
	_reset_load_session()
	# v0.3.4：装填会话结束袋若空则立刻补，手装按钮不用等怪走一格。
	ensure_bag_refilled_if_empty()
	if magazine.is_empty():
		magazine.start_index = 0
		_log("弹药袋与弹夹皆空，无法行动。")
		if bag.is_empty() and discard.is_empty():
			_lose_ammo_exhausted()
			_emit()
			return {
				"ok": true,
				"done": true,
				"ammo_id": Magazine.EMPTY,
				"slot": -1,
				"rotate_to": 0,
				"exhausted": true,
				"needs_spin": false,
			}
		# 弃牌仍有弹：标记下回合洗回，不因袋空判负
		needs_reshuffle_next_load = true
	_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return {
		"ok": true,
		"done": true,
		"ammo_id": Magazine.EMPTY,
		"slot": -1,
		"rotate_to": rotate_to,
		"exhausted": false,
		"needs_spin": needs_spin,
	}


func _finish_load_session_empty() -> bool:
	_complete_load_session()
	return true



func _lose_ammo_exhausted() -> void:
	## 仅当袋+弃+膛皆空且无法洗回时触发（正常对局袋空会在下回合洗回，不应走到这里）。
	lose_reason = LoseReason.AMMO_EXHAUSTED
	abandon_pending_gold()
	_clear_all_sin_muzzle(true)
	_reset_muzzle()
	_purge_ghost_ammo()
	_clear_combat_bonus_ammo()
	magazine = Magazine.new()
	_reset_load_session()
	_set_phase(Phase.LOST)
	_log("失败：弹药耗尽（袋、弃牌与弹夹皆空，无法洗回）。")
	_emit()


## ROLL 不耗弹：下回合 LOAD 前把膛内剩余弹归还弹药袋（不进弃牌堆）。
func _return_magazine_to_bag() -> void:
	if magazine == null or magazine.is_empty():
		return
	var n := 0
	for i in magazine.slots.size():
		var id: int = magazine.slots[i]
		if id != Magazine.EMPTY:
			_bag_append(id, magazine.slot_temp_life(i))
			n += 1
	magazine.clear()
	if n > 0:
		_log("膛内未耗 %d 发归还弹药袋。" % n)


## 下回合洗回：标记为真，或袋已空且弃牌有弹时，把弃牌洗混回袋。不在当回合装弹中途洗满。
func _reshuffle_if_needed_for_load() -> void:
	if needs_reshuffle_next_load or (bag.is_empty() and not discard.is_empty()):
		_reshuffle_discard_into_bag()
		needs_reshuffle_next_load = false


func _lose_hp() -> void:
	lose_reason = LoseReason.HP
	abandon_pending_gold()
	_clear_all_sin_muzzle(true)
	_reset_muzzle()
	_purge_ghost_ammo()
	_clear_combat_bonus_ammo()
	magazine = Magazine.new()
	_reset_load_session()
	_set_phase(Phase.LOST)
	_log("失败：玩家血量归零，整局结束。")
	_emit()


func _reshuffle_discard_into_bag() -> void:
	_sync_temp_arrays()
	for i in discard.size():
		var id: int = discard[i]
		var t = discard_temp[i] if i < discard_temp.size() else 0.0
		_bag_append(id, t)
	discard.clear()
	discard_temp.clear()
	_shuffle_bag()
	_log("弃牌堆洗回弹药袋（%d 发）。" % bag.size())


func _take_one_ammo_from_bag(ammo_id: int) -> bool:
	## 从袋中取出一发指定 id（优先靠后），同步 temp 标记。
	_sync_temp_arrays()
	for i in range(bag.size() - 1, -1, -1):
		if int(bag[i]) == ammo_id:
			bag.remove_at(i)
			if i < bag_temp.size():
				bag_temp.remove_at(i)
			hooks.emit_hook(&"on_bag_leave", {"cs": self, "ammo_id": ammo_id, "reason": "take"})
			return true
	return false


func _fill_empty_chambers_with_ghosts() -> int:
	## 用袋内幽灵填满弹夹所有空位；返回填入数量。
	if magazine == null:
		return 0
	var filled := 0
	for i in magazine.slots.size():
		if magazine.slots[i] != Magazine.EMPTY:
			continue
		var ge: Dictionary = _take_one_ammo_from_bag_entry(FireResolver.ID_GHOST)
		if not bool(ge.get("ok", false)):
			break
		magazine.set_slot(i, FireResolver.ID_GHOST, _normalize_temp_for(FireResolver.ID_GHOST, ge.get("temp", 0.0)))
		filled += 1
	return filled


func count_ghosts_in_bag() -> int:
	var n := 0
	for x in bag:
		if int(x) == FireResolver.ID_GHOST:
			n += 1
	return n


func _apply_tombstone_on_fire() -> Array:
	## v0.4.20 墓碑（老大重定）：
	## - 袋里没有幽灵 → 袋内生成 TOMBSTONE_GHOST_SPAWN(2) 颗临时幽灵（TTL GHOST_TTL_SEC），本发不带幽灵；
	## - 袋里有幽灵 → 袋内所有幽灵跟着墓碑一起射出（每颗独立结算枪口），不再生成新幽灵。
	if count_ghosts_in_bag() <= 0:
		for _i in CombatConstants.TOMBSTONE_GHOST_SPAWN:
			_bag_append(FireResolver.ID_GHOST, CombatConstants.GHOST_TTL_SEC)
		_log("墓碑弹药：袋里没幽灵 → 生成 %d 颗临时幽灵（TTL %.0fs）。" % [CombatConstants.TOMBSTONE_GHOST_SPAWN, CombatConstants.GHOST_TTL_SEC])
		return []
	return _rapid_fire_all_bag_ghosts()


func _take_one_ammo_from_bag_entry(ammo_id: int) -> Dictionary:
	## 从袋取出一发指定 id，返回 {ok, id, temp}；没有则 ok=false。
	_sync_temp_arrays()
	for i in range(bag.size() - 1, -1, -1):
		if int(bag[i]) == ammo_id:
			var tv = bag_temp[i] if i < bag_temp.size() else 0.0
			bag.remove_at(i)
			if i < bag_temp.size():
				bag_temp.remove_at(i)
			hooks.emit_hook(&"on_bag_leave", {"cs": self, "ammo_id": ammo_id, "reason": "ghost_fire"})
			return {"ok": true, "id": ammo_id, "temp": Magazine.temp_value(tv)}
	return {"ok": false, "id": -1, "temp": 0.0}


func _consume_pending_tombstone_ghost_shots() -> Array:
	var out: Array = _pending_tombstone_ghost_shots.duplicate()
	_pending_tombstone_ghost_shots.clear()
	return out


func _rapid_fire_all_bag_ghosts() -> Array:
	## 极速连射袋内所有幽灵；每发独立走枪口结算。返回 shot 记录（供 UI/测试）。
	var shots: Array = []
	var guard := 32
	while guard > 0:
		guard -= 1
		var entry: Dictionary = _take_one_ammo_from_bag_entry(FireResolver.ID_GHOST)
		if not bool(entry.get("ok", false)):
			break
		var rec: Dictionary = _fire_virtual_ammo_shot(FireResolver.ID_GHOST, Magazine.temp_value(entry.get("temp", 0.0)))
		shots.append(rec)
	if not shots.is_empty():
		_log("墓碑弹药：连射袋内幽灵 ×%d。" % shots.size())
	return shots


func _fire_virtual_ammo_shot(ammo_id: int, shot_temp: float = 0.0, to_discard: bool = true) -> Dictionary:
	## 不耗转轮仓的虚拟击发（墓碑幽灵连射 / 连发窗免费弹）。单独结算枪口。
	var start_before: int = magazine.start_index if magazine != null else 0
	var saved_slot: int = last_fired_slot
	var saved_ammo: int = last_shot_ammo_id
	var flags := FireResolver.inherits_from(ammo_id)
	last_shot_muzzle_outline_ids = _muzzle_outline_ammo_ids_for_shot()
	_mount_sin_muzzle_from(flags)
	var pierce := _muzzle_pierce or bool(flags["pierce"])
	var gas := _muzzle_gas or bool(flags["gas"])
	var fire := _muzzle_fire or bool(flags["fire"])
	var water := _muzzle_water or bool(flags["water"])
	var thunder := _muzzle_thunder or bool(flags["thunder"])
	var base_dmg: int = FireResolver.base_damage_for(ammo_id, [ammo_id], 0)
	base_dmg = _scale_outgoing_damage(base_dmg)
	last_shot_ammo_id = ammo_id
	last_shot_hit_cell = -1
	last_shot_dealt = 0
	last_shot_hit_cells.clear()
	last_shot_hit_amounts.clear()
	last_shot_was_pierce = pierce
	last_fired_slot = -1
	last_blank_skip_steps = 0
	last_shot_was_blank = false
	if to_discard:
		_discard_append(ammo_id, shot_temp)
	_mount_muzzle_from(flags)
	var dealt_total := _apply_shot_with_optional_echo(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
	_fire_total_damage += dealt_total
	_remove_dead()
	var rec := {
		"extra": true,
		"virtual": true,
		"ammo_id": ammo_id,
		"slot": -1,
		"blank_skip": 0,
		"start_before": start_before,
		"start_after": magazine.start_index if magazine != null else 0,
		"hit_cells": last_shot_hit_cells.duplicate(),
		"hit_amounts": last_shot_hit_amounts.duplicate(),
		"muzzle_outline_ids": last_shot_muzzle_outline_ids.duplicate(),
		"pierce": last_shot_was_pierce,
	}
	var first_dealt_hook: int = 0
	for a in rec.get("hit_amounts", []):
		first_dealt_hook += int(a)
	hooks.emit_hook(&"on_shot", {"cs": self, "ammo_id": ammo_id, "virtual": true, "dealt": first_dealt_hook})
	if last_shot_was_echoed:
		var twin_dealt: int = 0
		for a in last_echo_hit_amounts:
			twin_dealt += int(a)
		rec["echo_twin_cells"] = last_echo_hit_cells.duplicate()
		rec["echo_twin_amounts"] = last_echo_hit_amounts.duplicate()
		hooks.emit_hook(&"on_shot", {"cs": self, "ammo_id": ammo_id, "virtual": true, "echo": true, "dealt": twin_dealt})
	# 恢复主发锤位/弹药 id，避免幽灵连射冲掉墓碑等主发的 last_fired_slot
	last_fired_slot = saved_slot
	last_shot_ammo_id = saved_ammo
	_emit()
	if _field_cleared():
		_abort_fire_cleared()
	return rec


func _purge_ghost_ammo() -> int:
	## 战斗结束：清除袋/弃/膛中的幽灵与小石头等 ephemeral。返回清除数量。
	var n := 0
	_sync_temp_arrays()
	var i := bag.size() - 1
	while i >= 0:
		if int(bag[i]) == FireResolver.ID_GHOST or int(bag[i]) == FireResolver.ID_PEBBLE:
			bag.remove_at(i)
			if i < bag_temp.size():
				bag_temp.remove_at(i)
			n += 1
		i -= 1
	i = discard.size() - 1
	while i >= 0:
		if int(discard[i]) == FireResolver.ID_GHOST or int(discard[i]) == FireResolver.ID_PEBBLE:
			discard.remove_at(i)
			if i < discard_temp.size():
				discard_temp.remove_at(i)
			n += 1
		i -= 1
	if magazine != null:
		for s in magazine.slots.size():
			if magazine.slots[s] == FireResolver.ID_GHOST or magazine.slots[s] == FireResolver.ID_PEBBLE:
				magazine.set_slot(s, Magazine.EMPTY, false)
				n += 1
	if n > 0:
		_log("战斗结束：临时衍生物消散 ×%d。" % n)
	return n


func _next_focus_damage() -> int:
	## 聚能：本装填周期内第 n 发聚能伤害 = 2+n（首发3）。装弹/卸弹/强制装填时清零。
	_focus_shots_fired += 1
	return 2 + _focus_shots_fired


func _reset_focus_shot_counter() -> void:
	_focus_shots_fired = 0




func _gold_ammo_damage() -> int:
	## 金币弹：3 + ⌊金币×20%⌋。
	return 3 + int(gold * 0.20)


func _spend_gold_ammo_cost(ammo_id: int) -> void:
	## 每射一发金币弹：金币≥1 则 −1。
	if ammo_id != FireResolver.ID_GOLD:
		return
	if gold < 1:
		return
	gold -= 1
	_log("金币弹药：金币 −1（现 %d）。" % gold)
	hooks.emit_hook(&"on_gold_ammo_spend", {"cs": self, "gold_after": gold})


func _adjacent_pebble_run_from_hammer() -> int:
	## 自击发点起不跳空、连续小石头段长（邻接判定）。
	if magazine == null:
		return 0
	var n := 0
	var i: int = magazine.chamber_at_fire_port()
	for _s in magazine.size():
		if magazine.slots[i] != FireResolver.ID_PEBBLE:
			break
		n += 1
		i = (i + 1) % magazine.size()
	return n


func _consume_pebble_fuse(count: int) -> void:
	## 连续清空 count 个小石头仓并逐格推进转轮；全部进弃牌。
	for _i in count:
		if magazine == null or magazine.is_empty():
			break
		var hammer: int = magazine.chamber_at_fire_port()
		var shot_temp: float = magazine.slot_temp_life(hammer)
		if magazine.slots[hammer] == FireResolver.ID_PEBBLE:
			magazine.set_slot(hammer, Magazine.EMPTY, false)
			_discard_append(FireResolver.ID_PEBBLE, shot_temp)
		_advance_cylinder_one_step()


func _maybe_spawn_pebbles_from_stone(ammo_id: int, dealt: int) -> void:
	## 石头命中：按实际伤害数向袋加入等量小石头 TTL。
	if ammo_id != FireResolver.ID_STONE or dealt <= 0:
		return
	for _i in dealt:
		_bag_append(FireResolver.ID_PEBBLE, CombatConstants.PEBBLE_TTL_SEC)
	_log("石头弹药：实际伤害 %d → 袋内 +%d 小石头（TTL %.0fs）。" % [
		dealt, dealt, CombatConstants.PEBBLE_TTL_SEC
	])
	hooks.emit_hook(&"on_stone_shatter", {"cs": self, "dealt": dealt, "pebbles": dealt})


func _prepare_point_fire_damages(full_order: Array[int], full_dmg: Array[int]) -> void:
	## 点射队列准备：聚能递增 / 小石头融合。写入 _fire_queue/_fire_damages/_pebble_fuse_count。
	_pebble_fuse_count = 0
	if full_order.is_empty():
		_fire_queue = [] as Array[int]
		_fire_damages = [] as Array[int]
		return
	var ammo0: int = int(full_order[0])
	var dmg0: int = int(full_dmg[0])
	if ammo0 == FireResolver.ID_FOCUS:
		dmg0 = _next_focus_damage()
	elif ammo0 == FireResolver.ID_GOLD:
		dmg0 = _gold_ammo_damage()
	elif ammo0 == FireResolver.ID_PEBBLE:
		var run: int = _adjacent_pebble_run_from_hammer()
		if run >= 2:
			_pebble_fuse_count = run
			dmg0 = run
			_log("小石头：相邻 ×%d 融合为 1 发（伤害 %d）。" % [run, dmg0])
			hooks.emit_hook(&"on_pebble_fuse", {"cs": self, "count": run, "damage": dmg0})
	_fire_queue = [ammo0] as Array[int]
	_fire_damages = [dmg0] as Array[int]


func begin_fire() -> bool:
	## rush!：每次只打锤位方向最近的 1 发；打完该发后收束，由 UI 进怪回合。
	## 伤害仍按当前匣内 fire_order 全文计算（旧彩弹组合修正），但队列仅含首发。
	if not can_fire():
		return false
	commit_load_session_if_active()
	# 玩家主动开火开启新链；额外轮内的 begin_fire 保留累计授予数
	if not _in_gold_extra_round:
		_extra_autofires_granted_this_chain = 0
	_reset_fire_session()
	var full_order: Array[int] = magazine.fire_order()
	if full_order.is_empty():
		return false
	var full_dmg: Array[int] = FireResolver.compute_shot_damages(full_order)
	_prepare_point_fire_damages(full_order, full_dmg)
	_fire_index = 0
	_set_phase(Phase.FIRING)
	_log("射击 1 发[%s]（匣内剩余将保留，可继续装/射）。" % _ammo_name(full_order[0]))
	_emit()
	return true


func peek_blank_skip_steps() -> int:
	## 不改状态：从当前锤位起，前进到最近有弹格需要的空仓步数（半满匣开火动画用）。
	if magazine == null or magazine.is_empty():
		return 0
	var skipped := 0
	var idx: int = magazine.start_index
	var guard := 0
	while guard < CombatConstants.MAGAZINE_SIZE:
		var h: int = magazine.chamber_at_fire_port(idx)
		if magazine.slots[h] != Magazine.EMPTY:
			return skipped
		idx = (idx + 1) % magazine.size()
		skipped += 1
		guard += 1
	return skipped


func fire_next_shot() -> bool:
	if phase != Phase.FIRING:
		return false
	# 上一发未视觉结算则先收束，避免卡住 FIRING
	if pace_after_fire and not _paced_shot.is_empty():
		finalize_paced_shot()
		if phase != Phase.FIRING:
			return false
	if _fire_index >= _fire_queue.size():
		_finish_fire()
		return false
	# 空仓：沿转轮前进方向快跳到最近有弹格，不逐空结算
	var skipped := 0
	var guard := 0
	while magazine != null and not magazine.is_empty() and guard < CombatConstants.MAGAZINE_SIZE:
		var h: int = magazine.chamber_at_fire_port()
		if magazine.slots[h] != Magazine.EMPTY:
			break
		_advance_cylinder_one_step()
		skipped += 1
		guard += 1
	last_blank_skip_steps = skipped
	if magazine == null or magazine.is_empty():
		last_shot_was_blank = skipped > 0
		last_fired_slot = magazine.chamber_at_fire_port() if magazine != null else -1
		last_shot_ammo_id = -1
		last_shot_hit_cell = -1
		last_shot_dealt = 0
		last_shot_muzzle_outline_ids.clear()
		last_shot_hit_cells.clear()
		last_shot_hit_amounts.clear()
		last_shot_was_pierce = false
		_finish_fire()
		return false
	var hammer: int = magazine.chamber_at_fire_port()
	if magazine.slots[hammer] == Magazine.EMPTY:
		last_shot_was_blank = true
		last_fired_slot = hammer
		last_shot_ammo_id = -1
		last_shot_hit_cell = -1
		last_shot_dealt = 0
		last_shot_muzzle_outline_ids.clear()
		last_shot_hit_cells.clear()
		last_shot_hit_amounts.clear()
		last_shot_was_pierce = false
		_finish_fire()
		return false

	last_shot_was_blank = false
	last_fired_slot = hammer
	var shot_temp: float = magazine.slot_temp_life(hammer)
	var ammo_id: int = _fire_queue[_fire_index]
	var base_dmg: int = _fire_damages[_fire_index]
	var fuse_n: int = _pebble_fuse_count
	if fuse_n >= 2 and ammo_id == FireResolver.ID_PEBBLE:
		_consume_pebble_fuse(fuse_n)
		_pebble_fuse_count = 0
		shot_temp = 0.0  # 已在 fuse 内各自 discard
	else:
		_consume_hammer_chamber(ammo_id)

	var flags := FireResolver.inherits_from(ammo_id)
	# 描边：开火前已在枪口的贡献色（不含本发刚挂上的罪孽）
	last_shot_muzzle_outline_ids = _muzzle_outline_ammo_ids_for_shot()
	# 罪孽层：本发先入枪口，本发伤害即享受新层
	_mount_sin_muzzle_from(flags)
	var pierce := _muzzle_pierce or bool(flags["pierce"])
	var gas := _muzzle_gas or bool(flags["gas"])
	var fire := _muzzle_fire or bool(flags["fire"])
	var water := _muzzle_water or bool(flags["water"])
	var thunder := _muzzle_thunder or bool(flags["thunder"])

	base_dmg = _scale_outgoing_damage(base_dmg)
	last_shot_ammo_id = ammo_id
	last_shot_hit_cell = -1
	last_shot_dealt = 0
	last_shot_hit_cells.clear()
	last_shot_hit_amounts.clear()
	last_shot_was_pierce = pierce

	if fuse_n < 2:
		_discard_append(ammo_id, shot_temp)
	# 元素枪口：本发后挂上，供后续击发附带
	_mount_muzzle_from(flags)
	if ammo_id == FireResolver.ID_TOMBSTONE:
		_pending_tombstone_ghost_shots.append_array(_apply_tombstone_on_fire())
	_spend_gold_ammo_cost(ammo_id)
	_fire_index += 1

	_note_last_non_sin_ammo(ammo_id)
	if pace_after_fire and player_confuse_remaining <= 0.0:
		# 只规划命中路径；扣血/飘字等拖尾飞到怪身上再 resolve_paced_hit
		# 色欲自混乱期间改为同步结算（伤害打自己）。
		var plan: Array = _build_shot_plan(base_dmg, pierce, ammo_id)
		for h in plan:
			last_shot_hit_cells.append(int(h.get("cell", -1)))
			last_shot_hit_amounts.append(0)
		if not plan.is_empty():
			last_shot_hit_cell = int(plan[0].get("cell", -1))
			last_shot_dealt = 0
		var more_paced: bool = _fire_index < _fire_queue.size()
		_paced_shot = {
			"ammo_id": ammo_id,
			"base_dmg": base_dmg,
			"pierce": pierce,
			"gas": gas,
			"fire": fire,
			"water": water,
			"thunder": thunder,
			"echo": _muzzle_echo,
			"hits": plan,
			"thunder_done": false,
			"resolved_total": 0,
			"gold": ammo_id == FireResolver.ID_BURST or ammo_id == FireResolver.ID_SUPER_ROUND,
			"await_finish": not more_paced,
		}
		_emit()
		return more_paced

	var dealt_total := _apply_shot_with_optional_echo(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
	_fire_total_damage += dealt_total
	_maybe_spawn_pebbles_from_stone(ammo_id, dealt_total)
	_remove_dead()

	# 金色/超级回合：本匣击发计入待追加轮；整匣后再额外自动装填射击。超级回合额外轮内可再叠（有上限）。
	_queue_extra_autofire_from_shot(ammo_id)

	_emit()

	# 中途清场：立刻停射进胜利，未击发归袋
	if _field_cleared():
		_abort_fire_cleared()
		return false

	if _fire_index >= _fire_queue.size():
		_finish_fire()
		return false
	return true



func has_paced_shot_pending() -> bool:
	return not _paced_shot.is_empty()


func _build_shot_plan(base_dmg: int, pierce: bool, ammo_id: int = -1) -> Array:
	## 规划本发命中顺序（前→后），不扣血。
	var plan: Array = []
	var targets: Array = []
	for e in enemies_sorted_by_cell():
		if e != null and e.is_alive():
			targets.append(e)
	if targets.is_empty():
		return plan
	if ammo_id == FireResolver.ID_SCATTER:
		var n: int = targets.size()
		var per: int
		if n >= 3:
			per = int(round(float(base_dmg) / float(n)))
		else:
			per = int(round(float(base_dmg) * 0.30))
		for e in targets:
			plan.append({"enemy": e, "cell": e.cell, "dmg": per, "resolved": false, "dealt": 0})
		return plan
	if pierce:
		var dmg := base_dmg
		for e in targets:
			if dmg <= 0:
				break
			plan.append({"enemy": e, "cell": e.cell, "dmg": dmg, "resolved": false, "dealt": 0})
			dmg -= 1
	else:
		var e0: EnemyInstance = targets[0]
		plan.append({"enemy": e0, "cell": e0.cell, "dmg": base_dmg, "resolved": false, "dealt": 0})
	return plan


func resolve_paced_hit(hit_index: int) -> int:
	## UI：拖尾飞到第 hit_index 个目标时结算该格伤害；返回实际扣血。
	if _paced_shot.is_empty():
		return 0
	var hits: Array = _paced_shot.get("hits", [])
	if hit_index < 0 or hit_index >= hits.size():
		return 0
	var h: Dictionary = hits[hit_index]
	if bool(h.get("resolved", false)):
		return int(h.get("dealt", 0))
	var e: EnemyInstance = h.get("enemy") as EnemyInstance
	var dealt := 0
	if e != null:
		dealt = _hit_enemy_with_elements(
			e,
			int(h.get("dmg", 0)),
			int(_paced_shot.get("ammo_id", -1)),
			bool(_paced_shot.get("gas", false)),
			bool(_paced_shot.get("fire", false)),
			bool(_paced_shot.get("water", false)),
			false,
		)
	h["resolved"] = true
	h["dealt"] = dealt
	hits[hit_index] = h
	_paced_shot["hits"] = hits
	if hit_index < last_shot_hit_amounts.size():
		last_shot_hit_amounts[hit_index] = dealt
	if hit_index == 0:
		last_shot_dealt = dealt
		last_shot_hit_cell = int(h.get("cell", -1))
	_paced_shot["resolved_total"] = int(_paced_shot.get("resolved_total", 0)) + dealt
	# 末命中后再导电链（湿可能由本发途经水弹挂上）
	if hit_index == hits.size() - 1:
		_resolve_paced_thunder_chain()
	_emit()
	return dealt


func _resolve_paced_thunder_chain() -> void:
	if _paced_shot.is_empty() or bool(_paced_shot.get("thunder_done", false)):
		return
	_paced_shot["thunder_done"] = true
	if not bool(_paced_shot.get("thunder", false)):
		return
	var chain_origin: EnemyInstance = null
	for h in _paced_shot.get("hits", []):
		var e: EnemyInstance = h.get("enemy") as EnemyInstance
		if e != null and e.wet_stacks > 0:
			chain_origin = e
			break
	if chain_origin == null:
		return
	var extra: int = _thunder_chain(
		chain_origin,
		int(_paced_shot.get("base_dmg", 0)),
		bool(_paced_shot.get("gas", false)),
		bool(_paced_shot.get("fire", false)),
		bool(_paced_shot.get("water", false)),
	)
	_paced_shot["resolved_total"] = int(_paced_shot.get("resolved_total", 0)) + extra


func finalize_paced_shot() -> void:
	## UI：本发拖尾飞完后收束（补结算、金计数、清场/整匣结束）。
	if _paced_shot.is_empty():
		return
	var hits: Array = _paced_shot.get("hits", [])
	for i in hits.size():
		if not bool(hits[i].get("resolved", false)):
			resolve_paced_hit(i)
	if not bool(_paced_shot.get("thunder_done", false)):
		_resolve_paced_thunder_chain()
	var total: int = int(_paced_shot.get("resolved_total", 0))
	last_shot_was_echoed = false
	last_echo_hit_cells.clear()
	last_echo_hit_amounts.clear()
	if bool(_paced_shot.get("echo", false)):
		_log("枪口【回声】：再次结算本发。")
		var first_cells: Array[int] = last_shot_hit_cells.duplicate()
		var first_amts: Array[int] = last_shot_hit_amounts.duplicate()
		var first_cell: int = last_shot_hit_cell
		var first_dealt: int = last_shot_dealt
		last_shot_hit_cells.clear()
		last_shot_hit_amounts.clear()
		var echo_total: int = _apply_shot_to_enemies(
			int(_paced_shot.get("ammo_id", -1)),
			int(_paced_shot.get("base_dmg", 0)),
			bool(_paced_shot.get("pierce", false)),
			bool(_paced_shot.get("gas", false)),
			bool(_paced_shot.get("fire", false)),
			bool(_paced_shot.get("water", false)),
			bool(_paced_shot.get("thunder", false)),
		)
		last_shot_was_echoed = true
		last_echo_hit_cells = last_shot_hit_cells.duplicate()
		last_echo_hit_amounts = last_shot_hit_amounts.duplicate()
		last_shot_hit_cells = first_cells
		last_shot_hit_amounts = first_amts
		last_shot_hit_cell = first_cell
		last_shot_dealt = first_dealt
		total += echo_total
	_fire_total_damage += total
	_maybe_spawn_pebbles_from_stone(int(_paced_shot.get("ammo_id", -1)), total)
	if bool(_paced_shot.get("gold", false)):
		_queue_extra_autofire_from_shot(int(_paced_shot.get("ammo_id", -1)))
	var await_finish: bool = bool(_paced_shot.get("await_finish", false))
	_paced_shot.clear()
	# pace：仍留尸体给 UI 飚血后再 flush；此处只判断存活
	if _field_cleared():
		_abort_fire_cleared()
		return
	if await_finish:
		_finish_fire()
		return
	_emit()


func _apply_scatter_shot(
	ammo_id: int, base_dmg: int, gas: bool, fire: bool, water: bool, thunder: bool,
	explosive: bool, targets: Array
) -> int:
	## 散射：实际伤害均分全场（四舍五入）；敌人<3 时每人只吃 30%。
	var n: int = targets.size()
	var per: int
	if n >= 3:
		per = int(round(float(base_dmg) / float(n)))
	else:
		per = int(round(float(base_dmg) * 0.30))
	_log("散射：实际%d → %s（敌人×%d）" % [
		base_dmg,
		("均分每人 %d" % per) if n >= 3 else ("少于3人，每人 30%% = %d" % per),
		n
	])
	var total := 0
	for e in targets:
		if e == null or not e.is_alive():
			continue
		var dealt_e: int = _hit_enemy_with_elements(e, per, ammo_id, gas, fire, water, thunder, "", explosive)
		total += dealt_e
		last_shot_hit_cells.append(e.cell)
		last_shot_hit_amounts.append(dealt_e)
	if not last_shot_hit_cells.is_empty():
		last_shot_hit_cell = last_shot_hit_cells[0]
		last_shot_dealt = last_shot_hit_amounts[0]
	return total


func _apply_shot_to_enemies(
	ammo_id: int, base_dmg: int, pierce: bool, gas: bool, fire: bool, water: bool, thunder: bool,
	explosive: bool = false
) -> int:
	_note_last_non_sin_ammo(ammo_id)
	if player_confuse_remaining > 0.0:
		var self_dmg: int = maxi(0, base_dmg)
		_apply_player_damage(self_dmg, "色欲")
		_log("击发[%s] → 玩家混乱中，伤害 %d 打到自己（HP %d/%d）。" % [
			_ammo_name(ammo_id), self_dmg, player_hp, player_max_hp
		])
		last_shot_hit_cell = CombatConstants.PLAYER_CELL
		last_shot_dealt = self_dmg
		last_shot_hit_cells = [CombatConstants.PLAYER_CELL]
		last_shot_hit_amounts = [self_dmg]
		hooks.emit_hook(&"on_self_hit", {"cs": self, "ammo_id": ammo_id, "dealt": self_dmg})
		if player_hp <= 0:
			_lose_hp()
		return self_dmg
	var targets: Array = enemies_sorted_by_cell()
	if targets.is_empty():
		_log("击发[%s] → 无可击中目标。" % _ammo_name(ammo_id))
		return 0
	if ammo_id == FireResolver.ID_SCATTER:
		return _apply_scatter_shot(ammo_id, base_dmg, gas, fire, water, thunder, explosive, targets)
	var total := 0
	if pierce:
		var dmg := base_dmg
		var chain_origin: EnemyInstance = null
		for e in targets:
			if dmg <= 0:
				break
			var dealt_e: int = _hit_enemy_with_elements(e, dmg, ammo_id, gas, fire, water, thunder, "", explosive)
			total += dealt_e
			last_shot_hit_cells.append(e.cell)
			last_shot_hit_amounts.append(dealt_e)
			# 穿透：以首个「有湿」目标为导电起点（含水本发刚挂上的湿）
			if thunder and chain_origin == null and e.wet_stacks > 0:
				chain_origin = e
			dmg -= 1
		if not last_shot_hit_cells.is_empty():
			last_shot_hit_cell = last_shot_hit_cells[0]
			last_shot_dealt = last_shot_hit_amounts[0]
		if thunder and chain_origin != null:
			total += _thunder_chain(chain_origin, base_dmg, gas, fire, water)
	else:
		var e: EnemyInstance = targets[0]
		var dealt_e: int = _hit_enemy_with_elements(e, base_dmg, ammo_id, gas, fire, water, thunder, "", explosive)
		total += dealt_e
		last_shot_hit_cell = e.cell
		last_shot_dealt = dealt_e
		last_shot_hit_cells.append(e.cell)
		last_shot_hit_amounts.append(dealt_e)
		if thunder and e.wet_stacks > 0:
			total += _thunder_chain(e, base_dmg, gas, fire, water)
	return total


func _apply_shot_with_optional_echo(
	ammo_id: int, base_dmg: int, pierce: bool, gas: bool, fire: bool, water: bool, thunder: bool,
	explosive: bool = false
) -> int:
	## 若枪口【回声】激活：同一发再结算一次（不递归叠回声、不重挂枪口）。
	last_shot_was_echoed = false
	last_echo_hit_cells.clear()
	last_echo_hit_amounts.clear()
	var total: int = _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder, explosive)
	if not _muzzle_echo:
		return total
	var first_cells: Array[int] = last_shot_hit_cells.duplicate()
	var first_amts: Array[int] = last_shot_hit_amounts.duplicate()
	var first_cell: int = last_shot_hit_cell
	var first_dealt: int = last_shot_dealt
	last_shot_hit_cells.clear()
	last_shot_hit_amounts.clear()
	_log("枪口【回声】：再次结算本发。")
	var echo_total: int = _apply_shot_to_enemies(ammo_id, base_dmg, pierce, gas, fire, water, thunder, explosive)
	last_shot_was_echoed = true
	last_echo_hit_cells = last_shot_hit_cells.duplicate()
	last_echo_hit_amounts = last_shot_hit_amounts.duplicate()
	# 主记录保留第一波，供 UI 第一条弹道；回声波在 last_echo_*
	last_shot_hit_cells = first_cells
	last_shot_hit_amounts = first_amts
	last_shot_hit_cell = first_cell
	last_shot_dealt = first_dealt
	return total + echo_total


func _explosive_splash(
	origin: EnemyInstance, boom_dmg: int, ammo_id: int, gas: bool, fire: bool, water: bool, thunder: bool, n_side: int
) -> int:
	## 炸药溅射：原点左右各最多 n_side 个相邻存活敌人，各吃 boom_dmg（不再二次炸药 AOE）。
	var total := 0
	var by_cell := occupied_cells()
	for dir in [-1, 1]:
		var found := 0
		var c: int = origin.cell + dir
		while found < n_side and c > CombatConstants.PLAYER_CELL and c < CombatConstants.BOARD_SIZE:
			if by_cell.has(c):
				var other: EnemyInstance = by_cell[c] as EnemyInstance
				if other != null and other.is_alive() and other != origin:
					var d: int = _hit_enemy_with_elements(
						other, boom_dmg, ammo_id, gas, fire, water, thunder, "炸药", false, false
					)
					total += d
					_log("  → 炸药溅射 %s 格%d 伤害%d" % [other.name_zh, other.cell, d])
					found += 1
			c += dir
	return total


func _hit_enemy_with_elements(
	e: EnemyInstance, dmg: int, ammo_id: int, gas: bool, fire: bool, water: bool, thunder: bool,
	damage_kind: String = "", explosive: bool = false, allow_explosive_aoe: bool = true
) -> int:
	var was_burning: bool = e.burn_stacks > 0
	var use_explosive: bool = allow_explosive_aoe and (explosive or _muzzle_explosive)
	var hit_dmg: int = dmg
	if use_explosive and was_burning:
		hit_dmg = dmg * 3
		if damage_kind == "":
			damage_kind = "炸药"
	var dealt: int = e.apply_hit(hit_dmg)
	_notify_enemy_damage(e, dealt, damage_kind)
	_try_greed_gold_drop(dealt, e.cell)
	_try_lifesteal_heal(dealt)
	_try_lust_confuse_on_hit(e)
	_try_sloth_slow_on_hit(e)
	if use_explosive and was_burning:
		var n_side: int = maxi(1, dmg - 2)
		explosive_detonated.emit(e.cell, n_side)
		dealt += _explosive_splash(e, dmg * 3, ammo_id, gas, fire, water, thunder, n_side)
	_log("击发[%s] → %s 格%d 伤害%d（HP %d/%d）%s" % [
		_ammo_name(ammo_id), e.name_zh, e.cell, dealt, e.hp, e.max_hp,
		(" " + e.status_text()) if e.status_text() != "" else ""
	])
	# 水：湿须在死亡早退前挂上，否则同发雷击无法以本发湿启动导电
	if water:
		e.wet_stacks = maxi(e.wet_stacks, dealt if dealt > 0 else dmg)
		e.burn_stacks = 0
		_log("  → 施加湿 %d（燃烧被覆盖）" % e.wet_stacks)
	if not e.is_alive():
		return dealt
	# 汽油
	if gas:
		if e.burn_stacks > 0:
			var bonus := e.gas_stacks + (dealt if dealt > 0 else dmg)
			# 已燃烧时，本应施加的汽油直接转化为伤害
			var convert := dealt if dealt > 0 else dmg
			var extra: int = e.apply_hit(convert)
			_notify_enemy_damage(e, extra, "汽油")
			dealt += extra
			_log("  → 已燃烧，汽油转化为伤害 %d" % extra)
		else:
			var add := dealt if dealt > 0 else dmg
			e.gas_stacks += add
			_log("  → 汽油 +%d（现 %d）" % [add, e.gas_stacks])
	# 火：点燃汽油链 + 燃烧
	if fire:
		if e.gas_stacks > 0 or _any_gas_adjacent_cluster(e):
			_ignite_gas_cluster(e)
		var burn_add := dealt if dealt > 0 else dmg
		e.burn_stacks += burn_add
		_log("  → 燃烧 +%d（现 %d）" % [burn_add, e.burn_stacks])
	return dealt


func _any_gas_adjacent_cluster(start: EnemyInstance) -> bool:
	return start.gas_stacks > 0


func _ignite_gas_cluster(start: EnemyInstance) -> void:
	## 所有与 start 通过相邻格子连在一起的带汽油敌人同时点燃。
	var by_cell := occupied_cells()
	var stack: Array = [start]
	var seen := {}
	while not stack.is_empty():
		var e: EnemyInstance = stack.pop_back()
		if seen.has(e):
			continue
		seen[e] = true
		if e.gas_stacks <= 0:
			continue
		var g := e.gas_stacks
		var boom: int = e.apply_damage(g)
		_notify_enemy_damage(e, boom, "汽油")
		e.burn_stacks += g
		e.gas_stacks = 0
		_log("  → %s 汽油引爆伤害%d，燃烧%d" % [e.name_zh, boom, e.burn_stacks])
		for dc in [-1, 1]:
			var nc: int = e.cell + dc
			if by_cell.has(nc):
				var other: EnemyInstance = by_cell[nc]
				if other.gas_stacks > 0 and not seen.has(other):
					stack.append(other)


func _thunder_chain(origin: EnemyInstance, dmg: int, gas: bool, fire: bool, water: bool) -> int:
	var by_cell := occupied_cells()
	var visited := {}
	visited[origin] = true
	var total := 0
	var queue: Array = [origin]
	while not queue.is_empty():
		var cur: EnemyInstance = queue.pop_front()
		for dc in [-1, 1]:
			var nc: int = cur.cell + dc
			if not by_cell.has(nc):
				continue
			var other: EnemyInstance = by_cell[nc]
			if visited.has(other):
				continue
			if other.wet_stacks <= 0:
				continue
			visited[other] = true
			_log("  → 导电传导 → %s 格%d" % [other.name_zh, other.cell])
			total += _hit_enemy_with_elements(
				other, dmg, 0, gas, fire, water, false, "导电"
			)
			queue.append(other)
	return total


func _ammo_name(ammo_id: int) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return CombatConstants.INVALID_AMMO_NAME
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	if def.is_empty():
		return "未知#%d" % ammo_id
	return str(def.get("name", str(ammo_id)))


func _advance_cylinder_one_step() -> void:
	## 转轮固定推进一格（60°）；空仓由 fire_next_shot 单独结算，不再跳过。
	if magazine == null or magazine.size() <= 0:
		return
	magazine.start_index = (magazine.start_index + 1) % magazine.size()


func _consume_hammer_chamber(expected_id: int) -> void:
	## 清空正上击发点那一仓，然后 start_index+1（固定转 60°）。空仓留给下一发明示结算。
	if magazine.is_empty():
		return
	var hammer: int = magazine.chamber_at_fire_port()
	if magazine.slots[hammer] == expected_id:
		magazine.slots[hammer] = Magazine.EMPTY
	else:
		# 兜底：自锤位起找第一发匹配（不应在逐步射满匣时触发）
		var i := hammer
		var seen := 0
		while seen < magazine.size():
			if magazine.slots[i] == expected_id:
				magazine.slots[i] = Magazine.EMPTY
				break
			i = (i + 1) % magazine.size()
			seen += 1
	# 末发清空后也推进一格（与中途击发一致），避免 start_index 瞬跳到 0 让 UI 红圈闪位。
	# 整匣收束 magazine.clear() 仍会归零；装弹会话会设 LOAD_SESSION_INITIAL_START。
	_advance_cylinder_one_step()


func _finish_fire() -> void:
	## 单发（或额外轮单发）收束。不 clear 弹匣——未击发弹药留在转轮里，可继续装/射。
	if _in_gold_extra_round:
		_in_gold_extra_round = false
		_log("额外轮射击完毕。总伤害 %d。匣内剩余 %d。" % [
			_fire_total_damage, magazine.loaded_count() if magazine != null else 0
		])
		_reset_fire_session()
		_set_phase(Phase.AWAIT_ACTION if (magazine != null and not magazine.is_empty()) else Phase.AWAIT_LOAD)
		_emit()
		return
	_log("本发射击完毕，伤害累计 %d。匣内剩余 %d。" % [
		_fire_total_damage, magazine.loaded_count() if magazine != null else 0
	])
	_reset_fire_session()
	if pace_after_fire:
		# 保留枪口与待追加金，供 UI 播额外轮。rush! 自动走位：不挂怪回合待办。
		if _check_end_after_player():
			_pending_gold_autofires = 0
			_post_fire_enemy_pending = false
			_emit()
			return
		_post_fire_enemy_pending = false if auto_enemy_advance else true
		_set_phase(Phase.AWAIT_ACTION if (magazine != null and not magazine.is_empty()) else Phase.AWAIT_LOAD)
		_emit()
		return
	_run_pending_gold_autofires("单发射击后")
	_pending_gold_autofires = 0
	# v0.3.4：枪口改持续时间，射击收束不再清
	if _check_end_after_player():
		_emit()
		return
	if not auto_enemy_advance:
		_run_enemy_turn()
	_emit()


func _abort_fire_cleared() -> void:
	## 连射中途敌人全灭：停射、未击发归袋；已击发金色仍尝试追加额外轮，再清枪口进胜利。
	var returned := 0
	if magazine != null and not magazine.is_empty():
		for id in magazine.slots:
			if id != Magazine.EMPTY:
				returned += 1
		_return_magazine_to_bag()
	_log("射击中途清场，未击发 %d 发归还弹药袋。总伤害 %d。" % [returned, _fire_total_damage])
	_in_gold_extra_round = false
	# 未击发已归袋，袋有弹；若场上已空则额外轮会跳过。
	if pace_after_fire:
		_reset_fire_session()
		# 场已空：额外轮无目标，直接清金/枪口进胜利
		_pending_gold_autofires = 0
		_reset_muzzle()
		_post_fire_enemy_pending = false
		_enter_won()
		_emit()
		return
	_run_pending_gold_autofires("中途清场后")
	_reset_fire_session()
	_pending_gold_autofires = 0
	_reset_muzzle()
	_enter_won()
	_emit()



func _queue_extra_autofire_from_shot(ammo_id: int) -> void:
	## v0.4.10：金币弹改为公式伤+扣金，不再追加额外轮。
	## v0.4.0：连发弹药开启/刷新连发窗。
	if ammo_id == FireResolver.ID_BURST or ammo_id == FireResolver.ID_SUPER_ROUND:
		_open_burst_window()


func _open_burst_window() -> void:
	## 连发窗：刷新为满时长（不叠多窗）。
	burst_window_remaining = CombatConstants.BURST_WINDOW_SEC
	_log("连发弹药：开启连发窗 %.1fs（窗内点射=免费平庸伤，不耗仓不转轮）。" % burst_window_remaining)
	hooks.emit_hook(&"on_burst_window", {"cs": self, "remaining": burst_window_remaining})


func is_burst_window_active() -> bool:
	return burst_window_remaining > 0.0


func is_dump_pending() -> bool:
	return _dump_pending


func is_volley_pending() -> bool:
	return _volley_pending


func spin_cylinder_for_volley() -> int:
	## v0.4.25：连射前随机转轮。0/1 发不转。不发射。UI 先逻辑转，再播动画，再出第一发弹道。
	if magazine == null or magazine.loaded_count() <= 1:
		return 0
	commit_load_session_if_active()
	if magazine == null or magazine.loaded_count() <= 1:
		return 0
	if burst_window_remaining > 0.0 or not can_fire():
		return 0
	var before: int = magazine.start_index
	var steps: int
	if magazine.loaded_count() < magazine.size():
		# v0.4.27 未装满：落点在有弹仓里均匀随机，绝不停在空仓。抽到当前仓 → 整圈（6 步，逻辑锤位不变）。
		steps = magazine.random_roll_to_loaded(rng)
		if steps < 0:
			return 0
		if steps == 0:
			steps = magazine.size()
	else:
		steps = magazine.random_roll(rng)
	if steps > 0:
		_log("连射前转轮随机 %d 步（起点槽 %d → %d）。" % [steps, before, magazine.start_index])
	_emit()
	return steps


func advance_empty_chambers() -> int:
	## 把锤位快进到最近有弹仓（不消耗弹药）。返回跳过的空仓数。
	## UI 在连射等待/开火前调用，让红圈停在「下一发要打的仓」上。
	if magazine == null or magazine.is_empty():
		return 0
	var skipped := 0
	var guard := 0
	while guard < CombatConstants.MAGAZINE_SIZE:
		var h: int = magazine.chamber_at_fire_port()
		if magazine.slots[h] != Magazine.EMPTY:
			break
		_advance_cylinder_one_step()
		skipped += 1
		guard += 1
	if skipped > 0:
		_emit()
	return skipped


static func volley_shot_interval_sec() -> float:
	## v0.4.24：连射每发间隔（未乘战斗速度）。射速帽是下限。
	return maxf(CombatConstants.VOLLEY_SHOT_INTERVAL_SEC, CombatConstants.MIN_FIRE_INTERVAL_SEC)


static func volley_rotate_sec() -> float:
	## 转一格动画时长，必须落在每发间隔之内。
	return minf(CombatConstants.VOLLEY_ROTATE_SEC, volley_shot_interval_sec())


func volley_next_empty_skips() -> int:
	## 击发位往后连续空仓数（下一发前要快转跳过的格数）。空匣返回 0。
	if magazine == null or magazine.is_empty():
		return 0
	var n := 0
	for i in CombatConstants.MAGAZINE_SIZE:
		var idx: int = (magazine.start_index + i) % CombatConstants.MAGAZINE_SIZE
		if magazine.slots[idx] != Magazine.EMPTY:
			break
		n += 1
	return n


static func volley_wait_before_next_sec() -> float:
	## 下一发前的等待（未乘战斗速度）。空仓由 advance_empty_chambers + 快转动画单独处理，不塞进这段等待。
	return volley_shot_interval_sec()


func _volley_should_continue() -> bool:
	if phase == Phase.WON or phase == Phase.LOST:
		return false
	if magazine == null or magazine.is_empty():
		return false
	return true


func interrupt_dump() -> bool:
	## 逻辑中断剩余倾泻。v0.4.22 起玩家再按开火不会走这里（连射/倾泻中按键直接忽略）。
	if not _dump_pending:
		return false
	_dump_interrupted = true
	_dump_pending = false
	_log("倾泻：被点射中断。")
	hooks.emit_hook(&"on_dump_end", {"cs": self, "interrupted": true})
	_complete_dump_followup()
	return true


func pending_gold_autofires() -> int:
	return _pending_gold_autofires


func post_fire_enemy_pending() -> bool:
	return _post_fire_enemy_pending


## UI：消耗一轮金色额外——开启逐步装填会话（不瞬装满、不扣回合）。
## 成功后请反复 load_next_chamber + apply_load_rotate（与普通装弹同动画），完成后再 begin_fire。
## 无 UI 的同步路径仍用 _auto_load_and_fire_once（测试/非 pace）。
func begin_gold_extra_load() -> bool:
	if _pending_gold_autofires <= 0:
		return false
	if alive_enemies().is_empty():
		_log("额外装填回合：战场已清空，剩余 %d 轮跳过。" % _pending_gold_autofires)
		_pending_gold_autofires = 0
		return false
	_reshuffle_if_needed_for_load()
	if bag.is_empty():
		_log("额外装填回合：无弹药可装。")
		_pending_gold_autofires = 0
		return false
	_pending_gold_autofires -= 1
	_in_gold_extra_round = true
	# rush!：不倾倒玩家已上膛弹药；只往空仓补，满匣则直接可射
	_load_session_active = false
	_load_next_slot = 0
	_load_raw_ids.clear()
	_load_resolved_ids.clear()
	if magazine.loaded_count() >= CombatConstants.MAGAZINE_SIZE:
		_log("额外轮：匣已满，直接射击（剩余待追加 %d）。" % _pending_gold_autofires)
		_set_phase(Phase.AWAIT_ACTION)
		_emit()
		return true
	_align_load_port_to_empty()
	_load_session_active = true
	_log("额外轮：自动补 1 发（不倾倒匣内弹，剩余待追加 %d）。" % _pending_gold_autofires)
	_set_phase(Phase.AWAIT_LOAD)
	_emit()
	return true


## UI：射击表现与金色额外轮都结束后，再跑怪回合（含流血）。
func resolve_post_fire_enemy_turn() -> void:
	## 兼容旧 pace：有待办才跑怪回合。rush! 自动走位时用 finalize_post_fire。
	if auto_enemy_advance:
		finalize_post_fire()
		return
	if not _post_fire_enemy_pending:
		return
	_post_fire_enemy_pending = false
	_pending_gold_autofires = 0
	# v0.3.4：枪口改持续时间，射击收束不再清
	if _check_end_after_player():
		_emit()
		return
	_run_enemy_turn()
	_emit()


func finalize_post_fire() -> void:
	## 本发（+额外轮）收束：枪口改持续时间，不再在收束时清；rush! 不进怪回合。
	_post_fire_enemy_pending = false
	_pending_gold_autofires = 0
	_turn_sin_clear_pending = false  # 愤怒/贪婪改由持续时间到期，不再延拍清
	if _check_end_after_player():
		_emit()
		return
	if magazine != null and not magazine.is_empty():
		if phase != Phase.FIRING and phase != Phase.WON and phase != Phase.LOST:
			_set_phase(Phase.AWAIT_ACTION)
	elif phase != Phase.FIRING and phase != Phase.WON and phase != Phase.LOST:
		_set_phase(Phase.AWAIT_LOAD)
	_emit()


func reset_enemy_glide() -> void:
	enemy_step_progress = 0.0
	_turn_sin_clear_pending = false
	_glide_movers.clear()
	_glide_movers_valid = false


func compute_enemy_movers() -> Dictionary:
	## 预测下一拍谁会左移 1 格（与 _move_enemy_steps 的升序占格规则一致：前方格空或前者也会走）。
	var out := {}
	var occ := occupied_cells()
	for e in enemies_sorted_by_cell():
		if e == null or e.is_dummy or int(e.mobility) <= 0:
			continue
		var next_cell: int = e.cell - 1
		if next_cell <= CombatConstants.PLAYER_CELL:
			continue
		if occ.has(next_cell):
			var front: EnemyInstance = occ[next_cell]
			if not out.has(front.get_instance_id()):
				continue
		out[e.get_instance_id()] = true
	return out


func _ensure_glide_movers() -> void:
	if _glide_movers_valid:
		return
	_glide_movers = compute_enemy_movers()
	_glide_movers_valid = true


func enemy_glide_fraction(e: EnemyInstance) -> float:
	## 视觉：该敌人在本格内已向左滑过的比例（0..1）；不会移动的敌人为 0。
	## 尸体（pace 下待飚血）保留死亡瞬间的滑行位，避免死时瞬移回格心。
	if e == null or not auto_enemy_advance:
		return 0.0
	if not e.is_alive() and not _glide_movers_valid:
		return 0.0
	_ensure_glide_movers()
	if not _glide_movers.has(e.get_instance_id()):
		return 0.0
	return clampf(enemy_step_progress, 0.0, 1.0)


func enemy_continuous_x(e: EnemyInstance) -> float:
	## 连续位置（以格为单位）：逻辑格减去本格已滑比例。
	if e == null:
		return 0.0
	return float(e.cell) - enemy_glide_fraction(e)


func advance_enemy_glide(delta_cells: float) -> int:
	## rush! 连续推进：累计滑行距离（格），每满 1 格调用一次 tick_enemy_auto_step。返回本次落格拍数。
	if shop_hold or not auto_enemy_advance or phase == Phase.WON or phase == Phase.LOST:
		return 0
	if delta_cells <= 0.0 or reward_pending:
		return 0  # v0.3.9：升级三选一 = 纯暂停，滑行进度原地不动
	_ensure_glide_movers()
	enemy_step_progress += delta_cells
	var steps := 0
	while enemy_step_progress >= 1.0 and steps < 8:
		enemy_step_progress -= 1.0
		steps += 1
		if not tick_enemy_auto_step():
			enemy_step_progress = 0.0
			break
	return steps


func tick_enemy_auto_step() -> bool:
	## rush! 连续推进一拍（滑满 1 格时落格）：会移动者向左 1 格，进入射程则攻击；结算燃烧/流血/再生/召唤。
	## 不进入 ENEMY_TURN，避免锁死装弹/射击按钮。返回 false 表示战斗已结束。
	if shop_hold or not auto_enemy_advance:
		return false
	if phase == Phase.WON or phase == Phase.LOST:
		return false
	_log("--- 敌人自动推进 ---")
	# v0.4.0：燃烧/流血改由 tick_dot(0.5s) 结算，落格拍不再跳 DoT。
	# 先算本拍移动名单：连续滑行时沿用拍首锁定的名单（新召唤/刚解除阻挡的下拍再走，避免瞬移）
	var movers: Dictionary = _glide_movers if _glide_movers_valid else compute_enemy_movers()
	for e in enemies_sorted_by_cell():
		if movers.has(e.get_instance_id()):
			var stacks: int = e.slow_stacks()
			if stacks > 0:
				e.slow_skip = (e.slow_skip + 1) % (1 + stacks)
				if e.slow_skip == 0:
					_move_enemy_steps(e, 1)
				else:
					_log("%s 减速跳过移动（缓×%d）。" % [e.name_zh, stacks])
			else:
				_move_enemy_steps(e, 1)
		if can_attack_player(e):
			_enemy_attack_or_confuse(e)
	if player_hp <= 0:
		_lose_hp()
		_emit()
		return false
	# v0.4.0 bleed → tick_dot
	_tick_zombie_regen_end_of_enemy_turn()
	_remove_dead()
	if _field_cleared():
		_enter_won()
		_emit()
		return false
	_try_super_zombie_summons()
	# v0.3.4：愤怒/贪婪改持续时间，落格拍不再清枪口；袋空仍兜底立刻补。
	_turn_sin_clear_pending = false
	ensure_bag_refilled_if_empty()
	# 下一拍重新锁定移动名单
	_glide_movers.clear()
	_glide_movers_valid = false
	# 保持玩家可操作阶段
	if phase != Phase.FIRING and phase != Phase.WON and phase != Phase.LOST:
		if magazine == null or magazine.is_empty():
			_set_phase(Phase.AWAIT_LOAD)
		else:
			_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return phase != Phase.WON and phase != Phase.LOST


func _run_pending_gold_autofires(reason: String) -> void:
	## 消耗待追加队列：每轮自动装填射击；超级回合在额外轮内可再入队，直到队列空或达安全上限。
	if _pending_gold_autofires <= 0:
		return
	var initial: int = _pending_gold_autofires
	_log("额外装填回合：%s，开始处理待追加 %d 轮（可嵌套，上限 %d）。" % [
		reason, initial, CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN
	])
	var ran := 0
	var safety: int = CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN
	while _pending_gold_autofires > 0 and ran < safety:
		if alive_enemies().is_empty():
			_log("额外装填回合：战场已清空，剩余 %d 轮跳过。" % _pending_gold_autofires)
			_pending_gold_autofires = 0
			break
		_pending_gold_autofires -= 1
		_in_gold_extra_round = true
		_auto_load_and_fire_once()
		_in_gold_extra_round = false
		_remove_dead()
		ran += 1
	if _pending_gold_autofires > 0:
		_log("额外装填回合：达安全上限，剩余 %d 轮跳过。" % _pending_gold_autofires)
		_pending_gold_autofires = 0


func _auto_load_and_fire_once() -> bool:
	## rush! 额外轮（同步）：不倾倒主匣；若有空仓从袋补 1 发，再同步打 1 发。枪口跨轮保留。
	_reshuffle_if_needed_for_load()
	if magazine == null:
		return false
	if magazine.loaded_count() < CombatConstants.MAGAZINE_SIZE and not bag.is_empty():
		_align_load_port_to_empty()
		var port: int = magazine.chamber_at_load_port()
		if magazine.slots[port] == Magazine.EMPTY:
			var drawn: Array[int] = _draw_random_from_bag(1)
			if drawn.is_empty():
				_log("额外装填回合：无弹药可装。")
				return false
			var raw_temp = _last_drawn_temps[0] if not _last_drawn_temps.is_empty() else 0.0
			var resolved: int = drawn[0]
			var swap: Dictionary = _try_insurance_swap_third_sin(resolved, raw_temp)
			resolved = int(swap.get("ammo_id", resolved))
			raw_temp = swap.get("temp", raw_temp)
			magazine.set_slot(port, resolved, _normalize_temp_for(resolved, raw_temp))
			hooks.emit_hook(&"on_chamber_loaded", {"cs": self, "ammo_id": resolved, "slot": port, "temporary": Magazine.temp_value(raw_temp) > 0.0})
			_apply_justice_strip_on_load(resolved)
			_check_sin_threshold_after_insert(resolved)
			_try_spawn_temp_sin_on_load(resolved)
			if bag.is_empty():
				needs_reshuffle_next_load = true
			_log("额外轮：补 1 发[%s]。" % _ammo_name(resolved))
	if magazine.is_empty():
		_log("额外装填回合：无弹药可射。")
		return false
	# 同步打 1 发（与 begin_fire 单发一致）
	var full_order: Array[int] = magazine.fire_order()
	var full_dmg: Array[int] = FireResolver.compute_shot_damages(full_order)
	_prepare_point_fire_damages(full_order, full_dmg)
	_fire_index = 0
	_set_phase(Phase.FIRING)
	while _fire_index < _fire_queue.size():
		if alive_enemies().is_empty():
			break
		var hammer: int = magazine.chamber_at_fire_port()
		var skip_g := 0
		while magazine.slots[hammer] == Magazine.EMPTY and skip_g < CombatConstants.MAGAZINE_SIZE:
			_advance_cylinder_one_step()
			skip_g += 1
			if magazine.is_empty():
				break
			hammer = magazine.chamber_at_fire_port()
		if magazine.is_empty() or magazine.slots[hammer] == Magazine.EMPTY:
			break
		var ammo_id: int = _fire_queue[_fire_index]
		var base_dmg: int = _fire_damages[_fire_index]
		var shot_temp: float = magazine.slot_temp_life(hammer)
		var fuse_n: int = _pebble_fuse_count
		if fuse_n >= 2 and ammo_id == FireResolver.ID_PEBBLE:
			_consume_pebble_fuse(fuse_n)
			_pebble_fuse_count = 0
			shot_temp = 0.0
		else:
			_consume_hammer_chamber(ammo_id)
		var flags := FireResolver.inherits_from(ammo_id)
		last_shot_muzzle_outline_ids = _muzzle_outline_ammo_ids_for_shot()
		_mount_sin_muzzle_from(flags)
		var pierce := _muzzle_pierce or bool(flags["pierce"])
		var gas := _muzzle_gas or bool(flags["gas"])
		var fire := _muzzle_fire or bool(flags["fire"])
		var water := _muzzle_water or bool(flags["water"])
		var thunder := _muzzle_thunder or bool(flags["thunder"])
		base_dmg = _scale_outgoing_damage(base_dmg)
		last_shot_ammo_id = ammo_id
		last_shot_hit_cell = -1
		last_shot_dealt = 0
		last_shot_hit_cells.clear()
		last_shot_hit_amounts.clear()
		last_shot_was_pierce = pierce
		# 额外轮：先挂元素枪口（含回声），本发即享受
		if fuse_n < 2:
			_discard_append(ammo_id, shot_temp)
		_mount_muzzle_from(flags)
		var dealt_auto: int = _apply_shot_with_optional_echo(ammo_id, base_dmg, pierce, gas, fire, water, thunder)
		_fire_total_damage += dealt_auto
		_maybe_spawn_pebbles_from_stone(ammo_id, dealt_auto)
		if ammo_id == FireResolver.ID_TOMBSTONE:
			_pending_tombstone_ghost_shots.append_array(_apply_tombstone_on_fire())
		_spend_gold_ammo_cost(ammo_id)
		_fire_index += 1
		_queue_extra_autofire_from_shot(ammo_id)
		_remove_dead()
	_log("额外轮单发射击完毕。")
	last_shot_was_blank = false
	last_fired_slot = -1
	_set_phase(Phase.AWAIT_ACTION if not magazine.is_empty() else Phase.AWAIT_LOAD)
	return true



func do_fire() -> bool:
	## 测试/同步路径：把匣内剩余弹一发发打完。
	## 每发后若有超级回合/金色额外轮，同步打完额外轮；怪回合 defer 到整段打完（避免测试被怪打死）。
	var any := false
	while can_fire():
		if not begin_fire():
			break
		any = true
		while phase == Phase.FIRING:
			fire_next_shot()
		# 额外轮：同步自动装填射击（_auto_load_and_fire_once）
		if _pending_gold_autofires > 0:
			_run_pending_gold_autofires("do_fire")
		if phase == Phase.WON or phase == Phase.LOST:
			_post_fire_enemy_pending = false
			return any
		# 吞掉单发后的怪回合标记，最后统一打一次
		if _post_fire_enemy_pending:
			_post_fire_enemy_pending = false
	if any and phase != Phase.WON and phase != Phase.LOST:
		_pending_gold_autofires = 0
		# v0.3.4：枪口改持续时间，do_fire 收束不再清
		if not _check_end_after_player() and not auto_enemy_advance:
			_run_enemy_turn()
		_emit()
	return any


## v0.4.22：一次开火打光已装弹。resolve_dump_sync=true 时本调用内打完（测试）；false 时只打第一发，其余交给 take_volley_shot / 倾泻步进。
## 连发窗内仍是免费平庸、不耗仓。倾泻主发仍走 0.06s 步进。连射或倾泻进行中再按 = 忽略。
## v0.4.25：连射前可由 spin_cylinder_for_volley 随机转；UI 每发之间按 VOLLEY_SHOT_INTERVAL_SEC 转一格。
## 红圈对准：advance_empty_chambers 先跳过空仓，_present_tap_shots 先闪击发仓再转格。
func fire_tap(resolve_dump_sync: bool = true) -> Array:
	var shots: Array = []
	if _volley_pending or _dump_pending:
		return shots
	if player_fire_gate_remaining > 0.0:
		return shots
	hooks.emit_hook(&"on_fire", {"cs": self, "burst_window": burst_window_remaining > 0.0})
	if sloth_fire_penalty_remaining > 0.0:
		fire_lock_remaining = maxf(fire_lock_remaining, CombatConstants.SLOTH_FIRE_LOCK_SEC)
	if burst_window_remaining > 0.0:
		var free_rec: Dictionary = _fire_virtual_ammo_shot(CombatConstants.WHITE_AMMO_ID, 0.0, false)
		free_rec["burst_free"] = true
		free_rec["extra"] = true
		shots.append(free_rec)
		# on_shot 已在 virtual 内发出（含回声第二下）；此处只补 UI 分录
		_append_echo_twin_shot(shots, free_rec, false)
		if auto_enemy_advance:
			finalize_post_fire()
		elif _post_fire_enemy_pending:
			resolve_post_fire_enemy_turn()
		_arm_player_fire_gate(shots)
		return shots
	if not can_fire():
		return shots
	if not begin_fire():
		return shots
	var fired_id_before: int = -1
	if magazine != null and not magazine.is_empty():
		fired_id_before = magazine.fire_order()[0]
	_fire_tap_one(shots)
	# 墓碑幽灵连射已在 fire_next_shot 非 paced 路径或 finalize 后由 _pending_tombstone_ghost_shots 注入
	for g in _consume_pending_tombstone_ghost_shots():
		shots.append(g)
		_append_echo_twin_from_rec(shots, g)
	# 倾泻：主发是倾泻则自动打剩余仓
	if fired_id_before == FireResolver.ID_DUMP and phase != Phase.WON and phase != Phase.LOST:
		_dump_pending = true
		_dump_interrupted = false
		hooks.emit_hook(&"on_dump_start", {"cs": self})
		_log("倾泻：开始自动射击剩余仓。")
		if resolve_dump_sync:
			var dguard := CombatConstants.MAGAZINE_SIZE + 2
			while _dump_pending and dguard > 0 and phase != Phase.WON and phase != Phase.LOST:
				dguard -= 1
				var more: Array = take_dump_shot()
				if more.is_empty():
					break
				shots.append_array(more)
		else:
			# UI 按 DUMP_SHOT_INTERVAL_SEC 步进；金色/收束延到倾泻结束。
			_dump_followup_pending = true
			_arm_player_fire_gate(shots)
			return shots
	elif _volley_should_continue():
		if resolve_dump_sync:
			_fire_volley_rest(shots)
		else:
			_volley_pending = true
			_volley_followup_pending = true
			_arm_player_fire_gate(shots)
			return shots
	var guard: int = CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN + 2
	while _pending_gold_autofires > 0 and guard > 0 and phase != Phase.WON and phase != Phase.LOST:
		guard -= 1
		if not begin_gold_extra_load():
			break
		if _load_session_active:
			var lr: Dictionary = load_next_chamber()
			if bool(lr.get("ok", false)) and not bool(lr.get("done", false)):
				apply_load_rotate()
			commit_load_session_if_active()
		if magazine == null or magazine.is_empty() or not can_fire():
			break
		if not begin_fire():
			break
		_fire_tap_one(shots, true)
		for g2 in _consume_pending_tombstone_ghost_shots():
			shots.append(g2)
			_append_echo_twin_from_rec(shots, g2)
	if auto_enemy_advance:
		finalize_post_fire()
	elif _post_fire_enemy_pending:
		resolve_post_fire_enemy_turn()
	_arm_player_fire_gate(shots)
	return shots


func _fire_volley_rest(shots: Array) -> void:
	## 同步打完剩余已装弹。空仓由 fire_next_shot 直接跳过，不单独占一发间隔。
	var guard := CombatConstants.MAGAZINE_SIZE + 3
	var saw_dump := false
	while guard > 0 and _volley_should_continue():
		guard -= 1
		if not can_fire() or not begin_fire():
			break
		var next_id := -1
		if magazine != null and not magazine.is_empty():
			var order: Array[int] = magazine.fire_order()
			if not order.is_empty():
				next_id = int(order[0])
		if next_id == FireResolver.ID_DUMP and not saw_dump:
			saw_dump = true
			hooks.emit_hook(&"on_dump_start", {"cs": self})
			_log("倾泻：连射途中打出倾泻弹。")
		_fire_tap_one(shots, true)
		for g in _consume_pending_tombstone_ghost_shots():
			shots.append(g)
			_append_echo_twin_from_rec(shots, g)
	if saw_dump:
		hooks.emit_hook(&"on_dump_end", {"cs": self, "interrupted": false})


func take_volley_shot() -> Array:
	## 连射步进：打出下一发已装弹。空仓在这一发里快跳。途中遇到倾泻则把剩余仓交给倾泻步进。
	var out: Array = []
	if not _volley_pending:
		return out
	if not _volley_should_continue() or not can_fire() or not begin_fire():
		_finish_volley()
		return out
	var next_id := -1
	if magazine != null and not magazine.is_empty():
		var order: Array[int] = magazine.fire_order()
		if not order.is_empty():
			next_id = int(order[0])
	_fire_tap_one(out, true)
	for g in _consume_pending_tombstone_ghost_shots():
		out.append(g)
		_append_echo_twin_from_rec(out, g)
	if (
		next_id == FireResolver.ID_DUMP
		and phase != Phase.WON and phase != Phase.LOST
		and magazine != null and not magazine.is_empty()
	):
		_volley_pending = false
		_volley_followup_pending = false
		_dump_pending = true
		_dump_interrupted = false
		_dump_followup_pending = true
		hooks.emit_hook(&"on_dump_start", {"cs": self})
		_log("倾泻：连射途中改为倾泻步进。")
		return out
	if not _volley_should_continue():
		_finish_volley()
	return out


func _finish_volley() -> void:
	_volley_pending = false
	if not _volley_followup_pending:
		return
	_volley_followup_pending = false
	if phase == Phase.WON or phase == Phase.LOST:
		return
	if auto_enemy_advance:
		finalize_post_fire()
	elif _post_fire_enemy_pending:
		resolve_post_fire_enemy_turn()
	player_fire_gate_remaining = CombatConstants.MIN_FIRE_INTERVAL_SEC


func _arm_player_fire_gate(shots: Array) -> void:
	## 打出至少一发才进入射速间隔。倾泻的后续步进不走这里。
	if shots.is_empty():
		return
	player_fire_gate_remaining = CombatConstants.MIN_FIRE_INTERVAL_SEC


func take_dump_shot() -> Array:
	## 倾泻步进：打出下一发已装填仓；无可打或已中断则结束倾泻。
	var out: Array = []
	if not _dump_pending or _dump_interrupted:
		_dump_pending = false
		return out
	if phase == Phase.WON or phase == Phase.LOST:
		_finish_dump(false)
		return out
	if magazine == null or magazine.is_empty() or not can_fire():
		_finish_dump(false)
		return out
	if not begin_fire():
		_finish_dump(false)
		return out
	_fire_tap_one(out, true)
	for g in _consume_pending_tombstone_ghost_shots():
		out.append(g)
		_append_echo_twin_from_rec(out, g)
	if magazine == null or magazine.is_empty():
		_finish_dump(false)
	return out


func _finish_dump(interrupted: bool) -> void:
	if not _dump_pending and not interrupted:
		return
	_dump_pending = false
	if interrupted:
		_dump_interrupted = true
	_log("倾泻：结束%s。" % ("（中断）" if interrupted else ""))
	hooks.emit_hook(&"on_dump_end", {"cs": self, "interrupted": interrupted})
	_complete_dump_followup()


func _complete_dump_followup() -> void:
	## 异步倾泻结束后补跑金色额外轮 + 收束（与 fire_tap 同步路径末尾对齐）。
	if not _dump_followup_pending:
		return
	_dump_followup_pending = false
	if phase == Phase.WON or phase == Phase.LOST:
		return
	var guard: int = CombatConstants.MAX_EXTRA_AUTOFIREs_PER_CHAIN + 2
	while _pending_gold_autofires > 0 and guard > 0 and phase != Phase.WON and phase != Phase.LOST:
		guard -= 1
		if not begin_gold_extra_load():
			break
		if _load_session_active:
			var lr: Dictionary = load_next_chamber()
			if bool(lr.get("ok", false)) and not bool(lr.get("done", false)):
				apply_load_rotate()
			commit_load_session_if_active()
		if magazine == null or magazine.is_empty() or not can_fire():
			break
		if not begin_fire():
			break
		var discard: Array = []
		_fire_tap_one(discard, true)
		for g2 in _consume_pending_tombstone_ghost_shots():
			pass
	if auto_enemy_advance:
		finalize_post_fire()
	elif _post_fire_enemy_pending:
		resolve_post_fire_enemy_turn()


func _fire_tap_one(shots: Array, extra: bool = false) -> void:
	var start_before: int = magazine.start_index if magazine != null else 0
	while phase == Phase.FIRING:
		fire_next_shot()
		if has_paced_shot_pending():
			var rec := {
				"extra": extra,
				"ammo_id": last_shot_ammo_id,
				"slot": last_fired_slot,
				"blank_skip": last_blank_skip_steps,
				"start_before": start_before,
				"hit_cells": last_shot_hit_cells.duplicate(),
				"muzzle_outline_ids": last_shot_muzzle_outline_ids.duplicate(),
				"pierce": last_shot_was_pierce,
			}
			finalize_paced_shot()
			rec["hit_amounts"] = last_shot_hit_amounts.duplicate()
			rec["start_after"] = magazine.start_index if magazine != null else 0
			shots.append(rec)
			hooks.emit_hook(&"on_shot", {"cs": self, "ammo_id": int(rec["ammo_id"]), "virtual": false, "dealt": _sum_hit_amounts(rec)})
			_append_echo_twin_shot(shots, rec)
		elif last_shot_ammo_id >= 0:
			# 非 paced 路径（测试常关 pace）：补一条记录
			var rec2 := {
				"extra": extra,
				"ammo_id": last_shot_ammo_id,
				"slot": last_fired_slot,
				"blank_skip": last_blank_skip_steps,
				"start_before": start_before,
				"start_after": magazine.start_index if magazine != null else 0,
				"hit_cells": last_shot_hit_cells.duplicate(),
				"hit_amounts": last_shot_hit_amounts.duplicate(),
				"muzzle_outline_ids": last_shot_muzzle_outline_ids.duplicate(),
				"pierce": last_shot_was_pierce,
			}
			shots.append(rec2)
			hooks.emit_hook(&"on_shot", {"cs": self, "ammo_id": last_shot_ammo_id, "virtual": false, "dealt": _sum_hit_amounts(rec2)})
			_append_echo_twin_shot(shots, rec2)


func _append_echo_twin_from_rec(shots: Array, primary: Dictionary) -> void:
	## 仅用 rec 自带的 echo_twin_*（幽灵等虚拟击发），不读全局 last_echo_*。
	if not primary.has("echo_twin_amounts"):
		return
	var twin: Dictionary = primary.duplicate(true)
	twin["echo"] = true
	twin["hit_cells"] = primary.get("echo_twin_cells", [])
	twin["hit_amounts"] = primary.get("echo_twin_amounts", [])
	shots.append(twin)


func _append_echo_twin_shot(shots: Array, primary: Dictionary, emit_hook: bool = true) -> void:
	## 回声第二波：再记一条 shot 供 UI 播第二发；可选再 emit 一次 on_shot。
	if primary.has("echo_twin_amounts") and not last_shot_was_echoed:
		_append_echo_twin_from_rec(shots, primary)
		return
	if not last_shot_was_echoed:
		return
	var twin: Dictionary = primary.duplicate(true)
	twin["echo"] = true
	twin["hit_cells"] = last_echo_hit_cells.duplicate()
	twin["hit_amounts"] = last_echo_hit_amounts.duplicate()
	shots.append(twin)
	if emit_hook:
		hooks.emit_hook(&"on_shot", {
			"cs": self,
			"ammo_id": int(twin.get("ammo_id", -1)),
			"virtual": bool(twin.get("virtual", false)),
			"echo": true,
			"dealt": _sum_hit_amounts(twin),
		})


func _sum_hit_amounts(rec: Dictionary) -> int:
	var t := 0
	for a in rec.get("hit_amounts", []):
		t += int(a)
	return t


## 测试辅助：只打 1 发并立刻结算怪回合（对齐 UI 点射一次）。
func do_fire_one() -> bool:
	if not begin_fire():
		return false
	while phase == Phase.FIRING:
		fire_next_shot()
	if _pending_gold_autofires > 0:
		_run_pending_gold_autofires("do_fire_one")
	if auto_enemy_advance:
		finalize_post_fire()
	elif _post_fire_enemy_pending:
		resolve_post_fire_enemy_turn()
	return true


## 仅转动转轮并记日志；不结束行动（供装填后 spin / UI 动画先转再结算）。失败 -1；多发步数 ∈ [1,size-1]，单发 0。
func apply_roll() -> int:
	if not can_start_roll():
		return -1
	commit_load_session_if_active()
	var before := magazine.start_index
	var steps: int = magazine.random_roll(rng)
	if magazine.loaded_count() <= 1:
		_log("重 roll：仅 %d 发，转轮不转（步数 0）。" % magazine.loaded_count())
	else:
		_log("重 roll：大盘随机转动 %d 步（击发红圈固定）。起点槽 %d → %d。" % [
			steps, before, magazine.start_index
		])
	_emit()
	return steps


## 玩家行动（射击/卸除/ROLL）结束后：判胜负或进入怪物回合。
func resolve_after_player_action() -> void:
	if _check_end_after_player():
		_emit()
		return
	if not auto_enemy_advance:
		_run_enemy_turn()
	_emit()


## 随机转轮并结束本回合（进怪物回合）。匣内仍有弹则怪回合后回 AWAIT_ACTION。UI：先 apply_roll 再 resolve_after_player_action。
func begin_roll() -> bool:
	if apply_roll() < 0:
		return false
	resolve_after_player_action()
	return true


func do_unload() -> bool:
	if not can_unload():
		return false
	commit_load_session_if_active()
	var removed_entries: Array = magazine.unload_all_entries()
	for entry in removed_entries:
		var id: int = int(entry.get("id", Magazine.EMPTY))
		var is_temp = entry.get("temp", 0.0)
		_discard_append(id, is_temp)
	var removed_size: int = removed_entries.size()
	_log("卸除 %d 发进入弃牌堆。" % removed_size)
	if _check_end_after_player():
		_emit()
		return true
	if not auto_enemy_advance:
		_run_enemy_turn()
	elif magazine.is_empty():
		_set_phase(Phase.AWAIT_LOAD)
	else:
		_set_phase(Phase.AWAIT_ACTION)
	_emit()
	return true


func _check_end_after_player() -> bool:
	_remove_dead()
	if _field_cleared():
		_enter_won()
		return true
	if player_hp <= 0:
		_lose_hp()
		return true
	return false


func _remove_dead() -> void:
	var kept: Array = []
	for e in enemies:
		if e.is_alive():
			kept.append(e)
		else:
			_log("%s 被击败。" % e.name_zh)
			_try_envy_copy_on_kill()
			_try_gluttony_heal_on_kill()
			var xp_cell: int = e.cell
			var xp_amt: int = xp_for_enemy(e)
			if xp_amt > 0:
				xp_orb_spawned.emit(xp_cell, xp_amt)
				hooks.emit_hook(&"on_xp_gain", {"cs": self, "amount": xp_amt, "cell": xp_cell})
			var dropped: int = _try_kill_gold_drop(e)
			hooks.emit_hook(&"on_kill", {
				"cs": self, "enemy_id": e.get_instance_id(), "cell": e.cell,
				"def_id": e.def_id, "gold": dropped,
			})
			if dropped > 0:
				hooks.emit_hook(&"on_kill_gold", {
					"cs": self, "enemy_id": e.get_instance_id(), "cell": e.cell,
					"def_id": e.def_id, "amount": dropped,
				})
			gain_xp(xp_for_enemy(e))
	enemies = kept


# ——— v0.3.8 经验值 ———

static func xp_needed_for_level(lv: int) -> int:
	var k: int = maxi(lv, 1) - 1
	return CombatConstants.XP_BASE + CombatConstants.XP_LINEAR * k + CombatConstants.XP_QUAD * k * k


func xp_needed() -> int:
	return xp_needed_for_level(level)


func xp_for_enemy(e) -> int:
	if e == null:
		return 0
	var v: int = maxi(1, int(e.max_hp))
	if int(e.def_id) == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
		v *= CombatConstants.XP_BOSS_MULT
	return v


func gain_xp(amount: int) -> void:
	## 击杀得经验；满了升级（溢出保留），每升一级排队一次三选一。
	if amount <= 0 or phase == Phase.LOST:
		return
	xp += amount
	var ups := 0
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		ups += 1
	if ups <= 0:
		return
	pending_levelups += ups
	_log("经验 +%d → 升到 Lv%d（待选奖励 %d 次）。" % [amount, level, pending_levelups])
	if not reward_pending:
		_begin_levelup_reward()


func _begin_levelup_reward() -> void:
	if pending_levelups <= 0:
		return
	reward_choices = generate_reward_choices()
	reward_pending = true
	reward_resolved = false
	last_reward_base_gold = 0
	_emit()


func _finish_one_levelup_reward() -> void:
	pending_levelups = maxi(0, pending_levelups - 1)
	if pending_levelups > 0:
		reward_choices = generate_reward_choices()
		reward_pending = true
		reward_resolved = false
	else:
		reward_pending = false
		reward_resolved = false
		reward_choices.clear()


func is_paused_for_reward() -> bool:
	return reward_pending


# ——— v0.3.8 连续刷怪 ———

func _field_cleared() -> bool:
	## 无波次：场上清空 → 立刻按规则补刷（不进胜利、不刷新任何状态）。永远返回 false。
	if not alive_enemies().is_empty():
		return false
	if spawn_paused:
		return false  # 沙盒：清场不自动补怪
	if reward_pending or has_corpse_enemies():
		# v0.3.9：升级三选一期间一律不刷怪（纯暂停）；选完恢复战斗时由 tick_combat_time 补刷。
		# 还有尸体（pace 飚血未清）时也先不刷：尸体清掉才发经验，避免先刷怪、后弹升级。
		return false
	_spawn_up_to_cap(true)
	_spawn_timer = spawn_interval_now()
	return false


func spawn_interval_now() -> float:
	return maxf(CombatConstants.SPAWN_INTERVAL_MIN, CombatConstants.SPAWN_INTERVAL_START - CombatConstants.SPAWN_INTERVAL_DECAY * elapsed_sec)


func spawn_alive_cap_now() -> int:
	var c: int = int(ceil((1.0 + elapsed_sec / CombatConstants.SPAWN_CAP_GROW_SEC) * CombatConstants.WAVE_SPAWN_COUNT_MULT))
	return mini(CombatConstants.BOARD_SIZE - 1, maxi(1, c))


func _pseudo_wave_now() -> int:
	return 1 + int(floor(elapsed_sec / CombatConstants.SPAWN_POOL_STEP_SEC))


func _free_spawn_cell() -> int:
	var occ: Dictionary = {}
	for c in occupied_cells():
		occ[int(c)] = true
	for k in CombatConstants.SPAWN_LANE_CELLS:
		var cell: int = CombatConstants.BOARD_SIZE - 1 - k
		if cell <= CombatConstants.PLAYER_CELL:
			break
		if not occ.has(cell):
			return cell
	return -1


func _spawn_enemy_at_lane(eid: int) -> bool:
	var cell: int = _free_spawn_cell()
	if cell < 0:
		return false
	var def: Dictionary = DataRegistry.get_enemy(eid)
	if def.is_empty():
		return false
	var e: EnemyInstance = _make_scaled_enemy(def, cell)
	enemies.append(e)
	_log("刷怪：%s 出现在格 %d（HP%d，%.0f 秒）。" % [e.name_zh, cell, e.max_hp, elapsed_sec])
	return true


func _pick_spawn_enemy_id() -> int:
	var pool: Array[int] = _spawn_pool_for_wave(_pseudo_wave_now())
	return pool[rng.randi_range(0, pool.size() - 1)]


func _spawn_up_to_cap(force_one: bool = false) -> int:
	var n := 0
	var cap: int = spawn_alive_cap_now()
	if force_one and alive_enemies().size() >= cap:
		cap = alive_enemies().size() + 1
	var guard := 12
	while alive_enemies().size() < cap and guard > 0:
		guard -= 1
		if not _spawn_enemy_at_lane(_pick_spawn_enemy_id()):
			break
		n += 1
	return n


func tick_combat_time(delta_sec: float) -> bool:
	## UI 每帧（战斗秒×速度，暂停/奖励期间不调用）：累计时长、刷怪、Boss、临时罪孽寿命、连发窗、DoT、地图商店。返回是否有变化。
	if shop_hold or delta_sec <= 0.0 or phase == Phase.LOST or phase == Phase.WON or reward_pending:
		return false
	var changed := false
	elapsed_sec += delta_sec
	if burst_window_remaining > 0.0:
		burst_window_remaining = maxf(0.0, burst_window_remaining - delta_sec)
		changed = true
	if player_confuse_remaining > 0.0:
		player_confuse_remaining = maxf(0.0, player_confuse_remaining - delta_sec)
		changed = true
	if sloth_fire_penalty_remaining > 0.0:
		sloth_fire_penalty_remaining = maxf(0.0, sloth_fire_penalty_remaining - delta_sec)
		changed = true
	if fire_lock_remaining > 0.0:
		fire_lock_remaining = maxf(0.0, fire_lock_remaining - delta_sec)
		changed = true
	tick_player_fire_gate(delta_sec)
	# 枪口层时长：与战斗秒同一入口，避免沙盒/脚本只推 tick_combat_time 时永不掉层。
	# UI 勿再另调 tick_muzzle_durations，否则会双倍衰减。
	changed = tick_muzzle_durations(delta_sec) or changed
	# 暴食击杀回血预算：每秒回复 = 层数 × GLUTTONY_PROCS_PER_SEC_PER_LAYER，上限=层数
	if _muzzle_gluttony > 0:
		var cap: float = float(_muzzle_gluttony) * CombatConstants.GLUTTONY_PROCS_PER_SEC_PER_LAYER
		_gluttony_heal_budget = minf(cap, _gluttony_heal_budget + cap * delta_sec)
	else:
		_gluttony_heal_budget = 0.0
	for e in enemies:
		if e != null:
			e.tick_status_timers(delta_sec)
	changed = tick_temp_sin_lifetimes(delta_sec) or changed
	changed = tick_dot(delta_sec) or changed
	changed = tick_map_shop(delta_sec) or changed
	if not spawn_paused:
		var boss_due: int = int(floor(elapsed_sec / CombatConstants.BOSS_EVERY_SEC))
		if boss_due > _boss_spawned:
			_boss_spawned = boss_due
			var bn: int = mini(int(ceil(float(boss_due) * CombatConstants.WAVE_SPAWN_COUNT_MULT)), CombatConstants.SPAWN_LANE_CELLS)
			var made := 0
			for _i in bn:
				if _spawn_enemy_at_lane(CombatConstants.SUPER_ZOMBIE_ENEMY_ID):
					made += 1
			if made > 0:
				encounter_kind = EncounterKind.BOSS
				_log("Boss 来袭：超级僵尸 ×%d（%.0f 秒）。" % [made, elapsed_sec])
				changed = true
		if alive_enemies().is_empty() and not has_corpse_enemies():
			# 三选一期间清场被推迟的补刷：恢复战斗第一帧补上（Boss 先占刷怪口）
			_field_cleared()
			changed = true
		_spawn_timer -= delta_sec
		if _spawn_timer <= 0.0:
			if alive_enemies().size() < spawn_alive_cap_now() and _spawn_enemy_at_lane(_pick_spawn_enemy_id()):
				changed = true
				_spawn_timer = spawn_interval_now()
			else:
				_spawn_timer = 0.25  # 满员或刷怪口被占：稍后重试
	if changed:
		_emit()
	return changed


func _resolve_burn_dot_tick() -> bool:
	## 燃烧一跳：先把层数一半（向上取整）扩散给相邻（高格位先），再受等同层数伤害并 -1。
	var burners: Array = []
	for e in alive_enemies():
		if e != null and e.burn_stacks > 0:
			burners.append(e)
	if burners.is_empty():
		return false
	burners.sort_custom(func(a, b): return a.cell > b.cell)  # 数字高 → 低
	var snap: Dictionary = {}
	for e in burners:
		snap[e] = int(e.burn_stacks)
	var by_cell := occupied_cells()
	# 扩散（拷贝，不扣自身）
	for e in burners:
		var b: int = int(snap.get(e, 0))
		var give: int = int(ceili(float(b) / 2.0))
		if give <= 0:
			continue
		for dc in [-1, 1]:
			var nc: int = e.cell + dc
			if not by_cell.has(nc):
				continue
			var other: EnemyInstance = by_cell[nc] as EnemyInstance
			if other == null or not other.is_alive():
				continue
			other.burn_stacks += give
			_log("%s 燃烧扩散 +%d → %s（现 %d）" % [e.name_zh, give, other.name_zh, other.burn_stacks])
	# 伤害并 -1（用扩散后的当前层数）
	for e in alive_enemies():
		if e.burn_stacks <= 0:
			continue
		var b2: int = e.burn_stacks
		var dealt: int = e.apply_damage(b2)
		_notify_enemy_damage(e, dealt, "燃烧")
		e.burn_stacks = maxi(0, e.burn_stacks - 1)
		_log("%s 燃烧结算伤害%d，燃烧剩余%d" % [e.name_zh, dealt, e.burn_stacks])
	return true


func tick_dot(delta_sec: float) -> bool:
	## v0.4.0：燃烧/流血每 DOT_TICK_SEC 跳一次（不再挂落格拍）。v0.4.3：燃烧先扩散再跳伤。
	if delta_sec <= 0.0:
		return false
	_dot_timer -= delta_sec
	if _dot_timer > 0.0:
		return false
	_dot_timer += CombatConstants.DOT_TICK_SEC
	if _dot_timer <= 0.0:
		_dot_timer = CombatConstants.DOT_TICK_SEC
	var changed := false
	hooks.emit_hook(&"on_dot_tick", {"cs": self, "kind": "all"})
	if gluttony_self_dot_remaining > 0.0:
		gluttony_self_dot_remaining = maxf(0.0, gluttony_self_dot_remaining - CombatConstants.DOT_TICK_SEC)
		_apply_player_damage(CombatConstants.GLUTTONY_SELF_DOT_DAMAGE, "暴食")
		_log("暴食持续掉血 %d（HP %d/%d · 剩余 %.1fs）" % [
			CombatConstants.GLUTTONY_SELF_DOT_DAMAGE, player_hp, player_max_hp, gluttony_self_dot_remaining
		])
		changed = true
		if player_hp <= 0:
			_lose_hp()
	if _resolve_burn_dot_tick():
		changed = true
	_remove_dead()
	if _field_cleared():
		_enter_won()
		_emit()
		return true
	_tick_bleed_end_of_enemy_turn()
	_remove_dead()
	if _field_cleared():
		_enter_won()
		_emit()
		return true
	if changed:
		_emit()
	return true



func acknowledge_shop_touch() -> void:
	shop_touch_pending = false


func tick_map_shop(delta_sec: float) -> bool:
	## v0.4.0 地图商店骨架：右侧刷出商店实体，随时间向左靠近；碰到玩家（cell<=1）打开商店。
	if map_shop_disabled:
		return false
	var changed := false
	var due_first := elapsed_sec >= CombatConstants.MAP_SHOP_FIRST_SEC and shop_spawn_count == 0
	var next_at := CombatConstants.MAP_SHOP_FIRST_SEC + float(shop_spawn_count) * CombatConstants.MAP_SHOP_RESPAWN_SEC
	var due_again := shop_spawn_count > 0 and shop_cell < 0 and not shop_touch_pending and elapsed_sec >= next_at
	if (due_first or due_again) and shop_cell < 0:
		shop_cell = CombatConstants.BOARD_SIZE - 1
		shop_spawn_count += 1
		_shop_move_prog = 0.0
		_log("地图商店出现在格 %d。" % shop_cell)
		changed = true
	if shop_cell >= 0:
		_shop_move_prog += delta_sec / CombatConstants.MAP_SHOP_STEP_SEC
		while _shop_move_prog >= 1.0 and shop_cell > 0:
			_shop_move_prog -= 1.0
			shop_cell -= 1
			changed = true
			_log("地图商店移至格 %d。" % shop_cell)
			if shop_cell <= CombatConstants.PLAYER_CELL + 1:
				shop_touch_pending = true
				_log("地图商店碰到玩家 → 打开商店。")
				hooks.emit_hook(&"on_shop_enter", {"cs": self, "shop_cell": shop_cell})
				shop_cell = -1
				_shop_move_prog = 0.0
				break
	return changed


func shop_glide_fraction() -> float:
	## 地图商店在当前格内已向左滑过的比例（0..1）。UI 每帧用它插值，避免一格一跳。
	if shop_cell < 0:
		return 0.0
	return clampf(_shop_move_prog, 0.0, 1.0)


func shop_visual_cell() -> float:
	## 连续格坐标。-1 = 商店不在场。
	if shop_cell < 0:
		return -1.0
	return float(shop_cell) - shop_glide_fraction()


func tick_player_fire_gate(delta_sec: float) -> void:
	## 射速帽独立于「敌人是否在自动走」。商店打开 / 升级三选一 / 胜负时停表。
	if shop_hold or reward_pending or delta_sec <= 0.0:
		return
	if phase == Phase.WON or phase == Phase.LOST:
		return
	if player_fire_gate_remaining > 0.0:
		player_fire_gate_remaining = maxf(0.0, player_fire_gate_remaining - delta_sec)


func player_status_ring_entries() -> Array:
	## 玩家自己的倒计时环：混乱、射速变慢（懒惰三罪）、自伤 DoT。锚点由 UI 按玩家位置摆。
	var out: Array = []
	if player_confuse_remaining > 0.0:
		out.append(_player_timed_ring(
			"confuse", "乱", player_confuse_remaining, CombatConstants.LUST_SELF_CONFUSE_SEC,
			Color(0.95, 0.45, 0.9)
		))
	if sloth_fire_penalty_remaining > 0.0:
		out.append(_player_timed_ring(
			"slow", "缓", sloth_fire_penalty_remaining, CombatConstants.SLOTH_FIRE_PENALTY_SEC,
			Color(0.45, 0.75, 1.0)
		))
	elif fire_lock_remaining > 0.0:
		out.append(_player_timed_ring(
			"lock", "锁", fire_lock_remaining, CombatConstants.SLOTH_FIRE_LOCK_SEC,
			Color(0.75, 0.75, 0.85)
		))
	if gluttony_self_dot_remaining > 0.0:
		out.append(_player_timed_ring(
			"dot", "伤", gluttony_self_dot_remaining, CombatConstants.MUZZLE_DURATION_GLUTTONY_SEC,
			Color(1.0, 0.45, 0.2)
		))
	return out


func _player_timed_ring(id: String, label: String, remaining: float, total: float, col: Color) -> Dictionary:
	var tot: float = maxf(maxf(total, remaining), 0.01)
	return {
		"id": id,
		"label": label,
		"stacks": 1,
		"remaining": remaining,
		"total": tot,
		"ratio": clampf(remaining / tot, 0.0, 1.0),
		"timed": true,
		"color": col,
	}


func tick_temp_sin_lifetimes(delta_sec: float) -> bool:
	## 每颗临时罪孽独立寿命；到期从所在处移除（袋 / 弃牌 / 转轮仓→变空仓）。
	if delta_sec <= 0.0:
		return false
	var changed := false
	_sync_temp_arrays()
	var i := bag.size() - 1
	while i >= 0:
		var tv: float = Magazine.temp_value(bag_temp[i])
		if tv > 0.0:
			tv -= delta_sec
			if tv <= 0.0:
				expired_temp_events.append({"where": "bag", "slot": -1, "id": int(bag[i])})
				_log("临时%s到期消失（袋）。" % _ammo_name(int(bag[i])))
				bag.remove_at(i)
				bag_temp.remove_at(i)
				changed = true
			else:
				bag_temp[i] = tv
		i -= 1
	i = discard.size() - 1
	while i >= 0:
		var dv: float = Magazine.temp_value(discard_temp[i])
		if dv > 0.0:
			dv -= delta_sec
			if dv <= 0.0:
				expired_temp_events.append({"where": "discard", "slot": -1, "id": int(discard[i])})
				discard.remove_at(i)
				discard_temp.remove_at(i)
				changed = true
			else:
				discard_temp[i] = dv
		i -= 1
	if magazine != null:
		for s in magazine.slots.size():
			if not magazine.is_slot_temporary(s):
				continue
			var mv: float = magazine.slot_temp_life(s) - delta_sec
			if mv <= 0.0:
				expired_temp_events.append({"where": "mag", "slot": s, "id": int(magazine.slots[s])})
				_log("临时%s到期消失（转轮仓 %d → 空仓）。" % [_ammo_name(int(magazine.slots[s])), s])
				magazine.set_slot(s, Magazine.EMPTY)
				changed = true
			else:
				magazine.temp_slots[s] = mv
	if changed:
		_emit()
	return changed


func temp_lifetimes_in_bag() -> Array:
	## UI：袋内临时罪孽剩余寿命（与 bag 同序，永久弹 0）。
	var out: Array = []
	for i in bag.size():
		out.append(Magazine.temp_value(bag_temp[i]) if i < bag_temp.size() else 0.0)
	return out



func flush_dead_enemies() -> void:
	## UI：弹点命中飚血播完后再清尸体并刷新。
	_remove_dead()
	_field_cleared()  # v0.3.9：清场补刷在发完经验之后（若刚升级则推迟到选完）
	_emit()


func has_corpse_enemies() -> bool:
	for e in enemies:
		if e != null and not e.is_alive():
			return true
	return false


func _run_enemy_turn() -> void:
	_set_phase(Phase.ENEMY_TURN)
	_log("--- 怪物回合 ---")
	# 燃烧跳伤（与 tick_dot 同一套：先扩散再结算）
	_resolve_burn_dot_tick()
	_remove_dead()
	if _field_cleared():
		_enter_won()
		return
	var order: Array = enemies_sorted_by_cell()
	for e in order:
		_move_enemy(e)
		if can_attack_player(e):
			_enemy_attack_or_confuse(e)
		else:
			_log("%s 未进入射程，不攻击（格 %d · 射程 %d）。" % [e.name_zh, e.cell, e.attack_range])
	if player_hp <= 0:
		_lose_hp()
		return
	_tick_bleed_end_of_enemy_turn()
	_tick_zombie_regen_end_of_enemy_turn()
	_remove_dead()
	if _field_cleared():
		_enter_won()
		return
	# 超级僵尸：每怪物回合在面前召唤一只僵尸
	_try_super_zombie_summons()
	# v0.3.4：枪口改持续时间，怪回合末不再清愤怒/贪婪；袋空立刻补。
	ensure_bag_refilled_if_empty()
	# ROLL 不清空弹匣：匣内仍有弹 → 可继续 FIRE/ROLL/UNLOAD；仅空匣才要求装填
	if magazine.is_empty():
		_set_phase(Phase.AWAIT_LOAD)
		_log("--- 请装填 ---")
	else:
		_set_phase(Phase.AWAIT_ACTION)
		_log("--- 请选择行动（膛内仍有弹药）---")


func _tick_bleed_end_of_enemy_turn() -> void:
	## 生物流血：回合结束失去等同层数生命，然后层数-1。石头对 debuff 伤害同样无视 <4。
	for e in alive_enemies():
		if e.bleed_stacks <= 0:
			continue
		var stacks: int = e.bleed_stacks
		var dealt: int = e.apply_damage(stacks)
		_notify_enemy_damage(e, dealt, "流血")
		e.bleed_stacks = maxi(0, e.bleed_stacks - 1)
		_log("%s 流血结算伤害%d（层%d→%d）" % [e.name_zh, dealt, stacks, e.bleed_stacks])


func _try_super_zombie_summons() -> void:
	## 超级僵尸每回合在自己面前（更低格号、朝向玩家）召唤一只僵尸；无空位则不生成。
	var bosses: Array = []
	for e in alive_enemies():
		if e.def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID:
			bosses.append(e)
	for boss in bosses:
		var front: int = boss.cell - 1
		if front <= CombatConstants.PLAYER_CELL:
			_log("%s 面前无空位，召唤失败。" % boss.name_zh)
			continue
		if occupied_cells().has(front):
			_log("%s 面前格 %d 已占用，召唤失败。" % [boss.name_zh, front])
			continue
		var def: Dictionary = DataRegistry.get_enemy(CombatConstants.ZOMBIE_ENEMY_ID)
		if def.is_empty():
			continue
		var z := EnemyInstance.new(def, front)
		enemies.append(z)
		_log("%s 召唤僵尸于面前格 %d。" % [boss.name_zh, front])


func _tick_zombie_regen_end_of_enemy_turn() -> void:
	## 僵尸标签：回合结束回复 5 HP（不超过上限）。
	for e in alive_enemies():
		if not e.has_tag("僵尸"):
			continue
		if e.hp >= e.max_hp:
			continue
		var before: int = e.hp
		e.hp = mini(e.max_hp, e.hp + 5)
		_log("%s 僵尸再生 +%d（HP %d/%d）。" % [e.name_zh, e.hp - before, e.hp, e.max_hp])


func _move_enemy(e: EnemyInstance) -> void:
	_move_enemy_steps(e, e.mobility)


func _move_enemy_steps(e: EnemyInstance, steps: int) -> void:
	## 向玩家方向（格号减小）推进最多 steps 格；遇玩家格或占格则停。
	var occ := occupied_cells()
	for _s in maxi(steps, 0):
		var next_cell: int = e.cell - 1
		if next_cell <= CombatConstants.PLAYER_CELL:
			break
		if occ.has(next_cell):
			break
		occ.erase(e.cell)
		e.cell = next_cell
		occ[e.cell] = e
	_log("%s 移动至格 %d。" % [e.name_zh, e.cell])


func phase_name() -> String:
	match phase:
		Phase.AWAIT_LOAD:
			return "等待装填"
		Phase.AWAIT_ACTION:
			return "选择行动"
		Phase.FIRING:
			return "射击中"
		Phase.ENEMY_TURN:
			return "怪物回合"
		Phase.WON:
			return "胜利"
		Phase.LOST:
			return "失败"
		_:
			return "未知"



func _clear_reward_state() -> void:
	reward_pending = false
	reward_resolved = false
	reward_choices.clear()


func _enter_won() -> void:
	## v0.3.8：已无波次胜利。旧调用点等价于「场上清空 → 立刻补刷」，不清任何状态。
	_field_cleared()

## 从启用弹药表随机抽 3 个（池≥3 时去重；不足则允许重复）。同名可多份入袋。
func generate_reward_choices() -> Array[int]:
	var pool: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			pool.append(aid)
	if pool.is_empty():
		pool.append(CombatConstants.WHITE_AMMO_ID)
	var out: Array[int] = []
	var need: int = CombatConstants.REWARD_CHOICE_COUNT
	if pool.size() >= need:
		var work: Array[int] = pool.duplicate()
		_shuffle(work)
		for i in need:
			out.append(work[i])
	else:
		for _i in need:
			out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


func can_pick_reward() -> bool:
	## v0.3.8：升级三选一，与阶段无关（战斗暂停中）。
	return reward_pending and not reward_resolved and phase != Phase.LOST


## 选择三选一中的第 index 发（0..2），加入弹药袋。
func pick_reward_ammo(index: int) -> bool:
	if not can_pick_reward():
		return false
	if index < 0 or index >= reward_choices.size():
		return false
	var ammo_id: int = reward_choices[index]
	_bag_append(ammo_id, false)
	# 不重拍基线（袋此刻只是部分池）：直接把奖励弹记入构筑基线
	if not DataRegistry.is_ammo_ephemeral(ammo_id):
		_combat_bag_baseline.append(ammo_id)
	_log("升级奖励：选择 %s 加入弹药袋（袋内 %d，Lv%d）。" % [_ammo_name(ammo_id), bag.size(), level])
	_finish_one_levelup_reward()
	_emit()
	return true


## 放弃三选一，换额外金币。
func skip_reward_for_gold() -> bool:
	if not can_pick_reward():
		return false
	var extra: int = CombatConstants.REWARD_SKIP_EXTRA_GOLD
	gold += extra
	_finish_one_levelup_reward()
	_log("奖励：放弃三选一，额外金币 +%d（现 %d）。" % [extra, gold])
	_emit()
	return true


## 灰盒预留：无伤通关额外金（当前恒 0）。
func _hook_no_damage_bonus_gold() -> int:
	if wave_took_damage:
		return 0
	return CombatConstants.REWARD_NO_DAMAGE_EXTRA_GOLD


## 灰盒预留：三回合内通关额外金（当前恒 0）。
func _hook_fast_clear_bonus_gold() -> int:
	if wave_player_turns > CombatConstants.REWARD_FAST_CLEAR_TURN_LIMIT:
		return 0
	return CombatConstants.REWARD_FAST_CLEAR_EXTRA_GOLD


func _spawn_pool_for_wave(w: int) -> Array[int]:
	## 沿用原波次表的种类池（非 Boss）；Boss 改为按时间单独刷。
	if w <= 1:
		return [1] as Array[int]
	if w == 2:
		return [1, 2] as Array[int]
	if w == 3:
		return [1, 2, 3] as Array[int]
	if w == 4:
		return [4] as Array[int]
	return [1, 2, 3, 4] as Array[int]


func encounter_label() -> String:
	match encounter_kind:
		EncounterKind.BOSS:
			return "Boss 波"
		_:
			return "战斗"


func reward_base_gold_for_encounter() -> int:
	match encounter_kind:
		EncounterKind.BOSS:
			return CombatConstants.REWARD_BOSS_BASE_GOLD
		_:
			return CombatConstants.REWARD_BASE_GOLD


## rush!：敌人直接用表内数值（超级僵尸 Boss 波亦然）。
func _make_scaled_enemy(def: Dictionary, cell: int) -> EnemyInstance:
	return EnemyInstance.new(def, cell)


# ——— 开发者工具 ———

func dev_add_ammo(ammo_id: int, count: int = 1) -> void:
	## 仅允许战斗启用弹药（平庸+罪孽）；老子弹等退役弹不可加袋。
	if ammo_id != CombatConstants.INVALID_AMMO_ID and not DataRegistry.is_ammo_enabled(ammo_id):
		_log("[开发] 已退役弹药不可添加：%s" % _ammo_name(ammo_id))
		return
	for _i in count:
		_bag_append(ammo_id, false)
		_note_baseline_add(ammo_id, false)
	_log("[开发] 弹药袋 +%d × %s（现 %d）" % [count, _ammo_name(ammo_id), bag.size()])
	_emit()


func dev_remove_ammo(ammo_id: int, count: int = 1) -> void:
	_sync_temp_arrays()
	var left := count
	var i := 0
	while i < bag.size() and left > 0:
		if bag[i] == ammo_id:
			var tv = bag_temp[i] if i < bag_temp.size() else 0.0
			var perm := _counts_as_permanent(int(bag[i]), tv)
			bag.remove_at(i)
			if i < bag_temp.size():
				bag_temp.remove_at(i)
			if perm:
				_baseline_remove_one(ammo_id)
			left -= 1
		else:
			i += 1
	_log("[开发] 移除 %s 后袋内 %d" % [_ammo_name(ammo_id), bag.size()])
	_emit()


func dev_clear_bag() -> void:
	var n: int = bag.size()
	bag.clear()
	bag_temp.clear()
	_log("[开发] 清空弹药袋（移除 %d）" % n)
	_emit()


func dev_kill_all_enemies() -> void:
	for e in enemies:
		e.hp = 0
	_remove_dead()
	_log("[开发] 一键杀敌")
	if _field_cleared():
		_enter_won()
	_emit()


func dev_add_gold(amount: int = 10) -> void:
	gold += amount
	_log("[开发] 金币 %+d → %d" % [amount, gold])
	_emit()


func dev_set_player_hp(v: int) -> void:
	player_hp = clampi(v, 0, player_max_hp)
	_log("[开发] 玩家 HP → %d" % player_hp)
	if player_hp <= 0:
		_lose_hp()
	_emit()


func dev_set_front_enemy_hp(v: int) -> void:
	var e := front_enemy()
	if e == null:
		_log("[开发] 无敌人")
		return
	e.hp = clampi(v, 0, e.max_hp)
	_log("[开发] %s HP → %d" % [e.name_zh, e.hp])
	_remove_dead()
	_emit()


func dev_teleport_front_enemy(cell: int) -> void:
	var e := front_enemy()
	if e == null:
		_log("[开发] 无敌人")
		return
	var c := clampi(cell, CombatConstants.PLAYER_CELL + 1, CombatConstants.BOARD_SIZE - 1)
	var occ := occupied_cells()
	occ.erase(e.cell)
	if occ.has(c):
		_log("[开发] 格 %d 已占用" % c)
		return
	e.cell = c
	_log("[开发] %s 瞬移至格 %d" % [e.name_zh, e.cell])
	_emit()


func dev_force_load(ids: Array[int]) -> void:
	if phase != Phase.AWAIT_LOAD and phase != Phase.AWAIT_ACTION:
		_log("[开发] 当前阶段无法强制装填")
		return
	_reset_focus_shot_counter()
	magazine.load_sequence(ids)
	if FireResolver.ID_JUSTICE in ids:
		_apply_justice_strip_on_load(FireResolver.ID_JUSTICE)
	turn_index += 1
	_set_phase(Phase.AWAIT_ACTION)
	_log("[开发] 强制装填 %s" % str(ids))
	_emit()


func dev_skip_enemy_turn() -> void:
	if phase == Phase.FIRING:
		_log("[开发] 射击中不可跳过")
		return
	_set_phase(Phase.AWAIT_LOAD)
	_log("[开发] 跳过怪物回合 → 请装填")
	_emit()


func dev_spawn_enemy(enemy_id: int, cell: int = -1) -> void:
	var def: Dictionary = DataRegistry.get_enemy(enemy_id)
	if def.is_empty():
		_log("[开发] 未知敌人 id=%d" % enemy_id)
		return
	if not bool(def.get("enabled_in_combat", false)):
		_log("[开发] 已退役敌人不可生成：%s" % def.get("name", enemy_id))
		return
	var c := cell
	if c < 0:
		c = CombatConstants.BOARD_SIZE - 1
		while occupied_cells().has(c) and c > CombatConstants.PLAYER_CELL + 1:
			c -= 1
	if occupied_cells().has(c) or c <= CombatConstants.PLAYER_CELL:
		_log("[开发] 无法在格 %d 生成" % c)
		return
	enemies.append(EnemyInstance.new(def, c))
	_log("[开发] 生成 %s 于格 %d" % [def.get("name", enemy_id), c])
	_emit()


# ——— 沙盒 ———

static func sandbox_muzzle_kinds() -> PackedStringArray:
	return PackedStringArray([
		"pierce", "gas", "flame", "water", "thunder", "echo", "explosive", "lifesteal",
		"wrath", "pride", "greed", "lust", "envy", "gluttony", "sloth",
	])


static func _sandbox_normalize_muzzle_kind(kind: String) -> String:
	## 挂弹路径 emit kind=flame；沙盒对外统一 flame（兼容旧别名 fire）。
	if kind == "fire":
		return "flame"
	return kind


static func sandbox_muzzle_label(kind: String) -> String:
	kind = _sandbox_normalize_muzzle_kind(kind)
	match kind:
		"pierce": return "穿甲"
		"gas": return "汽油"
		"flame": return "火焰"
		"water": return "水"
		"thunder": return "雷"
		"echo": return "回声"
		"explosive": return "炸药"
		"lifesteal": return "吸血"
		"wrath": return "愤怒"
		"pride": return "傲慢"
		"greed": return "贪婪"
		"lust": return "色欲"
		"envy": return "嫉妒"
		"gluttony": return "暴食"
		"sloth": return "懒惰"
		_: return kind


func _sandbox_muzzle_layers(kind: String) -> Array:
	kind = _sandbox_normalize_muzzle_kind(kind)
	match kind:
		"pierce": return _muzzle_pierce_layers
		"gas": return _muzzle_gas_layers
		"flame": return _muzzle_fire_layers
		"water": return _muzzle_water_layers
		"thunder": return _muzzle_thunder_layers
		"echo": return _muzzle_echo_layers
		"explosive": return _muzzle_explosive_layers
		"lifesteal": return _muzzle_lifesteal_layers
		"wrath": return _muzzle_wrath_layers
		"pride": return _muzzle_pride_layers
		"greed": return _muzzle_greed_layers
		"lust": return _muzzle_lust_layers
		"envy": return _muzzle_envy_layers
		"gluttony": return _muzzle_gluttony_layers
		"sloth": return _muzzle_sloth_layers
		_: return []


func _sandbox_muzzle_max_stacks(kind: String) -> int:
	kind = _sandbox_normalize_muzzle_kind(kind)
	match kind:
		"pierce", "gas", "flame", "water", "thunder", "echo", "explosive":
			return 1
		_:
			return 99


func sandbox_set_muzzle(kind: String, stacks: int, duration_sec: float) -> bool:
	## 用自定义层数与每层剩余秒覆写枪口（stacks=0 或 duration<=0 即清除该种）。
	kind = _sandbox_normalize_muzzle_kind(kind)
	if kind not in sandbox_muzzle_kinds():
		_log("[沙盒] 未知枪口 kind=%s" % kind)
		return false
	var layers: Array = _sandbox_muzzle_layers(kind)
	stacks = clampi(stacks, 0, _sandbox_muzzle_max_stacks(kind))
	layers.clear()
	if stacks > 0 and duration_sec > 0.0:
		for _i in stacks:
			layers.append(duration_sec)
	if kind == "gluttony":
		# 覆写层数时直接对齐 cap（勿用 maxf，避免减层后预算偏高）
		if _muzzle_gluttony > 0:
			_gluttony_heal_budget = float(_muzzle_gluttony) * CombatConstants.GLUTTONY_PROCS_PER_SEC_PER_LAYER
		else:
			_gluttony_heal_budget = 0.0
	_log("[沙盒] 枪口【%s】→ ×%d · 每层 %.1fs" % [sandbox_muzzle_label(kind), layers.size(), maxf(0.0, duration_sec)])
	hooks.emit_hook(&"on_muzzle_apply", {"cs": self, "kind": kind, "stacks_after": layers.size()})
	_emit()
	return true


func sandbox_clear_muzzle(kind: String = "") -> void:
	if kind.is_empty():
		_reset_muzzle()
		_clear_all_sin_muzzle(true)
		_log("[沙盒] 已清空全部枪口")
		_emit()
		return
	sandbox_set_muzzle(kind, 0, 0.0)


func sandbox_add_ammo(ammo_id: int, count: int = 1, temp_life: float = 0.0) -> void:
	## 沙盒：任意表内弹药可入袋；temp_life>0 则为临时寿命（秒）。
	if DataRegistry.get_ammo(ammo_id).is_empty() and ammo_id != CombatConstants.INVALID_AMMO_ID:
		_log("[沙盒] 未知弹药 id=%d" % ammo_id)
		return
	var n: int = maxi(0, count)
	var life: float = maxf(0.0, temp_life)
	for _i in n:
		_bag_append(ammo_id, life)
		_note_baseline_add(ammo_id, life)
	_log("[沙盒] 袋 +%d × %s%s（现 %d）" % [
		n, _ammo_name(ammo_id),
		(" · TTL %.1fs" % life) if life > 0.0 else "",
		bag.size()
	])
	_emit()


func sandbox_set_bag_temp(index: int, temp_life: float) -> bool:
	_sync_temp_arrays()
	if index < 0 or index >= bag.size():
		_log("[沙盒] 袋下标无效 %d" % index)
		return false
	var aid: int = int(bag[index])
	var was_perm := _counts_as_permanent(aid, bag_temp[index])
	bag_temp[index] = _normalize_temp_for(aid, maxf(0.0, temp_life))
	var now_perm := _counts_as_permanent(aid, bag_temp[index])
	if was_perm and not now_perm:
		_baseline_remove_one(aid)
	elif (not was_perm) and now_perm:
		_combat_bag_baseline.append(aid)
	_log("[沙盒] 袋[%d] %s TTL → %.1fs" % [index, _ammo_name(aid), float(bag_temp[index])])
	_emit()
	return true


func sandbox_spawn_enemy(enemy_id: int, cell: int = -1) -> bool:
	## 沙盒生成：允许表内 enabled 敌人（含木桩）。
	var before: int = enemies.size()
	dev_spawn_enemy(enemy_id, cell)
	return enemies.size() > before


func sandbox_spawn_dummy(hp: int = -1, cell: int = -1) -> EnemyInstance:
	var def: Dictionary = DataRegistry.get_enemy(CombatConstants.DUMMY_ENEMY_ID)
	if def.is_empty():
		def = {
			"id": CombatConstants.DUMMY_ENEMY_ID,
			"name": "木桩",
			"hp": CombatConstants.SANDBOX_DUMMY_DEFAULT_HP,
			"atk": 0,
			"mobility": 0,
			"tags": ["木桩"],
			"dummy": true,
		}
	var c := cell
	if c < 0:
		c = CombatConstants.BOARD_SIZE - 1
		while occupied_cells().has(c) and c > CombatConstants.PLAYER_CELL + 1:
			c -= 1
	if occupied_cells().has(c) or c <= CombatConstants.PLAYER_CELL:
		_log("[沙盒] 无法在格 %d 生成木桩" % c)
		return null
	var e := EnemyInstance.new(def, c)
	e.is_dummy = true
	e.mobility = 0
	e.atk = 0
	e.attack_range = 0
	var want_hp: int = hp if hp > 0 else CombatConstants.SANDBOX_DUMMY_DEFAULT_HP
	e.max_hp = want_hp
	e.hp = want_hp
	enemies.append(e)
	_log("[沙盒] 木桩 HP%d 于格 %d" % [e.hp, e.cell])
	_emit()
	return e


func sandbox_clear_enemies() -> void:
	enemies.clear()
	_log("[沙盒] 已清空场上敌人")
	_emit()


func sandbox_set_enemy_status(opts: Dictionary) -> bool:
	## 作用于最前方存活敌人。键：burn/gas/wet/bleed(int)、confuse(float秒)、slow_stacks(int)、slow_sec(float)。
	var e: EnemyInstance = front_enemy()
	if e == null:
		_log("[沙盒] 无敌人可改状态")
		return false
	if opts.has("burn"):
		e.burn_stacks = maxi(0, int(opts.get("burn", 0)))
	if opts.has("gas"):
		e.gas_stacks = maxi(0, int(opts.get("gas", 0)))
	if opts.has("wet"):
		e.wet_stacks = maxi(0, int(opts.get("wet", 0)))
	if opts.has("bleed"):
		e.bleed_stacks = maxi(0, int(opts.get("bleed", 0)))
	if opts.has("burn"):
		e.burn_peak = e.burn_stacks
	if opts.has("bleed"):
		e.bleed_peak = e.bleed_stacks
	if opts.has("confuse"):
		e.set_confuse_remaining(float(opts.get("confuse", 0.0)))
	if opts.has("slow_stacks"):
		e.clear_slow_layers()
		var n: int = maxi(0, int(opts.get("slow_stacks", 0)))
		var sec: float = float(opts.get("slow_sec", CombatConstants.SLOTH_SLOW_LAYER_SEC))
		for _i in n:
			e.add_slow_layer(maxf(0.01, sec))
	if opts.has("hp"):
		e.hp = clampi(int(opts.get("hp", e.hp)), 0, maxi(e.max_hp, int(opts.get("hp", e.hp))))
		if int(opts.get("hp", 0)) > e.max_hp:
			e.max_hp = int(opts.get("hp", e.max_hp))
			e.hp = e.max_hp
	_log("[沙盒] %s 状态 → %s" % [e.name_zh, e.status_text()])
	_emit()
	return true


func sandbox_set_player_timer(kind: String, sec: float) -> bool:
	var v: float = maxf(0.0, sec)
	match kind:
		"burst":
			burst_window_remaining = v
		"confuse":
			player_confuse_remaining = v
		"sloth_penalty":
			sloth_fire_penalty_remaining = v
		"fire_lock":
			fire_lock_remaining = v
		"gluttony_dot":
			gluttony_self_dot_remaining = v
		_:
			_log("[沙盒] 未知玩家计时 kind=%s" % kind)
			return false
	_log("[沙盒] 玩家计时 %s → %.1fs" % [kind, v])
	_emit()
	return true


func sandbox_refill_empty_chambers(ammo_id: int = CombatConstants.WHITE_AMMO_ID) -> int:
	if magazine == null:
		return 0
	var n := 0
	for i in magazine.slots.size():
		if int(magazine.slots[i]) == Magazine.EMPTY:
			magazine.set_slot(i, ammo_id, false)
			n += 1
	if n > 0:
		if phase == Phase.AWAIT_LOAD:
			_set_phase(Phase.AWAIT_ACTION)
		_log("[沙盒] 空仓补 %d × %s" % [n, _ammo_name(ammo_id)])
		_emit()
	return n


func sandbox_set_spawn_paused(paused: bool) -> void:
	spawn_paused = paused
	if not spawn_paused:
		_spawn_timer = 0.25
	_log("[沙盒] 连续刷怪 %s" % ("暂停" if spawn_paused else "恢复"))
	_emit()


func sandbox_reset(sin_ammo_id: int = -1) -> void:
	var sid: int = selected_sin_ammo_id if sin_ammo_id < 0 else sin_ammo_id
	start_sandbox(0, sid)
