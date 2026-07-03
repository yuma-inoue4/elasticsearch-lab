# Ansible チートシート

elasticsearch-lab 向け。WSL2 への導入から、playbook 実行まで。

---

## 導入手順（WSL2）

### 前提


| 項目       | 内容                        |
| -------- | ------------------------- |
| ホスト OS   | Windows ラップトップ            |
| 実行環境     | WSL2（Ubuntu 22.04 推奨）     |
| インストール方法 | `apt`（Ubuntu 公式リポジトリ）     |
| バージョン指定  | **不要**（lab 用途では apt 版で十分） |


> **注意:** Ansible は Multipass と違い、WSL2 内に直接インストールする。Windows 側へのインストールは不要。

---

### Step 1: パッケージ一覧を更新

```bash
sudo apt update
```

GitLab CE リポジトリなど別件の GPG 警告が出ても、Ubuntu 本体のリポジトリが `Hit` なら **Ansible のインストールには影響しない**。

---

### Step 2: Ansible をインストール

```bash
sudo apt install -y ansible
```

Ubuntu 22.04（jammy）では **2.10.x 系** が入る。本 lab の playbook（`command` / `add_host` / `ping` など）には問題ない。

---



### Step 3: 動作確認

```bash
ansible --version
```

例:

```text
ansible 2.10.8
  ...
```

---



### 導入完了チェックリスト

- [ ] `sudo apt update` が完了した
- [ ] `sudo apt install -y ansible` が完了した
- [ ] `ansible --version` でバージョンが表示される

---



## Ansible とは

**複数サーバの設定・操作をコード（YAML）で自動化するツール。**

シェルスクリプトをサーバ台数分書く代わりに、playbook に「やりたいこと」を書いて一括実行する。


| 従来（手動 / シェル）        | Ansible               |
| ------------------- | --------------------- |
| 各 VM に SSH して同じコマンド | 1 回の playbook 実行で全 VM |
| IP を inventory に直書き | 動的に IP 取得して登録         |
| 手順が人の記憶に依存          | playbook が手順書兼実行脚本    |


---



## 主要な概念



### inventory（インベントリ）

**「操作対象のホスト一覧」**。playbook の `hosts:` と対になる。

- どのホスト名 / IP に接続するかを定義
- `ansible.cfg` が inventory の**場所**、`inventory/*.yaml` が**中身**
- 本 lab では VM の IP は **手書きしない**
- `localhost` のみ静的定義し、VM は `add_host` で実行中に追加

例（`inventory/localhost.yaml`）:

```yaml
---
all:
  hosts:
    localhost:
      ansible_connection: local
```


| 項目                          | 意味                                    |
| --------------------------- | ------------------------------------- |
| `all`                       | 全ホストの親グループ                            |
| `localhost`                 | ホスト名（Play 1 の `hosts: localhost` と一致） |
| `ansible_connection: local` | SSH せず WSL2 上で直接実行（Multipass コマンド用）   |


最初の Play は WSL2 から `multipass.exe` を叩くため **localhost + local 接続**だけでよい。

VM 向けの SSH 設定は `add_host` 後の Play 2 以降で追記する。

### playbook（プレイブック）

**「自動化の設計書」**。YAML で書く。

- 複数の **Play**（処理の塊）からなる
- 1 Play =「どのホストに」「何をするか」

```yaml
- name: Play の説明
  hosts: 対象ホスト
  tasks:
    - name: タスクの説明
      モジュール名:
        パラメータ: 値
```



### task（タスク）

**「1 つの作業単位」**。モジュールを呼び出す。

例: パッケージインストール、ファイル配置、コマンド実行、ホスト登録

### module（モジュール）

**Ansible が提供する機能部品。**


| モジュール                                 | 用途                    |
| ------------------------------------- | --------------------- |
| `ansible.builtin.command`             | シェルコマンド実行             |
| `ansible.builtin.debug`               | 変数・メッセージのデバッグ表示       |
| `ansible.builtin.ping`                | SSH 接続確認              |
| `ansible.builtin.add_host`            | 実行中に inventory へホスト追加 |
| `ansible.builtin.wait_for_connection` | SSH 待ち                |




### role（ロール）

**task を機能単位に分割した再利用パッケージ**（Filebeat 導入など）。

初期 playbook では使わず、後から `roles/` に分割する。

### 変数（vars）

