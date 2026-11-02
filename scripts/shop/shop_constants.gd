class_name ShopConstants
## 商店常量。稀有度权重/价格 v0.4.15；移除与重随沿用灰盒经济。

## 货架栏位数
const STOCK_SIZE := 5

## 兼容旧测试/缺稀有度回退：等同 uncommon 价
const AMMO_PRICE := 8

## 稀有度键（与 data/ammo.json rarity 字段一致）
const RARITY_COMMON := "common"
const RARITY_UNCOMMON := "uncommon"
const RARITY_RARE := "rare"
const RARITY_EPIC := "epic"

## 展示名
const RARITY_LABEL := {
	"common": "普通",
	"uncommon": "精良",
	"rare": "稀有",
	"epic": "史诗",
}

## 货架抽稀有度权重（越高越常见）
const RARITY_WEIGHT := {
	"common": 45,
	"uncommon": 30,
	"rare": 18,
	"epic": 7,
}

## 售价：按稀有度缩放；uncommon=旧统一价 8
const RARITY_PRICE := {
	"common": 5,
	"uncommon": 8,
	"rare": 14,
	"epic": 22,
}

## 重随：先免费 1 次，之后每次花费
const FREE_REROLLS := 1
const REROLL_COST := 5
## 移除费用：单店累计递增；离店重置
const REMOVE_BASE_COST := 10
const REMOVE_COST_STEP := 5


static func rarity_label(rarity: String) -> String:
	return str(RARITY_LABEL.get(rarity, rarity))


static func price_for_rarity(rarity: String) -> int:
	if RARITY_PRICE.has(rarity):
		return int(RARITY_PRICE[rarity])
	return AMMO_PRICE
