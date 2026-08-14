#!/usr/bin/env bash
# verify-hermes-load.sh — Confirm Hermes discovers hephaestus skills.
#
# Hermes has no project-local skill discovery: it reads ~/.hermes/skills plus
# whatever `skills.external_dirs` names. So this checks the wiring, not just the
# files, and prints the exact YAML to add when the wiring is missing.
#
# Requires `hermes` on PATH. Exit 0 when the CLI is absent so the script can stay
# in CI optionally; pass --require to fail instead.
#
# Every check below is free — layout assertions plus unbilled CLI calls like
# `chat --help` and `skills list` — and so only proves a skill *resolves*.
# It cannot prove Hermes injects the skill's **body** — `-s` could
# preload nothing but the description and every assertion here would still pass,
# which is precisely how #154 lost two measurement runs to a workflow the model
# never actually received. Nothing offline closes that gap: `hermes skills
# inspect` reads registries, not local dirs, and `hermes prompt-size` reports the
# skills *index* only. It takes one inference call, so it is opt-in via --live
# rather than a default that silently bills every quality-gate run.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-hermes-load.sh
#   bash .hephaestus/scripts/verify-hermes-load.sh
#   bash scripts/verify-hermes-load.sh --require /path/to/project
#   bash scripts/verify-hermes-load.sh --live          # + one billed probe

set -uo pipefail

REQUIRE=0
LIVE=0
while :; do
  case "${1:-}" in
    --require) REQUIRE=1; shift ;;
    --live)    LIVE=1; shift ;;
    *)         break ;;
  esac
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Verify the *project's* skills, not the submodule's. Run from an installed
# project the script lives at <project>/.hephaestus/scripts/, and it is
# <project>/.hermes/skills that install.sh links and tells the user to wire —
# the submodule copy has no project-specific orient. The `.hephaestus` unwrap
# comes first because it holds even when the submodule is a symlink (bash's
# logical `cd` keeps the link name in $SRC); cwd is only a fallback, since a
# Hermes user's $HOME always has a .hermes/skills that is not this project.
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)" || exit 1
elif [ "$(basename "$SRC")" = ".hephaestus" ]; then
  ROOT="$(cd "$SRC/.." && pwd)"
elif [ -d "$PWD/.hermes/skills" ]; then
  ROOT="$PWD"
else
  ROOT="$SRC"
fi
cd "$ROOT" || exit 1
SKILLS_DIR="$ROOT/.hermes/skills"

if ! command -v hermes >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: hermes not on PATH" >&2
    exit 1
  fi
  echo "skip: hermes not on PATH"
  exit 0
fi

fail=0

# ── Unattended contract ──────────────────────────────────────────────────────
# loop.sh runs `hermes chat -s … -q … --yolo --accept-hooks`, and /worktrees
# spawns with the same -s/-q pair. --yolo bypasses command approval and
# --accept-hooks is the separate gate for shell hooks — losing either leaves an
# unattended session parked on a prompt with no TTY to answer. Checked against
# `hermes chat --help` because chat's flag set is its own, not the top level's.
# Word-boundary grep, not substring: -s alone would match inside --skills.
if ! chat_help=$(hermes chat --help 2>&1); then
  echo "ERR: hermes chat --help failed" >&2
  exit 1
fi
for flag in -s -q --yolo --accept-hooks; do
  if ! grep -qE "(^|[[:space:],])${flag}([[:space:],=]|$)" <<< "$chat_help"; then
    echo "ERR: hermes chat --help no longer documents ${flag}" >&2
    echo "     the hermes entry in loop.sh's dispatch table depends on it to run" >&2
    echo "     unattended — re-measure and update the dispatch table" >&2
    fail=1
  fi
done

# ── Delegate briefs ──────────────────────────────────────────────────────────
for agent in coder explorer reviewer tester researcher; do
  if [ ! -f ".hermes/agents/$agent.md" ]; then
    echo "ERR: missing Hermes delegate brief .hermes/agents/$agent.md" >&2
    fail=1
  elif ! grep -q "generated from .claude/agents/$agent.md" ".hermes/agents/$agent.md"; then
    echo "ERR: Hermes delegate brief $agent is not generated from .claude/agents/$agent.md" >&2
    fail=1
  fi
