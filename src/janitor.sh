#!/bin/bash

set -euo pipefail

JANITOR_VERSION="0.2.1"

TARGET="."
DRY_RUN=false
FORCE=false
IGNORE_PATTERNS=()

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
      FORCE=true
      shift
      ;;
    --ignore)
      if [[ $# -lt 2 ]]; then
        echo "Option --ignore requires a pattern" >&2
        exit 1
      fi
      IGNORE_PATTERNS+=("$2")
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

candidates=()
while IFS= read -r -d '' dir; do
  candidates+=("$dir")
done < <(
  find "$TARGET" \
    \( -type d -name node_modules \
    -o -type d -name vendor \
    -o -type d -name .venv \
    -o -type d -name venv \
    -o -type d -name env \
    \) \
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

read -r -p "$prompt" answer
case "$answer" in
  y|Y|yes|YES) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

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
