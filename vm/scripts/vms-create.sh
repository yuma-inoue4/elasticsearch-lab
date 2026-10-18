#!/usr/bin/env bash
# 対象: Multipass VM 4 台（es-controller / es-stack / es-target-01 / es-target-02）
# すること: VM を起動する。中身（ES など）は入れない。controller に Ansible と SSH 鍵を置く。
# 使い方: bash scripts/vms-create.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUPPORT_DIR="${SCRIPT_DIR}/support"
# shellcheck source=support/common.sh
. "${SUPPORT_DIR}/common.sh"

echo "Multipass: ${MP_BIN} / image: ${MP_IMAGE}"
warn_legacy_vms

cloud_init="$(cloud_init_mp_path)"
echo "cloud-init: ${cloud_init}"

for name in ${VM_NAMES}; do
  state="$(vm_field "${name}" "state")"
  ip="$(vm_field "${name}" "ipv4")"

  if [[ "${state}" == "Running" && -n "${ip}" ]]; then
    echo "${name}: 稼働中 (${ip}) … launch スキップ"
    continue
  fi

  if [[ "${state}" == "Stopped" ]]; then
    echo "${name}: start"
    mp start "${name}"
    wait_ipv4 "${name}" >/dev/null
    sleep "${MP_LAUNCH_PAUSE_SEC}"
    continue
  fi

  if [[ "${state}" == "Deleted" ]]; then
    echo "${name}: Deleted 残り … purge"
    mp purge || mp delete --purge "${name}" || true
    sleep "${MP_LAUNCH_PAUSE_SEC}"
  elif [[ -n "${state}" ]]; then
    echo "${name}: 状態 ${state} … delete --purge して作り直す"
    mp delete --purge "${name}" || true
    sleep "${MP_LAUNCH_PAUSE_SEC}"
  fi

  echo "${name}: launch (mem=$(vm_memory "${name}") cpus=$(vm_cpus "${name}") disk=$(vm_disk "${name}"))"
  mp launch "${MP_IMAGE}" \
    --name "${name}" \
    --memory "$(vm_memory "${name}")" \
    --cpus "$(vm_cpus "${name}")" \
    --disk "$(vm_disk "${name}")" \
    --timeout "${MP_LAUNCH_TIMEOUT}" \
    --cloud-init "${cloud_init}"

  wait_ipv4 "${name}" >/dev/null
  echo "${name}: launch 後 ${MP_LAUNCH_PAUSE_SEC}s 待機"
  sleep "${MP_LAUNCH_PAUSE_SEC}"
done

echo "=== IPv4 ==="
for name in ${VM_NAMES}; do
  printf '%s\t%s\n' "${name}" "$(wait_ipv4 "${name}")"
done

bash "${SUPPORT_DIR}/ansible-inventory-generate.sh"
push_ssh_key_to_controller
sync_ansible_to_controller
install_ansible_on_controller

echo
echo "VM 起動まで完了。作り込みは:"
echo "  bash ${LAB_ROOT}/scripts/controller-ansible-run.sh"
