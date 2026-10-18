#!/usr/bin/env bash
# 対象: Windows 側の Multipass デーモン（multipassd）
# すること: 無応答になったデーモンを再起動する（UAC 承認が必要）
# 使い方: bash scripts/support/multipass-daemon-fix.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PS1="${SCRIPT_DIR}/multipass-daemon-fix.ps1"
WIN_PS1="$(wslpath -w "$PS1")"
LOG='/mnt/c/Users/Public/multipass-fix-result.txt'

echo "UAC が出たら「はい」を選んでください。"
powershell.exe -NoProfile -Command \
  "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${WIN_PS1}'"

echo "=== 結果 ==="
if [[ -f "$LOG" ]]; then
  cat "$LOG"
else
  echo "ログがありません。UAC をキャンセルした可能性があります: $LOG"
  exit 1
fi
