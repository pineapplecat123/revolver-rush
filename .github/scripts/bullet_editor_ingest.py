#!/usr/bin/env python3
"""Merge companion/bullet-editor/inbox/*.json into data.json, then delete them.

Upsert by id for both inbox files and env BULLET_JSON (workflow_dispatch):
  new id     -> append a row (in_game=false, created_at and updated_at set)
  existing id -> update name/type/damage/rarity/effect/notes only;
                 in_game is always set false; created_at and id are kept;
                 updated_at is bumped.
Client-supplied in_game / created_at / updated_at are ignored.
Bad files are skipped and left in place.
Prints the merged names; exit 0 even when nothing to do.
"""
from __future__ import annotations

import json
import os
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
MAX_INPUT = 8000
MAX_ROWS = 2000


def now_iso() -> str:
    return datetime.now(TZ).replace(microsecond=0).isoformat()


def clean_record(rec, fallback_id: str = ""):
    if not isinstance(rec, dict):
        raise ValueError("not an object")
    rid = str(rec.get("id") or fallback_id)
    if not ID_RE.match(rid):
        raise ValueError(f"bad id {rid!r}")
    clean = {k: str(rec.get(k) if rec.get(k) is not None else "").strip()[:n] for k, n in TEXT_FIELDS.items()}
    if not clean["name"]:
        raise ValueError("missing name")
    return rid, clean


def upsert(rid: str, clean: dict, bullets: list, by_id: dict, ts: str) -> None:
    if rid in by_id:
        row = by_id[rid]
        row.update(clean)
        row["in_game"] = False
        row["updated_at"] = ts
        row["id"] = rid
        return
    if len(bullets) >= MAX_ROWS:
        raise ValueError("too many rows")
    row = {"id": rid, **clean, "in_game": False, "created_at": ts, "updated_at": ts}
    bullets.append(row)
    by_id[rid] = row


def ingest(base: Path | None = None, bullet_json: str | None = None) -> tuple[list[str], list[str]]:
    """Merge BULLET_JSON and inbox/*.json into base/data.json. Returns (merged names, failed)."""
    base = base or BASE
    data_path = base / "data.json"
    inbox = base / "inbox"
    doc = json.loads(data_path.read_text(encoding="utf-8"))
    bullets = doc.setdefault("bullets", [])
    by_id = {b.get("id"): b for b in bullets}
    merged, failed = [], []
    raw = bullet_json if bullet_json is not None else os.environ.get("BULLET_JSON", "")
    raw = (raw or "").strip()
    if raw:
        try:
            if len(raw) > MAX_INPUT:
                raise ValueError("input too large")
            rid, clean = clean_record(json.loads(raw))
            upsert(rid, clean, bullets, by_id, now_iso())
            merged.append(clean["name"])
        except Exception as e:
            failed.append(f"dispatch: {e}")
    if inbox.is_dir():
        for f in sorted(inbox.glob("*.json")):
            try:
                text = f.read_text(encoding="utf-8")
                if len(text) > MAX_INPUT:
                    raise ValueError("input too large")
                rid, clean = clean_record(json.loads(text), f.stem)
                upsert(rid, clean, bullets, by_id, now_iso())
            except Exception as e:  # keep bad file for a human to look at
                failed.append(f"{f.name}: {e}")
                continue
            f.unlink()
            merged.append(clean["name"])
    if merged:
        doc["updated_at"] = now_iso()
        data_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return merged, failed


def main() -> int:
    merged, failed = ingest()
    for line in failed:
        print("SKIP " + line, file=sys.stderr)
    print("MERGED " + str(len(merged)) + (": " + ", ".join(merged) if merged else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
