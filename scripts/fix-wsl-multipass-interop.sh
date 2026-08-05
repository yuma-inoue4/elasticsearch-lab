#!/usr/bin/env bash
# WSL2 から multipass.exe 等の Windows 実行ファイルが動かないときに、
# WSL↔Windows 連携（binfmt / WSLInterop）を修復するスクリプト。
# Mac では不要。問題が起きた Windows + WSL2（systemd=true）でのみ使う。
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "sudo で実行してください: sudo bash $0"
  exit 1
fi

# .exe を見つけたら /init 経由で Windows 側に渡して実行する、というルールを登録
# WSL2(Ubuntu)では実行できないため
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
