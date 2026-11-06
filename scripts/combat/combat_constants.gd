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

## feat/gameplay-redo：运行时只露平庸弹（袋开局/店/奖励/图鉴/沙盒列表）；测试仍可直接塞其它 id。
## 运行时默认 true（combat_ui / main 也会钉死）；GUT 用 test_00 关掉，避免旧测试炸开局袋。
static var GAMEPLAY_REDO_PLAIN_ONLY: bool = true
## 「手」区容量；倒出最多抽这么多。
const HAND_SIZE := 6
## plain-only 开局袋：足够多的平庸，方便测倒出/装入手感。
const STARTER_PLAIN_ONLY_COUNT := 24

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
const MUZZLE_DURATION_WRATH_SEC := 8.0
const MUZZLE_DURATION_GREED_SEC := 8.0
const MUZZLE_DURATION_ELEMENT_SEC := 8.0  ## 穿甲/汽油/火/水/雷/回声/炸药
const MUZZLE_DURATION_LIFESTEAL_SEC := 8.0  ## 吸血（可叠层）
## v0.4.36：傲慢 30 秒。
const MUZZLE_DURATION_PRIDE_SEC := 30.0


## ——— v0.3.8 无波次 / 经验值 / 临时罪孽寿命 ———
## v0.4.36：临时罪孽不再计时；打出即毁（与嫉妒复制同）。保留常量名兼容旧调用，值为 0。
const TEMP_SIN_LIFETIME_SEC := 0.0
## 临时/嫉妒一次性标记写入 temp 槽的哨兵（<0 = 不计时，打出即毁）。
const FIRE_ONCE_TEMP := -1.0
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
## DoT（燃烧/流血/暴食自伤）独立 0.7s 跳一次，不再挂在落格拍。
const DOT_TICK_SEC := 0.7
## 地图商店：首次出现与再次刷新间隔（战斗秒）。
const MAP_SHOP_FIRST_SEC := 45.0
const MAP_SHOP_RESPAWN_SEC := 90.0
## 幽灵 TTL：与临时罪孽同寿命。
## v0.4.20 墓碑：打出时袋里没幽灵 → 生成这么多颗临时幽灵
const TOMBSTONE_GHOST_SPAWN := 2
const GHOST_TTL_SEC := 30.0  ## v0.4.36：30 秒
## 小石头 TTL：与幽灵同寿命。
const PEBBLE_TTL_SEC := 30.0  ## v0.4.36：30 秒
## 嫉妒复制弹：一次性临时，打出即毁；不再设 TTL 兜底（v0.4.36）。
const ENVY_COPY_TTL_SEC := 0.0
## v0.4.30：嫉妒持续期间，每发「打中敌人」的子弹有此概率复制自身一发一次性临时弹
const ENVY_HIT_COPY_CHANCE := 0.25

## 吸血枪口：每层概率与回血比例。
const LIFESTEAL_CHANCE_PER_STACK := 0.20
const LIFESTEAL_HEAL_RATIO := 0.50

## ——— v0.4.11+ 空壳四罪 ———
const MUZZLE_DURATION_LUST_SEC := 8.0
const MUZZLE_DURATION_ENVY_SEC := 8.0
const MUZZLE_DURATION_GLUTTONY_SEC := 8.0
const MUZZLE_DURATION_SLOTH_SEC := 8.0
## 色欲：每层使命中敌人混乱的概率；混乱持续秒数；三罪自混乱秒数。
const LUST_CONFUSE_CHANCE_PER_STACK := 0.20
const LUST_CONFUSE_SEC := 5.0
const LUST_SELF_CONFUSE_SEC := 3.0
## 嫉妒：旧击杀复制概率（v0.4.30 起不用）；三罪弃牌数保留。
const ENVY_COPY_CHANCE_PER_STACK := 0.30
const ENVY_THREE_SIN_DISCARD := 2
## 暴食：击杀回 1 HP；每层每秒最多 1 次；三罪自伤 DoT。
const GLUTTONY_HEAL_ON_KILL := 1
const GLUTTONY_PROCS_PER_SEC_PER_LAYER := 1.0
const GLUTTONY_SELF_DOT_DAMAGE := 1
## v0.4.36：三罪自伤持续 3.5s，每 DOT_TICK_SEC(0.7) 扣 1。
const GLUTTONY_SELF_DOT_SEC := 3.5
## 懒惰：减速层时长；三罪改为禁枪 3 秒（不再用射速窗/短锁）。
const SLOTH_SLOW_LAYER_SEC := 5.0
const SLOTH_FIRE_BAN_SEC := 3.0
## 旧名保留给测试兼容（数值对齐禁枪）。
const SLOTH_FIRE_PENALTY_SEC := 3.0
const SLOTH_FIRE_LOCK_SEC := 3.0

## v0.4.21 玩家点射射速帽。手动连点与连发窗免费点射共用，不能快过这个数。
## 10 次/秒 = 间隔 0.1 秒。
const MAX_FIRE_RATE_HZ := 10.0
const MIN_FIRE_INTERVAL_SEC := 0.1

## v0.4.24 一键连射节奏：打一发 → 转轮转一格（动画）→ 下一发 …… 直到已装弹打完。
## 间隔吃战斗速度；不会快过 MIN_FIRE_INTERVAL_SEC。转一格动画 VOLLEY_ROTATE_SEC 放在间隔之内。
## v0.4.29：空仓也算正常一拍（同样等间隔、停留、转一格），不再快跳；连射打完最后一颗已装弹即结束。
const VOLLEY_SHOT_INTERVAL_SEC := 0.25
const VOLLEY_ROTATE_SEC := 0.18
## v0.4.24：装满后、开火前都不再随机转轮；从当前击发仓直接开打。
const LOAD_FULL_RANDOM_SPIN := false

## v0.4.21 击杀掉金币。普通怪 25% 掉 2；Boss（超级僵尸）必掉 8。木桩不掉。
const KILL_GOLD_DROP_CHANCE := 0.25
const KILL_GOLD_DROP_AMOUNT := 2
const KILL_GOLD_BOSS_DROP_CHANCE := 1.0
const KILL_GOLD_BOSS_DROP_AMOUNT := 8

