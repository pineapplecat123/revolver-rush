#!/usr/bin/env python3
"""Seal the one-tap submit token for /redo/bullets/ into companion/bullet-editor/submit-key.json.

The token must be a fine-grained PAT limited to pineapplecat123/revolver-rush with ONLY
"Actions: Read and write" (Metadata read is automatic). It is AES-GCM encrypted with a
PBKDF2 key from the page PIN, so the repo never holds it in plaintext (and GitHub secret
scanning will not auto-revoke it). Anyone who cracks the PIN from the page can still use
it: rotate by revoking the PAT and re-running this script.

  BULLET_SUBMIT_TOKEN=... BULLET_PIN=... python3 .github/scripts/bullet_editor_seal_key.py
  python3 .github/scripts/bullet_editor_seal_key.py --clear   # disable one-tap submit
"""
from __future__ import annotations

import base64
import getpass
import hashlib
import json
import os
import sys
import unicodedata
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

OUT = Path(__file__).resolve().parents[2] / "companion" / "bullet-editor" / "submit-key.json"
GATE = "6f1e76e002ffa351d514e393ef9b95a13a7609ae91688194a62dc5a3903afd32"
ITER = 200_000


def norm_pin(s: str) -> str:
    s = unicodedata.normalize("NFC", s).strip()
    return "".join(chr(ord(c) - 0xFEE0) if "\uff10" <= c <= "\uff19" else c for c in s)


def main() -> int:
    if "--clear" in sys.argv:
        OUT.unlink(missing_ok=True)
        print(f"removed {OUT}")
        return 0
    pin = norm_pin(os.environ.get("BULLET_PIN") or getpass.getpass("PIN: "))
    if hashlib.sha256(("rr-bullets-v1:" + pin).encode()).hexdigest() != GATE:
        print("ERROR: PIN does not match the page gate", file=sys.stderr)
        return 1
    token = (os.environ.get("BULLET_SUBMIT_TOKEN") or getpass.getpass("token: ")).strip()
    if not token:
        print("ERROR: empty token", file=sys.stderr)
        return 1
    salt, iv = os.urandom(16), os.urandom(12)
    key = hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, ITER, 32)
    ct = AESGCM(key).encrypt(iv, token.encode(), None)
    b64 = lambda b: base64.b64encode(b).decode()
    OUT.write_text(json.dumps({"v": 1, "kdf": "PBKDF2-SHA256", "iter": ITER, "salt": b64(salt),
                               "iv": b64(iv), "ct": b64(ct)}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
