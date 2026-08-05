#!/usr/bin/env bash
# check_composition.sh — Verify README ## Composition section matches the
# `requires:` and `chains:` metadata declared on each command file.
#
# Bidirectional check:
#   1. Every (cmd, requires) annotation in the README matches the file's header.
#   2. The set of children visible under each parent in the README tree equals
#      the parent file's `chains:` list (catches edges removed from a file but
#      kept in README, and phantom edges added to README that no file declares).
#
# Exits 0 if in sync, 1 if drift detected (with diff report on stderr).
# Invoked by /update-docs and by tests/test_composition.sh.
# hephaestus:doc-verifier

set -uo pipefail
# -e omitted intentionally: we collect drift across all checks instead of
# bailing on the first mismatch.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
CMDS_DIR="$ROOT/.claude/commands"

drift=0
report() { drift=1; echo "  ✗ $1" >&2; }

# cmd_meta <file> → "<requires>|<chains>" (empty fields if header missing)
cmd_meta() {
  local file=$1 req chs
  req=$(grep -m1 -oE '<!-- requires:[^>]*-->' "$file" 2>/dev/null \
        | sed -E 's|<!-- requires: *||; s| *-->||')
  chs=$(grep -m1 -oE '<!-- chains:[^>]*-->' "$file" 2>/dev/null \
        | sed -E 's|<!-- chains: *||; s| *-->||')
  echo "${req}|${chs}"
}

# Normalize a chain list "/a, /b, /c" or "none"/"" → sorted space-separated "a b c"
normalize_chains() {
  local raw=$1
  [ -z "$raw" ] || [ "$raw" = "none" ] && { echo ""; return; }
  echo "$raw" | tr ',/' ' ' | tr -s ' ' | xargs -n1 | sort -u | xargs
}

# Pull just the body of the ## Composition section
comp_block=$(awk '/^## Composition/{f=1; next} f && /^## /{f=0} f' "$README")
if [ -z "$comp_block" ]; then
  echo "ERR: no '## Composition' section in README.md" >&2
  exit 1
fi

# Extract from each line of the comp block (bash-3.2 safe — no associative
# arrays; stored as newline-delimited records instead):
#   - readme_req    = lines of "cmd|requires-annotation"
#   - readme_chains = lines of "parent child" edges visible in the tree
readme_req=""
readme_chains=""
re_cmd_req='/([a-z][a-z0-9-]+)[[:space:]].*\(requires:[[:space:]]*([^)]+)\)'
current_root=""
current_top=""
while IFS= read -r line; do
  # Capture (cmd, requires) annotation
  if [[ "$line" =~ $re_cmd_req ]]; then
    cmd="${BASH_REMATCH[1]}"
    req="${BASH_REMATCH[2]}"
    req="${req%"${req##*[![:space:]]}"}"  # rtrim
    readme_req="${readme_req}${cmd}|${req}
"

    # Determine tree position to assign parent→child edge
    if [[ "$line" =~ ^/ ]]; then
      # root of a new tree (no leading branch glyph or indent)
      current_root=$cmd
      current_top=""
    elif [[ "$line" =~ ^[├└] ]]; then
      # top-level child of the current root
      [ -n "$current_root" ] && readme_chains="${readme_chains}${current_root} ${cmd}
"
      current_top=$cmd
    else
      # indented sub-child of the most recent top-level
      [ -n "$current_top" ] && readme_chains="${readme_chains}${current_top} ${cmd}
"
    fi
  fi
done <<< "$comp_block"

readme_children_for() {
  printf '%s' "$readme_chains" | awk -v p="$1" '$1==p{out=out" "$2} END{print out}'
}

# (1) Every (cmd, requires) annotation in the README must match the file's metadata.
while IFS='|' read -r cmd expected_req; do
  [ -z "$cmd" ] && continue
  file="$CMDS_DIR/${cmd}.md"
  if [ ! -f "$file" ]; then
    report "README mentions /$cmd but $file does not exist"
    continue
  fi
  meta=$(cmd_meta "$file")
  actual_req="${meta%|*}"
  if [ "$actual_req" != "$expected_req" ]; then
    report "/$cmd: README says (requires: $expected_req); file declares (requires: $actual_req)"
  fi
done <<< "$readme_req"

# (2) For every parent → children edge implied by the README tree, the parent
# file's `chains:` list must equal that set. Catches both: chain removed from
# file but kept in README, and phantom child added to README.
parents_seen=$(printf '%s' "$readme_chains" | awk '{print $1}')
# Also include parents that have chains: declared in their file but no children
# in the README at all (otherwise we'd miss "all children dropped" drift).
for f in "$CMDS_DIR"/*.md; do
  cmd=$(basename "$f" .md)
  meta=$(cmd_meta "$f")
  chs="${meta#*|}"
  [ -z "$chs" ] || [ "$chs" = "none" ] && continue
  parents_seen="${parents_seen}
${cmd}"
done
parents_seen=$(printf '%s\n' "$parents_seen" | sed '/^$/d' | sort -u)

for parent in $parents_seen; do
  file="$CMDS_DIR/${parent}.md"
  [ -f "$file" ] || continue
  meta=$(cmd_meta "$file")
  file_set=$(normalize_chains "${meta#*|}")
  readme_set=$(normalize_chains "$(readme_children_for "$parent")")
  if [ "$file_set" != "$readme_set" ]; then
    report "/$parent: README children = '${readme_set:-<none>}'; file chains = '${file_set:-<none>}'"
  fi
done

if [ "$drift" -eq 0 ]; then
  echo "✓ README Composition tree in sync with command metadata"
  exit 0
fi

echo "" >&2
echo "Drift detected — update README.md ## Composition to match the metadata above," >&2
echo "or update the affected command's <!-- requires:/chains: --> headers." >&2
exit 1
