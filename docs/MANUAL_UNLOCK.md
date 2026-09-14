# Manual unlock sequence

`scripts/unlock.sh`が実行する処理の詳細です。パスはrepository rootからの相対パスです。

## 1. mtkclientの準備

```bash
./scripts/prepare-mtkclient.sh
python3 -m pip install -r mtkclient/requirements.txt
```

## 2. 一時root

`root/`は`mouseos/sh53d-temp-root`のGit submoduleです。未取得ならrepository rootで`git submodule update --init --recursive`を実行します。続けて`./scripts/prepare-root.sh`で固定release `v0.2.0`のbinaryを取得・検証します。

```bash
cd root
./run.sh
cd ..
adb shell "/data/local/tmp/sh53d-root -c 'id; getenforce'"
```

`uid=0`と`Permissive`の両方が必要です。

## 3. BROM moduleのdry-run

```bash
adb push brom-entry/sh53d_brom_entry-runtime.ko /data/local/tmp/
adb shell "/data/local/tmp/sh53d-root -c 'insmod /data/local/tmp/sh53d_brom_entry-runtime.ko execute=0 timeout_ms=60000'"
adb shell "/data/local/tmp/sh53d-root -c 'dmesg | tail -40'"
adb shell "/data/local/tmp/sh53d-root -c 'rmmod sh53d_brom_entry'"
```

logに`dry run only; no MMIO or storage write performed`があることを確認します。

## 4. read-only Carbonara試験

端末固有のmtkclient stateをrepositoryの管理対象に入れず、古いsessionも再利用しないよう、空の作業directoryを作ります。

```bash
repo_root=$PWD
mkdir -p "$repo_root/.work"
work=$(mktemp -d "$repo_root/.work/manual.XXXXXX")
cd "$work"
python3 "$repo_root/mtkclient/mtk.py" printgpt \
    --ptype carbonara \
    --skipwdt \
    --loader "$repo_root/mtkclient/mtkclient/Loader/MTK_DA_V5.bin" \
    --preloader "$repo_root/firmware/preloader_a.bin"
```

mtkclientがPreLoader VCOM待機に入ったら、別terminalで実行します。

```bash
adb shell "/data/local/tmp/sh53d-root -c 'insmod /data/local/tmp/sh53d_brom_entry-runtime.ko execute=1 timeout_ms=60000'"
```

ADBはwatchdog resetで切断されます。mtkclient側で次を確認します。

```text
Using signed DA1 for an explicit Carbonara attempt
Sending emi data succeeded
Successfully uploaded stage 2
DA Extensions successfully added at 0x4fff0000
GPT Table:
```

## 5. seccfg backup

同じ作業directoryで実行します。DA sessionが継続中なので、mtkclientは`.state`から再接続します。

```bash
python3 "$repo_root/mtkclient/mtk.py" r seccfg seccfg-before.bin \
    --ptype carbonara \
    --skipwdt \
    --loader "$repo_root/mtkclient/mtkclient/Loader/MTK_DA_V5.bin" \
    --preloader "$repo_root/firmware/preloader_a.bin"
sha256sum seccfg-before.bin
```

## 6. eraseとunlock

ここからuserdataへの破壊的変更が始まります。以下の2 commandの間でAndroidを起動させないでください。SH-53DのGPTに`md_udc`は存在しません。

```bash
python3 "$repo_root/mtkclient/mtk.py" e metadata,userdata \
    --ptype carbonara \
    --skipwdt \
    --loader "$repo_root/mtkclient/mtkclient/Loader/MTK_DA_V5.bin" \
    --preloader "$repo_root/firmware/preloader_a.bin"

python3 "$repo_root/mtkclient/mtk.py" da seccfg unlock \
    --ptype carbonara \
    --skipwdt \
    --loader "$repo_root/mtkclient/mtkclient/Loader/MTK_DA_V5.bin" \
    --preloader "$repo_root/firmware/preloader_a.bin"
```

1つ目は`All partitions formatted.`、2つ目は`Successfully wrote seccfg.`で終わることを確認します。

## 7. reset

```bash
python3 "$repo_root/mtkclient/mtk.py" reset \
    --ptype carbonara \
    --skipwdt \
    --loader "$repo_root/mtkclient/mtkclient/Loader/MTK_DA_V5.bin" \
    --preloader "$repo_root/firmware/preloader_a.bin"
```

USB cableを抜いて電源ボタンを長押しし、unlock warningと初期セットアップ画面を確認します。
