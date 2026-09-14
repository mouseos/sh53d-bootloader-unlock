#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

readonly EXPECTED_FINGERPRINT='DOCOMO/SH-53D/SH-53D:13/TP1A.220624.014/38JP_1_30I:user/release-keys'
readonly EXPECTED_PRELOADER_SHA256='98613d63052fa2f499802d7e35be47ca95025cd5a1400b9c546f09daa54c75f8'
readonly EXPECTED_MODULE_SHA256='a12d7f2bf1094412bb8ea3aec30759831c4be7560e1a76548cca36c02715a193'
readonly EXPECTED_MTKCLIENT_COMMIT='cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3'
readonly EXPECTED_LOADER_SHA256='aef234190ccb8145d2e3b8459741e9adb70f2caa8481aa216c1b25152afaca1f'
readonly REMOTE_DIR='/data/local/tmp'

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mtkclient_dir=$(realpath "${1:-"$repo_root/mtkclient"}")
mtk="$mtkclient_dir/mtk.py"
loader="$mtkclient_dir/mtkclient/Loader/MTK_DA_V5.bin"
preloader="$repo_root/firmware/preloader_a.bin"
module="$repo_root/brom-entry/sh53d_brom_entry-runtime.ko"
work_root="$repo_root/.work"
phase='host checks'

on_error() {
    status=$?
    echo "Stopped during: $phase" >&2
    if [[ "$phase" == 'erase' || "$phase" == 'seccfg unlock' ]]; then
        echo 'The destructive stage had started. Keep the device in DA mode and inspect the logs before resetting it.' >&2
    fi
    exit "$status"
}
trap on_error ERR

for command in adb git grep python3 realpath sha256sum tee timeout; do
    command -v "$command" >/dev/null || {
        echo "Required command not found: $command" >&2
        exit 1
    }
done

[[ -f "$mtk" && -f "$loader" ]] || {
    echo "Patched mtkclient was not found at $mtkclient_dir" >&2
    exit 1
}
[[ "$(git -C "$mtkclient_dir" rev-parse HEAD)" == "$EXPECTED_MTKCLIENT_COMMIT" ]] || {
    echo 'Unexpected mtkclient base commit.' >&2
    exit 1
}
expected_changes=$'mtkclient/Library/DA/mtk_da_handler.py\nmtkclient/Library/DA/xflash/xflash_lib.py'
actual_changes=$(git -C "$mtkclient_dir" diff --name-only | sort)
[[ "$actual_changes" == "$expected_changes" ]] || {
    echo 'Unexpected tracked changes in the mtkclient tree.' >&2
    printf '%s\n' "$actual_changes" >&2
    exit 1
}
[[ "$(sha256sum "$loader" | awk '{print $1}')" == "$EXPECTED_LOADER_SHA256" ]] || {
    echo 'MTK_DA_V5.bin hash mismatch.' >&2
    exit 1
}
[[ "$(sha256sum "$preloader" | awk '{print $1}')" == "$EXPECTED_PRELOADER_SHA256" ]] || {
    echo 'preloader_a.bin hash mismatch.' >&2
    exit 1
}
[[ "$(sha256sum "$module" | awk '{print $1}')" == "$EXPECTED_MODULE_SHA256" ]] || {
    echo 'BROM entry module hash mismatch.' >&2
    exit 1
}
grep -F 'explicit Carbonara attempt' "$mtkclient_dir/mtkclient/Library/DA/mtk_da_handler.py" >/dev/null
grep -F 'connagent == b"brom" and self.mtk.config.ptype == "carbonara"' \
    "$mtkclient_dir/mtkclient/Library/DA/xflash/xflash_lib.py" >/dev/null
python3 "$mtk" --help >/dev/null

device_count=$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
[[ "$device_count" == 1 ]] || {
    echo "Exactly one authorized adb device is required (found $device_count)." >&2
    exit 1
}
fingerprint=$(adb shell getprop ro.build.fingerprint | tr -d '\r')
[[ "$fingerprint" == "$EXPECTED_FINGERPRINT" ]] || {
    echo "Unsupported build: $fingerprint" >&2
    exit 1
}
root_state=$(adb shell "$REMOTE_DIR/sh53d-root" -c 'id; getenforce' | tr -d '\r')
grep -F 'uid=0(root)' <<<"$root_state" >/dev/null
grep -Fx 'Permissive' <<<"$root_state" >/dev/null

