# Ansible 構築スタディ

elasticsearch-lab 向け。Ansible インストール後、小さく動くものから段階的に `ansible/` を組み立てる手順。

仕様書: `docs/elasticsearch-lab-spec.md` §7  
概念メモ: `cheatsheet/ansible.md`

---

## 方針

- いきなり `playbook/site.yaml` を全部書かない
- **1 ステップずつ `ansible-playbook` を実行して成功を確認**する
- VM の IP は手書き inventory に書かない（`add_host` で動的登録）
- 最初は VM **1 台**、SSH / ping は後半に回す
- playbook ファイルは **`ansible/playbook/` 配下**に格納する（ディレクトリ単位で管理）

### playbook の実行コマンド

`ansible.cfg` は inventory の場所だけ指定し、playbook のパスは指定しない。  
`cd ansible` したうえで、**playbook へのパスを毎回指定**する。

```bash
ansible-playbook playbook/site.yaml
```

---

## Step 0: インストール確認

```bash
sudo apt update
sudo apt install ansible
ansible --version
```

localhost への ad hoc 実行:

```bash
ansible localhost -m ping -c local
```

`pong` が返れば Ansible 本体は OK。

---

## Step 1: `ansible.cfg`

**最初に作るファイル。** playbook 実行時の共通設定を置く。

```text
ansible/
└── ansible.cfg
```

最低限の内容:

```ini
[defaults]
inventory = ./inventory
host_key_checking = False
retry_files_enabled = False
```


| 設定                          | 意味                                   |
| --------------------------- | ------------------------------------ |
| `inventory`                 | inventory ファイルの場所                    |
| `host_key_checking = False` | SSH 初回接続時のホスト鍵確認を省略（Multipass VM 向け） |


この時点では playbook はまだ不要。

---

## Step 2: `inventory/localhost.yaml`

**最初の Play は localhost で動かす**（Multipass コマンドを WSL2 から叩くため）。

```text
ansible/
├── ansible.cfg
└── inventory/
    └── localhost.yaml
```

### inventory とは

**Ansible が「誰に対して作業するか」を把握するためのホスト一覧。**

playbook の `hosts: localhost` と対になる。Ansible は実行前に inventory を読み、`localhost` という名前のホストが存在するか確認する。

| ファイル | 役割 |
|----------|------|
| `ansible.cfg` | 全 playbook 共通の実行設定（inventory の**場所**を指定） |
| `inventory/localhost.yaml` | ホスト一覧の**中身**（誰が操作対象か） |

`ansible.cfg` の `inventory = ./inventory` により、`inventory/` フォルダ内の YAML が読み込まれる。

### なぜ localhost だけか

本 lab の流れは 2 段階になる。

```text
Play 1（localhost）  … WSL2 上で multipass launch / list を実行
Play 2（source_vms） … Multipass VM に SSH して Filebeat などを設定
```

最初の Play では **まだ VM の IP が確定していない**（または毎回変わる）。  
だから静的 inventory には `localhost` だけ書き、VM は後から `add_host` で動的に登録する（Step 6）。

### ファイル例

```yaml
---
all:
  hosts:
    localhost:
      ansible_connection: local
```

### 各行の意味

| 行 | 意味 |
|----|------|
| `---` | YAML ファイルの開始（おまじない） |
| `all:` | グループ名 `all`（全ホストの親グループ） |
| `hosts:` | このグループに属するホスト一覧 |
| `localhost:` | ホスト名。playbook の `hosts: localhost` と一致させる |
| `ansible_connection: local` | SSH せず、**このマシン上で直接**コマンドを実行する |

`ansible_connection: local` が重要。これがないと Ansible は `localhost` に SSH しようとして失敗することがある。WSL2 上で `multipass.exe` を叩く Play 1 では **local 接続**が正しい。

### 書かないもの

- **VM の IP**（`172.x.x.x`）… IP は変わるため `multipass list --format json` + `add_host` で都度登録
- **Multipass VM 名**（`vm-source-01` など）… Step 6 まで inventory に書かない

### 確認

```bash
cd ~/repo/elasticsearch-lab/ansible
ansible-inventory --list
```

`localhost` が表示されれば OK。

```bash
ansible localhost -m ping -c local
```

`pong` が返れば inventory の設定は問題ない。

### よくあるミス

| ミス | 結果 |
|------|------|
| ファイル名の typo（`localshot.yaml` など） | 動くこともあるが、意図とずれる。`localhost.yaml` 推奨 |
| `ansble_connection`（スペルミス） | 設定が効かず SSH 接続を試みて失敗 |
| VM の IP を直書き | IP 変更のたびに手修正が必要になる |

---

## Step 3: 最小 `playbook/site.yaml`（multipass list だけ）

**Ansible → Multipass の線路を通す。** VM 作成はまだしない。

```text
ansible/
├── ansible.cfg
├── playbook/
│   └── site.yaml      ← 追加
└── inventory/
    └── localhost.yaml
```

例:

```yaml
---
- name: Multipass 疎通確認
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: multipass list を実行
      ansible.builtin.command: multipass.exe list
      register: mp_list_result
      changed_when: false

    - name: 結果を表示
      ansible.builtin.debug:
        var: mp_list_result.stdout
```

実行:

```bash
ansible-playbook playbook/site.yaml
```

### 成功条件

- エラーなく終了する
- `multipass list` 相当の出力が表示される

### 注意

- WSL2 の bash エイリアス（`mp`）は **Ansible からは使えない**
- `multipass.exe` を直接書く（後で変数化する）

---

