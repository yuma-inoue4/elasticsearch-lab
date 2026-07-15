# 進捗メモ

elasticsearch-lab の学習・構築の区切りを記録する。

## 完了（v0.2.0 時点）

- [x] 仕様書・設計ドキュメントの作成
- [x] Windows 版 Multipass を WSL2 から操作できるようにした
- [x] Multipass で VM を手動起動・操作（`launch` / `list` / `info` / `shell` / `exec` / `stop` / `start`）
- [x] `multipass list --format json` で IP 取得できることを確認
- [x] チートシート作成（`cheatsheet/multipass.md`）

## Ansible 検証（進行中）

仕様書（`docs/elasticsearch-lab-spec.md` §7）の流れに沿って、手動操作を Ansible に置き換える。

メイン playbook: `ansible/playbook/create-vms.yaml`（旧 `site.yaml`）

実行（必ず `ansible/` で）:

```bash
cd ~/repo/elasticsearch-lab/ansible
ansible-playbook playbook/create-vms.yaml
```

1. [x] Ansible を WSL2 にインストール
2. [x] Step 3: Multipass 疎通（`list --format json`）
3. [x] Step 4: `inventory/group_vars/all.yaml` で変数化（`mp_cmd` / `mp_vms`）
4. [x] Step 5: `loop` + `when` で `launch`（2回目は `skipped`）
5. [ ] Step 6: `add_host` + 2 つ目の Play（debug で名前→IP）
6. [ ] Step 7: SSH + `ping`（`pong`）

### ここまで完了したこと（〜2026-07-15）

- `ansible.cfg` / `inventory/localhost.yaml` / `inventory/group_vars/all.yaml`
- 既存名抽出 → 未作成なら `launch` → `refresh` で再 list
- `.list` を `mp_existing_ips_and_names` に保存（name / ipv4 付きの辞書リスト）
- IP だけのリストでは `add_host` に進めない、と理解した

### 次回はここから（Step 6）

止まっている場所: `create-vms.yaml` の `add_host`（コメントアウト中）と Play 2 未作成。

やること:

1. `add_host` を有効化・修正する
   - `loop` は IP だけリストではなく、**辞書のリスト**（`.list` / `mp_existing_ips_and_names`）
   - `name: "{{ item.name }}"`
   - `ansible_host: "{{ item.ipv4[0] }}"`（`ipv4` は配列）
   - `groups: source_vms`（または決めたグループ名）
   - できれば `mp_vms` に定義した VM だけに絞る
2. **同じファイルに 2 つ目の Play** を追加
   - `hosts: source_vms`
   - `gather_facts: false`
   - `debug` で `inventory_hostname → ansible_host`
3. まだ SSH / `ping` はやらない（Step 7）

成功条件: `vm-worker-1 → 172.x.x.x` のような表示が出る。

参考: `cheatsheet/ansible-study.md` Step 6

### ゴール（この段階）

- 手書き inventory なしで VM を Ansible から起動できる
- 取得した IP を `add_host` し、後続 Play の対象にできる
- （その次）SSH で VM に届く

### その先（メモ）

- Step 7: SSH + `ping`
- 削除用 playbook（任意）
- Docker Compose で Elasticsearch
- Filebeat 導入・ログ送信
