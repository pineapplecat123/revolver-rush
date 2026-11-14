#!/usr/bin/env python3
"""Copy implemented bullets from the bullet editor into data/ammo.json.

Matches editor rows to ammo.json by name (e.g. 起势弹). Only updates ammo
rows that already exist — it never invents a new ammo id, and never deletes
one. Rows that exist only in the editor (尾重弹 while it is on hold) are
skipped.

Copied when present:
  name, effect -> special, school, rarity (mapped to common/rare/...),
  type tag (开始/中间/结束, other tags such as 清算 are kept),
  damage -> base_damage only when the ammo uses fixed numeric damage,
  muzzle_color, bullet_color (#RRGGBB).

Usage:
  python3 tools/sync_bullet_editor.py
  python3 tools/sync_bullet_editor.py --dry-run
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "companion" / "bullet-editor" / "data.json"
AMMO = ROOT / "data" / "ammo.json"
COLOR_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
TYPE_TAGS = ("开始", "中间", "结束")
RARITY = {
    "普通": "common",
    "common": "common",
    "稀有": "rare",
    "rare": "rare",
    "史诗": "epic",
    "epic": "epic",
    "传说": "legendary",
    "legendary": "legendary",
}


def normalize_hex(value):
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    if not s.startswith("#"):
        s = "#" + s
    if not COLOR_RE.match(s):
        return None
    return "#" + s[1:].upper()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def apply_editor_row(ammo: dict, editor: dict) -> list[str]:
    changes: list[str] = []
    name = str(editor.get("name") or "").strip()
    if name and ammo.get("name") != name:
        ammo["name"] = name
        changes.append("name")
    effect = str(editor.get("effect") or "").strip()
    if effect and ammo.get("special") != effect:
        ammo["special"] = effect
        changes.append("special")
    school = str(editor.get("school") or "").strip()
    if school and ammo.get("school") != school:
        ammo["school"] = school
        changes.append("school")
    rarity_raw = str(editor.get("rarity") or "").strip()
    if rarity_raw:
        rarity = RARITY.get(rarity_raw, rarity_raw)
        if ammo.get("rarity") != rarity:
            ammo["rarity"] = rarity
            changes.append("rarity")
    typ = str(editor.get("type") or "").strip()
    if typ in TYPE_TAGS:
        tags = [str(t) for t in (ammo.get("tags") or [])]
        # replace previous type tag, keep the rest
        others = [t for t in tags if t not in TYPE_TAGS]
        new_tags = [typ] + others
        if tags != new_tags:
            ammo["tags"] = new_tags
            changes.append("tags")
    if str(ammo.get("base_damage_mode", "fixed")) == "fixed":
        dmg = str(editor.get("damage") or "").strip()
        if dmg != "":
            try:
                if "." in dmg:
                    num = float(dmg)
                    num_out = int(num) if num.is_integer() else num
                else:
                    num_out = int(dmg)
                if ammo.get("base_damage") != num_out:
                    ammo["base_damage"] = num_out
                    changes.append("base_damage")
            except ValueError:
                pass
    for key in ("muzzle_color", "bullet_color"):
        col = normalize_hex(editor.get(key))
        if col and ammo.get(key) != col:
            ammo[key] = col
            changes.append(key)
    return changes


def sync(dry_run: bool = False) -> int:
    editor_doc = load(EDITOR)
    ammo_doc = load(AMMO)
    by_name = {str(b.get("name") or "").strip(): b for b in editor_doc.get("bullets", [])}
    reports = []
    skipped = []
    for item in ammo_doc.get("items", []):
        name = str(item.get("name") or "").strip()
        src = by_name.get(name)
        if src is None:
            skipped.append(f"ammo {item.get('id')} {name}: not in editor")
            continue
        changes = apply_editor_row(item, src)
        if changes:
            reports.append(f"{name} (id {item.get('id')}): " + ", ".join(changes))
        else:
            reports.append(f"{name} (id {item.get('id')}): already in sync")
    for b in editor_doc.get("bullets", []):
        name = str(b.get("name") or "").strip()
        if name and name not in {str(a.get("name") or "").strip() for a in ammo_doc.get("items", [])}:
            skipped.append(f"editor {name}: not in ammo.json (skipped)")
    print("SYNC " + str(len(reports)) + " ammo row(s)")
    for line in reports:
        print("  " + line)
    for line in skipped:
        print("SKIP " + line)
    if dry_run:
        print("dry-run: ammo.json not written")
        return 0
    AMMO.write_text(json.dumps(ammo_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print what would change, do not write ammo.json")
    args = ap.parse_args()
    if not EDITOR.exists() or not AMMO.exists():
        print("missing data files", file=sys.stderr)
        return 2
    return sync(dry_run=args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
