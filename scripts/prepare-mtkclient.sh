#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

readonly MTKCLIENT_COMMIT='cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3'
readonly MTKCLIENT_URL='https://github.com/bkerler/mtkclient.git'

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target=${1:-"$repo_root/mtkclient"}
patch="$repo_root/patches/0001-Support-Carbonara-with-BROM-origin-DA1.patch"

if [[ -e "$target" ]]; then
    echo "Refusing to overwrite existing path: $target" >&2
    exit 1
fi

git clone "$MTKCLIENT_URL" "$target"
git -C "$target" checkout --detach "$MTKCLIENT_COMMIT"
git -C "$target" apply --check "$patch"
git -C "$target" apply "$patch"

python3 -m py_compile \
    "$target/mtkclient/Library/DA/mtk_da_handler.py" \
    "$target/mtkclient/Library/DA/xflash/xflash_lib.py"
git -C "$target" diff --check

echo "Prepared mtkclient at $target"
