# SH-53D bootloader unlock

Sharp AQUOS wish3 SH-53Dの出荷状態で拒否されるbootloader unlockを、rootからBootROMに入り、mtkclientのCarbonara経路で実行するための再現資料です。

## Unlock検証済み環境

| 項目 | 値 |
| --- | --- |
| 機種 | Sharp AQUOS wish3 SH-53D |
| Software | `38JP_1_30I` |
| Fingerprint | `DOCOMO/SH-53D/SH-53D:13/TP1A.220624.014/38JP_1_30I:user/release-keys` |
| Android | 13 |
| Security patch | 2023-12-05 |
| Kernel | Linux 4.19.191+, arm64 |
| SoC | MediaTek MT6833 |
| HW code | `0x989` |
| HW subcode | `0x8a00` |
| HW version | `0xca00` |
| BROM SW version | `0x0` |
| DA | XFlash V5 |

実機で、署名済みDA1起動、Carbonara、patch済みDA2、DA extension、HACCによるV4 seccfg更新、data wipe後のunlocked起動まで確認しています。

## Android 15でのBROM/GPT確認

更新後の`38JP_3_330`でも、Linux 6.6用moduleからBROMへ入り、stock署名DAでread-only `printgpt`が成功することを実機確認しました。

| 項目 | 値 |
| --- | --- |
| Software | `38JP_3_330` |
| Android | 15 |
| Kernel | `6.6.89-android15-8-gbe8d201b0d27-ab13762941-4k` |
| BROM | MT6833, HW code `0x989`, target config `0xe1` |
| DA | supplied Preloader + stock署名XFlash V5 DA |
| 結果 | DA1、DRAM setup、DA2、UFS初期化、GPT 74 entry取得に成功 |

検証に使ったbinaryは`brom-entry/sh53d_brom_entry-38JP_3_330.ko`です。詳細なコマンドとGPT上の主要offsetは[Android 15 BROM/printgpt実機記録](docs/ANDROID15_PRINTGPT.md)に記載しています。既存の`scripts/unlock.sh`は`38JP_1_30I`専用であり、`38JP_3_330`では実行しません。

## 重要な注意

この手順はuserdataとmetadataを消去します。必ず事前にバックアップしてください。異なるbuildでroot exploitやkernel moduleを実行すると、kernel panic、起動不能、データ損失の可能性があります。

`metadata,userdata`のeraseと`da seccfg unlock`は、Androidを間に起動させず、同じDA session内で連続して実行します。古いerase結果を使い回すと、更新されたseccfgと再生成されたuserdata/metadataが不整合になり、boot loopの原因になります。

Preloader partitionのflash、raw `dd`によるseccfg書き換え、HACC MMIOのAndroid kernelからの直接呼び出しはこの手順に含まれません。

## 収録内容

- `root/`: `38JP_1_30I`専用の[sh53d-temp-root](https://github.com/mouseos/sh53d-temp-root)をcommit `ead30afee63467082ed721613184e1f0a76990ca`に固定したGit submodule
- `brom-entry/`: retained USBDL flagを設定してBROMへresetするkernel moduleのソースと、4.19/6.6の実機確認済み`.ko`
- `firmware/preloader_a.bin`: `38JP_1_30I`から取得したEMI初期化用Preloader
- `patches/`: BROM起点のCarbonaraを有効にするmtkclient patch
- `scripts/prepare-mtkclient.sh`: 検証済みmtkclient revisionの取得とpatch適用
- `scripts/prepare-root.sh`: submoduleに固定したroot release `v0.2.0`のbinary取得とhash検証
- `scripts/unlock.sh`: 対象build、ファイルhash、DA extension起動、erase成功を確認しながらunlockするrunner
- `docs/BROM_ENTRY.md`: BROM遷移の根拠とregister transaction
- `docs/MTKCLIENT_PATCH.md`: CarbonaraをBROM起点で有効にする変更点と実機結果
- `docs/MANUAL_UNLOCK.md`: runnerと同じ処理を手動で確認する手順
- `docs/ANDROID15_PRINTGPT.md`: `38JP_3_330`でのBROM遷移とread-only GPT取得記録

## 準備

Linux hostにADB、Python 3、Git、curl、USBへのアクセス権が必要です。mtkclientの依存packageは本家の手順で導入してください。

```bash
git clone --recursive https://github.com/mouseos/sh53d-bootloader-unlock.git
cd sh53d-bootloader-unlock
./scripts/prepare-root.sh
./scripts/verify-files.sh
./scripts/prepare-mtkclient.sh
python3 -m pip install -r mtkclient/requirements.txt
```

USB debuggingを有効化し、hostのADB keyを端末側で許可します。バッテリ残量を確保し、不応答時に物理的な強制再起動ができる状態で実行してください。

通常のclone後にsubmoduleが空の場合は、次で固定commitを取得します。

```bash
git submodule update --init --recursive
```

## 実行

最初に一時rootを取得します。root exploitはraceのため失敗することがあり、失敗時に端末が再起動する場合があります。

```bash
cd root
./run.sh
cd ..
```

rootとSELinux permissiveを確認したらrunnerを起動します。

```bash
./scripts/unlock.sh ./mtkclient
```

runnerは次の順序を強制します。

1. build fingerprintと収録ファイルのhashを確認
2. BROM moduleのdry-run
3. Carbonara + DA extensionでread-only `printgpt`
4. `seccfg`の事前backup
5. 明示確認後に`metadata,userdata`をerase
6. Androidを起動させず、直ちに`da seccfg unlock`
7. DA reset

reset後はUSB cableを一度抜き、電源ボタンを長押しして起動します。unlock warningと初期セットアップ画面が表示されることを確認します。

## 復帰

BROM handshake開始後やDA起動後に通信が止まると、ソフトウェアだけでAndroidへ戻れない場合があります。host processを停止し、USB cableを抜いて電源ボタンによる強制再起動を行います。

erase成功後にseccfg unlockが失敗した場合は、端末をDA状態に保ち、ログを確認して`da seccfg unlock`を再試行します。原因が不明なまま別partitionを書き込まないでください。

## Upstream

BROM起点Carbonaraの修正は[mtkclient PR #356](https://github.com/bkerler/mtkclient/pull/356)として提出済みです。

## License

特記のない文書とscriptはApache License 2.0、`brom-entry/`はGPL-2.0-only、mtkclient patchはGPL-3.0-onlyです。`root/`のlicenseはsubmodule内の`LICENSE`に従います。`firmware/preloader_a.bin`はSharpのファームウェアから取得したbinaryで、これらのopen-source licenseの対象ではありません。
