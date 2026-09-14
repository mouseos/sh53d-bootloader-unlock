# Android 15 BROM/printgpt実機記録

## 対象

- Sharp AQUOS wish3 SH-53D
- Software `38JP_3_330`
- Android 15
- Kernel `6.6.89-android15-8-gbe8d201b0d27-ab13762941-4k`
- Bootloader unlock済み端末

この確認ではflashのunlock、erase、partition書込みを行っていません。

## BROM module

`brom-entry/sh53d_brom_entry-38JP_3_330.ko`を使用しました。

```text
vermagic: 6.6.89-android15-8-gbe8d201b0d27-ab13762941-4k SMP preempt mod_unload modversions aarch64
SHA-256: e5c547e58789e8709a3d81806ee59bdca77eb736784a9f7da17ab65c6546bef7
```

dry-run:

```sh
insmod /data/local/tmp/sh53d_brom_entry-38JP_3_330.ko execute=0 timeout_ms=60000
```

確認したlog:

```text
sh53d_brom_entry: planned BOOT_MISC0=0x444c00f1 timeout_ms=60000 execute=0
sh53d_brom_entry: dry run only; no MMIO or storage write performed
```

module loadは終了値0でした。moduleをremoveした後、host側でmtkclientを待機させ、`execute=1 timeout_ms=60000`でBROMへ遷移しました。

## printgpt

```sh
python3 mtk.py printgpt \
    --stock \
    --skipwdt \
    --loader mtkclient/Loader/MTK_DA_V5.bin \
    --preloader firmware/preloader_a.bin
```

`MTK_DA_V5.bin`のSHA-256は`aef234190ccb8145d2e3b8459741e9adb70f2caa8481aa216c1b25152afaca1f`です。supplied Preloaderは38JP_1_30Iから取得した収録済みbinaryで、SHA-256は`98613d63052fa2f499802d7e35be47ca95025cd5a1400b9c546f09daa54c75f8`です。

実測結果:

```text
BROM mode detected
HW code:       0x989
Target config: 0xe1
SBC:           enabled
SLA/DAA:       disabled
DA1 upload:    success
DRAM setup:    success
DA2 upload:    success
UFS init:      success
GPT entries:   74
exit status:   0
```

主要entry:

| Partition | Offset | Length |
| --- | ---: | ---: |
| `lk_a` | `0x25600000` | `0x200000` |
| `lk_b` | `0x43600000` | `0x200000` |
| `super` | `0x94800000` | `0x200000000` |
| `userdata` | `0x294800000` | `0xc4eff8000` |

終了後にDA reset commandを送るとUSB deviceは消失し、60秒以内にADBへは復帰しませんでした。通常起動にはUSB cableを抜き、電源ボタンで起動します。
