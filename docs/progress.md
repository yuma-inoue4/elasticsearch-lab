# 進捗メモ

elasticsearch-lab の学習・構築の区切りを記録する。

## 完了（v0.2.0 時点）

- [x] 仕様書・設計ドキュメントの作成
- [x] Windows 版 Multipass を WSL2 から操作できるようにした
- [x] Multipass で VM を手動起動・操作
- [x] `multipass list --format json` で IP 取得できることを確認
- [x] チートシート作成（`cheatsheet/multipass.md`）

## Ansible 検証（進行中）

メイン playbook: `ansible/playbook/create-vms.yaml`  
変数: `ansible/inventory/group_vars/all.yaml`  
鍵・SSH 詳細メモ: `ansible/playbook/memo.md`（下部「SSH / 鍵まわり」）

```bash
cd ~/repo/elasticsearch-lab/ansible
ansible-playbook playbook/create-vms.yaml
```

| Step | 内容 | 状態 |
|------|------|------|
| 3〜5 | list / 変数化 / launch（冪等） | 完了 |
| 6 | `add_host` で `target` グループに登録 + IP debug | 完了 |
| 7 | Play 3: `hosts: target` + SSH `ping` | **次回ここから** |

### ここまで完了したこと（〜2026-07-24）

- Play 1: VM 作成（未作成のみ launch、`sleep 5` 付き）
- Play 2: `add_host`（`vm_group: target`）で IP を実行時 inventory に登録
- IP 確認 debug 成功（例: `172.19.28.56`, `172.19.17.153`）
- WSL から VM IP へは届かないことを確認（`ping` 100% loss）
- `mp shell` は通る／Windows PowerShell から SSH 成功
- 自前 ed25519 鍵を作成し、VM の `authorized_keys` に公開鍵を配布済み
- `group_vars` に Windows `ssh.exe` + 秘密鍵パスを設定済み

### 次回はここから（Step 7 / Play 3）

`create-vms.yaml` 末尾の Play 3 が途中（タスク未完成）。続き:

```yaml
- name: Multipass VM への SSH 疎通確認
  hosts: "{{ vm_group }}"   # target
  gather_facts: false
  # connection: ssh は省略可（デフォルト）
  # ※ connection: local は付けない

  tasks:
    - name: SSH 接続を待つ
      ansible.builtin.wait_for_connection:
        timeout: 120

    - name: ping で疎通確認
      ansible.builtin.ping:

    - name: 接続先を表示
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} → {{ ansible_host }}"
```

成功条件: 各 VM で `pong`、`vm-target-01 → 172.x.x.x` のような表示。

`group_vars`（設定済み・確認用）:

```yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: /mnt/c/Users/y.inoue/.ssh/elastic_ed25519
ansible_ssh_executable: /mnt/c/Windows/System32/OpenSSH/ssh.exe
ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

補足:

- `add_host` の `group:` はできれば `groups:` に直す（動作していれば後回し可）
- VM 再作成したら公開鍵の再配布が必要（`mp exec` + `authorized_keys`）

### ゴール（この段階）

- Ansible から VM 2 台へ SSH でき、`ping` が `pong` を返す

### その先（メモ）

- Filebeat / ログ送信
- Docker Compose で Elasticsearch
- 削除用 playbook（任意）