done

# ── Discovery wiring ─────────────────────────────────────────────────────────
# Wired either by skills.external_dirs naming this project's .hermes/skills, or
# by HERMES_HOME pointing at this project's .hermes (whose skills/ is native).
cfg_path=$(hermes config path 2>/dev/null || true)

wired=0
if [ -n "${HERMES_HOME:-}" ] && [ "$(cd "$HERMES_HOME" 2>/dev/null && pwd)" = "$ROOT/.hermes" ]; then
  wired=1
  echo "  ✓ HERMES_HOME points at $ROOT/.hermes"
elif [ -n "$cfg_path" ] && [ -f "$cfg_path" ]; then
  if grep -qF "$SKILLS_DIR" "$cfg_path"; then
    wired=1
    echo "  ✓ skills.external_dirs names $SKILLS_DIR"
  fi
fi

if [ "$wired" -eq 0 ]; then
  echo "ERR: Hermes is not wired to this project's skills." >&2
  echo "     Add to $(hermes config path 2>/dev/null || echo '~/.hermes/config.yaml') under the top-level \`skills:\` key:" >&2
  echo "" >&2
  echo "       skills:" >&2
  echo "         external_dirs:" >&2
  echo "           - $SKILLS_DIR" >&2
  echo "" >&2
  echo "     Or start Hermes with HERMES_HOME=$ROOT/.hermes for a project-scoped profile." >&2
  exit 1
fi

# ── Live skill listing ───────────────────────────────────────────────────────
if ! listing=$(hermes skills list 2>/dev/null); then
  echo "ERR: hermes skills list failed" >&2
  exit 1
fi

for skill in autopilot start-issue ship finish critique; do
  case "$listing" in
    *"$skill"*) ;;
    *)
      echo "ERR: Hermes skill listing missing $skill" >&2
      fail=1
      ;;
  esac
done

# ── Preload identifier ───────────────────────────────────────────────────────
# `/worktrees` spawns sessions with `hermes chat -s hephaestus/start-issue -q`.
# `-s` is load-bearing: a bare `/start-issue` handed to `-q` is never dispatched
# as a skill (single-query mode bypasses the slash dispatcher and sends it to
# the model as literal text), so the identifier must resolve. Asserted on the
# layout rather than by running `hermes chat`, which would bill an inference
# call; Hermes resolves `-s <category>/<skill>` against this exact path.
#
# It must resolve to exactly one skill. Hermes refuses to guess between
# candidates and returns `Unknown skill(s)`, so a second install offering
# hephaestus/start-issue kills every spawned window just as surely as none does
# — a state the README's own instructions reach, since a user-level install
# symlinks ~/.hermes/skills while --vendor writes real copies a project then
# names in external_dirs. Dedup is by resolved path, matching Hermes: a symlink
# and its target are one candidate, not a collision.

