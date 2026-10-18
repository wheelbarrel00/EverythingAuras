#!/usr/bin/env python3
"""Deterministic M33kAuras -> Everything Auras transform for the vendor-ea branch.

Usage: py tools/ea_transform.py <clean checkout of an M33kAuras release>
Rewrites the tree in place (never .git). The same input always gives the same output.
"""
import os
import re
import sys
from collections import Counter

OLD, NEW = "M33kAuras", "EverythingAuras"

EA_OWNED_DROPS = (
    "WeakAuras/",
    "M33Auras/",
    ".github/",
    ".pkgmeta",
    ".gitignore",
    "README.md",
    "CONTRIBUTING.md",
)

# AI assistant instruction files from upstream never enter the fork (the pattern keeps the word out of this file).
AI_FILES = re.compile(r"(?i)(^|/)(c[l]aude[^/]*\.md|agents[^/]*\.md|\.c[l]aude/)")

BINARY_EXT = {".blp", ".tga", ".ogg", ".mp3", ".wav", ".ttf", ".otf", ".m2", ".png",
              ".jpg", ".jpeg", ".gif", ".zip", ".bmp", ".ico"}

PROTECT = [re.compile(r"github\.com/m33shoq/M33kAuras[\w./#?=&%+-]*"), re.compile(r"discord\.gg/M33kAuras")]

GENERIC = [("M33KAURAS", "EVERYTHINGAURAS"), ("M33kAuras", NEW), ("m33kauras", "everythingauras")]

# Appended, not prepended, so line numbers stay equal to M33kAuras' for reading its bug reports.
NOTICE_LUA = "-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md\n"

# Addon-message prefixes are capped at 16 characters by AceComm-3.0 and Chomp.
SPECIAL_STRINGS = {"M33kAurasProg": "EAurasProg"}

FOREVER_INTERFACE = range(16000, 20000)

HITS = Counter()


def is_binary(path, data):
    if os.path.splitext(path)[1].lower() in BINARY_EXT:
        return True
    return b"\x00" in data[:8192]


def top_folder_new(top):
    return NEW + top[len(OLD):] if top.startswith(OLD) else None


def new_relpath(rel):
    if AI_FILES.search(rel):
        return None
    for d in EA_OWNED_DROPS:
        if rel == d or (d.endswith("/") and rel.startswith(d)):
            return None
    parts = rel.split("/")
    newtop = top_folder_new(parts[0])
    if newtop is None:
        return "/".join(p.replace(OLD, NEW) for p in parts)
    parts[0] = newtop
    if len(parts) == 2 and parts[1].lower().endswith(".toc"):
        parts[1] = newtop + "_Camelot.toc"
    else:
        parts[1:] = [p.replace(OLD, NEW) for p in parts[1:]]
    return "/".join(parts)


def protect(text):
    saved = []

    def stash(m):
        saved.append(m.group(0))
        return "\x00P%d\x00" % (len(saved) - 1)

    for rx in PROTECT:
        text = rx.sub(stash, text)
    return text, saved


def unprotect(text, saved):
    return re.sub(r"\x00P(\d+)\x00", lambda m: saved[int(m.group(1))], text)


def counted_sub(rule, pattern, repl, text, flags=0):
    new, n = re.subn(pattern, repl, text, flags=flags)
    HITS[rule] += n
    return new


def forever_interface(m):
    keep = [v.strip() for v in m.group(1).split(",") if v.strip().isdigit() and int(v) in FOREVER_INTERFACE]
    if not keep:
        HITS["toc-interface-empty"] += 1
        return m.group(0)
    return "## Interface: " + ", ".join(keep) + m.group(2)


def transform_text(rel_new, text):
    text, saved = protect(text)
    text = counted_sub("slash", re.escape('"/wa", "/M33kAuras"'), '"/eauras", "/everythingauras"', text)
    # Custom code written for M33kAuras calls M33kAuras.*, so the sandbox keeps that key.
    text = counted_sub("sandbox-compat", r"(?m)^(\s*)M33kAuras = FakeM33kAuras,(\r?)$",
                       lambda m: f"{m.group(1)}M33kAuras = FakeM33kAuras,{m.group(2)}\n"
                                 f"{m.group(1)}\x00KEEPOLD\x00 = FakeM33kAuras,{m.group(2)}", text)
    for old_s, new_s in SPECIAL_STRINGS.items():
        text = counted_sub("comm-prefix", re.escape(f'"{old_s}"'), f'"{new_s}"', text)
    text = counted_sub("ai-comment", r"hello c[l]aude/copilot/gemini/etc! ", "", text)
    # The packager would ask CurseForge to expand these for EA's own project, so blank them as M33kAuras' releases do.
    text = counted_sub("localization-token", r"(?m)^--@localization\(.*\)@(\r?)$", r"\1", text)
    if re.fullmatch(r"(EverythingAuras\w*)/\1_Camelot\.toc", rel_new):
        text = counted_sub("toc-title", r"(?m)^## Title: M33kAuras", "## Title: Everything Auras", text)
        text = counted_sub("toc-interface", r"(?m)^## Interface:\s*(.+?)(\r?)$", forever_interface, text)
    for a, b in GENERIC:
        text = text.replace(a, b)
    text = text.replace("\x00KEEPOLD\x00", OLD)
    text = counted_sub("toc-path-ref", r"\b(EverythingAuras\w*)([/\\]+)(?:EverythingAuras\w*|M33Auras\w*)\.toc\b",
                       lambda m: f"{m.group(1)}{m.group(2)}{m.group(1)}_Camelot.toc", text)
    return unprotect(text, saved)


