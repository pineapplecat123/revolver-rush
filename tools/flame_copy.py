#!/usr/bin/env python3
"""Shared copy helpers: keep bullet-specific flame text, drop universal rules."""
from __future__ import annotations

import re

# Exact historical/current universal consume paragraphs. Unique mechanics such as
# 升级引爆「发射时消耗全部层」must not match these strings.
UNIVERSAL_PARAGRAPHS = (
    "【消耗枪口火焰】自身公式伤害（含基础0的特殊公式）>0时，按生成顺序应用全部层，各效果减最早一层；零伤害或空仓不消耗、无弹道，开始不豁免。",
    "【消耗枪口火焰】自身公式伤害（含基础伤害0的特殊公式）>0时，按生成顺序应用全部层，各效果再减最早一层；自身伤害0或空仓不消耗、无弹道。开始类型不豁免。",
    "【消耗枪口火焰】自身公式伤害>0时，按生成顺序获得全部现存层效果，各效果再消耗最早一层；基础伤害0的特殊公式同样判断。自身伤害0、空仓不消耗且无弹道；开始类型不豁免。",
    "【消耗枪口火焰】先以自身公式计算伤害（包括基础伤害为0的特殊公式）；自身计算伤害大于0时，按生成顺序获得全部现存火焰层效果，再分别消耗每种效果最早生成的一层；自身零伤害和空仓不消耗，也不产生弹道。开始类型不豁免。",
)

RULES_DOC_REL = "docs/game_rules.md"


def strip_universal_flame_rules(text: str) -> str:
    s = text or ""
    for para in UNIVERSAL_PARAGRAPHS:
        s = s.replace(para, "")
    s = re.sub(r"[ \t]+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    s = re.sub(r"[ \t]{2,}", " ", s)
    return s.strip()


def strip_appended_effect(game_description: str, effect: str) -> str:
    """Keep owner flavor; drop a second paragraph that only repeats the effect."""
    gd = strip_universal_flame_rules(game_description)
    eff = strip_universal_flame_rules(effect)
    if "\n" not in gd or not eff:
        return gd
    first, rest = gd.split("\n", 1)
    rest = rest.strip()
    if rest and (rest == eff or rest.startswith(eff) or eff.startswith(rest)):
        return first.strip()
    return gd
