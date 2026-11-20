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


if __name__ == "__main__":
    unittest.main()
