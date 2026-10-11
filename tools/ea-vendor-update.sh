#!/usr/bin/env bash
# usage: tools/ea-vendor-update.sh <M33kAuras release tag>
# Moves vendor-ea to the transformed release. Then: git switch -c sync/<tag> main && git merge --no-ff vendor-ea
set -euo pipefail

tag="${1:?usage: ea-vendor-update.sh <M33kAuras release tag>}"
root="$(git rev-parse --show-toplevel)"
ref="refs/upstream/m33/$tag"
tmp="$(mktemp -d)"
trap 'git -C "$root" worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

if [ -n "$(git -C "$root" status --porcelain)" ]; then
  echo "working tree not clean" >&2; exit 1
fi
# Upstream tags live outside refs/tags so git describe and the packager never see them.
if ! git -C "$root" rev-parse --verify -q "$ref" >/dev/null; then
  git -C "$root" fetch m33 --no-tags "refs/tags/$tag:$ref"
fi
upstream="$(git -C "$root" rev-parse --verify "$ref^{commit}")"

git -C "$root" worktree add --detach "$tmp/wt" "$upstream" >/dev/null
cp "$root/tools/ea_transform.py" "$tmp/"
( cd "$tmp/wt" && py "$tmp/ea_transform.py" . )
# -f: commit the renamed tree as is, even where ignore rules would hide tracked files.
git -C "$tmp/wt" add -A -f
tree="$(git -C "$tmp/wt" write-tree)"

if git -C "$root" rev-parse --verify -q refs/heads/vendor-ea >/dev/null; then
  if [ "$(git -C "$root" rev-parse vendor-ea^{tree})" = "$tree" ]; then
    echo "vendor-ea already matches $tag"; exit 0
  fi
  commit="$(git -C "$root" commit-tree "$tree" -p vendor-ea -p "$upstream" -m "vendor-ea: M33kAuras $tag transformed")"
else
  commit="$(git -C "$root" commit-tree "$tree" -p "$upstream" -m "vendor-ea: M33kAuras $tag transformed")"
fi
git -C "$root" update-ref refs/heads/vendor-ea "$commit"
echo "$commit" >> "$root/.git-blame-ignore-revs.pending"
echo "vendor-ea -> $(git -C "$root" rev-parse --short vendor-ea) ($tag)"
echo "next: git switch -c sync/$tag main && git merge --no-ff vendor-ea"
echo "then move .git-blame-ignore-revs.pending into .git-blame-ignore-revs in the merge commit"