COMM_CALL = re.compile(r"(?:RegisterComm|SendCommMessage|RegisterAddonPrefix|SmartAddonMessage|SendAddonMessage|"
                       r"RegisterAddonMessagePrefix)\(\s*\"([^\"]*)\"")


def walk(root):
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != ".git"]
        for f in fn:
            yield os.path.relpath(os.path.join(dp, f), root).replace("\\", "/")


def validate(root):
    problems = []
    expect = {"slash": 1, "sandbox-compat": 1, "comm-prefix": 1, "toc-title": 5, "toc-interface": 5}
    for rule, minimum in expect.items():
        if HITS[rule] < minimum:
            problems.append(f"rule '{rule}' matched {HITS[rule]} times (expected >= {minimum})")
    if HITS["toc-interface-empty"]:
        problems.append("a TOC lists no Forever interface number")
    for rel in walk(root):
        p = os.path.join(root, rel)
        data = open(p, "rb").read()
        if is_binary(rel, data):
            continue
        src = data.decode("utf-8", errors="surrogateescape")
        if re.search(r"(?i)c[l]aude|a[n]thropic", src):
            problems.append(f"{rel}: contains an AI tool name")
        if AI_FILES.search(rel) or re.search(r"(?i)c[l]aude|a[n]thropic", rel):
            problems.append(f"{rel}: AI tool file name")
        if "--@localization" in src:
            problems.append(f"{rel}: @localization token left")
        if not (rel.endswith(".lua") and rel.split("/")[0].startswith(NEW) and "/Libs/" not in rel):
            continue
        for m in COMM_CALL.finditer(src):
            if len(m.group(1)) > 16:
                problems.append(f"{rel}: comm prefix '{m.group(1)}' is longer than 16 characters")
        for line_no, line in enumerate(src.split("\n"), 1):
            scrub = line.replace("M33kAuras = FakeEverythingAuras,", "")
            for rx in PROTECT:
                scrub = rx.sub("", scrub)
            if re.search(r"M33kAuras|M33KAURAS|m33kauras", scrub):
                problems.append(f"{rel}:{line_no}: old name left")
    for e in os.listdir(root):
        if e.startswith(NEW) and os.path.isdir(os.path.join(root, e)):
            tocs = [f for f in os.listdir(os.path.join(root, e)) if f.lower().endswith(".toc")]
            if tocs != [e + "_Camelot.toc"]:
                problems.append(f"{e}: TOC files {tocs}, expected exactly [{e}_Camelot.toc]")
    return problems


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: py tools/ea_transform.py <clean M33kAuras checkout>")
    root = os.path.abspath(sys.argv[1])
    # Not idempotent: a second run would rename the sandbox compatibility key.
    if any(e.startswith(NEW) for e in os.listdir(root)):
        raise SystemExit("refusing: tree already contains EverythingAuras folders")
    stats = Counter()
    for rel in sorted(walk(root)):
        src = os.path.join(root, rel)
        new_rel = new_relpath(rel)
        if new_rel is None:
            os.remove(src)
            stats["dropped"] += 1
            continue
        data = open(src, "rb").read()
        new_data = data
        if not is_binary(rel, data):
            text = data.decode("utf-8", errors="surrogateescape")
            new_text = transform_text(new_rel, text)
            if new_text != text and new_rel.endswith(".lua"):
                if not new_text.endswith("\n"):
                    new_text += "\n"
                new_text += NOTICE_LUA
            if new_text != text:
                stats["content"] += 1
                new_data = new_text.encode("utf-8", errors="surrogateescape")
        dst = os.path.join(root, new_rel)
        if new_rel != rel:
            stats["renamed"] += 1
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            os.remove(src)
        if new_rel != rel or new_data is not data:
            with open(dst, "wb") as fh:
                fh.write(new_data)
    for dp, _, _ in sorted(os.walk(root, topdown=False), key=lambda t: -len(t[0])):
        if ".git" in dp.replace("\\", "/").split("/"):
            continue
        if dp != root and not os.listdir(dp):
            os.rmdir(dp)
    problems = validate(root)
    print(f"ea_transform: {dict(stats)} rule hits {dict(sorted(HITS.items()))}")
    if problems:
        print("VALIDATION FAILED:")
        for p in problems[:50]:
            print("  " + p)
        sys.exit(2)


if __name__ == "__main__":
    main()
