#!/usr/bin/env bash

set -eu;

if test ! -e /ide/bin/gp-code || test ! -v GITPOD_REPO_ROOT; then {
    printf 'gitconfig-gitpod.sh: This script is meant to be run on Gitpod, quitting...\n' && exit 0;
} fi

SOURCE_DIR="$(readlink -f "$0")" && SOURCE_DIR="${SOURCE_DIR%/*}";
cat $SOURCE_DIR/gitconfig >> $HOME/.gitconfig