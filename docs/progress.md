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

1. [x] Ansible を WSL2 にインストール（`sudo apt install ansible`）
2. [x] 最小の playbook を作成（`ansible/playbook/site.yaml`）— Step 3 疎通確認
3. [x] `inventory/group_vars/all.yaml` で変数化 — Step 4
4. [ ] Step 5 完了: `launch`（`loop` + `when`）まで
5. [ ] `add_host` + `ping` で SSH 接続確認

### ここまで完了したこと（Step 3〜5 途中）

- `ansible.cfg` / `inventory/localhost.yaml` 作成
- `command` + `register` + `debug` で Multipass JSON 取得
- `set_fact` で `mp_existing_names`（既存 VM 名リスト）作成
- 学習メモ: `cheatsheet/ansible.md` の「Step 4〜5 学習メモ」参照

### 次回やること

- Step 5 残り: `mp_vms` を `loop` し、`when: item.name not in mp_existing_names` で `launch`
- Step 6: `add_host` + 2 つ目の Play

### ゴール（この段階）

- 手書き inventory なしで VM 1 台を Ansible から起動できる
- 取得した IP で Ansible が VM に届く

### その先（メモ）

- VM 2 台目（`vm-source-01` / `vm-source-02`）
- Docker Compose で Elasticsearch 起動
- Filebeat 導入・ログ送信