**パラメータの置き場。**

- `group_vars/all.yaml` … 全ホスト共通
- playbook 内の `vars:` … その Play 限定
- `-e` オプション … 実行時に上書き



### ansible.cfg

**すべての playbook 実行時に共通で効く設定ファイル。**

`ansible-playbook playbook/site.yaml` を実行するたびに Ansible が読み込み、inventory の場所や SSH の挙動など **実行環境の前提**を決める。playbook（何をするか）や inventory（誰に対するか）とは役割が異なる。


| ファイル              | 役割                     |
| ----------------- | ---------------------- |
| `site.yaml`       | やること（タスク）              |
| `inventory/`      | 対象ホスト                  |
| `**ansible.cfg`** | **全 playbook 共通の実行設定** |


本 lab では `ansible/ansible.cfg` 格納

```ini
[defaults]
inventory = ./inventory
host_key_checking = False
retry_files_enabled = False
```


| 設定                            | 意味                       |
| ----------------------------- | ------------------------ |
| `inventory`                   | ホスト一覧（inventory）のパス      |
| `host_key_checking = False`   | SSH ホスト鍵確認を省略（検証 lab 向け） |
| `retry_files_enabled = False` | 失敗時の `.retry` ファイルを作らない  |


VM 名・IP・Multipass コマンドなど **中身のパラメータは書かない**（`group_vars` や playbook に書く）。

**毎回同じ実行ルールだけ**を `ansible.cfg` に置くのが基本。

その他のセクション（参考）:


| セクション                    | 用途                                |
| ------------------------ | --------------------------------- |
| `[defaults]`             | ほとんどのコマンドに効く基本設定（本 lab ではここだけで十分） |
| `[inventory]`            | inventory プラグインの有効化など             |
| `[privilege_escalation]` | sudo（`become`）のデフォルト              |
| `[ssh_connection]`       | SSH 接続の細かい挙動                      |


---



## 本 lab での流れ（仕様書 §7）

```text
1. localhost で playbook 開始
2. multipass launch   → VM 作成
3. multipass list --format json  → IP 取得
4. add_host           → Ansible の作業対象に登録
5. source_vms 向け Play → SSH + ping で接続確認
6. （後で）Filebeat 導入 ...
```



### add_host のイメージ

```yaml
- name: VM を作業対象に追加
  ansible.builtin.add_host:
    name: vm-source-01
    ansible_host: "172.23.200.180"   # multipass から取得した IP
    groups: source_vms
```

- VM 作成や IP 探索は **別タスク**が担当
- `add_host` は「取得済み IP を Ansible に教える」だけ

---



## ディレクトリ構成

本 lab では playbook を `playbook/` **ディレクトリ配下**に格納する。

```text
ansible/
├── ansible.cfg           # 設定（inventory パスなど）
├── playbook/
│   └── site.yaml          # メイン playbook
└── inventory/
    ├── localhost.yaml     # localhost のみ（VM は動的追加）
    └── group_vars/
        └── all.yaml       # mp_cmd, mp_vms, SSH 設定など
```

playbook が増えた場合も `playbook/teardown.yaml` のように同ディレクトリに追加する。

---



## 実行方法

```bash
cd ~/repo/elasticsearch-lab/ansible

# VM 2 台（group_vars/all.yaml の定義どおり）
ansible-playbook playbook/site.yaml

# ドライラン（変更せず task 一覧だけ見る）
ansible-playbook playbook/site.yaml --check
```

---



## よく使うコマンド

```bash
ansible-playbook playbook/site.yaml          # playbook 実行
ansible-playbook playbook/site.yaml -v       # 詳細ログ
ansible-playbook playbook/site.yaml -vvv     # さらに詳細
ansible localhost -m ping          # localhost 疎通（inventory 利用）
ansible-inventory --list           # inventory 内容確認
```

---



## Step 3 学習メモ（最小 playbook）

Step 3 の `playbook/site.yaml` を題材に、タスクの書き方と周辺概念を整理する。

### いまの playbook

```yaml
---
- name: multipass 疎通確認
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: multipass list を実行
      ansible.builtin.command: multipass.exe list
      register: mp_list_result
      changed_when: false

    - name: multipass list の結果を表示
      ansible.builtin.debug:
        var: mp_list_result.stdout
```

```text
タスク1: multipass.exe list を実行 → 結果を mp_list_result に保存
タスク2: mp_list_result.stdout を画面に表示
```



