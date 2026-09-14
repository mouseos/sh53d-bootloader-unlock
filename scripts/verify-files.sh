#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [[ ! -f root/dist/sh53d-root ]]; then
    echo 'Root release binaries are missing. Run ./scripts/prepare-root.sh first.' >&2
    exit 1
fi
sha256sum --check SHA256SUMS
