#!/usr/bin/env python3
"""Merge companion/bullet-editor/inbox/*.json into data.json, then delete them.

Upsert by id: new id -> appended (in_game=false); known id -> fields updated,
in_game and created_at preserved. Bad files are skipped and left in place.
Prints the merged names; exit 0 even when nothing to do.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "companion" / "bullet-editor"
DATA = BASE / "data.json"
INBOX = BASE / "inbox"
TZ = timezone(timedelta(hours=8))
TEXT_FIELDS = {"name": 40, "type": 20, "damage": 20, "rarity": 20, "effect": 1000, "notes": 1000}
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def now_iso() -> str:
    return datetime.now(TZ).replace(microsecond=0).isoformat()


def main() -> int:
    doc = json.loads(DATA.read_text(encoding="utf-8"))
    bullets = doc.setdefault("bullets", [])
    by_id = {b.get("id"): b for b in bullets}
    merged, failed = [], []
    for f in sorted(INBOX.glob("*.json")):
        try:
            rec = json.loads(f.read_text(encoding="utf-8"))
            if not isinstance(rec, dict):
                raise ValueError("not an object")
            rid = str(rec.get("id") or f.stem)
            if not ID_RE.match(rid):
                raise ValueError(f"bad id {rid!r}")
            clean = {k: str(rec.get(k, "") if rec.get(k) is not None else "").strip()[:n] for k, n in TEXT_FIELDS.items()}
            if not clean["name"]:
                raise ValueError("missing name")
        except Exception as e:  # keep bad file for a human to look at
            failed.append(f"{f.name}: {e}")
            continue
        ts = now_iso()
        if rid in by_id:
            by_id[rid].update(clean)
            by_id[rid]["updated_at"] = ts
        else:
            row = {"id": rid, **clean, "in_game": False,
                   "created_at": str(rec.get("created_at") or ts), "updated_at": ts}
            bullets.append(row)
            by_id[rid] = row
        f.unlink()
        merged.append(clean["name"])
    if merged:
        doc["updated_at"] = now_iso()
        DATA.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for line in failed:
        print("SKIP " + line, file=sys.stderr)
    print("MERGED " + str(len(merged)) + (": " + ", ".join(merged) if merged else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