### task の基本形

```yaml
- name: 人間向けの説明        # ログ用ラベル（実行内容には影響しない）
  モジュール名: パラメータ
  オプション: 値
```

---



## `ansible.builtin` とは

**Ansible 本体に最初から同梱されている標準モジュール**を使う、という指定。


| 書き方                       | 意味                       |
| ------------------------- | ------------------------ |
| `command`                 | 短い書き方（古い playbook でよく見る） |
| `ansible.builtin.command` | 正式なフルネーム（推奨）             |


Ansible 2.10 以降はモジュールが **コレクション**単位で整理されている。

```yaml
ansible.builtin.command      # 標準（追加インストール不要）
community.docker.container   # 別途インストールが必要な場合もある
```



### どこに「入っている」か

- **操作対象の VM には入っていない**
- **Ansible を動かしている側（WSL2）に同梱されている**

```text
WSL2（コントロールノード）
  ├── ansible コマンド
  └── ansible.builtin.* モジュール群  ← ここ

localhost / Multipass VM
  └── モジュールは入っていない（指示を受けるだけ）
```

---



## モジュール解説（Step 3 で使うもの）



### `ansible.builtin.command`

**シェルでコマンドを 1 つ実行するモジュール。**

WSL2 上で手打ちするのと同じことを Ansible にやらせる。


| モジュール     | 違い                               |
| --------- | -------------------------------- |
| `command` | コマンドをそのまま実行。パイプ `|` やリダイレクトは使えない |
| `shell`   | `/bin/sh` 経由。パイプや `&&` なども使える    |


`multipass.exe list` だけなら `command` で十分。

### `ansible.builtin.debug`

**デバッグ用に変数の中身を表示するモジュール。** 本番の設定変更ではなく確認用。


| パラメータ                        | 意味         |
| ---------------------------- | ---------- |
| `var: mp_list_result.stdout` | 変数の中身を表示   |
| `msg: "hello"`               | 固定メッセージを表示 |


`register` で保存した値を次のタスクで使う、という基本パターンの練習になる。

---



## タスクオプション



### `register: 変数名`

**タスクの実行結果を、後のタスクで使える変数に保存する。**

`register: mp_list_result` のあと、だいたい次の情報が入る。

```yaml
mp_list_result:
  stdout: "No instances found.\n"   # 標準出力
  stderr: ""                        # エラー出力
  rc: 0                             # 終了コード（0 = 成功）
  cmd: ["multipass.exe", "list"]    # 実行したコマンド
  changed: true/false               # Ansible が「変更があった」と判断したか
```

`register` がないとコマンドは動いても、**結果を次のタスクに渡せない**。  
Step 5 以降では `stdout` を JSON としてパースして VM の有無を判定する。

### `changed_when: false`

Ansible は各タスクについて **「サーバの状態を変えたか（changed）」** を記録する。


| 状態        | 意味          |
| --------- | ----------- |
| `ok`      | 成功したが変更なし   |
| `changed` | 成功し、何かを変更した |
| `failed`  | 失敗          |


`command` モジュールは成功すると基本的に `changed` になりやすい。  
でも `multipass list` は**一覧を見るだけ**で、VM も設定も変えない。

そこで `changed_when: false` を付けて「成功しても変更は起きていない」と Ansible に伝える。

```text
localhost : ok=2  changed=0  ...   ← 意図どおり
```

`changed_when` がないと毎回 `changed=1` になり、ログが紛らわしくなる。

### 関連オプション（参考）


| オプション              | 意味                      |
| ------------------ | ----------------------- |
| `when: 条件`         | 条件が真のときだけタスクを実行         |
| `failed_when: 条件`  | 条件が真のとき失敗扱いにする          |
| `changed_when: 条件` | いつ `changed` とみなすか自分で定義 |


---



## `multipass.exe` とは

**Windows にインストールされた Multipass の実行ファイル。** Ansible 専用の記法ではない。

### なぜ `.exe` が必要か

本 lab の構成:

```text
Windows ホスト
  └── Multipass（Windows 版）
        C:\Program Files\Multipass\bin\multipass.exe
        └── Hyper-V で VM を動かす

WSL2（Ubuntu）
  └── Ansible を実行する場所
```

Multipass は **WSL2 内ではなく Windows 側**にインストールされている。  
WSL2 からは Windows の `.exe` をそのまま呼べる。

