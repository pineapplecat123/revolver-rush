extends GutTest
## 先关掉 PLAIN_ONLY，让本分支其余回归测仍按经典 10+5 开局 / 全弹药池跑。
## test_rr_gameplay_redo 自己在 before_each 打开。


func before_all() -> void:
	CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY = false


func test_plain_only_disabled_for_legacy_suite() -> void:
	assert_false(CombatConstants.GAMEPLAY_REDO_PLAIN_ONLY)
