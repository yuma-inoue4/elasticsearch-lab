#!/usr/bin/env bash
# 対象: 他のホスト用スクリプト
# すること: Multipass コマンド解決・VM 定義・controller へのファイル転送などの共通処理
# 単体では実行しない（scripts/ の入口から source される）

set -euo pipefail

SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SUPPORT_DIR}/../.." && pwd)"

MP_IMAGE="${MP_IMAGE:-24.04}"
MP_LAUNCH_TIMEOUT="${MP_LAUNCH_TIMEOUT:-600}"
MP_LAUNCH_PAUSE_SEC="${MP_LAUNCH_PAUSE_SEC:-10}"
MP_WAIT_IP_RETRIES="${MP_WAIT_IP_RETRIES:-36}"
MP_WAIT_IP_DELAY="${MP_WAIT_IP_DELAY:-10}"

SSH_DIR="${LAB_ROOT}/state/ssh"
SSH_KEY="${SSH_DIR}/id_ed25519"
SSH_PUBKEY="${SSH_KEY}.pub"
CLOUD_INIT_RENDERED="${LAB_ROOT}/state/cloud-init/user-data.yaml"
CONTROLLER_LAB_DIR="/home/ubuntu/elasticsearch-lab"

# 改訂案の 4 台。名前は Multipass インスタンス名 = Ansible inventory ホスト名
VM_NAMES="es-controller es-stack es-target-01 es-target-02"
LEGACY_VM_NAMES="vm-target-01 vm-target-02 vm-es-stack"

if command -v multipass.exe >/dev/null 2>&1; then
  MP_BIN="multipass.exe"
elif command -v multipass >/dev/null 2>&1; then
  MP_BIN="multipass"
else
  echo "multipass が見つかりません。Mac は brew、Windows はホストに Multipass を入れてください。" >&2
  exit 1
fi

mp() {
  command "${MP_BIN}" "$@"
}

is_mp_exe() {
  [[ "${MP_BIN}" == *.exe ]]
}

# Multipass に渡すパス。WSL 上の Linux パスは Windows パスへ変換する。
to_mp_path() {
  local p="$1"
  if is_mp_exe && command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$p"
  else
    printf '%s\n' "$p"
  fi
}

# multipass.exe transfer / --cloud-init は WSL UNC より Public 配下が安定しやすい
staging_dir() {
  if is_mp_exe && [[ -d /mnt/c/Users/Public ]]; then
    mkdir -p /mnt/c/Users/Public/elasticsearch-lab-staging
    printf '%s\n' /mnt/c/Users/Public/elasticsearch-lab-staging
  else
    mkdir -p "${LAB_ROOT}/state/staging"
    printf '%s\n' "${LAB_ROOT}/state/staging"
  fi
}

vm_memory() {
  case "$1" in
    es-controller) echo 2G ;;
    es-stack) echo 4G ;;
    *) echo 1G ;;
  esac
}

vm_cpus() {
  case "$1" in
    es-controller | es-stack) echo 2 ;;
    *) echo 1 ;;
  esac
}

vm_disk() {
  case "$1" in
    es-controller | es-stack) echo 10G ;;
    *) echo 5G ;;
  esac
}

vm_group() {
  case "$1" in
    es-controller) echo controller ;;
    es-stack) echo es_stack ;;
    *) echo targets ;;
  esac
}

mp_list_json() {
  mp list --format json
}

vm_field() {
  local name="$1"
  local field="$2"
  mp_list_json | python3 -c '
import json, sys
name, field = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
for vm in data.get("list") or []:
    if vm.get("name") == name:
        val = vm.get(field)
        if field == "ipv4":
            ips = val or []
            print(ips[0] if ips else "")
        elif val is None:
            print("")
        else:
            print(val)
        break
' "${name}" "${field}"
}

vm_exists() {
  local name="$1"
  local found
  found="$(vm_field "${name}" "name")"
  [[ "${found}" == "${name}" ]]
}

ensure_ssh_key() {
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  if [[ ! -f "${SSH_KEY}" ]]; then
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "elasticsearch-lab"
  fi
  chmod 600 "${SSH_KEY}"
  chmod 644 "${SSH_PUBKEY}"
}

render_cloud_init() {
  ensure_ssh_key
  mkdir -p "$(dirname "${CLOUD_INIT_RENDERED}")"
  python3 -c '
from pathlib import Path
import sys
tpl, key, dest = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
dest.write_text(tpl.read_text().replace("__SSH_PUBLIC_KEY__", key.read_text().strip()) + "\n")
' "${LAB_ROOT}/cloud-init/user-data.yaml.tpl" "${SSH_PUBKEY}" "${CLOUD_INIT_RENDERED}"
}

cloud_init_mp_path() {
  render_cloud_init
  local stage
  stage="$(staging_dir)"
  cp "${CLOUD_INIT_RENDERED}" "${stage}/user-data.yaml"
  to_mp_path "${stage}/user-data.yaml"
}

wait_ipv4() {
  local name="$1"
  local i ip
  for i in $(seq 1 "${MP_WAIT_IP_RETRIES}"); do
    ip="$(vm_field "${name}" "ipv4")"
    if [[ -n "${ip}" ]]; then
      printf '%s\n' "${ip}"
      return 0
    fi
    echo "  ${name}: IPv4 待ち (${i}/${MP_WAIT_IP_RETRIES})"
    sleep "${MP_WAIT_IP_DELAY}"
  done
  echo "${name} の IPv4 が取得できません。bash scripts/support/multipass-daemon-fix.sh を試してください。" >&2
  return 1
}

warn_legacy_vms() {
  local name found=0
  for name in ${LEGACY_VM_NAMES}; do
    if vm_exists "${name}"; then
      echo "警告: 旧構成の VM が残っています: ${name}"
      found=1
    fi
  done
  if [[ "${found}" -eq 1 ]]; then
    echo "メモリ不足のときは: bash ${LAB_ROOT}/scripts/vms-delete.sh --legacy"
  fi
}

install_ansible_on_controller() {
  echo "es-controller に ansible-core を入れる"
  mp exec es-controller -- sudo bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! command -v ansible-playbook >/dev/null 2>&1; then
  apt-get install -y ansible-core
fi
ansible-playbook --version | head -n 1
'
}

push_ssh_key_to_controller() {
  local stage
  stage="$(staging_dir)"
  cp "${SSH_KEY}" "${stage}/id_ed25519"
  mp transfer "$(to_mp_path "${stage}/id_ed25519")" es-controller:/tmp/id_ed25519
  mp exec es-controller -- bash -lc '
set -euo pipefail
mkdir -p ~/.ssh
chmod 700 ~/.ssh
mv /tmp/id_ed25519 ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
'
}

sync_ansible_to_controller() {
  local stage tarfile
  stage="$(staging_dir)"
  tarfile="${stage}/ansible.tar.gz"
  tar -czf "${tarfile}" -C "${LAB_ROOT}" ansible
  mp transfer "$(to_mp_path "${tarfile}")" es-controller:/tmp/ansible.tar.gz
  mp exec es-controller -- bash -lc "
set -euo pipefail
mkdir -p ${CONTROLLER_LAB_DIR}
tar -xzf /tmp/ansible.tar.gz -C ${CONTROLLER_LAB_DIR}
rm -f /tmp/ansible.tar.gz
"
}

run_playbook_on_controller() {
  local playbook="${1:-playbook/site.yaml}"
  shift || true
  mp exec es-controller -- bash -lc "cd ${CONTROLLER_LAB_DIR}/ansible && ansible-playbook ${playbook} $*"
}