phase='BROM module dry-run'
adb push "$module" "$REMOTE_DIR/sh53d_brom_entry-runtime.ko" >/dev/null
adb shell "$REMOTE_DIR/sh53d-root" -c \
    'insmod /data/local/tmp/sh53d_brom_entry-runtime.ko execute=0 timeout_ms=60000'
dry_run_log=$(adb shell "$REMOTE_DIR/sh53d-root" -c 'dmesg | tail -40' | tr -d '\r')
grep -F 'dry run only; no MMIO or storage write performed' <<<"$dry_run_log" >/dev/null
adb shell "$REMOTE_DIR/sh53d-root" -c 'rmmod sh53d_brom_entry'

mkdir -p "$work_root"
work=$(mktemp -d "$work_root/run.XXXXXX")

mtk_args=(
    --ptype carbonara
    --skipwdt
    --loader "$loader"
    --preloader "$preloader"
)
run_mtk() {
    (cd "$work" && PYTHONUNBUFFERED=1 python3 "$mtk" "$@" "${mtk_args[@]}")
}

phase='read-only Carbonara validation'
echo 'Starting read-only Carbonara validation.'
(cd "$work" && timeout --signal=INT 180s env PYTHONUNBUFFERED=1 \
    python3 "$mtk" printgpt "${mtk_args[@]}") 2>&1 | tee "$work/printgpt.log" &
mtk_pid=$!
for ((attempt = 0; attempt < 30; attempt++)); do
    if grep -F 'Waiting for PreLoader VCOM' "$work/printgpt.log" >/dev/null 2>&1; then
        break
    fi
    kill -0 "$mtk_pid" >/dev/null 2>&1
    sleep 0.5
done
grep -F 'Waiting for PreLoader VCOM' "$work/printgpt.log" >/dev/null
adb shell "$REMOTE_DIR/sh53d-root" -c \
    'insmod /data/local/tmp/sh53d_brom_entry-runtime.ko execute=1 timeout_ms=60000' \
    >/dev/null 2>&1 || true
wait "$mtk_pid"
grep -F 'Using signed DA1 for an explicit Carbonara attempt' "$work/printgpt.log" >/dev/null
grep -F 'DA Extensions successfully added at 0x4fff0000' "$work/printgpt.log" >/dev/null
grep -F 'GPT Table:' "$work/printgpt.log" >/dev/null
grep -E '^metadata:' "$work/printgpt.log" >/dev/null
grep -E '^seccfg:' "$work/printgpt.log" >/dev/null
grep -E '^userdata:' "$work/printgpt.log" >/dev/null

phase='seccfg backup'
run_mtk r seccfg "$work/seccfg-before.bin" 2>&1 | tee "$work/seccfg-backup.log"
[[ -s "$work/seccfg-before.bin" ]]
sha256sum "$work/seccfg-before.bin" | tee "$work/seccfg-before.sha256"

cat <<'EOF'

The read-only test and seccfg backup succeeded.
The next command permanently erases metadata and userdata, then changes seccfg.
Do not continue unless all user data has been backed up.
EOF
read -r -p 'Type ERASE AND UNLOCK SH-53D to continue: ' confirmation
[[ "$confirmation" == 'ERASE AND UNLOCK SH-53D' ]] || {
    echo 'Cancelled before destructive operations.'
    exit 0
}

phase='erase'
run_mtk e metadata,userdata 2>&1 | tee "$work/erase.log"
grep -F 'All partitions formatted.' "$work/erase.log" >/dev/null

phase='seccfg unlock'
run_mtk da seccfg unlock 2>&1 | tee "$work/unlock.log"
grep -F 'Successfully wrote seccfg.' "$work/unlock.log" >/dev/null

phase='DA reset'
run_mtk reset 2>&1 | tee "$work/reset.log"

trap - ERR
echo
echo 'seccfg unlock completed.'
echo 'Disconnect the USB cable, hold the power button to start the phone, and verify the unlock warning.'
