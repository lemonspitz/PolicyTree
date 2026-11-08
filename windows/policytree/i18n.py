"""Interface language, same scheme as Sources/Localization.swift on the Mac.

The Indonesian text in the code is the key; strings_<code>.json next to this file holds the
translation (one file shared by both apps). Pure Python, so the model can use it without Qt.
"""
from __future__ import annotations

import json
import locale
import os

CHOICES = [("system", "Ikuti sistem"), ("id", "Bahasa Indonesia"), ("en", "English")]
_HERE = os.path.dirname(os.path.abspath(__file__))
code = "id"
_table: dict = {}


def resolve(pref: str) -> str:
    if pref in ("id", "en"):
        return pref
    try:
        sys_lang = (locale.getlocale()[0] or "") or os.environ.get("LANG", "")
    except ValueError:
        sys_lang = ""
    sys_lang = sys_lang.lower()
    return "id" if sys_lang.startswith(("id", "indonesian", "ms", "malay")) else "en"


def init(pref: str = "id") -> str:
    """Fixed for the life of the process: a new language takes a restart."""
    global code, _table
    code = resolve(os.environ.get("POLICYTREE_LANG") or pref or "id")
    _table = {}
    if code != "id":
        path = os.path.join(_HERE, f"strings_{code}.json")
        try:
            with open(path, encoding="utf-8") as f:
                _table = json.load(f)
        except (OSError, ValueError):
            _table = {}
    return code


def is_english() -> bool:
    return code == "en"


def L(s: str, *args) -> str:
    """Translates an Indonesian interface string; {0}, {1}… are filled after translation.
    A key may end in |context when one Indonesian word needs two translations (see the Mac file)."""
    out = _table.get(s)
    if out is None:
        out = s.split("|", 1)[0]
    for i, a in enumerate(args):
        out = out.replace("{%d}" % i, str(a))
    return out