```bash
multipass.exe list
# 実体: /mnt/c/Program Files/Multipass/bin/multipass.exe
```



### Ansible で `multipass.exe` と書く理由

手動の bash ではエイリアスを使えるが、**Ansible は対話シェルではない**ため `~/.bashrc` のエイリアスは効かない。


| 書き方                  | 結果                             |
| -------------------- | ------------------------------ |
| `multipass.exe list` | Windows 版 Multipass を呼ぶ（正しい）   |
| `multipass list`     | WSL2 内の Linux コマンドを探す → 見つからない |
| `mp list`            | エイリアス → Ansible では効かない         |


Step 4 では `group_vars/all.yaml` に `multipass_cmd: multipass.exe` と変数化し、playbook では `{{ multipass_cmd }} list` と書く。

---



## `ansible-doc` の使い方

**Ansible モジュールの説明書をターミナルで読むコマンド。** playbook に書く前の調べ物に使う。

### モジュールの説明を読む

```bash
ansible-doc command                  # 短い名前
ansible-doc ansible.builtin.command  # フルネーム（どちらでも可）
ansible-doc debug
ansible-doc ping
```

表示内容: モジュールの説明 / 使えるパラメータ（OPTIONS）/ 書き方の例（EXAMPLES）。  
長い場合は `q` で終了。

### 一覧を見る（`-l`）

```bash
ansible-doc -l
```

モジュールは数千個あるので `grep` と組み合わせる。

```bash
ansible-doc -l | grep ping
ansible-doc -l | grep add_host
ansible-doc -l | grep command
```



### playbook のひな形だけ見る（`-s`）

```bash
ansible-doc -s debug
ansible-doc -s add_host
```

「とりあえずどう書くか」がすぐ分かる。実務では `-s` がよく使われる。

### 調べ方の流れ

```text
1. ansible-doc -l | grep キーワード   … モジュールを探す
2. ansible-doc -s モジュール名         … 書き方のひな形を見る
3. ansible-doc モジュール名            … 詳しい説明・全オプションを読む
```

Step 3 で試すなら:

```bash
ansible-doc -s command
ansible-doc -s debug
```

---

## Step 4〜5 学習メモ（変数・データ型・JSON 変換）

Step 4（`group_vars`）と Step 5（JSON 取得 → 既存 VM 名リスト作成）までの整理。

### 進捗（ここまで）

- [x] Step 3: `command` + `register` + `debug` で Multipass 疎通
- [x] Step 4: `inventory/group_vars/all.yaml` に変数を外出し
- [x] Step 5（途中）: JSON 取得 → `set_fact` で `mp_existing_names` 作成
- [ ] Step 5（残り）: `loop` + `when` で `launch`

### `group_vars` の置き場所（重要）

`inventory = ./inventory`（ディレクトリ指定）かつ playbook が `playbook/` 配下のとき:

| 置き場所 | playbook で効く？ |
|----------|------------------|
| `inventory/group_vars/all.yaml` | 効く（推奨） |
| `playbook/group_vars/all.yaml` | 効く |
| `ansible/group_vars/all.yaml` | **効かない**（`ansible-inventory` では見えることがある） |

`group_vars` は「変数の置き場」ではなく **inventory のグループ向けスコープ**を表す。`all.yaml` = `all` グループ向け。

---

## データ型の整理（Ansible / Jinja2）

playbook で扱う値の型と、よく出る場所。

| 型 | 例 | 出どころ |
|----|-----|----------|
| 文字列 `str` | `"multipass.exe"`, JSON 文字列 | `register` の `stdout`, `group_vars` |
| 辞書 `dict` | `{ "list": [ ... ] }` | `from_json` 後、YAML の `key: value` |
| 配列 `list` | `["test-vm-1"]`, `[{name:...}]` | `.list`, `map` 後の `\| list` |
| 真偽値 `bool` | `true` / `false` | `when:`, `gather_facts:` |
| 数値 `int` | `1` | `cpus: 1` |

### Terraform の `map` との違い

| | Ansible / Jinja2 | Terraform |
|---|---|---|
| `map` | **フィルタ**（配列の各要素を変換） | **型**（キーと値の集まり） |
| 辞書・オブジェクト | `dict` / JSON オブジェクト | `map` 型 / `object` 型 |