## Step 4: `group_vars/all.yaml`

**ハードコードが増える前に変数を外に出す。**

```text
ansible/
├── ansible.cfg
├── playbook/
│   └── site.yaml
└── inventory/
    ├── localhost.yaml
    └── group_vars/
        └── all.yaml       ← 追加（inventory 配下）
```

> **注意:** playbook が `playbook/` サブディレクトリにある場合、`ansible/group_vars/` では playbook 実行時に読まれない。`inventory/group_vars/` または `playbook/group_vars/` を使う（詳細は `cheatsheet/ansible.md`）。

例:

```yaml
---
multipass_cmd: multipass.exe

multipass_vms:
  - name: vm-source-01
    memory: 1G
    cpus: 1
```

`playbook/site.yaml` の `multipass.exe list` を `{{ multipass_cmd }} list` に書き換える。

実行して Step 3 と同様に成功することを確認。

---

## Step 5: `multipass launch`（VM 1 台）

**VM 作成の自動化。** まだ 1 台だけ。

`playbook/site.yaml` に task を追加:

1. `{{ multipass_cmd }} list --format json` で現状取得
2. 対象 VM が一覧に **なければ** `launch`

### 成功条件

```bash
multipass.exe list
```

対象 VM が **Running** になる。

### ヒント

- JSON は `register` で受け取り `from_json` フィルタでパース
- 既存 VM 名と `multipass_vms` を比較して `when:` で launch を制御

---

## Step 6: `add_host` + 2 つ目の Play

**仕様書 §7 の核心。** 取得した IP を Ansible の作業対象に登録する。

### Play 1（localhost）に追加

- launch / start 後、再度 `list --format json`
- `add_host` で `source_vms` グループに登録

```yaml
- name: VM を Ansible の実行対象に追加
  ansible.builtin.add_host:
    name: "{{ item.name }}"
    ansible_host: "{{ item.ipv4[0] }}"
    groups: source_vms
```

### Play 2（source_vms）— まだ ping しない

```yaml
- name: 登録確認
  hosts: source_vms
  gather_facts: false

  tasks:
    - name: ホスト名と IP を表示
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} → {{ ansible_host }}"
```

### 成功条件

- `vm-source-01 → 172.x.x.x` のような debug が出る

### add_host の役割（再確認）


| やること         | 担当                                 |
| ------------ | ---------------------------------- |
| VM 作成        | `multipass launch` タスク             |
| IP 取得        | `multipass list --format json` タスク |
| inventory 登録 | `**add_host` だけ**                  |


---

## Step 7: SSH + `ping` モジュール

Play 6 が動いてから。Multipass VM への SSH 設定を足す。

`group_vars/all.yaml` に追加:

```yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: /mnt/c/ProgramData/Multipass/data/ssh-keys/id_rsa
ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

Play 2 に task を追加:

```yaml
- name: SSH 接続を待つ
  ansible.builtin.wait_for_connection:
    timeout: 120

- name: ping モジュールで疎通確認
  ansible.builtin.ping:
```

### 成功条件

- 各 VM で `pong` が返る

---

## Step 8: VM 2 台・冪等性

最後に拡張する。

### やること

1. `multipass_vms` に 2 台目（`vm-source-02`）を追加
2. 既存 VM は `launch` をスキップ
3. 停止中（`Stopped`）なら `start` する

### 成功条件

- 2 回連続 `ansible-playbook playbook/site.yaml` しても、2 回目は launch されない（冪等）
- 2 台とも `ping` が成功する

---

## 最初に作らなくていいもの


| ファイル                | 作るタイミング        |
| ------------------- | -------------- |
| `roles/`            | Filebeat 導入の段階 |
| VM 用の手書き inventory  | 使わない           |
| 複雑な `playbook/site.yaml` 一発書き | Step 3〜7 を経てから |


---

## 完成イメージ（ディレクトリ）

```text
ansible/
├── ansible.cfg
├── playbook/
│   └── site.yaml
├── inventory/
│   └── localhost.yaml
└── group_vars/
    └── all.yaml
```

---

## ステップ早見表


| Step | 作るもの                      | ゴール                             |
| ---- | ------------------------- | ------------------------------- |
| 0    | —                         | Ansible インストール確認                |
| 1    | `ansible.cfg`             | 実行環境の定義                         |
| 2    | `inventory/localhost.yaml` | localhost のみ inventory に登録      |
| 3    | 最小 `playbook/site.yaml`    | `multipass list` が Ansible から動く |
| 4    | `group_vars/all.yaml`      | 変数の整理                           |
| 5    | launch 1 台                | VM 作成の自動化                       |
| 6    | `add_host`                | 動的 inventory                    |
| 7    | `ping`                    | SSH 接続確認                        |
| 8    | 2 台・冪等性                   | 仕様書どおりの初期構成                     |


---

## 今日の目安

**Step 1〜3 まで**がちょうどよい。

「Ansible が Multipass を叩ける」まで行ければ、Step 4 以降は同じパターンの積み上げ。

---

## トラブルシュート


| 症状                             | 確認すること                               |
| ------------------------------ | ------------------------------------ |
| `multipass: command not found` | `multipass.exe` を直接指定しているか           |
| `mp` が使えない                     | エイリアスは Ansible 非対話シェルでは効かない          |
| JSON パースエラー                    | `register` した stdout が空でないか          |
| `add_host` 後に Play 2 がスキップ     | `hosts: source_vms` のスペル、IPv4 が空でないか |
| SSH ping 失敗                    | 鍵パス、VM が Running か、IP が最新か           |


