# Elasticsearch 検証環境 仕様書

## 1. 目的

本ドキュメントは、ローカルラップトップ上に Elasticsearch の検証環境を構築するための仕様を定義する。

主な目的は以下である。

- Elasticsearch に対して複数ホストからログを投入する構成を検証する
- 検証環境をコードで管理し、再現可能にする
- ラップトップ上で完結する最小構成とする
- Ansible、Docker Compose、Multipass の役割を明確に分離する

## 2. 前提環境

本構成は以下の環境を前提とする。

- ホストマシン: Windows ラップトップ
- メモリ: 32GB
- Docker 実行環境: WSL2 上の Docker
- Elasticsearch 管理: Docker Compose
- 検証用 VM 管理: Multipass
- VM 内設定管理: Ansible

## 3. 全体構成

```text
Windows Laptop
│
├── WSL2
│   ├── Docker
│   │   └── Docker Compose
│   │       ├── Elasticsearch
│   │       └── Kibana（任意）
│   │
│   └── Ansible
│       ├── Multipass VM の作成
│       ├── VM の IP 取得
│       ├── VM を Ansible 実行対象に登録
│       └── VM 内ミドルウェア設定
│
└── Multipass
    ├── vm-source-01
    │   ├── Filebeat
    │   └── 検証用ログ生成
    │
    └── vm-source-02
        ├── Filebeat
        └── 検証用ログ生成
```

## 4. 採用方針

### 4.1 Elasticsearch は Docker Compose で管理する

Elasticsearch 本体は Multipass VM ではなく、WSL2 上の Docker Compose で起動する。

理由:

- Elasticsearch の起動、停止、設定管理がシンプル
- VM のオーバーヘッドを避けられる
- `docker-compose.yml` により構成をコード管理できる
- 検証環境として十分な再現性がある

### 4.2 検証用 VM は Multipass で作成する

ログ送信元となる VM は Multipass で作成する。

理由:

- 複数ホストからのログ収集を検証できる
- 実際の Linux ホストに近い形で Filebeat を動かせる
- systemd やパッケージ管理を含む検証ができる

### 4.3 VM 内の構成管理は Ansible で行う

Multipass VM の作成、IP 取得、ミドルウェア導入、設定ファイル配布は Ansible で管理する。

Ansible が担当すること:

- Multipass VM の作成
- Multipass VM の削除
- Multipass VM の IP 取得
- Ansible 実行対象への VM 登録
- VM 内への Filebeat インストール
- Filebeat 設定ファイルの配布
- 検証用ログ生成設定
- hostname やログパスなどの VM ごとの差分管理

Ansible が担当しないこと:

- WSL2 のインストール
- Docker のインストール
- Elasticsearch コンテナの詳細運用
- Windows ホスト自体の構成管理

## 5. VM 台数

初期構成では Multipass VM を 2 台とする。

| VM 名 | 役割 | メモリ | CPU |
|---|---|---:|---:|
| `vm-source-01` | ログ送信元 1 | 1GB | 1 |
| `vm-source-02` | ログ送信元 2 | 1GB | 1 |

2 台とする理由:

- 1 台ではマルチホスト検証にならない
- 2 台あればホスト名差分、ログパス差分、送信元差分を確認できる
- 32GB RAM のラップトップ上で無理なく動作する
- 3 台以上は必要になった段階で追加する

## 6. VM に導入するミドルウェア

初期構成では、VM に以下を導入する。

| ミドルウェア | 用途 |
|---|---|
| Filebeat | ログを Elasticsearch に送信する |
| cron / logger / shell script | 検証用ログを生成する |

初期構成では導入しないもの:

| ミドルウェア | 理由 |
|---|---|
| Logstash | 最小構成では不要。必要になったら Docker Compose 側に追加する |
| Metricbeat | メトリクス検証が必要になった段階で追加する |
| nginx | アクセスログ検証が必要になった段階で追加する |

## 7. Ansible の実行方式

手書き inventory は使用しない。

Ansible playbook の中で以下を行う。

1. `multipass launch` で VM を作成する
2. `multipass list --format json` で VM の IP を取得する
3. `add_host` で取得した IP を Ansible の実行対象に登録する
4. 登録した VM に対して SSH 接続する
5. Filebeat などの設定を行う

### 7.1 `add_host` の役割

`add_host` は、Ansible 実行中にホストを作業対象として登録するための仕組みである。

`add_host` 自体は以下を行わない。

- VM の作成
- IP の探索
- Multipass コマンドの実行

`add_host` が行うことは以下のみである。

- 取得済みの IP アドレスを Ansible に登録する
- 登録したホストを指定グループに所属させる
- 後続の Play でそのホストに対して作業できるようにする

例:

```yaml
- name: vm-source-01 を Ansible の作業対象に追加
  ansible.builtin.add_host:
    name: vm-source-01
    ansible_host: "取得済みの IP アドレス"
    groups: source_vms
```

## 8. Elasticsearch 側の管理

Elasticsearch は Docker Compose で管理する。

想定操作:

