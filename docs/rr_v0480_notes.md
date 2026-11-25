# v0.4.80 gameplay / editor integration

## Source and scope

- Started at `a10a510` (v0.4.79), fetched and fast-forwarded the required worktree to live editor ingest HEAD `7865647` (28 editor rows, updated 2026-11-25 10:26 CST/Asia/Shanghai).
- The public `/redo/bullets/data.json` was stale (16 rows). Authoritative source is `companion/bullet-editor/data.json` on `feat/gameplay-redo`, populated by the sanctioned ingest workflow. Ran `.github/scripts/bullet_editor_ingest.py` and `tools/sync_bullet_editor.py`; source-to-game sync is now idempotent.
- Editor UX commit `2ad89c2` integrated normally as `3f0977a`, no conflicts. No independent editor UI/auth changes. Paired editor gate/seal follow-up `3d590da` integrated normally as `dbb17f4`, no conflicts; all three paired files are included. No independent auth changes.
- No main checkout, PR, force push, or credential/submission-key changes by this gameplay task.

## Latest owner rule (t640, supersedes earlier intermediate instructions)

The shot receives all current layers, in creation order, before consumption. Every effect **type** consumes one layer on each intrinsically positive-damage shot; zero-own-damage utility shots and empty chambers consume none. Flat additions cannot bootstrap zero-own-damage utility shots. Start-type bullets have no immunity. Alternate formula damage counts even when stored base is zero. A +50% layer means multiply by 1.5; do not add percentage points across layers.

Same-type repeated grants stay as separately ordered groups. Only the oldest eligible group of that effect type loses one layer per shot; other groups retain their layers. This is the documented FIFO-within-type choice, not decay once per independently granted group and not global-one-layer decay. Existing explicitly last-shot-targeted 尾加倍 still activates only on the last actual shot.

Canonical raw sequence: base3, three ×1.5 layers followed by two ×2 layers => 40.5, 13.5, 4.5, 3, 3. Final rounding remains at the established integer shot boundary (41,14,5,3,3).

Old rest-of-volley durations are materialized into layer counts at creation using remaining loaded shots; one-shot effects create one layer. 空拍 creates one ×2 layer per empty slot in the initial load snapshot. Transfer creates `max(round(predicted)-3,0)` flat +1 layers. Unspent current-data flame layers persist across load-plan resets; wall-clock waiting does not consume them. Old `duration_type` enum names are compatibility/schema labels, not a countdown.

## Ingested four new bullets

- 56 需要鼓励: when an applying enhancement increases its damage, its own formula base is 6 instead of 3, then ordered flames apply.
- 57 模仿伤害: half the previous actual fired shot's actual damage, rounded up; no prior actual shot or a miss yields 0.
- 58 超级放大: twice the previous actual fired shot's actual damage.
- 59 空拍: count original load-snapshot empties, create that many ×2 flame layers.

Also updated 加伤弹 / 倍伤弹 to the latest ordered layer semantics; 随机复制弹 samples up to two **other currently loaded chambers**, no self fallback. Separate chambers with the same ammo id remain separate candidates. The editor's removed sin exclusion is reflected: no additional exclusion was invented. Source metadata/copy for existing bullets was synchronized.

## Eight unpublished designs deliberately not implemented

1. 总伤传递弹: when exactly is the next load snapshot taken to determine the divisor? How many flame layers are created, when is this cross-cylinder grant installed, and how do multiple grants stack under t640?
2. 双倍给下一个: does “copy identical modifiers” copy all layers, one per type, or already-consumed/surviving layers? What is copied for Transfer's per-layer values and last-shot targeting? Exact layer count under t640 is missing.
3. 加强尾部: average actual damage among all original end-type shots or only remaining ones? Rounding of division is missing; layer count/lifetime conversion is unspecified.
4. 恐怖汲取: does one enhancement event mean per affected shot, per effect type, or per applied layer? Do multiple layers/types on the same shot count multiple times? This directly changes its power-of-two formula.
5. 升级引爆: base damage field is blank; is it an intrinsically zero-damage utility discharge or a damaging projectile too? Does its global 4-per-consumed-layer damage itself receive flames or consume again? Which statuses count as consumable layers (including speed/targeted pending flames)?
6. 分裂尾弹: does “previous damage” mean the previous actual shot's total across all hits or one target? Apply current flames before splitting or to each per-enemy share? Enemy count at trigger or impact? Missing formula ordering affects all-target damage, so not guessed.
7. 吃拍: are adjacent slots based on the original load snapshot or current chamber state after earlier shots emptied? Are first/last physical cylinder slots adjacent? Without these, the number of +100% modifiers is ambiguous.
8. 黑视: which mechanics see the virtual empties (空拍/吃拍 only, all formulas, auto-loading, copies/targeting)? Does it preserve real loaded counts for scheduling? When does its virtual-empty mask activate/end under layer consumption?

Terminology-only changes on unpublished designs do not imply they were implemented or marked in_game.

## Copy migration audit

`docs/rr_v0480_description_migration.json` records every changed design `effect`, game `special`, `game_description` (old and new, by source file/id/name). Notes are not leaked into game UI and were not edited. The committed editor JSON is the editable source of truth, so normal sync cannot revert the game copy. No separate external spreadsheet has been claimed updated. Copy was kept concise so the strict all-28-record/all-field PNG layout regression remains within its 16,000 px guard; no weakened export assertion ships.

The active enhancement descriptions use 【枪口火焰】【消耗枪口火焰】【火焰层数】 and describe zero-damage eligibility. Obsolete, non-current legacy sin/element code paths are not new data-driven flame definitions; their historic compatibility timer code was not converted or assigned invented layer counts. Enemy status timers were not changed.

## Visuals and performance

- Hopper uses two fixed spatial clip windows for the same simulated circles and glyphs: above the opaque front casing and below the outlet lip. No per-body visibility switch, teleport, spawn, payout change, or altered physics constants.
- `tools/rr_v0480_gumball_demo.gd` drives the existing pointer-drag lever workflow in Godot, with stills under `docs/shots/rr_v0480_gumball_*.png`.
- `tools/rr_v0480_flame_demo.gd` drives actual manual-shot UI with a deterministic seeded pair of table-colored flame groups, to show creation burst / five individual icons / zero-retention / positive-shot consumption. This is a seeded mechanics demonstration, not a randomly earned gameplay run.
- Persistent muzzle fire and burning enhanced tracers use batched drawing capped at eight visual color shells; layer icons remain exact and horizontally scrollable. No per-particle physics nodes added.
- `docs/shots/rr_v0480_gumball_outlet_sequence.png` is a consecutive-frame contact sheet from the recorded Godot movie, showing progressive spatial emergence.

## Validation / deployment handoff

Final GUT/check numbers and commit are in the parent handoff. Font charset and web subset rebuild are mandatory and run after final UI text changes. Editor UX and paired auth follow-up are integrated; ready for a normal push to `origin HEAD:feat/gameplay-redo` after this pre-push parent handoff. This task reports ready-to-integrate before that final push, as requested. `/redo/` is not claimed updated until push and Pages succeed.

Validation: full GUT 705/705 across 87 scripts, 15,577 assertions; Python 24/24, editor color 504 assertions, overview regression/JS syntax and pre-push checks passed. Known pre-existing async warmup/resource-leak log warnings remain.

Evidence: `docs/shots/rr_v0480_gumball_occlusion.mp4` (13.9 s) and `docs/shots/rr_v0480_flames.mp4` (8.17 s), rendered directly from Godot; no browser capture claimed. Flame demo shows 5 layers retained through zero damage, then 3, 1 and 0 as the two types independently decay.
