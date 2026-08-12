#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  JANITOR="$ROOT/src/janitor.sh"
  WORK="$(mktemp -d)"
  TRASH="$(mktemp -d)"
  export JANITOR_TRASH_DIR="$TRASH"
}

teardown() {
  rm -rf "$WORK" "$TRASH"
}

make_tree() {
  mkdir -p "$WORK/project-a/node_modules/pkg"
  echo x >"$WORK/project-a/node_modules/pkg/index.js"
  mkdir -p "$WORK/project-b/vendor/lib"
  echo y >"$WORK/project-b/vendor/lib/foo.php"
  mkdir -p "$WORK/keep-me/node_modules/pkg"
  echo z >"$WORK/keep-me/node_modules/pkg/index.js"
}

@test "ignore one pattern excludes matching paths" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --ignore 'keep-me'"
  [ "$status" -eq 0 ]
  [ -d "$WORK/keep-me/node_modules" ]
  [ ! -d "$WORK/project-a/node_modules" ]
  [ ! -d "$WORK/project-b/vendor" ]
}

@test "ignore multiple patterns excludes each match" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --ignore 'project-a' --ignore 'project-b'"
  [ "$status" -eq 0 ]
  [ -d "$WORK/project-a/node_modules" ]
  [ -d "$WORK/project-b/vendor" ]
  [ ! -d "$WORK/keep-me/node_modules" ]
}

@test "skip line is printed for ignored paths" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --ignore 'keep-me'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[skip] matches --ignore 'keep-me':"*keep-me*node_modules* ]]
}

@test "missing trash directory errors and mentions --force" {
  make_tree
  export JANITOR_TRASH_DIR="$WORK/no-such-trash"
  run bash -c "yes | '$JANITOR' '$WORK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Trash directory not found"* ]]
  [[ "$output" == *"--force"* ]]
  [ -d "$WORK/project-a/node_modules" ]
}

@test "moves targets to trash when trash exists" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK'"
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/project-a/node_modules" ]
  [ ! -d "$WORK/project-b/vendor" ]
  [ ! -d "$WORK/keep-me/node_modules" ]
  # basenames land in trash (collision may rename; at least one node_modules)
  found=0
  for p in "$TRASH"/*; do
    base=$(basename "$p")
    case "$base" in
      node_modules|node_modules.*|vendor|vendor.*) found=1 ;;
    esac
  done
  [ "$found" -eq 1 ]
  [[ "$output" == *"Moved to Trash"* ]]
}

@test "force permanently deletes without using trash" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --force"
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/project-a/node_modules" ]
  [ ! -d "$WORK/project-b/vendor" ]
  # trash should remain empty (only . or empty)
  entries=("$TRASH"/*)
  if [[ -e "${entries[0]}" ]]; then
    # fail if anything was moved into trash
    false
  fi
  [[ "$output" == *"Cleared:"* ]]
}

@test "dry-run does not move or delete" {
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --dry-run"
  [ "$status" -eq 0 ]
  [ -d "$WORK/project-a/node_modules" ]
  [ -d "$WORK/project-b/vendor" ]
  [ -d "$WORK/keep-me/node_modules" ]
  entries=("$TRASH"/*)
  if [[ -e "${entries[0]}" ]]; then
    false
  fi
  [[ "$output" == *"Would move to Trash"* ]]
}
