#!/bin/bash

set -e

TARGET="${1:-.}"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
  TARGET="."
  DRY_RUN=true
elif [[ "$2" == "--dry-run" ]]; then
  DRY_RUN=true
fi

find "$TARGET" \
  \( -type d -name node_modules \
  -o -type d -name vendor \
  -o -type d -name .venv \
  -o -type d -name venv \
  -o -type d -name env \
  \) \
  -prune \
  -print0 |
while IFS= read -r -d '' dir; do
  if $DRY_RUN; then
    echo "[dry-run] $dir"
  else
    echo "Removing: $dir"
    rm -rf "$dir"
  fi
done