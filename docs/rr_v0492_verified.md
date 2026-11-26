# v0.4.92 验证

- 根因有两层，都会在倒完后把物理堆毁掉：
  1. v0.4.91 倒完时 `take_catch_bodies()` 把已入手的球从物理盒拿走，再 `_apply_fallen_hand_layout` + `_refresh_hand_list` 生成没有重力的手牌并重排；`_untilt_after_pour` 还关掉手区碰撞盒、把 z_index 收回。
  2. `dump_to_hand_items` 会立刻 `_emit()` 刷新。此时出袋球还没标成 `catch_body`，`sync_ammo_ids` 把它们当成袋内存货：袋里只剩 4 发时会删掉多出来的出袋球（先删位置高的），只留下一部分。随后袋内同步再补回袋里的球。于是手牌逻辑有 6 发，物理堆却不够，看起来像消失，剩下的又像被排成一行。
- 修正：倒完不再收走 catch_body，也不改排成手牌。袋子回正后手区碰撞盒一直开着，球继续落、撞、堆，并保持可见。`sync_ammo_ids` / `_remove_one_ball` / `bag_body_count` 不再把已出袋或入手的球算作袋内存货。手牌在物理堆存在时隐藏。从堆里拖出发可装膛；放下则回到落点继续受重力。膛里的弹拖回已有物理堆时，会在落点生成一发物理球。
- 视觉：`docs/shots/rr_v0492_pour_hand_pile.png`（720×1280）。倒出 6 发全部还在手区当物理球（`catch_bodies=6 hand=6`，没有手牌控件），其中一发仍在下落、间距不齐；袋里剩 4 发，袋子仍倒扣。
