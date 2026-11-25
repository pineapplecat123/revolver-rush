#!/usr/bin/env python3
"""Editor HTML/JS literals and data.json migration for game_description."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = "普通的一个子弹..."
EDITOR = ROOT / "companion" / "bullet-editor"


class EditorGameDescriptionTest(unittest.TestCase):
    def test_html_textarea_saves_actual_default_not_placeholder_only(self):
        html = (EDITOR / "index.html").read_text(encoding="utf-8")
        self.assertIn("游戏内描述", html)
        m = re.search(
            r'<textarea[^>]*id="f_game_description"[^>]*>(.*?)</textarea>',
            html,
            re.S,
        )
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), DEFAULT)
        self.assertNotIn('placeholder="普通的一个子弹..."', html)
        self.assertIn("游戏内描述", html)

    def test_js_default_literal_and_migration_helpers(self):
        js = (EDITOR / "app.js").read_text(encoding="utf-8")
        self.assertIn("var DEFAULT_GAME_DESCRIPTION = '%s';" % DEFAULT, js)
        self.assertIn("function migratedGameDescription", js)
        self.assertIn("function buildRec", js)
        self.assertIn("game_description", js)
        self.assertIn("never the new default", js)
        self.assertTrue("..." in DEFAULT)
        self.assertNotIn("…", DEFAULT)
        self.assertEqual(DEFAULT[-3:], "...")

    def test_existing_editor_rows_migrated_from_effect_not_default(self):
        doc = json.loads((EDITOR / "data.json").read_text(encoding="utf-8"))
        bullets = doc["bullets"]
        self.assertGreater(len(bullets), 0)
        for b in bullets:
            self.assertIn("game_description", b)
            gd = b.get("game_description")
            effect = b.get("effect") or ""
            if effect and effect != DEFAULT:
                self.assertNotEqual(gd, DEFAULT, msg=b.get("id"))
            self.assertIn("notes", b)



    def test_italic_swap_base_damage_label_and_x_formula_rows(self):
        css = (EDITOR / "style.css").read_text(encoding="utf-8")
        self.assertIn(".desc.play{font-style:italic}", css)
        self.assertNotIn(".desc.effect{font-style:italic}", css)
        html = (EDITOR / "index.html").read_text(encoding="utf-8")
        self.assertIn('<label for="f_damage">基础伤害</label>', html)
        self.assertIn('<option value="damage">基础伤害</option>', html)
        self.assertIn('inputmode="text"', html)
        ov = (EDITOR / "overview.js").read_text(encoding="utf-8")
        self.assertIn("['damage', '基础伤害']", ov)
        self.assertIn("field[0] === 'game_description' ? 'italic' : 'normal'", ov)
        bullets = json.loads((EDITOR / "data.json").read_text(encoding="utf-8"))["bullets"]
        by_name = {b["name"]: b for b in bullets}
        formula_x = {"总伤二分弹", "模仿伤害", "超级放大", "分裂尾弹"}
        true_zero = {"加伤弹", "倍伤弹", "加速弹", "随机复制弹", "重复开始弹", "尾加倍弹", "双倍给下一个", "空拍", "黑视"}
        for name in formula_x:
            self.assertEqual(by_name[name]["damage"], "X", msg=name)
            self.assertIn("X =", by_name[name]["notes"], msg=name)
        for name in true_zero:
            self.assertEqual(by_name[name]["damage"], "0", msg=name)
        self.assertEqual(by_name["升级引爆"]["damage"], "")
        for name in ("模仿伤害", "超级放大"):
            self.assertIn("尚未结算时沿用其四舍五入后的预计伤害", by_name[name]["notes"])


if __name__ == "__main__":
    unittest.main()
