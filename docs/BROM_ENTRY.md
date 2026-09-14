# BROM entry implementation

## 概要

SH-53Dのstock Preloaderは、Security AOのretained registerにUSB download requestを設定し、watchdog reset後にBootROMへ入る正規処理を持っています。`brom-entry/sh53d_brom_entry.c`は、そのregister transactionをAndroidのroot kernel moduleから再現します。block deviceやPreloader partitionにはアクセスしません。

## Preloaderで確認した処理

`SetBromDownloadFlag`:

```text
0x1001a100 <- 0x0000ad98
0x1001a108 <- old | 1
0x1001a100 <- 0
0x1001a080 <- 0x444c0000 | ((timeout_seconds << 2) & 0x0000fffc) | 1
```

`0x1001a080` bit 0がUSB download enable、bit 1がbootloader download selectionです。moduleはbit 1がclearであることを確認し、BROM downloadを選択します。

## Moduleのguard

- 既定の`execute=0`は計算値をlogするだけでMMIO writeやresetを行わない。
- `execute=1`が明示された場合だけregisterを書く。
- device treeの`mediatek,security_ao` resourceが`0x1001a000`から始まり、必要な大きさを持つことを検査する。
- timeoutは1秒単位の1〜60秒に制限する。
- `BOOT_MISC0`をread backし、不一致なら元の`BOOT_MISC0`とreset-retention値を復元してresetしない。
- 検証成功後だけ`emergency_restart()`を実行する。

## 実機結果

`38JP_3_330`でmoduleをloadし、BROM USB `0e8d:0003`の列挙とmtkclient handshakeを確認しました。60秒のtimeoutでmtkclientを先に待機させた場合、署名済みDA1の起動まで進みました。

BROM handshake後にmtkclientがwatchdogを停止すると、retained flagのtimeoutはAndroidへの復帰を保証しません。通信不能時はUSBを抜き、物理的な強制再起動が必要です。

## Build

実機用binaryのvermagicは次のとおりです。

```text
6.6.89-android15-8-gbe8d201b0d27-ab13762941-4k SMP preempt mod_unload modversions aarch64
```

再buildには同じkernel release、configuration、`Module.symvers`、Clang toolchainが必要です。Sharp公開のAQUOS wish3 V3.21G kernel 6.6 sourceとClang 18でexternal moduleとしてbuildした後、実機の`uname -r`と`modinfo`のvermagicを必ず一致させます。

```bash
make -C /path/to/kernel-6.6 \
    O=/path/to/kernel-out \
    M="$PWD/brom-entry" \
    ARCH=arm64 LLVM=1 LLVM_IAS=1 modules
```

収録済み`sh53d_brom_entry-runtime.ko`は実機でload・BROM遷移を確認したartifactです。
