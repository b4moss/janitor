#!/bin/bash

set -euo pipefail

JANITOR_VERSION="0.3.0"

TARGET="."
DRY_RUN=false
FORCE=false
CLI_FORCE=false
CLI_IGNORE_PATTERNS=()
IGNORE_PATTERNS=()
TARGETS=(node_modules vendor .venv venv env)
CONFIRM=true
CONFIG_TRASH_DIR=""

# --- config helpers ---------------------------------------------------------

default_config_json() {
  cat <<'EOF'
{
  "version": 1,
  "targets": ["node_modules", "vendor", ".venv", "venv", "env"],
  "ignore": [],
  "trash_dir": null,
  "default_action": "trash",
  "confirm": true
}
EOF
}

resolve_config_path() {
  if [[ -n "${JANITOR_CONFIG_PATH:-}" ]]; then
    printf '%s\n' "$JANITOR_CONFIG_PATH"
    return
  fi
  local dir="${JANITOR_CONFIG_DIR:-$HOME/.config/janitor}"
  printf '%s\n' "${dir}/config.json"
}

ensure_config() {
  local path=$1
  if [[ -f "$path" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  default_config_json >"$path"
}

# Validate config and emit a shell-safe env block on stdout.
# Warnings go to stderr. Exit non-zero on invalid config.
read_config_env() {
  local path=$1
  python3 - "$path" <<'PY'
import json
import shlex
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f"invalid JSON: {e}", file=sys.stderr)
    sys.exit(2)
except OSError as e:
    print(f"cannot read config: {e}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict):
    print("config root must be an object", file=sys.stderr)
    sys.exit(2)

version = data.get("version", 1)
if version != 1:
    print(f"unsupported config version: {version}", file=sys.stderr)
    sys.exit(2)

allowed = {"version", "targets", "ignore", "trash_dir", "default_action", "confirm"}
unknown = sorted(set(data) - allowed)
if unknown:
    print(
        "warning: ignoring unknown config keys: " + ", ".join(unknown),
        file=sys.stderr,
    )

targets = data.get("targets", ["node_modules", "vendor", ".venv", "venv", "env"])
if not isinstance(targets, list) or not targets or not all(
    isinstance(t, str) and t for t in targets
):
    print(
        "config.targets must be a non-empty array of non-empty strings",
        file=sys.stderr,
    )
    sys.exit(2)

ignore = data.get("ignore", [])
if not isinstance(ignore, list) or not all(isinstance(i, str) and i for i in ignore):
    print("config.ignore must be an array of non-empty strings", file=sys.stderr)
    sys.exit(2)

trash_dir = data.get("trash_dir", None)
if trash_dir is not None and not isinstance(trash_dir, str):
    print("config.trash_dir must be a string or null", file=sys.stderr)
    sys.exit(2)

default_action = data.get("default_action", "trash")
if default_action not in ("trash", "force"):
    print("config.default_action must be 'trash' or 'force'", file=sys.stderr)
    sys.exit(2)

confirm = data.get("confirm", True)
if not isinstance(confirm, bool):
    print("config.confirm must be a boolean", file=sys.stderr)
    sys.exit(2)

def bash_array(name, values):
    if not values:
        return f"{name}=()"
    return f"{name}=(" + " ".join(shlex.quote(v) for v in values) + ")"

print(bash_array("TARGETS", targets))
print(bash_array("CONFIG_IGNORE", ignore))
print(f"CONFIG_TRASH_DIR={shlex.quote('' if trash_dir is None else trash_dir)}")
print(f"CONFIG_DEFAULT_ACTION={shlex.quote(default_action)}")
print(f"CONFIG_CONFIRM={'true' if confirm else 'false'}")
PY
}

cmd_config_show() {
  local path
  path=$(resolve_config_path)
  ensure_config "$path"
  python3 - "$path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
print(json.dumps(data, indent=2, ensure_ascii=False))
print(f"\n# config path: {path}", file=sys.stderr)
PY
}

# --- argument parsing -------------------------------------------------------

if [[ $# -gt 0 && "$1" == "config" ]]; then
  shift
  if [[ $# -eq 0 ]]; then
    echo "Usage: janitor config show" >&2
    exit 1
  fi
  case "$1" in
    show)
      cmd_config_show
      exit 0
      ;;
    *)
      echo "Unknown config subcommand: $1" >&2
      echo "Usage: janitor config show" >&2
      exit 1
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-V)
      printf 'janitor %s\n' "$JANITOR_VERSION"
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      CLI_FORCE=true
      FORCE=true
      shift
      ;;
    --ignore)
      if [[ $# -lt 2 ]]; then
        echo "Option --ignore requires a pattern" >&2
        exit 1
      fi
      CLI_IGNORE_PATTERNS+=("$2")
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

CONFIG_PATH=$(resolve_config_path)
ensure_config "$CONFIG_PATH"

CONFIG_IGNORE=()
CONFIG_DEFAULT_ACTION="trash"
CONFIG_CONFIRM=true
config_env=$(read_config_env "$CONFIG_PATH") || exit $?
# shellcheck disable=SC1090
eval "$config_env"

# CLI --force wins; otherwise honor config default_action.
if ! $CLI_FORCE && [[ "$CONFIG_DEFAULT_ACTION" == "force" ]]; then
  FORCE=true
fi
if [[ "$CONFIG_CONFIRM" == "false" ]]; then
  CONFIRM=false
fi

# ignore: config + CLI (merge)
IGNORE_PATTERNS=()
if (( ${#CONFIG_IGNORE[@]} > 0 )); then
  IGNORE_PATTERNS+=("${CONFIG_IGNORE[@]}")
fi
if (( ${#CLI_IGNORE_PATTERNS[@]} > 0 )); then
  IGNORE_PATTERNS+=("${CLI_IGNORE_PATTERNS[@]}")
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Not a directory: $TARGET" >&2
  exit 1
fi

# Colors (only when stdout is a TTY).
if [[ -t 1 ]]; then
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  GREEN=$'\033[32m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
fi

# Format size in KB as human-readable (KB / MB / GB).
format_size() {
  local kb=$1
  if (( kb >= 1048576 )); then
    awk -v kb="$kb" 'BEGIN { printf "%.2f GB", kb / 1048576 }'
  elif (( kb >= 1024 )); then
    awk -v kb="$kb" 'BEGIN { printf "%.2f MB", kb / 1024 }'
  else
    printf "%d KB" "$kb"
  fi
}

resolve_trash_dir() {
  if [[ -n "${JANITOR_TRASH_DIR:-}" ]]; then
    printf '%s\n' "$JANITOR_TRASH_DIR"
  elif [[ -n "$CONFIG_TRASH_DIR" ]]; then
    printf '%s\n' "$CONFIG_TRASH_DIR"
  elif [[ "$(uname -s)" == Darwin ]]; then
    printf '%s\n' "$HOME/.Trash"
  else
    printf '%s\n' "$HOME/.local/share/Trash/files"
  fi
}

unique_trash_dest() {
  local trash_dir=$1
  local base
  base=$(basename "$2")
  local dest="${trash_dir}/${base}"
  if [[ ! -e "$dest" ]]; then
    printf '%s\n' "$dest"
    return
  fi
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  dest="${trash_dir}/${base}.${ts}"
  local n=1
  while [[ -e "$dest" ]]; do
    dest="${trash_dir}/${base}.${ts}.${n}"
    n=$((n + 1))
  done
  printf '%s\n' "$dest"
}

trash_target() {
  local dir=$1
  local trash_dir=$2
  local dest
  dest=$(unique_trash_dest "$trash_dir" "$dir")
  mv "$dir" "$dest"
}

remove_target() {
  local dir=$1
  rm -rf "$dir"
}

should_ignore() {
  local dir=$1
  local pattern
  if (( ${#IGNORE_PATTERNS[@]} == 0 )); then
    return 1
  fi
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    # bash =~ uses ERE-like matching against the full path.
    if [[ "$dir" =~ $pattern ]]; then
      printf '%s\n' "$pattern"
      return 0
    fi
  done
  return 1
}

find_expr=()
for i in "${!TARGETS[@]}"; do
  if (( i == 0 )); then
    find_expr+=(-type d -name "${TARGETS[$i]}")
  else
    find_expr+=(-o -type d -name "${TARGETS[$i]}")
  fi
done

candidates=()
while IFS= read -r -d '' dir; do
  candidates+=("$dir")
done < <(
  find "$TARGET" \
    \( "${find_expr[@]}" \) \
    -prune \
    -print0
)

dirs=()
if (( ${#candidates[@]} > 0 )); then
  for dir in "${candidates[@]}"; do
    if matched_pattern=$(should_ignore "$dir"); then
      printf "%s[skip] matches --ignore '%s': %s%s\n" \
        "$CYAN" "$matched_pattern" "$dir" "$RESET"
      continue
    fi
    dirs+=("$dir")
  done
fi

count=${#dirs[@]}

if (( count == 0 )); then
  echo "No target directories found under: $TARGET"
  exit 0
fi

sizes_kb=()
total_kb=0

echo "Found $count target director$([[ $count -eq 1 ]] && echo "y" || echo "ies"):"
echo

for dir in "${dirs[@]}"; do
  # du -sk: size in 1K blocks (portable on macOS / Linux)
  kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
  kb=${kb:-0}
  sizes_kb+=("$kb")
  total_kb=$((total_kb + kb))
  printf "  %s%s%s  %s%s%s\n" \
    "$RED" "$(format_size "$kb")" "$RESET" \
    "$YELLOW" "$dir" "$RESET"
done

echo
printf "%sTotal: %s (%s director%s)%s\n" \
  "$RED" \
  "$(format_size "$total_kb")" \
  "$count" \
  "$([[ $count -eq 1 ]] && echo "y" || echo "ies")" \
  "$RESET"
echo

if $DRY_RUN; then
  if $FORCE; then
    prompt="Proceed with dry-run (would permanently delete)? [y/N] "
  else
    prompt="Proceed with dry-run (would move to Trash)? [y/N] "
  fi
elif $FORCE; then
  prompt="Permanently delete these directories? [y/N] "
else
  prompt="Move these directories to Trash? [y/N] "
fi

if $CONFIRM; then
  read -r -p "$prompt" answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

echo

trash_dir=""
if ! $DRY_RUN && ! $FORCE; then
  trash_dir=$(resolve_trash_dir)
  if [[ ! -d "$trash_dir" ]]; then
    echo "Trash directory not found: $trash_dir" >&2
    echo "Use --force to permanently delete instead." >&2
    exit 1
  fi
fi

for i in "${!dirs[@]}"; do
  dir="${dirs[$i]}"
  kb="${sizes_kb[$i]}"
  if $DRY_RUN; then
    if $FORCE; then
      printf "%s[dry-run] would remove: %s  %s%s\n" \
        "$CYAN" "$(format_size "$kb")" "$dir" "$RESET"
    else
      printf "%s[dry-run] would move to Trash: %s  %s%s\n" \
        "$CYAN" "$(format_size "$kb")" "$dir" "$RESET"
    fi
  elif $FORCE; then
    printf "%sRemoving: %s  %s%s\n" "$CYAN" "$(format_size "$kb")" "$dir" "$RESET"
    remove_target "$dir"
  else
    printf "%sMoving to Trash: %s  %s%s\n" \
      "$CYAN" "$(format_size "$kb")" "$dir" "$RESET"
    trash_target "$dir" "$trash_dir"
  fi
done

echo
if $DRY_RUN; then
  if $FORCE; then
    printf "%sWould clear: %s%s\n" "$GREEN" "$(format_size "$total_kb")" "$RESET"
  else
    printf "%sWould move to Trash: %s%s\n" "$GREEN" "$(format_size "$total_kb")" "$RESET"
  fi
elif $FORCE; then
  printf "%sCleared: %s%s\n" "$GREEN" "$(format_size "$total_kb")" "$RESET"
else
  printf "%sMoved to Trash: %s%s\n" "$GREEN" "$(format_size "$total_kb")" "$RESET"
fi
