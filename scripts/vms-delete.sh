#!/usr/bin/env bash
# 対象: Multipass VM（lab 用）
# すること: VM を削除する
# 使い方:
#   bash scripts/vms-delete.sh           # 改訂案の 4 台
#   bash scripts/vms-delete.sh --legacy  # 旧 vm-target-* / vm-es-stack も削除
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=support/common.sh
. "${SCRIPT_DIR}/support/common.sh"

names="${VM_NAMES}"
if [[ "${1:-}" == "--legacy" ]]; then
  names="${names} ${LEGACY_VM_NAMES}"
fi

echo "削除対象: ${names}"
for name in ${names}; do
  if vm_exists "${name}"; then
    echo "delete --purge ${name}"
    mp delete --purge "${name}" || true
  else
    echo "${name}: 存在しない"
  fi
done

echo "完了"
