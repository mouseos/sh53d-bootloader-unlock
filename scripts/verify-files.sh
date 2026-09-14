#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [[ ! -f root/out/preload-sh53d-38JP_3_330.so ]]; then
    echo 'Root preload artifact is missing. Run ./scripts/prepare-root.sh first.' >&2
    exit 1
fi
sha256sum --check SHA256SUMS
cmp root-prebuilt/preload-sh53d-38JP_3_330.so root/out/preload-sh53d-38JP_3_330.so
