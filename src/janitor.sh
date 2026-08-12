#!/bin/bash

set -euo pipefail

TARGET="."
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
    *)
      TARGET="$arg"
      ;;
  esac
done

if [[ ! -d "$TARGET" ]]; then
  echo "Not a directory: $TARGET" >&2
  exit 1
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

dirs=()
while IFS= read -r -d '' dir; do
  dirs+=("$dir")
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
  printf "  %s  %s\n" "$(format_size "$kb")" "$dir"
done

echo
echo "Total: $(format_size "$total_kb") ($count director$([[ $count -eq 1 ]] && echo "y" || echo "ies"))"
echo

if $DRY_RUN; then
  prompt="Proceed with dry-run? [y/N] "
else
  prompt="Remove these directories? [y/N] "
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

for i in "${!dirs[@]}"; do
  dir="${dirs[$i]}"
  kb="${sizes_kb[$i]}"
  if $DRY_RUN; then
    printf "[dry-run] %s  %s\n" "$(format_size "$kb")" "$dir"
  else
    printf "Removing: %s  %s\n" "$(format_size "$kb")" "$dir"
    rm -rf "$dir"
  fi
done

echo
if $DRY_RUN; then
  echo "Would clear: $(format_size "$total_kb")"
else
  echo "Cleared: $(format_size "$total_kb")"
fi
