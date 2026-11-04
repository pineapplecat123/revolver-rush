class_name CombatConstants
## 战斗常量表（灰盒）。

const BOARD_SIZE := 10
const PLAYER_CELL := 0
const MAGAZINE_SIZE := 6
const PLAYER_MAX_HP := 20
const WHITE_AMMO_ID := 1
const CIVILIAN_ENEMY_ID := 1
const ZOMBIE_ENEMY_ID := 4
const SUPER_ZOMBIE_ENEMY_ID := 5
const DUMMY_ENEMY_ID := 900  ## 沙盒木桩
const SANDBOX_DUMMY_DEFAULT_HP := 999
## v0.4.20 沙盒：进沙盒默认摆 3 个木桩（隔一格站开，方便测散射/爆炸/连锁）。
const SANDBOX_DEFAULT_DUMMY_CELLS: Array[int] = [3, 5, 7]
## v0.4.20 沙盒伤害统计：DPS 与「最近单次最大」都看最近这么多战斗秒。
const SANDBOX_DPS_WINDOW_SEC := 5.0
## 灰盒开局：平庸弹 + 所选罪孽弹。
const STARTER_WHITE_COUNT := 10
const STARTER_SIN_COUNT := 5
const STARTER_BAG_TOTAL := STARTER_WHITE_COUNT + STARTER_SIN_COUNT

## 战斗胜利奖励（灰盒）
const REWARD_BASE_GOLD := 10
const REWARD_SKIP_EXTRA_GOLD := 5
const REWARD_CHOICE_COUNT := 3
# 预留（灰盒不做）：无伤额外金、三回合内额外金
const REWARD_NO_DAMAGE_EXTRA_GOLD := 0
const REWARD_FAST_CLEAR_EXTRA_GOLD := 0
const REWARD_FAST_CLEAR_TURN_LIMIT := 3

## 灰盒：无效弹药（Boss 塞袋用；非 Excel 表行，本地常量）
const INVALID_AMMO_ID := 9001
const INVALID_AMMO_NAME := "无效弹药"

## rush! Boss 波（超级僵尸）基础金币
const REWARD_BOSS_BASE_GOLD := 25

## 无效弹药说明（袋内详情用）
const INVALID_AMMO_SPECIAL := "击发伤害为 0。由 Boss 等效果塞入弹药袋，占用抽弹名额。"

## 转轮端口（屏幕固定角）
## 击发点 = 正上（仓位角度 -90°）。六等分无法同时占正上与正左，上弹口取左上仓（相对击发 +5 步 = -60°）。
const FIRE_PORT_OFFSET_STEPS := 0
const LOAD_PORT_OFFSET_STEPS := 5
## begin_load 时 start_index，使仓 0 对准上弹口：(1+5)%6=0
const LOAD_SESSION_INITIAL_START := 1

## 金色/超级回合额外装填射击：单次玩家开火链最多追加轮数（防全匣超级回合软锁）
const MAX_EXTRA_AUTOFIREs_PER_CHAIN := 10

## rush! 敌人连续向左滑行：走完 1 格所需秒数（受战斗速度倍率影响）。
## v0.3.2 为 1.15s/格一跳；v0.3.3 改平滑连续并放慢约 30%（1.65s/格 ≈ 41 px/s @CELL_W 68）。
## v0.4.26：所有敌人移动速度 ×0.5（1.65 → 3.3 s/格，≈41 → ≈21 px/s）。攻击/伤害/血量不变。
## v0.4.28 自由行走：刷在最右格再往外 1.6 格（视野外）；走进到右侧 0.45 格内才能被打到；个体速度 ±13%。
const WALK_IN_SPAWN_OFFSET_CELLS := 1.6
const WALK_IN_TARGETABLE_SLACK := 0.45
const ENEMY_SPEED_VARIATION := 0.13
const ENEMY_AUTO_STEP_SEC := 3.3
## 走路动画按 1.65 s/格 设计；播放速度 = 实际滑行速度 × 这个值（1× 战斗速度下 = 0.5）。
const ENEMY_WALK_ANIM_REF_STEP_SEC := 1.65
## 地图商店滑行速度保持原样（不跟敌人一起减速）。
const MAP_SHOP_STEP_SEC := 1.65

## rush! 波次刷怪数量倍率（相对设计表）；ceil 后上限 BOARD_SIZE-1。
const WAVE_SPAWN_COUNT_MULT := 1.5

## 枪口状态持续时间（秒，受战斗速度倍率缩放；傲慢整场，无计时）。
## 设计表原为「挂上到回合结束」；rush! 无经典回合，改为固定秒数。
const MUZZLE_DURATION_WRATH_SEC := 4.0
const MUZZLE_DURATION_GREED_SEC := 4.0
const MUZZLE_DURATION_ELEMENT_SEC := 4.0  ## 穿甲/汽油/火/水/雷/回声
const MUZZLE_DURATION_LIFESTEAL_SEC := 4.0  ## 吸血（可叠层）
## v0.3.7：傲慢也计时，明显长于其它枪口（口头「计时比较久」→ 选 12 秒）。
const MUZZLE_DURATION_PRIDE_SEC := 12.0


