#!/usr/bin/env bash
# 対象: es-controller 上の Ansible
# すること: Playbook を controller の中で実行する（ホストの ap は使わない）
# 使い方:
#   bash scripts/controller-ansible-run.sh
#   bash scripts/controller-ansible-run.sh playbook/elastic_stack.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUPPORT_DIR="${SCRIPT_DIR}/support"
# shellcheck source=support/common.sh
. "${SUPPORT_DIR}/common.sh"

playbook="${1:-playbook/site.yaml}"
if [[ $# -gt 0 ]]; then
  shift
fi

if ! vm_exists es-controller; then
  echo "es-controller がありません。先に bash scripts/vms-create.sh を実行してください。" >&2
  exit 1
fi

bash "${SUPPORT_DIR}/ansible-inventory-generate.sh"
push_ssh_key_to_controller
sync_ansible_to_controller
install_ansible_on_controller

echo "ansible-playbook ${playbook}  (on es-controller)"
run_playbook_on_controller "${playbook}" "$@"
