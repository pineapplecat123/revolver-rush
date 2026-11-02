# CombatHooks（v0.4.0）

涌现式连携流派预留的战斗生命周期钩子总线。实现：`scripts/combat/combat_hooks.gd`，挂在 `CombatState.hooks`。

## API

- `hooks.subscribe(event, callable)` / `unsubscribe` / `clear`
- `hooks.emit_hook(event, payload)`（payload 至少含 `"cs"`）
- 信号 `hooks.hooked(event, payload)` 亦可连接

## 事件一览

| 事件 | 时机 | 常用字段 |
|------|------|----------|
| `on_fire` | 点射/开火链开始 | `burst_window` |
| `on_shot` | 任意一发结算后（含虚拟） | `ammo_id`, `virtual`, `dealt`, `burst_free?` |
| `on_chamber_loaded` | 弹药入仓 | `ammo_id`, `slot`, `temporary` |
| `on_bag_enter` | 弹药入袋 | `ammo_id`, `temp_life`, `temporary` |
| `on_bag_leave` | 弹药离袋 | `ammo_id`, `reason` (`draw`/`take`/`ghost_fire`) |
| `on_three_sin` | 三罪孽惩罚触发 | `sin_id`, `count` |
| `on_muzzle_apply` | 枪口层挂上 | `kind`, `stacks_after` |
| `on_kill` | 敌人被移除 | `enemy_id`, `cell`, `def_id` |
| `on_shop_enter` | 地图商店触碰 | `shop_cell` |
| `on_dump_start` / `on_dump_end` | 倾泻开始/结束 | `interrupted?` |
| `on_burst_window` | 连发窗开启/刷新 | `remaining` |
| `on_temp_sin_spawn` | 临时罪孽入袋 | `sin_id`, `source` |
| `on_dot_tick` | DoT 跳 | `kind` |

当前订阅方可为空；弹药机制已在既有路径 emit。

## v0.4.1
- `on_muzzle_apply`：`kind=echo`（回声挂上/刷新）
- `on_shot`：回声第二波带 `echo: true`

## v0.4.2
- `on_muzzle_apply`：`kind=lifesteal`

## v0.4.3
- `on_muzzle_apply`：`kind=flame`
- `on_dot_tick`：燃烧跳前先扩散

## v0.4.4
- `on_muzzle_apply`：`kind=explosive`

## v0.4.6
- `on_insurance_swap`：保险挡住第3颗罪孽；`sin_id`
