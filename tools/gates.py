#!/usr/bin/env python3
"""Runs every Everything Auras gate and prints real output. Exit code 1 if any gate fails.

Usage: py tools/gates.py [--skip-tests]
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_DIR = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5"
LUA = os.path.join(LUA_DIR, "lua5.1.exe")
LUAC = os.path.join(LUA_DIR, "luac5.1.exe")
ADDONS = ["EverythingAuras", "EverythingAurasOptions", "EverythingAurasTemplates",
          "EverythingAurasModelPaths", "EverythingAurasArchive"]
# Inherited from M33kAuras 5.20.7-rg4-m99, they fail the same way there (measured 2026-10-11).
KNOWN_TEST_FAILURES = {"aura_list_async_test.lua", "progress_texture_test.lua"}
# Shipped code lints clean (M33kAuras m99 started at 309). Known dead code is named in .luacheckrc.
SHIPPED_WARNING_LIMIT = 0
TEXT_EXT = {".lua", ".toc", ".xml", ".yml", ".yaml", ".py", ".sh", ".pkgmeta", ".md", ""}
NO_EM_DASH_EXT = {".lua", ".toc", ".xml", ".yml", ".yaml", ".py", ".sh"}
EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]")

failed = []


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def git_files(*args):
    return [p for p in run(["git", *args]).stdout.splitlines() if p]


def gate_luac():
    files = git_files("ls-files", "-co", "--exclude-standard", "--", "*.lua")
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        scratch = os.path.join(tmp, "f.lua")
        for rel in files:
            data = open(os.path.join(ROOT, rel), "rb").read()
            # WoW accepts a UTF-8 BOM, luac 5.1 does not.
            if data.startswith(b"\xef\xbb\xbf"):
                data = data[3:]
            open(scratch, "wb").write(data)
            r = subprocess.run([LUAC, "-p", scratch], capture_output=True, text=True)
            if r.returncode != 0:
                bad.append(f"{rel}: {r.stderr.strip()}")
    print(f"luac -p: {len(files)} files, {len(bad)} failures")
    for b in bad:
        print("  " + b)
    if bad:
        failed.append("luac")


def gate_luacheck():
    r = run(["luacheck", ".", "--no-color", "--formatter", "plain", "--codes"])
    per = collections.Counter()
    shipped = []
    for line in r.stdout.splitlines():
        path = line.split(":")[0].replace("\\", "/")
        top = path.split("/")[0]
        per[top] += 1
        if top in ADDONS:
            shipped.append(line)
    total = sum(per.values())
    print(f"luacheck: {total} warnings, {len(shipped)} in shipped addon code")
    for k, v in per.most_common():
        print(f"  {v:5d} {k}")
    if r.returncode not in (0, 1):
        print(r.stdout[-2000:], r.stderr[-2000:])
        failed.append("luacheck")
    elif len(shipped) > SHIPPED_WARNING_LIMIT:
        print(f"  shipped warnings rose above the limit of {SHIPPED_WARNING_LIMIT}")
        failed.append("luacheck")


def gate_tests():
    names = re.findall(r'^\s*"([\w]+_test\.lua)",', open(os.path.join(ROOT, "tests", "run.lua"), encoding="utf-8").read(), re.M)
    fails = []
    for name in names:
        r = run([LUA, os.path.join("tests", name)])
        if r.returncode != 0:
            fails.append(name)
    print(f"tests: {len(names) - len(fails)} of {len(names)} files pass")
    for f in fails:
        print(f"  FAIL {f}{' (known)' if f in KNOWN_TEST_FAILURES else ''}")
    if set(fails) - KNOWN_TEST_FAILURES:
        failed.append("tests")


def gate_tocs():
    problems = []
    interfaces = set()
    for a in ADDONS:
        toc = os.path.join(ROOT, a, a + "_Camelot.toc")
        text = open(toc, encoding="utf-8-sig").read()
        if not re.search(r"(?m)^## Version: @project-version@\s*$", text):
            problems.append(f"{a}: version is not @project-version@")
        m = re.search(r"(?m)^## Interface:\s*(.+?)\s*$", text)
        interfaces.add(m.group(1) if m else None)
        if not os.path.isfile(os.path.join(ROOT, a, "LICENSE")):
            problems.append(f"{a}: no LICENSE")
    if len(interfaces) != 1:
        problems.append(f"TOC interface lines differ: {sorted(map(str, interfaces))}")
    tokens = [p for p in git_files("grep", "-l", "--", "--@localization") if p.endswith(".lua")]
    problems += [f"{p}: @localization token" for p in tokens]
    print(f"TOCs and packaging: {len(problems)} problems (interface {', '.join(map(str, interfaces))})")
    for p in problems:
        print("  " + p)
    if problems:
        failed.append("tocs")


def gate_text():
    changed = set(git_files("diff", "--name-only", "vendor-ea")) | set(git_files("ls-files", "-o", "--exclude-standard"))
    problems = []
    for rel in sorted(changed):
        path = os.path.join(ROOT, rel)
        ext = os.path.splitext(rel)[1].lower()
        if not os.path.isfile(path) or "/Libs/" in "/" + rel.replace("\\", "/") or ext not in TEXT_EXT:
            continue
        text = open(path, "rb").read().decode("utf-8", errors="replace")
        norm = rel.replace("\\", "/")
        if (ext == ".lua" and norm.split("/")[0] in ADDONS and "/EA/" not in norm
                and not text.rstrip().splitlines()[-1].startswith("-- Modified for Everything Auras")):
            problems.append(f"{rel}: changed from vendor-ea but has no GPL change notice on its last line")
        for n, line in enumerate(text.splitlines(), 1):
            if re.search(r"(?i)c[l]aude|a[n]thropic", line):
                problems.append(f"{rel}:{n}: AI tool name")
            if EMOJI.search(line):
                problems.append(f"{rel}:{n}: emoji")
            if ext in NO_EM_DASH_EXT and "\u2014" in line:
                problems.append(f"{rel}:{n}: em dash")
    print(f"text scan over {len(changed)} changed files: {len(problems)} problems")
    for p in problems:
        print("  " + p)
    if problems:
        failed.append("text")


gate_luac()
gate_luacheck()
if "--skip-tests" not in sys.argv:
    gate_tests()
gate_tocs()
gate_text()
print("GATES:", "FAILED " + ", ".join(failed) if failed else "all passed")
sys.exit(1 if failed else 0)
