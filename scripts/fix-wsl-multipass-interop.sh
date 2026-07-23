#!/usr/bin/env bash
# WSL2 + systemd=true 環境で Windows .exe（multipass 等）を動かすための interop 修正
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "sudo で実行してください: sudo bash $0"
  exit 1
fi

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