```bash
docker compose up -d
docker compose down
docker compose restart elasticsearch
docker compose logs -f elasticsearch
```

Docker Compose で管理する内容:

- Elasticsearch のバージョン
- ポート公開
- JVM heap 設定
- データ永続化ボリューム
- 認証設定
- Kibana の追加有無

## 9. リソース目安

32GB RAM のラップトップを前提に、初期構成では以下を目安とする。

| コンポーネント | 目安 |
|---|---:|
| Elasticsearch heap | 2GB |
| Elasticsearch コンテナ全体 | 4GB 程度 |
| Kibana | 512MB - 1GB |
| Multipass VM 1 台 | 1GB |
| Multipass VM 2 台合計 | 2GB |
| WSL2 / Docker | 数GB |
| Windows / ブラウザ等 | 残り |

初期構成では、Elasticsearch + VM 2 台で十分に動作可能な見込み。

## 10. ディレクトリ構成案

```text
elasticsearch-lab/
├── README.md
├── docker/
│   └── docker-compose.yml
│
├── ansible/
│   ├── ansible.cfg
│   ├── playbook/
│   │   └── site.yaml
│   ├── group_vars/
│   │   └── all.yaml
│   └── roles/
│       ├── multipass_vm/
│       ├── filebeat/
│       └── log_generator/
│
└── docs/
    └── elasticsearch-lab-spec.md
```

## 11. 初期構築フロー

初期構築は以下の順で行う。

1. WSL2 上で Docker / Docker Compose を利用可能にする
2. Docker Compose で Elasticsearch を起動する
3. Elasticsearch に `curl` で接続確認する
4. Ansible playbook を実行する
5. Multipass VM 2 台を作成する
6. VM の IP を取得する
7. `add_host` で VM を Ansible 実行対象に登録する
8. VM に Filebeat を導入する
9. VM から Elasticsearch へログ送信する
10. Elasticsearch 側でログ投入を確認する

## 12. 検証ログ生成方針

初期構成では、各 VM 上で軽量なログ生成スクリプトを systemd timer または cron から定期実行する。

ログ生成の目的:

- 複数ホストから Elasticsearch にログが入ることを確認する
- `host.name`、`service.name`、`log.level`、`event.dataset` などの検索条件を検証する
- 正常ログ、警告ログ、エラーログを意図的に発生させる
- VM ごとのログ内容差分を確認する

初期構成では、アプリケーション本体や nginx は導入せず、JSON Lines 形式の検証ログをファイルに追記する方式を採用する。

推奨ログ出力先:

```text
/var/log/es-lab/app.log
```

推奨ログ形式:

```json
{"timestamp":"2026-06-09T00:00:00Z","level":"INFO","service":"dummy-app","message":"request completed","status":200,"duration_ms":42}
```

## 13. 今後の拡張候補

必要に応じて以下を追加する。

- Kibana
- Logstash
- Metricbeat
- nginx アクセスログ
- VM 3 台目以降
- Ansible role 分割
- Elasticsearch 認証設定
- Ansible Vault による秘密情報管理
- 動的 inventory スクリプト化

## 14. 初期スコープ外

初期構築では以下は対象外とする。

- 本番運用相当の冗長構成
- Elasticsearch クラスタ構成
- Kubernetes
- Cloud 環境連携
- Windows ホスト自体の完全自動構成
- CI/CD 化
- 監視基盤の本格導入

## 15. 完了条件

初期構成の完了条件は以下とする。

- `docker compose up -d` で Elasticsearch が起動する
- `ansible-playbook playbook/site.yaml` で Multipass VM が 2 台作成される
- Ansible が VM の IP を自動取得する
- 手書き inventory なしで VM に SSH 接続できる
- VM 2 台に Filebeat が導入される
- VM 2 台から Elasticsearch にログが送信される
- Elasticsearch 側で送信元ホストの違いを確認できる

## 16. 設計上の判断

本構成では、Elasticsearch は Docker Compose、ログ送信元 VM は Multipass、VM 内設定は Ansible という役割分担にする。

この分離により、以下を実現する。

- Elasticsearch の管理をシンプルにする
- VM の中身は Ansible で再現可能にする
- 手書き inventory を不要にする
- ラップトップ上で動く最小構成にする
- 後から Logstash、Kibana、Metricbeat などを追加しやすくする

## 17. 学習メモ: JSON の括弧

Elasticsearch のクエリは JSON で書くため、`[ ]` と `{ }` の意味を押さえておく。

- `[ ]`: 配列。複数の値や条件を順番に並べるためのリスト。
- `{ }`: オブジェクト。ある項目の中身、設定、条件をまとめて書くための箱。

例:

```json
"sort": [
  { "created": "desc" }
]
```

この場合、`sort` の中身は配列であり、その中に `{ "created": "desc" }` というソート条件が 1 つ入っている。

`{ "created": "desc" }` は、`created` フィールドを降順で並べる、という意味である。

```json
"query": {
  "match_all": {}
}
```

この場合、`query` の中身として `match_all` 条件を指定している。`match_all` の追加設定がないため、空の `{}` を書いている。
