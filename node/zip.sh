#!/bin/bash
OLD_DIR="$(pwd)"
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

# Start from an empty archive: 7zz only adds and updates entries, so a file
# deleted from node/ would otherwise stay in the zip and get deployed.
rm -f src.zip

# 7zz is pinned in mise.toml. state/ is the initial state seed.js loads into an
# empty database. -mx=1 is the fastest compression, as zip's -1 was.
7zz a -tzip -mx=1 src.zip *.js *.json state/*.json || exit 1

cd "$OLD_DIR"
