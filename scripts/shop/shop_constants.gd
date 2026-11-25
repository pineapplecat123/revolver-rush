class_name ShopConstants
## 商店常量。统一单价与无稀有度随机库存；移除与重随沿用灰盒经济。

## 货架栏位数
const STOCK_SIZE := 5

## 弹药统一售价：已批准每颗5金，不再按稀有度或条目分级。
const AMMO_PRICE := 5

## 重随：先免费 1 次，之后每次花费
const FREE_REROLLS := 1
const REROLL_COST := 5
## 移除费用：单店累计递增；离店重置
const REMOVE_BASE_COST := 10
const REMOVE_COST_STEP := 5


static func price_for_ammo(_ammo_id: int) -> int:
	return AMMO_PRICE
