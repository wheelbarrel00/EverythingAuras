#!/usr/bin/env python3
"""Applies WeakAuras commits to the working tree under Everything Auras names, one three-way merge per file.

Usage: py tools/wa_pick.py [--revert] <WeakAuras commit> [...]
Fetch first: git fetch wa --no-tags main:refs/upstream/wa/main
A commit with any conflict is rolled back whole and reported as deferred. Nothing is committed.
--revert undoes picks made earlier in the working tree, in the order given.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = re.compile(r"https?://[^\s\"'\]\)]+")
TOKENS = [("WeakAurasProg", "EAurasProg"), ("WEAKAURAS", "EVERYTHINGAURAS"), ("WeakAuras", "EverythingAuras"),
          ("weakauras", "everythingauras")]
SKIP_DIRS = (".github/",)


def git(*args, binary=False):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode("utf-8", "replace"))
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def ea_path(path):
    if path.endswith(".toc") or path.startswith(SKIP_DIRS):
        return None
    for old, new in TOKENS[1:]:
        path = path.replace(old, new)
    return path


def ea_text(text):
    saved = []

    def stash(m):
        saved.append(m.group(0))
        return "\x00U%d\x00" % (len(saved) - 1)

    text = URL.sub(stash, text)
    for old, new in TOKENS:
        text = text.replace(old, new)
    return re.sub(r"\x00U(\d+)\x00", lambda m: saved[int(m.group(1))], text)


def blob(commit, path):
    try:
        return git("show", f"{commit}:{path}", binary=True).decode("utf-8", "surrogateescape").replace("\r\n", "\n")
    except RuntimeError:
        return None


def pick(commit, revert=False):
    subject = git("log", "-1", "--format=%s", commit).strip()
    changes = []
    for line in git("diff-tree", "-r", "--no-commit-id", "--name-status", "-M", f"{commit}^", commit).splitlines():
        parts = line.split("\t")
        status = parts[0][0]
        old, new = (parts[1], parts[2]) if status == "R" else (parts[1], parts[1])
        changes.append((status, old, new))
    snapshot, conflicts, skipped, touched = {}, [], [], []
    for status, old, new in changes:
        target = ea_path(new)
        if target is None:
            skipped.append(new)
            continue
        local = os.path.join(ROOT, target)
        base = blob(f"{commit}^", old) if status != "A" else None
        theirs = blob(commit, new) if status != "D" else None
        base = ea_text(base) if base is not None else None
        theirs = ea_text(theirs) if theirs is not None else None
        if revert:
            base, theirs = theirs, base
            status = {"A": "D", "D": "A"}.get(status, status)
        exists = os.path.isfile(local)
        raw = open(local, "rb").read() if exists else None
        snapshot[local] = raw
        touched.append(target)
        if status == "D":
            if exists and raw.decode("utf-8", "surrogateescape").replace("\r\n", "\n") == base:
                os.remove(local)
            else:
                conflicts.append(f"{target} (deleted upstream, changed here)")
            continue
        if not exists:
            if base is None:
                os.makedirs(os.path.dirname(local), exist_ok=True)
                open(local, "wb").write(theirs.encode("utf-8", "surrogateescape"))
            else:
                conflicts.append(f"{target} (missing here)")
            continue
        ours = raw.decode("utf-8", "surrogateescape")
        crlf = "\r\n" in ours
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for name, text in (("ours", ours.replace("\r\n", "\n")), ("base", base or ""), ("theirs", theirs)):
                paths[name] = os.path.join(tmp, name)
                open(paths[name], "wb").write(text.encode("utf-8", "surrogateescape"))
            r = subprocess.run(["git", "merge-file", "-L", "Everything Auras", "-L", "WeakAuras base", "-L",
                                f"WeakAuras {commit[:8]}", paths["ours"], paths["base"], paths["theirs"]],
                               capture_output=True)
            merged = open(paths["ours"], "rb").read().decode("utf-8", "surrogateescape")
        if r.returncode != 0:
            conflicts.append(f"{target} ({r.returncode} conflict(s))")
            continue
        if crlf:
            merged = merged.replace("\n", "\r\n")
        open(local, "wb").write(merged.encode("utf-8", "surrogateescape"))
    if conflicts:
        for local, raw in snapshot.items():
            if raw is None:
                if os.path.isfile(local):
                    os.remove(local)
            else:
                open(local, "wb").write(raw)
    state = "deferred" if conflicts else ("reverted" if revert else "applied")
    print(f"{commit[:8]} {state}: {subject}")
    for c in conflicts:
        print(f"  conflict {c}")
    for s in skipped:
        print(f"  skipped {s} (apply by hand if needed)")
    return state, subject, conflicts, skipped


if __name__ == "__main__":
    args = sys.argv[1:]
    revert = "--revert" in args
    commits = [a for a in args if a != "--revert"]
    if not commits:
        raise SystemExit(__doc__)
    results = [pick(git("rev-parse", c).strip(), revert) for c in commits]
    done = sum(1 for r in results if r[0] != "deferred")
    print(f"{done} {'reverted' if revert else 'applied'}, {len(results) - done} deferred")
