#!/usr/bin/env bash
# models.sh — Resolve an agent's model tier into per-harness settings.
#
# Sourced by the sync-*-adapters.sh generators; not executable on its own.
# Requires ROOT (hephaestus root) and MODE (sync|--check) to be set by the caller.
#
# See .ai/models.conf for the file format and override precedence.

MODEL_TIERS="opus sonnet haiku inherit"

# Flat "harness.tier.key=value" pairs, newline-separated. Later lines win, so
# layers are appended in precedence order and read back last-match-first.
MODEL_MAP=""

models_load_file() {
  local file=$1 line key value
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    # Trim surrounding whitespace from both halves.
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$key" ] && [ -n "$value" ] || continue
    MODEL_MAP="${MODEL_MAP}${key}=${value}"$'\n'
  done < "$file"
}

# Layer the override files over the shipped defaults. --check deliberately reads
# the shipped file alone: committed adapters must not depend on who ran the
# generator, or the drift gate would fail on every machine but one.
models_load() {
  models_load_file "$ROOT/.ai/models.conf"
  [ "$MODE" = "--check" ] && return 0

  local applied=""
  local user_file="${HOME:-}/.hephaestus/models.conf"
  local project_file="$PWD/.ai/models.conf"

  if [ -f "$user_file" ]; then
    models_load_file "$user_file"
    applied="$applied $user_file"
  fi
  if [ "$PWD" != "$ROOT" ] && [ -f "$project_file" ]; then
    models_load_file "$project_file"
    applied="$applied $project_file"
  fi
  if [ -n "${HEPHAESTUS_MODELS:-}" ]; then
    if [ ! -f "$HEPHAESTUS_MODELS" ]; then
      echo "ERR: HEPHAESTUS_MODELS points at a missing file: $HEPHAESTUS_MODELS" >&2
      return 1
    fi
    models_load_file "$HEPHAESTUS_MODELS"
    applied="$applied $HEPHAESTUS_MODELS"
  fi

  if [ -n "$applied" ]; then
    echo "note: model map overridden by$applied — generated adapters will differ from the shipped defaults that --check enforces" >&2
  fi
}

# models_lookup <harness> <tier> <key> — echo the value, or nothing if unset.
models_lookup() {
  local harness=$1 tier=$2 key=$3
  [ "$tier" = "inherit" ] && return 0
  printf '%s' "$MODEL_MAP" | awk -F= -v k="${harness}.${tier}.${key}" '
    $1 == k { v = $0; sub(/^[^=]*=/, "", v); last = v }
    END { if (last != "") print last }
  '
}

# models_validate_tier <tier> <file> — empty tier is allowed and means inherit.
models_validate_tier() {
  local tier=$1 file=$2
  [ -z "$tier" ] && return 0
  case " $MODEL_TIERS " in
    *" $tier "*) return 0 ;;
  esac
  echo "ERR: invalid model tier '$tier' in $file (expected one of: $MODEL_TIERS)" >&2
  return 1
}
