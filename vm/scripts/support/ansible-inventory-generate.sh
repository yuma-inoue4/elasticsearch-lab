#!/usr/bin/env bash
# 対象: ansible/inventory/hosts.yaml
# すること: Multipass の VM IP から Ansible inventory を生成する
# 通常は vms-create.sh / controller-ansible-run.sh から呼ばれる（単体では実行しない）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

dest="${LAB_ROOT}/ansible/inventory/hosts.yaml"
mkdir -p "$(dirname "${dest}")"

mp_list_json | python3 -c '
import json, sys
from pathlib import Path

dest = Path(sys.argv[1])
wanted = sys.argv[2].split()
data = json.load(sys.stdin)
found = {vm.get("name"): vm for vm in (data.get("list") or [])}

missing = []
ips = {}
for name in wanted:
    vm = found.get(name) or {}
    addr = (vm.get("ipv4") or [None])[0]
    if not addr:
        missing.append("%s (state=%s)" % (name, vm.get("state") or "absent"))
    else:
        ips[name] = addr

if missing:
    sys.stderr.write("IPv4 未取得: " + ", ".join(missing) + "\n")
    sys.exit(1)

text = """# ansible-inventory-generate.sh が自動生成する。手編集しない。
---
all:
  vars:
    ansible_user: ubuntu
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/id_ed25519
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  children:
    controller:
      hosts:
        es-controller:
          ansible_connection: local
          ansible_host: %(controller)s
    es_stack:
      hosts:
        es-stack:
          ansible_host: %(stack)s
    targets:
      hosts:
        es-target-01:
          ansible_host: %(t1)s
        es-target-02:
          ansible_host: %(t2)s
""" % {
    "controller": ips["es-controller"],
    "stack": ips["es-stack"],
    "t1": ips["es-target-01"],
    "t2": ips["es-target-02"],
}

dest.write_text(text)
print("wrote %s" % dest)
' "${dest}" "${VM_NAMES}"
