# janitor

Clean up your packages as oneshot.

janitor will clean ups...

- `vendor/`
- `node_modules/`
- `.venv`
- `venv/`
- `env/`

## How to use

### Homebrew

```shell
brew tap b4moss/tap
brew install b4moss/tap/janitor

# clean up recursively from current directory.
janitor . 

# When you hit this command, janitor will count up target directories and total filesize.
# Finally, will ask you really do it or not "Remove these directories? [y/N]"

# execute specific directory
janitor /path/to/directory

# dry run
janitor . --dry-run

```

###

```shell
# clone

git clone https://github.com/b4moss/janitor
cd janitor

# setup
chmod +x ./janitor.sh

# execute
./janitor.sh .

# dry run
./janitor.sh . --dry-run

# execute specific directory
.janitor.sh /path/to/directory
```

LICENSE: **MIT LICENSE**

----

by [B4M LLC.](https://b4m.co.jp)