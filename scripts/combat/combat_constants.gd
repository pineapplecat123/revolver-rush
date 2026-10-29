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
const ENEMY_AUTO_STEP_SEC := 1.65

## rush! 波次刷怪数量倍率（相对设计表）；ceil 后上限 BOARD_SIZE-1。
const WAVE_SPAWN_COUNT_MULT := 1.5

## 枪口状态持续时间（秒，受战斗速度倍率缩放；傲慢整场，无计时）。
## 设计表原为「挂上到回合结束」；rush! 无经典回合，改为固定秒数。
const MUZZLE_DURATION_WRATH_SEC := 4.0
const MUZZLE_DURATION_GREED_SEC := 4.0
const MUZZLE_DURATION_ELEMENT_SEC := 4.0  ## 穿甲/汽油/火/水/雷
## v0.3.7：傲慢也计时，明显长于其它枪口（口头「计时比较久」→ 选 12 秒）。
const MUZZLE_DURATION_PRIDE_SEC := 12.0


## ——— v0.3.8 无波次 / 经验值 / 临时罪孽寿命 ———
## 临时罪孽（三罪孽惩罚每触发一次 +1 颗同种）寿命：18 秒（战斗秒 × 速度，暂停时停）。
const TEMP_SIN_LIFETIME_SEC := 18.0
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
