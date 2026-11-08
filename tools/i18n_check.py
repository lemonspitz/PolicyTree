#!/usr/bin/env python3
"""Checks the shared English dictionary against every L("...") key in the Mac (Swift) and
Windows (Python) sources. Exit code 1 lists missing keys, unused entries, or placeholder mismatches.

    python3 tools/i18n_check.py            # check
    python3 tools/i18n_check.py --missing  # print missing keys as a JSON skeleton
"""
import ast
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICT = os.path.join(ROOT, "windows", "policytree", "strings_en.json")


def swift_unescape(s):
    def rep(m):
        e = m.group(1)
        if e.startswith("u{"):
            return chr(int(e[2:-1], 16))
        return {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}[e]
    return re.sub(r'\\(u\{[0-9A-Fa-f]+\}|[nt"\\0])', rep, s)


def swift_keys(path):
    src = open(path, encoding="utf-8").read()
    keys = set()
    for m in re.finditer(r'\bL\(\s*"""\n(.*?)\n([ \t]*)"""', src, re.S):
        indent = m.group(2)
        lines = [ln[len(indent):] if ln.startswith(indent) else ln.lstrip() for ln in m.group(1).split("\n")]
        keys.add(swift_unescape("\n".join(lines)))
    for m in re.finditer(r'\bL\(\s*"(?!"")((?:[^"\\\n]|\\.)*)"', src):
        keys.add(swift_unescape(m.group(1)))
    return keys


def python_keys(path):
    keys = set()
    for node in ast.walk(ast.parse(open(path, encoding="utf-8").read())):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "L" and node.args \
                and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
            keys.add(node.args[0].value)
    return keys


def all_keys():
    keys = set()
    for f in glob.glob(os.path.join(ROOT, "Sources", "*.swift")):
        keys |= swift_keys(f)
    for f in glob.glob(os.path.join(ROOT, "windows", "policytree", "*.py")):
        keys |= python_keys(f)
    return keys


def main():
    keys = all_keys()
    table = json.load(open(DICT, encoding="utf-8")) if os.path.exists(DICT) else {}
    missing = sorted(k for k in keys if k not in table)
    unused = sorted(k for k in table if k not in keys)
    bad = sorted(k for k in keys & table.keys()
                 if sorted(re.findall(r"\{\d\}", k)) != sorted(re.findall(r"\{\d\}", table[k])))
    if "--missing" in sys.argv:
        print(json.dumps({k: "" for k in missing}, ensure_ascii=False, indent=1))
        return 0
    for title, items in (("Belum diterjemahkan", missing), ("Tidak dipakai lagi", unused), ("Penanda {n} tidak cocok", bad)):
        if items:
            print(f"{title} ({len(items)}):")
            for k in items:
                print("  " + json.dumps(k, ensure_ascii=False))
    print(f"{len(keys)} kunci, {len(table)} terjemahan.")
    return 1 if missing or unused or bad else 0


if __name__ == "__main__":
    sys.exit(main())
