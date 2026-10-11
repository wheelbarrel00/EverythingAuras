#!/usr/bin/env python3
"""Writes a git-ignored <Folder>.toc beside each <Folder>_Camelot.toc so retail can load a dev copy.

Usage: py tools/make-dev-tocs.py [retail interface list, default "120100, 120105"]
Never shipped: the files are ignored by .gitignore. Rerun after any _Camelot.toc change.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RETAIL = sys.argv[1] if len(sys.argv) > 1 else "120100, 120105"

for folder in sorted(os.listdir(ROOT)):
    src = os.path.join(ROOT, folder, folder + "_Camelot.toc")
    if not os.path.isfile(src):
        continue
    text = open(src, "rb").read().decode("utf-8")
    text, n = re.subn(r"(?m)^## Interface:[^\r\n]*", "## Interface: " + RETAIL, text, count=1)
    if n != 1:
        raise SystemExit(f"{src}: no ## Interface line")
    dst = os.path.join(ROOT, folder, folder + ".toc")
    open(dst, "wb").write(text.encode("utf-8"))
    print("wrote", os.path.relpath(dst, ROOT))