# Every root Hermes searches: its home skills dir, then each external_dirs entry.
# Both YAML list forms are read — under-counting here would restore the very
# false-healthy report this check exists to prevent.
skill_roots() {
  printf '%s\n' "${HERMES_HOME:-$HOME/.hermes}/skills"
  [ -n "$cfg_path" ] && [ -f "$cfg_path" ] || return 0
  awk '
    /^[[:space:]]*#/           { next }
    /^[^[:space:]#]/           { in_s = ($0 ~ /^skills:/); in_e = 0 }
    in_s && $1 == "external_dirs:" && /\[/ {
      line = $0; sub(/^[^[]*\[/, "", line); sub(/\].*$/, "", line)
      n = split(line, a, ",")
      for (i = 1; i <= n; i++) { gsub(/^[ \t"'\'']+|[ \t"'\'']+$/, "", a[i]); if (a[i] != "") print a[i] }
      next
    }
    in_s && $1 == "external_dirs:" && NF == 1 { in_e = 1; next }
    in_e && /^[[:space:]]*-/   {
      line = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      gsub(/^["'\'']+|["'\'']+$/, "", line); if (line != "") print line; next
    }
    in_e && NF                 { in_e = 0 }
  ' "$cfg_path"
}

matches=""
while IFS= read -r root; do
  [ -n "$root" ] || continue
  case "$root" in "~/"*) root="$HOME/${root#\~/}" ;; esac
  [ -f "$root/hephaestus/start-issue/SKILL.md" ] || continue
  # pwd -P resolves a symlinked skill dir — what a user-level install creates.
  resolved=$(cd "$root/hephaestus/start-issue" 2>/dev/null && pwd -P) || continue
  matches="${matches}${resolved}/SKILL.md"$'\n'
done <<EOF
$(skill_roots)
EOF

matches=$(printf '%s' "$matches" | sort -u)
match_count=$(printf '%s' "$matches" | grep -c . || true)

if [ "$match_count" -eq 0 ]; then
  echo "ERR: no skill at hephaestus/start-issue —" >&2
  echo "     'hermes chat -s hephaestus/start-issue' cannot resolve, so the" >&2
  echo "     /worktrees spawn would start sessions with no skill loaded." >&2
  fail=1
elif [ "$match_count" -gt 1 ]; then
  echo "ERR: hephaestus/start-issue is ambiguous — $match_count skills claim it:" >&2
  printf '%s\n' "$matches" | sed 's/^/       /' >&2
  echo "     Hermes refuses to guess between them, so 'hermes chat -s" >&2
  echo "     hephaestus/start-issue' aborts and every /worktrees window dies." >&2
  echo "     Drop one install: uninstall the user-level copy, or remove this" >&2
  echo "     project's entry from skills.external_dirs." >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

# ── Live body probe (--live) ─────────────────────────────────────────────────
# Asks the model to confirm a sentence only the skill *body* carries, and mirrors
# the real spawn form so it exercises the path /worktrees actually uses. Measured
# discriminating, not vacuous: `-s hephaestus/start-issue` answers OK while
# `-s hephaestus/ship` and a bare session both answer MISSING. (`--ignore-rules`
# is deliberately absent, though measurement says it would not have mattered —
# it does not suppress `-s` preloads in v0.15.1 despite what its help text says.)
if [ "$LIVE" -eq 1 ]; then
  probe="Do not use any tools. If your loaded instructions contain the exact \
phrase 'this skill is the /start-issue adapter', reply with the single token \
HEPH_BODY_OK and nothing else. Otherwise reply HEPH_BODY_MISSING."

  # `timeout` is coreutils, absent from a stock macOS, and no other shipped
  # script here depends on it. Without the guard its "command not found" would
  # surface as an empty reply and get misreported below as a credentials fault.
  if command -v timeout >/dev/null 2>&1; then
    reply=$(timeout 180 hermes chat -s hephaestus/start-issue -Q -q "$probe" 2>&1)
  else
    reply=$(hermes chat -s hephaestus/start-issue -Q -q "$probe" 2>&1)
  fi

  # MISSING is tested first on purpose. Both sentinels appear in the probe text,
  # so a reply that echoes the question back contains both — matching OK first
  # would turn that into a false pass, the one outcome this check exists to
  # prevent. Ordering it this way makes an ambiguous reply fail loudly instead.
  case "$reply" in
    *HEPH_BODY_MISSING*)
      echo "ERR: Hermes resolved hephaestus/start-issue but did not load its body." >&2
      echo "     Every layout check above passes, so the skill file is found — the" >&2
      echo "     model just never receives the workflow. Sessions spawned this way" >&2
      echo "     improvise instead of following the workflow." >&2
      exit 1
      ;;
    *HEPH_BODY_OK*)
      echo "  ✓ live probe: skill body reaches the model"
      ;;
    *)
      # No sentinel either way: the call itself failed. Report it as an
      # inconclusive probe, never as a passing body check.
      echo "ERR: live probe inconclusive — hermes chat returned no sentinel." >&2
      echo "     Usually missing or expired credentials (\`hermes auth status\`)." >&2
      printf '     response: %s\n' "$(printf '%s' "$reply" | tr '\n' ' ' | cut -c1-200)" >&2
      exit 1
      ;;
  esac
fi

echo "✓ Hermes loads hephaestus skills and delegate briefs"
