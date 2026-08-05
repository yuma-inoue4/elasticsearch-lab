# elasticsearch-lab 改訂案

Ansible + Multipass による Elasticsearch 検証環境の方針整理。

---

## 1. 改訂理由と内容

### 改訂理由

- 私用 Mac と業務 Windows の両方で、同じ手順・同じ成果物で検証したい
- Elasticsearch が情報収集する対象として、コンテナではなく **Linux VM を2台** 用意したい
- 構成管理は Ansible で行い、OS 差分はできるだけホスト側の薄い層に閉じたい
- 当初案（Mac ネイティブ Ansible / Windows は WSL2 上 Ansible）だと、制御ノードの置き場が OS ごとに分かれる

### 改訂内容（採用方針）

| 項目 | 内容 |
|---|---|
| 仮想化 | Multipass（Ubuntu VM） |
| VM 数 | 4台（controller / es-stack / target×2） |
| VM 作成 | ホストからスクリプトで一括起動（中身は未作り込み） |
| 構成管理 | `es-controller` 上の Ansible が各 VM を作り込む |
| スクリプト | Mac / Windows(WSL2) で **同じ Bash スクリプト** |
| Windows | Multipass はホストに導入。起動・命令は WSL2 から `multipass.exe` を実行 |
| 対象外に近いもの | Vagrant+VirtualBox、クラウド VM、収集対象の Docker 化 |

### 処理の流れ（理解の整理）

1. ホスト（Mac 本体、または Windows では WSL2）から Multipass で VM を4台作成する
   （この時点では詳細な作り込みはしない）
2. ホストから `es-controller` へ Ansible 実行を依頼する
   （例: `multipass exec es-controller -- ansible-playbook ...`）
3. Ansible が `es-stack` / `es-target-01` / `es-target-02` を作り込む
   （Agent/Beats、サンプル負荷、ES/Kibana/Fleet など）

### 役割分担

| 作業 | 担当 |
|---|---|
| VM の作成・削除 | ホスト上の Bash スクリプト（Multipass） |
| OS パッケージ・Agent・ES 等の作り込み | `es-controller` 内の Ansible |
| ES 接続先 | Ansible 変数（`group_vars` 等） |

補足:

- Ansible から Multipass VM を「新規作成」するのは現実的でない
  （Multipass デーモンはホスト側にあり、controller 内からは通常操作できない）
- Windows ネイティブの PowerShell だけでは Bash スクリプトは動かないが、**WSL2 上から実行すれば Mac と同じスクリプトでよい**
- 残る OS 差は「Multipass の入れ方」と「Windows は WSL2 から叩く」程度
  （`--cloud-init` パスの `wslpath -w` 変換、WSL↔VM 疎通は実装時に吸収）

### Elasticsearch の置き場

- **Ansible と同じ `es-controller` には載せない**（メモリ競合・役割混在を避ける）
- 専用 VM **`es-stack`** に Elasticsearch / Kibana / Fleet を配置する
- 収集対象は `es-target-01` / `es-target-02` のみ

---

## 2. 構成

### 論理構成（木構造）

```text
elasticsearch-lab（改訂後）
├── ホスト OS
│   ├── Mac
│   │   ├── Multipass（ネイティブ）
│   │   └── Bash スクリプト（up / down / inventory 相当）
│   └── Windows
│       ├── Multipass（ホスト側にインストール）
│       └── WSL2 (Ubuntu)
│           └── 同じ Bash スクリプト
│               └── multipass.exe を呼び出し
│
└── Multipass VM × 4
    ├── es-controller
    │   ├── Ansible（制御ノード）
    │   ├── inventory / playbooks / roles
    │   └── 役割: 他 VM への SSH 構成適用
    │
    ├── es-stack
    │   ├── Elasticsearch
    │   ├── Kibana
    │   └── Fleet Server（Agent 利用時）
    │
    ├── es-target-01
    │   ├── Elastic Agent または Filebeat/Metricbeat
    │   └── サンプル負荷（nginx / ログ生成 等）
    │
    └── es-target-02
        ├── Elastic Agent または Filebeat/Metricbeat
        └── サンプル負荷（nginx / ログ生成 等）
```

### データ／制御の流れ

```text
[Mac または WSL2]
        │
        │ 1) multipass launch × 4
        │ 2) multipass exec es-controller -- ansible-playbook ...
        ▼
┌─────────────────┐
│  es-controller  │
│    (Ansible)    │
└────────┬────────┘
         │ SSH で作り込み
    ┌────┴────┬──────────────┐
    ▼         ▼              ▼
┌────────┐ ┌──────────┐ ┌──────────┐
│es-stack│ │target-01 │ │target-02 │
│ ES等   │ │ Agent等  │ │ Agent等  │
└───▲────┘ └────┬─────┘ └────┬─────┘
    │           │            │
    └───────────┴────────────┘
         ログ / メトリクス送信
```

### リポジトリ構成（案）

```text
ansible-es-lab/  （または elasticsearch-lab 配下へ統合）
├── README.md
├── scripts/
│   ├── up.sh              # VM 4台起動
│   ├── down.sh            # VM 削除
│   ├── inventory.sh       # IP 取得・inventory 生成
│   └── lib.sh             # multipass / multipass.exe 解決
├── cloud-init/
│   └── user-data.yaml.tpl # SSH 鍵投入など最小初期化
└── ansible/               # controller 上で実行する想定
    ├── ansible.cfg
    ├── inventory.ini
    ├── group_vars/
    └── playbooks/
        ├── site.yml
        ├── bootstrap.yml
        ├── elastic_stack.yml   # es-stack 向け（追加）
        ├── elastic_agent.yml
        └── sample_workload.yml
```

### 旧方針との対比（要点）

```text
旧（OS 差が制御ノードに出る）
├── Mac:     ホスト Ansible → Multipass target×2
└── Windows: WSL2 Ansible  → Multipass target×2

新（制御は controller に集約、スクリプトは共通）
├── Mac / WSL2: 同じ Bash → Multipass×4
└── Ansible は常に es-controller 内
```

---

## 補足（実装時の注意）

- Apple Silicon では Multipass VM が ARM になるため、Agent/Beats/ES はアーキテクチャを変数で吸収する
- 初回は target + controller だけでも検証可能。`es-stack` は後追いでもよいが、本改訂案では4台構成を正式とする
- 既存の Docker ベース `elasticsearch-lab` は、必要なら `es-stack` 代替の参考実装として残す選択肢あり
