#!/usr/bin/env python3
"""Writes the retail <Folder>.toc files. Rerun after any _Camelot.toc change."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Copied from BigWigs.toc at each release, which lists a patch's number before it goes live.
RETAIL_INTERFACE = "120100, 120105, 120107"
# With no TOC the addon does not exist on retail, so the options' template gates stay shut (decision 22).
NO_RETAIL_TOC = {"EverythingAurasTemplates"}


def read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def camelot_folders():
    return [f for f in sorted(os.listdir(ROOT)) if os.path.isfile(os.path.join(ROOT, f, f + "_Camelot.toc"))]


def retail_toc(text, folder):
    text, n = re.subn(r"(?m)^## Interface:[^\r\n]*", "## Interface: " + RETAIL_INTERFACE, text, count=1)
    if n != 1:
        raise SystemExit(f"{folder}: no ## Interface line")
    text = text.replace("A modified fork of WeakAuras for WoW Forever.", "A modified fork of WeakAuras.")
    if folder == "EverythingAuras":
        text, n = re.subn(r"(?m)^EA\\Names\.lua(\r?)$",
                          lambda m: f"EA\\Names.lua{m[1]}\nEA\\Retail.lua{m[1]}", text, count=1)
        if n != 1:
            raise SystemExit(f"{folder}: no EA\\Names.lua line")
    return text


if __name__ == "__main__":
    for folder in camelot_folders():
        if folder in NO_RETAIL_TOC:
            continue
        text = retail_toc(read(os.path.join(ROOT, folder, folder + "_Camelot.toc")), folder)
        dst = os.path.join(ROOT, folder, folder + ".toc")
        with open(dst, "wb") as f:
            f.write(text.encode("utf-8"))
        print("wrote", os.path.relpath(dst, ROOT))
