# v0.4.93 验证

- 根因：v0.4.92 让 `sync_ammo_ids` 不再把已出袋的球算作袋内存货，这修好了「倒完被删掉」。但倒出全部子弹时，球已经离开袋子，而 `state.bag` 要等到 `dump_to_hand_items` 才扣空。这段时间里任何 `_refresh` / `sync_ammo_ids(state.bag)`（战斗 tick、敌人滑行、dump 的 emit 时机不对都会触发）会以为袋是空的，按库存在袋里再生成一轮，随后逻辑扣袋又把它们删掉。看起来就是「倒空袋子后立刻闪出一些子弹再消失」。
- 修正：计算缺货时把尚未 promote 的出袋球算作已经覆盖对应库存，不再生成重复袋内球；倒出动画期间 `_refresh_bag_list` 不再 sync（中途补袋仍走 `_sync_bag_physics_during_pour`）。倒完后的手区物理堆、第二批碰撞不受影响。
- 视觉：`docs/shots/rr_v0493_full_dump_empty_bag.png`（720×1280）。6 发全部倒入手当物理堆，袋内为空，没有残留或闪现的袋内球。
