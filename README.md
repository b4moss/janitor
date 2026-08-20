# janitor

Clean up your packages as oneshot.

janitor will clean ups...

- `vendor/`
- `node_modules/`
- `.venv`
- `venv/`
- `env/`

By default, matching directories are **moved to Trash** (not permanently deleted).

## How to use

### Homebrew

```shell
brew tap b4moss/tap
brew install b4moss/tap/janitor

# clean up recursively from current directory (move to Trash)
janitor .

# When you hit this command, janitor will count up target directories and total filesize.
# Finally, will ask you really do it or not.

# execute specific directory
janitor /path/to/directory

# print version
janitor --version

# dry run (no move / no delete)
janitor . --dry-run

# permanently delete instead of moving to Trash
janitor . --force

# exclude paths matching a regex (repeatable)
janitor . --ignore 'keep-me'
janitor . --ignore 'project-a' --ignore 'vendor/legacy'
```

### From source

```shell
# clone
git clone https://github.com/b4moss/janitor
cd janitor

# setup
chmod +x ./src/janitor.sh

# execute
./src/janitor.sh .

# dry run
./src/janitor.sh . --dry-run

# execute specific directory
./src/janitor.sh /path/to/directory
```

## Trash behavior

- **macOS**: `~/.Trash`
- **Linux**: `~/.local/share/Trash/files`
- If the Trash directory does not exist, janitor exits with an error and suggests `--force`.
- `--force` permanently deletes with `rm -rf` (confirmation prompt still appears).
- `--dry-run` never moves or deletes.

## Ignore

`--ignore REGEX` matches against the full found path (ERE-like). Pass the option multiple times to apply multiple patterns. Ignored paths are listed as `[skip]`.

## Tests

```shell
bats tests/
```

LICENSE: **MIT LICENSE**

----

by [B4M LLC.](https://b4m.co.jp)
