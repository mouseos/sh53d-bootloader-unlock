# mtkclient Carbonara patch

## 対象

- Upstream: `https://github.com/bkerler/mtkclient.git`
- Base commit: `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`
- Upstream PR: [#356](https://github.com/bkerler/mtkclient/pull/356)

## 元の挙動

protectedなBROM modeで`--stock`を指定しない場合、`DaHandler.configure_da()`はpayload typeがCarbonaraであっても先に`bypass_security()`を実行していました。さらにXFlashのDA2 uploadでCarbonaraを呼ぶ条件は、DA1が返すconnection agentが`preloader`の場合に限定されていました。

SH-53Dでは署名済みDA1をBROMから起動できますが、そのDA1はconnection agentとして`brom`を返します。そのため従来条件ではCarbonaraに入らず、stock DA2が起動されます。stock DA2はDA extensionのcustom register accessを提供しないため、V4 seccfgのHACC処理は`Unsupported ctrl code`で失敗します。

## 変更箇所

`mtkclient/Library/DA/mtk_da_handler.py`:

- explicit `--ptype carbonara`ではBROM exploitを呼ばない。
- BootROMが検証できる署名済みDA1のuploadへ進む。

`mtkclient/Library/DA/xflash/xflash_lib.py`:

- 従来の`connagent == b"preloader"`を維持する。
- explicit Carbonaraの場合に限り`connagent == b"brom"`も許可する。
- DA1内のDA2 digestをpatch後DA2のdigestへ置き換え、patch後DA2を起動する。

`--stock`とCarbonara以外のpayload typeの分岐は変更しません。

## 実機検証

Sharp AQUOS wish3 SH-53D、software `38JP_3_330`、MT6833/XFlash V5で次を確認しました。

1. BROMが署名済みDA1を受理
2. DA syncとEMI初期化に成功
3. DA1内offset `0x3b548`のDA2 SHA-256位置を検出
4. patch済みDA2を受理・起動
5. DA extensionを`0x4fff0000`で起動
6. `printgpt`成功
7. V4 seccfgのHACC AES128-CBC処理とunlock record書込みに成功
8. data wipe後のunlocked起動を確認