同名だが別物。Ansible の `map` は JavaScript の `array.map()` に近い。

---

## JSON 変換パイプライン（Step 5 の核心）

Multipass の JSON から既存 VM 名リストを作る式:

```jinja2
{{ (mp_list_json.stdout | from_json).list | map(attribute='name') | list }}
```

### Multipass JSON の形

```json
{
    "list": [
        {
            "name": "test-vm-1",
            "state": "Running",
            "ipv4": ["172.23.204.125"]
        }
    ]
}
```

### 段階ごとの変換

| 段階 | 処理 | 型 | 結果イメージ |
|------|------|-----|-------------|
| ① | `mp_list_json.stdout` | `str` | `'{"list":[...]}'`（文字列） |
| ② | `\| from_json` | `dict` | `{ "list": [ {...} ] }` |
| ③ | `.list` | `list` | `[ {name:"test-vm-1", ...} ]` |
| ④ | `\| map(attribute='name')` | フィルタ | 各要素から `name` だけ抽出 |
| ⑤ | `\| list` | `list` | `["test-vm-1"]` |

### `.list` と `\| list` は別物

| 書き方 | 種類 | 意味 |
|--------|------|------|
| `.list` | キーアクセス | JSON 辞書の **`"list"` キー**の値を取る（Multipass が付けた名前） |
| `\| list` | Jinja2 フィルタ | 値を **リスト型に確定**する |

### `map(attribute='name')` とは

- **データ型ではない**。配列の **変換フィルタ**
- 各 VM オブジェクトから `name` だけ抜き出す
- Python なら `[vm["name"] for vm in vm_list]`
- jq なら `.list[].name`

### 変換途中を見るには

**`command` ではなく `debug` を使う**（`command` に辞書を渡すとエラーになる）。

```yaml
- name: 確認 ② from_json 後
  ansible.builtin.debug:
    var: mp_list_json.stdout | from_json

- name: 確認 ③ .list 後
  ansible.builtin.debug:
    var: (mp_list_json.stdout | from_json).list

- name: 確認 ⑤ 最終
  ansible.builtin.debug:
    var: (mp_list_json.stdout | from_json).list | map(attribute='name') | list
```

---

## `set_fact` の書き方

```yaml
- name: 既存の VM 名の一覧を作成
  ansible.builtin.set_fact:
    mp_existing_names: "{{ (mp_list_json.stdout | from_json).list | map(attribute='name') | list }}"
```

`mp_existing_names` は **`set_fact:` より1段深くインデント**（モジュールのパラメータ）。

```yaml
# NG（conflicting action statements エラー）
  ansible.builtin.set_fact:
  mp_existing_names: "..."

# OK
  ansible.builtin.set_fact:
    mp_existing_names: "..."
```

| モジュール | 用途 |
|------------|------|
| `register` | コマンド実行結果を **生データ**で保存 |
| `set_fact` | 加工した値を **変数として保存**（以降のタスクで使う） |
| `debug` | 変数の中身を **表示**（確認用） |

---

## 次回（Step 5 続き）

```yaml
- name: VM がなければ launch
  ansible.builtin.command: >
    {{ mp_cmd }} launch
    --name {{ item.name }}
    --memory {{ item.memory }}
    --cpus {{ item.cpus }}
  loop: "{{ mp_vms }}"
  when: item.name not in mp_existing_names
```

---

## トラブルシュート


| 症状                              | 確認すること                                                      |
| ------------------------------- | ----------------------------------------------------------- |
| `apt update` で GitLab の GPG エラー | Ansible とは無関係。Ubuntu 本体が `Hit` ならそのまま install 可             |
| `ansible: command not found`    | `sudo apt install -y ansible` を実行したか、シェルを開き直したか             |
| `multipass_cmd` / `mp_cmd` 未定義 | `group_vars` の置き場所（`inventory/group_vars/` か） |
| `conflicting action statements` | `set_fact` のパラメータのインデント（モジュール名より深く） |
| `from_json` を `command` に渡した | データの確認は `debug` / `set_fact` を使う |
| SSH ping が失敗                    | SSH 鍵パス `/mnt/c/ProgramData/Multipass/data/ssh-keys/id_rsa` |
| VM が既にある                        | playbook は launch をスキップ（既存なら start のみ）                      |
| IP が変わった                        | 正常。playbook 実行のたびに JSON から再取得                               |