## ——— v0.3.8 无波次 / 经验值 / 临时罪孽寿命 ———
## 临时罪孽（装入时 20% +1 同种）寿命：10 秒（战斗秒 × 速度，暂停时停）。v0.4.20：18→10。
const TEMP_SIN_LIFETIME_SEC := 10.0
## 经验：击杀得 XP = 敌人 max_hp（Boss/超级僵尸 ×2）。
const XP_BOSS_MULT := 2
## 升级阈值：need(L) = XP_BASE + XP_LINEAR*(L-1) + XP_QUAD*(L-1)^2  → L1 30, L2 55, L3 90, L4 135, L5 190 …
const XP_BASE := 30
const XP_LINEAR := 20
const XP_QUAD := 5
## 连续刷怪：间隔 = max(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_START - SPAWN_INTERVAL_DECAY*秒)
const SPAWN_INTERVAL_START := 4.0
const SPAWN_INTERVAL_MIN := 1.2
const SPAWN_INTERVAL_DECAY := 0.02
## 场上存活上限 = min(BOARD_SIZE-1, ceil((1 + 秒/SPAWN_CAP_GROW_SEC) × WAVE_SPAWN_COUNT_MULT))
const SPAWN_CAP_GROW_SEC := 45.0
## 种类池按「伪波次」= 1 + floor(秒/SPAWN_POOL_STEP_SEC) 沿用原波次表
const SPAWN_POOL_STEP_SEC := 30.0
## Boss：每 BOSS_EVERY_SEC 秒刷 ceil(k×1.5) 只超级僵尸（k=第几次 Boss）
const BOSS_EVERY_SEC := 180.0
## 只在最右 SPAWN_LANE_CELLS 格内刷（尊重占格）
const SPAWN_LANE_CELLS := 3

## ——— v0.4.0 语法基建 ———
## 装入罪孽时 20% 概率袋内 +1 同种临时罪孽（三罪孽惩罚不再加临时）。v0.4.20：0.33→0.20。
const LOAD_TEMP_SIN_CHANCE := 0.20
## DoT（燃烧/流血）独立 0.5s 跳一次，不再挂在落格拍。
const DOT_TICK_SEC := 0.5
## 地图商店：首次出现与再次刷新间隔（战斗秒）。
const MAP_SHOP_FIRST_SEC := 45.0
const MAP_SHOP_RESPAWN_SEC := 90.0
## 幽灵 TTL：与临时罪孽同寿命。
## v0.4.20 墓碑：打出时袋里没幽灵 → 生成这么多颗临时幽灵
const TOMBSTONE_GHOST_SPAWN := 2
const GHOST_TTL_SEC := 18.0  ## v0.4.20：与临时罪孽寿命拆开，保持 18 秒
## 小石头 TTL：与幽灵同寿命。
const PEBBLE_TTL_SEC := 18.0  ## v0.4.20：与临时罪孽寿命拆开，保持 18 秒
## 嫉妒击杀复制非罪弹入袋的 TTL（v0.4.20 从临时罪孽寿命拆出，保持 18 秒）
const ENVY_COPY_TTL_SEC := 18.0

## 吸血枪口：每层概率与回血比例。
const LIFESTEAL_CHANCE_PER_STACK := 0.20
const LIFESTEAL_HEAL_RATIO := 0.50

## ——— v0.4.11+ 空壳四罪 ———
const MUZZLE_DURATION_LUST_SEC := 4.0
const MUZZLE_DURATION_ENVY_SEC := 4.0
const MUZZLE_DURATION_GLUTTONY_SEC := 4.0
const MUZZLE_DURATION_SLOTH_SEC := 4.0
## 色欲：每层使命中敌人混乱的概率；混乱持续秒数；三罪自混乱秒数。
const LUST_CONFUSE_CHANCE_PER_STACK := 0.20
const LUST_CONFUSE_SEC := 1.0
const LUST_SELF_CONFUSE_SEC := 1.0
## 嫉妒：击杀时每层复制上一发非罪的概率；三罪弃牌数。
const ENVY_COPY_CHANCE_PER_STACK := 0.30
const ENVY_THREE_SIN_DISCARD := 2
## 暴食：击杀回 1 HP；每层每秒最多 1 次；三罪自伤 DoT 每跳伤害。
const GLUTTONY_HEAL_ON_KILL := 1
const GLUTTONY_PROCS_PER_SEC_PER_LAYER := 1.0
const GLUTTONY_SELF_DOT_DAMAGE := 1
## 懒惰：减速层时长；三罪射速窗与开火锁（窗内每次开火后锁住，近似 −50% 射速）。
const SLOTH_SLOW_LAYER_SEC := 3.0
const SLOTH_FIRE_PENALTY_SEC := 4.0
const SLOTH_FIRE_LOCK_SEC := 0.5

## v0.4.21 玩家点射射速帽。手动连点与连发窗免费点射共用，不能快过这个数。
## 10 次/秒 = 间隔 0.1 秒。
const MAX_FIRE_RATE_HZ := 10.0
const MIN_FIRE_INTERVAL_SEC := 0.1

## v0.4.24 一键连射节奏：打一发 → 转轮转一格（动画）→ 下一发 …… 直到已装弹打完。
## 间隔吃战斗速度；不会快过 MIN_FIRE_INTERVAL_SEC。转一格动画 VOLLEY_ROTATE_SEC 放在间隔之内。
## 空仓不单独等一整格间隔：并进下一发的转动里，每个空仓只多 VOLLEY_EMPTY_SKIP_SEC。
const VOLLEY_SHOT_INTERVAL_SEC := 0.25
const VOLLEY_ROTATE_SEC := 0.18
const VOLLEY_EMPTY_SKIP_SEC := 0.04
## v0.4.24：装满后、开火前都不再随机转轮；从当前击发仓直接开打。
const LOAD_FULL_RANDOM_SPIN := false

## v0.4.21 击杀掉金币。普通怪 25% 掉 2；Boss（超级僵尸）必掉 8。木桩不掉。
const KILL_GOLD_DROP_CHANCE := 0.25
const KILL_GOLD_DROP_AMOUNT := 2
const KILL_GOLD_BOSS_DROP_CHANCE := 1.0
const KILL_GOLD_BOSS_DROP_AMOUNT := 8

