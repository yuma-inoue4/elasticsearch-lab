#!/usr/bin/env bash
# 対象: WSL2 から Windows の .exe（multipass.exe など）を起動する仕組み
# すること: WSLInterop（binfmt）を直す。Mac では不要。
# 使い方: sudo bash scripts/support/wsl-exe-launch-fix.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "sudo で実行してください: sudo bash $0"
  exit 1
fi

# .exe を見つけたら /init 経由で Windows 側に渡して実行する、というルールを登録
install -d /usr/lib/binfmt.d
echo ':WSLInterop:M::MZ::/init:PF' > /usr/lib/binfmt.d/WSLInterop.conf
chmod 644 /usr/lib/binfmt.d/WSLInterop.conf

systemctl restart systemd-binfmt

echo "=== WSLInterop.conf ==="
cat /usr/lib/binfmt.d/WSLInterop.conf
echo
echo "=== binfmt handlers ==="
ls /proc/sys/fs/binfmt_misc/
echo
echo "完了。Windows PowerShell で wsl --shutdown を実行し、WSL2 を開き直してください。"
