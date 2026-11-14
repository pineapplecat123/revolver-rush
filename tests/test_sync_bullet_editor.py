#!/usr/bin/env python3
"""Unit tests for tools/sync_bullet_editor.py"""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sync_bullet_editor", ROOT / "tools" / "sync_bullet_editor.py")
mod = importlib.util.module_from_spec(spec)
sys.modules["sync_bullet_editor"] = mod
spec.loader.exec_module(mod)


class SyncHelpersTest(unittest.TestCase):
    def test_normalize_hex(self):
        self.assertEqual(mod.normalize_hex("4ae06a"), "#4AE06A")
        self.assertEqual(mod.normalize_hex("#2cc4b4"), "#2CC4B4")
        self.assertIsNone(mod.normalize_hex(""))
        self.assertIsNone(mod.normalize_hex("zzz"))

    def test_apply_copies_colors_and_keeps_formula_damage(self):
        ammo = {
            "id": 43,
            "name": "终审弹",
            "base_damage": None,
            "base_damage_mode": "formula",
            "special": "旧",
            "tags": ["结束", "清算"],
            "school": "清算",
            "rarity": "common",
        }
        editor = {
            "name": "终审弹",
            "effect": "新效果",
            "damage": "0",
            "type": "结束",
            "school": "清算",
            "muzzle_color": "#db3d38",
            "bullet_color": "#DB3D38",
        }
        changes = mod.apply_editor_row(ammo, editor)
        self.assertIn("special", changes)
        self.assertIn("muzzle_color", changes)
        self.assertIn("bullet_color", changes)
        self.assertNotIn("base_damage", changes)
        self.assertEqual(ammo["special"], "新效果")
        self.assertEqual(ammo["muzzle_color"], "#DB3D38")
        self.assertEqual(ammo["tags"], ["结束", "清算"])

    def test_apply_updates_fixed_damage_and_type_tag(self):
        ammo = {
            "id": 40,
            "name": "起势弹",
            "base_damage": 0,
            "base_damage_mode": "fixed",
            "tags": ["开始", "清算"],
        }
        editor = {"name": "起势弹", "damage": "0", "type": "开始", "bullet_color": "#52C76B"}
        changes = mod.apply_editor_row(ammo, editor)
        self.assertIn("bullet_color", changes)
        self.assertEqual(ammo["base_damage"], 0)
        self.assertEqual(ammo["tags"], ["开始", "清算"])


if __name__ == "__main__":
    unittest.main()
