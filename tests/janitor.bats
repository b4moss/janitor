#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  JANITOR="$ROOT/src/janitor.sh"
  WORK="$(mktemp -d)"
  TRASH="$(mktemp -d)"
  CONF="$(mktemp -d)"
  export JANITOR_TRASH_DIR="$TRASH"
  export JANITOR_CONFIG_DIR="$CONF"
}

teardown() {
  rm -rf "$WORK" "$TRASH" "$CONF"
}

make_tree() {
  mkdir -p "$WORK/project-a/node_modules/pkg"
  echo x >"$WORK/project-a/node_modules/pkg/index.js"
  mkdir -p "$WORK/project-b/vendor/lib"
  echo y >"$WORK/project-b/vendor/lib/foo.php"
  mkdir -p "$WORK/keep-me/node_modules/pkg"
  echo z >"$WORK/keep-me/node_modules/pkg/index.js"
}

@test "version option prints janitor version" {
  run "$JANITOR" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "janitor 0.3.0" ]]
}

@test "version short option -V prints janitor version" {
  run "$JANITOR" -V
  [ "$status" -eq 0 ]
  [[ "$output" == "janitor 0.3.0" ]]
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

@test "creates default config on first run" {
  [ ! -f "$CONF/config.json" ]
  make_tree
  run bash -c "yes | '$JANITOR' '$WORK' --dry-run"
  [ "$status" -eq 0 ]
  [ -f "$CONF/config.json" ]
  run python3 -c "import json; d=json.load(open('$CONF/config.json')); assert d['version']==1"
  [ "$status" -eq 0 ]
}

@test "config show prints JSON and creates file if missing" {
  [ ! -f "$CONF/config.json" ]
  run "$JANITOR" config show
  [ "$status" -eq 0 ]
  [ -f "$CONF/config.json" ]
  [[ "$output" == *'"version": 1'* ]]
  [[ "$output" == *'"default_action": "trash"'* ]]
}

@test "config targets replaces built-in list" {
  make_tree
  mkdir -p "$WORK/project-a/dist/out"
  echo d >"$WORK/project-a/dist/out/a.js"
  cat >"$CONF/config.json" <<'EOF'
{
  "version": 1,
  "targets": ["dist"],
  "ignore": [],
  "trash_dir": null,
  "default_action": "trash",
  "confirm": true
}
EOF
  run bash -c "yes | '$JANITOR' '$WORK'"
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/project-a/dist" ]
  [ -d "$WORK/project-a/node_modules" ]
  [ -d "$WORK/project-b/vendor" ]
}

@test "config ignore merges with CLI --ignore" {
  make_tree
  cat >"$CONF/config.json" <<'EOF'
{
  "version": 1,
  "targets": ["node_modules", "vendor"],
  "ignore": ["project-a"],
  "trash_dir": null,
  "default_action": "trash",
  "confirm": true
}
EOF
  run bash -c "yes | '$JANITOR' '$WORK' --ignore 'keep-me'"
  [ "$status" -eq 0 ]
  [ -d "$WORK/project-a/node_modules" ]
  [ -d "$WORK/keep-me/node_modules" ]
  [ ! -d "$WORK/project-b/vendor" ]
}

@test "config confirm false skips prompt" {
  make_tree
  cat >"$CONF/config.json" <<'EOF'
{
  "version": 1,
  "targets": ["node_modules", "vendor"],
  "ignore": [],
  "trash_dir": null,
  "default_action": "trash",
  "confirm": false
}
EOF
  # no yes pipe
  run "$JANITOR" "$WORK"
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/project-a/node_modules" ]
  [[ "$output" != *"Aborted."* ]]
}

@test "config default_action force permanently deletes" {
  make_tree
  cat >"$CONF/config.json" <<'EOF'
{
  "version": 1,
  "targets": ["node_modules", "vendor"],
  "ignore": [],
  "trash_dir": null,
  "default_action": "force",
  "confirm": false
}
EOF
  run "$JANITOR" "$WORK"
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/project-a/node_modules" ]
  entries=("$TRASH"/*)
  if [[ -e "${entries[0]}" ]]; then
    false
  fi
  [[ "$output" == *"Cleared:"* ]]
}

@test "invalid config version fails" {
  cat >"$CONF/config.json" <<'EOF'
{
  "version": 99,
  "targets": ["node_modules"]
}
EOF
  run "$JANITOR" "$WORK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported config version"* ]]
}
