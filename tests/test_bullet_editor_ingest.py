#!/usr/bin/env python3
"""Unit tests for bullet_editor_ingest upsert behavior."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".github" / "scripts"))
import bullet_editor_ingest as ingest  # noqa: E402


SCHEMA = {
    "_schema": "v1",
    "schema": 1,
    "updated_at": "2026-11-13T10:00:00+08:00",
    "bullets": [],
}


def seed(base: Path, bullets, updated_at="2026-11-13T10:00:00+08:00"):
    doc = dict(SCHEMA)
    doc["updated_at"] = updated_at
    doc["bullets"] = bullets
    (base / "data.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (base / "inbox").mkdir(exist_ok=True)


def load(base: Path):
    return json.loads((base / "data.json").read_text(encoding="utf-8"))


def row(rid, **kw):
    rec = {
        "id": rid,
        "name": "旧名",
        "type": "旧类型",
        "damage": "1",
        "rarity": "普通",
        "effect": "旧效果",
        "notes": "旧备注",
        "in_game": False,
        "created_at": "2026-11-13T10:00:00+08:00",
        "updated_at": "2026-11-13T10:00:00+08:00",
    }
    rec.update(kw)
    return rec


class IngestUpsertTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        seed(self.base, [])
        self._max = ingest.MAX_ROWS

    def tearDown(self):
        ingest.MAX_ROWS = self._max
        self.tmp.cleanup()

    def test_dispatch_new_id_appends(self):
        payload = {
            "id": "b-new-1",
            "name": "新弹",
            "type": "开始",
            "damage": "3",
            "rarity": "稀有",
            "effect": "爆炸",
            "notes": "备注",
            "in_game": True,
            "created_at": "1999-01-01T00:00:00+08:00",
            "updated_at": "1999-01-01T00:00:00+08:00",
        }
        merged, failed = ingest.ingest(self.base, json.dumps(payload, ensure_ascii=False))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["新弹"])
        doc = load(self.base)
        self.assertEqual(len(doc["bullets"]), 1)
        b = doc["bullets"][0]
        self.assertEqual(b["id"], "b-new-1")
        self.assertEqual(b["name"], "新弹")
        self.assertEqual(b["type"], "开始")
        self.assertEqual(b["damage"], "3")
        self.assertEqual(b["rarity"], "稀有")
        self.assertEqual(b["effect"], "爆炸")
        self.assertEqual(b["notes"], "备注")
        self.assertIs(b["in_game"], False)
        self.assertTrue(b["created_at"].endswith("+08:00"))
        self.assertEqual(b["created_at"], b["updated_at"])
        self.assertNotEqual(b["created_at"], "1999-01-01T00:00:00+08:00")
        self.assertGreaterEqual(doc["updated_at"], b["updated_at"][:19])

    def test_dispatch_existing_id_updates_and_forces_in_game_false(self):
        seed(self.base, [row("b-old", in_game=True, name="旧名")])
        payload = {
            "id": "b-old",
            "name": "新名",
            "type": "结束",
            "damage": "9",
            "rarity": "传说",
            "effect": "新效果",
            "notes": "新备注",
            "in_game": True,
        }
        merged, failed = ingest.ingest(self.base, json.dumps(payload, ensure_ascii=False))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["新名"])
        doc = load(self.base)
        self.assertEqual(len(doc["bullets"]), 1)
        b = doc["bullets"][0]
        self.assertEqual(b["id"], "b-old")
        self.assertEqual(b["name"], "新名")
        self.assertEqual(b["type"], "结束")
        self.assertEqual(b["damage"], "9")
        self.assertEqual(b["rarity"], "传说")
        self.assertEqual(b["effect"], "新效果")
        self.assertEqual(b["notes"], "新备注")
        self.assertIs(b["in_game"], False)
        self.assertEqual(b["created_at"], "2026-11-13T10:00:00+08:00")
        self.assertNotEqual(b["updated_at"], "2026-11-13T10:00:00+08:00")
        self.assertTrue(b["updated_at"].endswith("+08:00"))
        self.assertNotEqual(doc["updated_at"], "2026-11-13T10:00:00+08:00")

    def test_inbox_existing_id_updates_and_unsets_in_game(self):
        seed(self.base, [row("b-in", in_game=True)])
        (self.base / "inbox" / "b-in.json").write_text(
            json.dumps({"id": "b-in", "name": "箱更", "type": "箱", "in_game": True}, ensure_ascii=False),
            encoding="utf-8",
        )
        merged, failed = ingest.ingest(self.base, "")
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["箱更"])
        self.assertFalse((self.base / "inbox" / "b-in.json").exists())
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["name"], "箱更")
        self.assertEqual(b["type"], "箱")
        self.assertIs(b["in_game"], False)
        self.assertEqual(b["created_at"], "2026-11-13T10:00:00+08:00")

    def test_inbox_new_id_appends(self):
        seed(self.base, [row("keep")])
        (self.base / "inbox" / "b-box.json").write_text(
            json.dumps({"id": "b-box", "name": "箱新", "type": "新"}, ensure_ascii=False),
            encoding="utf-8",
        )
        merged, failed = ingest.ingest(self.base, "")
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["箱新"])
        doc = load(self.base)
        self.assertEqual([b["id"] for b in doc["bullets"]], ["keep", "b-box"])
        b = doc["bullets"][1]
        self.assertEqual(b["name"], "箱新")
        self.assertIs(b["in_game"], False)
        self.assertTrue(b["created_at"].endswith("+08:00"))
        self.assertEqual(b["created_at"], b["updated_at"])
        self.assertFalse((self.base / "inbox" / "b-box.json").exists())

    def test_field_length_caps(self):
        payload = {
            "id": "b-cap",
            "name": "名" * 80,
            "type": "T" * 40,
            "damage": "D" * 40,
            "rarity": "R" * 40,
            "school": "S" * 40,
            "effect": "E" * 1500,
            "notes": "N" * 1500,
        }
        merged, failed = ingest.ingest(self.base, json.dumps(payload))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["名" * 40])
        b = load(self.base)["bullets"][0]
        self.assertEqual(len(b["name"]), 40)
        self.assertEqual(len(b["type"]), 20)
        self.assertEqual(len(b["damage"]), 20)
        self.assertEqual(len(b["rarity"]), 20)
        self.assertEqual(len(b["school"]), 20)
        self.assertEqual(len(b["effect"]), 1000)
        self.assertEqual(len(b["notes"]), 1000)

    def test_input_too_large_is_skipped(self):
        seed(self.base, [row("keep")])
        raw = json.dumps({"id": "b-huge", "name": "大", "effect": "x" * 9000})
        merged, failed = ingest.ingest(self.base, raw)
        self.assertEqual(merged, [])
        self.assertTrue(any("input too large" in x for x in failed))
        doc = load(self.base)
        self.assertEqual([b["id"] for b in doc["bullets"]], ["keep"])
        self.assertEqual(doc["updated_at"], "2026-11-13T10:00:00+08:00")

    def test_max_rows_blocks_new_but_allows_update(self):
        ingest.MAX_ROWS = 1
        seed(self.base, [row("only", in_game=True, name="仅有")])
        merged, failed = ingest.ingest(self.base, json.dumps({"id": "extra", "name": "多一颗"}))
        self.assertEqual(merged, [])
        self.assertTrue(any("too many rows" in x for x in failed))
        self.assertEqual(len(load(self.base)["bullets"]), 1)

        merged, failed = ingest.ingest(self.base, json.dumps({"id": "only", "name": "改名", "in_game": True}))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["改名"])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["name"], "改名")
        self.assertIs(b["in_game"], False)
        self.assertEqual(len(load(self.base)["bullets"]), 1)

    def test_missing_name_and_bad_id_rejected(self):
        seed(self.base, [row("keep")])
        _, failed = ingest.ingest(self.base, json.dumps({"id": "ok", "name": "  "}))
        self.assertTrue(any("missing name" in x for x in failed))
        _, failed = ingest.ingest(self.base, json.dumps({"id": "bad id!", "name": "x"}))
        self.assertTrue(any("bad id" in x for x in failed))
        self.assertEqual([b["id"] for b in load(self.base)["bullets"]], ["keep"])

    def test_school_create_update_default_and_cap(self):
        # omitted school defaults to empty string
        merged, failed = ingest.ingest(self.base, json.dumps({"id": "b-no-school", "name": "无派"}))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["无派"])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["school"], "")
        self.assertIs(b["in_game"], False)

        # create with school
        merged, failed = ingest.ingest(self.base, json.dumps({
            "id": "b-school", "name": "有派", "school": "  连击  ", "in_game": True,
        }))
        self.assertEqual(failed, [])
        b = [x for x in load(self.base)["bullets"] if x["id"] == "b-school"][0]
        self.assertEqual(b["school"], "连击")
        self.assertIs(b["in_game"], False)

        # update school; created_at preserved
        created = b["created_at"]
        merged, failed = ingest.ingest(self.base, json.dumps({
            "id": "b-school", "name": "有派", "school": "爆发", "type": "开始",
        }))
        self.assertEqual(failed, [])
        b = [x for x in load(self.base)["bullets"] if x["id"] == "b-school"][0]
        self.assertEqual(b["school"], "爆发")
        self.assertEqual(b["type"], "开始")
        self.assertEqual(b["name"], "有派")
        self.assertEqual(b["created_at"], created)
        self.assertIs(b["in_game"], False)

        # old row missing school key gets school="" when updated without it
        seed(self.base, [row("b-old-no-school", in_game=False)])
        raw = json.loads((self.base / "data.json").read_text(encoding="utf-8"))
        self.assertNotIn("school", raw["bullets"][0])
        merged, failed = ingest.ingest(self.base, json.dumps({"id": "b-old-no-school", "name": "旧名", "type": "旧类型"}))
        self.assertEqual(failed, [])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["school"], "")
        self.assertEqual(b["name"], "旧名")
        self.assertEqual(b["created_at"], "2026-11-13T10:00:00+08:00")

    def test_inbox_bad_file_left_in_place(self):
        seed(self.base, [])
        bad = self.base / "inbox" / "nope.json"
        bad.write_text("{not json", encoding="utf-8")
        merged, failed = ingest.ingest(self.base, "")
        self.assertEqual(merged, [])
        self.assertEqual(len(failed), 1)
        self.assertTrue(failed[0].startswith("nope.json:"))
        self.assertTrue(bad.exists())
        self.assertEqual(load(self.base)["updated_at"], "2026-11-13T10:00:00+08:00")


    def test_colors_create_update_and_preserve(self):
        payload = {
            "id": "b-col",
            "name": "彩弹",
            "type": "开始",
            "muzzle_color": "4ae06a",
            "bullet_color": "#52c76b",
            "in_game": True,
        }
        merged, failed = ingest.ingest(self.base, json.dumps(payload))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["彩弹"])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["muzzle_color"], "#4AE06A")
        self.assertEqual(b["bullet_color"], "#52C76B")
        self.assertIs(b["in_game"], False)

        # omitted colors leave previous values
        merged, failed = ingest.ingest(self.base, json.dumps({
            "id": "b-col", "name": "彩弹改", "type": "结束",
        }))
        self.assertEqual(failed, [])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["name"], "彩弹改")
        self.assertEqual(b["type"], "结束")
        self.assertEqual(b["muzzle_color"], "#4AE06A")
        self.assertEqual(b["bullet_color"], "#52C76B")

        # valid update
        merged, failed = ingest.ingest(self.base, json.dumps({
            "id": "b-col", "name": "彩弹改",
            "muzzle_color": "#2CC4B4", "bullet_color": "#F2CC38",
        }))
        self.assertEqual(failed, [])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["muzzle_color"], "#2CC4B4")
        self.assertEqual(b["bullet_color"], "#F2CC38")

        # invalid color is ignored, other fields still apply
        merged, failed = ingest.ingest(self.base, json.dumps({
            "id": "b-col", "name": "还在", "muzzle_color": "not-a-color",
        }))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ["还在"])
        b = load(self.base)["bullets"][0]
        self.assertEqual(b["name"], "还在")
        self.assertEqual(b["muzzle_color"], "#2CC4B4")

    def test_colors_omitted_on_new_row(self):
        merged, failed = ingest.ingest(self.base, json.dumps({"id": "b-nocol", "name": "无色"}))
        self.assertEqual(failed, [])
        b = load(self.base)["bullets"][0]
        self.assertNotIn("muzzle_color", b)
        self.assertNotIn("bullet_color", b)


if __name__ == "__main__":
    unittest.main()
