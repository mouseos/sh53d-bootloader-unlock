#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

readonly EXPECTED_ROOT_COMMIT='7f5c29c7d27a5bd4bc0855d10efd7453fd542337'
readonly EXPECTED_ARTIFACT_SHA256='a3a41a6c29b53eec429cb20acfda3e56c50f6e921af3a9e40c86fb4dd87feb01'

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_artifact="$repo_root/root-prebuilt/preload-sh53d-38JP_3_330.so"
target_artifact="$repo_root/root/out/preload-sh53d-38JP_3_330.so"

[[ -f "$repo_root/root/run.sh" ]] || {
    echo 'Root submodule is missing. Run git submodule update --init --recursive.' >&2
    exit 1
}
[[ "$(git -C "$repo_root/root" rev-parse HEAD)" == "$EXPECTED_ROOT_COMMIT" ]] || {
    echo 'Unexpected root submodule commit.' >&2
    exit 1
}
[[ "$(sha256sum "$source_artifact" | awk '{print $1}')" == "$EXPECTED_ARTIFACT_SHA256" ]] || {
    echo 'Root preload artifact hash mismatch.' >&2
    exit 1
}

mkdir -p "$(dirname "$target_artifact")"
cp "$source_artifact" "$target_artifact"
echo "Prepared $target_artifact"
