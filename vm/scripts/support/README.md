# scripts/support

**普段はここを直接実行しない。** 入口は一つ上の `vms-create.sh` / `vms-delete.sh` / `controller-ansible-run.sh`。

このディレクトリは、入口から呼ばれる内部処理と、壊れたときだけ使う修復です。

| ファイル | 対象 | すること | いつ使う |
|---|---|---|---|
| `common.sh` | 他スクリプト | Multipass コマンド解決などの共通処理 | 入口から `source` される。単体実行しない |
| `ansible-inventory-generate.sh` | `ansible/inventory/hosts.yaml` | VM の IP から名簿を作る | create / run から呼ばれる |
| `multipass-daemon-fix.sh` | Windows の Multipass デーモン | 無応答を直す | `mp list` が返らないとき |
| `multipass-daemon-fix.ps1` | 同上 | 実際の修復処理 | `.sh` から呼ばれる |
| `wsl-exe-launch-fix.sh` | WSL から `.exe` を起動する仕組み | interop を直す | `multipass.exe` 自体が動かないとき（Mac 不要） |

## 障害時だけ

```bash
bash scripts/support/multipass-daemon-fix.sh
sudo bash scripts/support/wsl-exe-launch-fix.sh
```

`wsl-exe-launch-fix.sh` のあとは、Windows の PowerShell で `wsl --shutdown` し、WSL を開き直す。
