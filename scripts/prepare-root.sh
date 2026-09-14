#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

readonly RELEASE='v0.2.0'
readonly RELEASE_BASE='https://github.com/mouseos/sh53d-temp-root/releases/download/v0.2.0'

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dist="$repo_root/root/dist"

command -v curl >/dev/null || {
    echo 'curl was not found.' >&2
    exit 1
}
[[ -f "$repo_root/root/run.sh" ]] || {
    echo 'Root submodule is missing. Run git submodule update --init --recursive.' >&2
    exit 1
}

mkdir -p "$dist"
files=(SHA256SUMS sh53d-slide.so sh53d-exploit.so sh53d-root sh53d-launcher.so)
for file in "${files[@]}"; do
    if [[ -e "$dist/$file" ]]; then
        continue
    fi
    curl --fail --location --retry 3 \
        --output "$dist/$file" "$RELEASE_BASE/$file"
done

(cd "$dist" && sha256sum --check SHA256SUMS)
echo "Prepared sh53d-temp-root $RELEASE binaries in $dist"
