# 検証ログ生成機構 詳細設計書

## 1. 目的

本ドキュメントは、Elasticsearch 検証環境において、各 Multipass VM 上で検証用ログを発生させる仕組みを定義する。

この仕組みの目的は以下である。

- 複数 VM から Elasticsearch にログが送信されることを確認する
- Filebeat によるログ収集を検証する
- Elasticsearch 側で `host.name`、`service.name`、`log.level` などの条件検索を試す
- 実アプリケーションを用意せず、軽量な仕組みで継続的にログを発生させる
- Ansible で再現可能な形にする

## 2. 採用方式

初期構成では、以下の方式を採用する。

```text
Bash スクリプト + systemd service + systemd timer
```

各 VM に Bash スクリプトを配置し、systemd timer により定期実行する。

## 3. 採用理由

### 3.1 Bash スクリプトを採用する理由

Bash スクリプトは、Linux サーバ上での簡易な処理に向いている。

本用途では、ログを 1 行生成してファイルに追記するだけであり、複雑なアプリケーションロジックは不要である。

採用理由:

- Linux 標準環境で扱いやすい
- 追加ランタイムが不要
- Ansible で配置しやすい
- ログ生成処理が単純で、Bash でも保守可能
- SRE / 運用学習として Bash の読み書きに慣れられる

### 3.2 systemd timer を採用する理由

systemd timer は、systemd 管理下で定期実行を行う仕組みである。

cron でも同様のことは可能だが、今回は Linux サーバ運用の学習も兼ねて systemd timer を採用する。

採用理由:

- `systemctl status` で状態確認できる
- `journalctl` で実行ログを確認できる
- service と timer を分離して管理できる
- Ansible で unit ファイルとして管理しやすい
- 実務で systemd を読む機会が多いため、学習価値がある

## 4. 全体構成

各 VM 上に以下を配置する。

```text
vm-source-01 / vm-source-02
│
├── /usr/local/bin/es-lab-log-generator.sh
│   └── JSON Lines 形式のログを 1 行生成する Bash スクリプト
│
├── /var/log/es-lab/app.log
│   └── 生成された検証ログ
│
├── /etc/systemd/system/es-lab-log-generator.service
│   └── ログ生成スクリプトを 1 回実行する service
│
└── /etc/systemd/system/es-lab-log-generator.timer
    └── service を定期実行する timer
```

ログ収集の流れ:

```text
systemd timer
  ↓ 定期実行
systemd service
  ↓ Bash スクリプトを 1 回実行
/usr/local/bin/es-lab-log-generator.sh
  ↓ JSON ログを追記
/var/log/es-lab/app.log
  ↓ Filebeat が監視
Elasticsearch
```

## 5. ファイル一覧

| ファイル | 役割 |
|---|---|
| `/usr/local/bin/es-lab-log-generator.sh` | 検証ログを生成する Bash スクリプト |
| `/var/log/es-lab/app.log` | 検証ログの出力先 |
| `/etc/systemd/system/es-lab-log-generator.service` | ログ生成スクリプトを 1 回実行する unit |
| `/etc/systemd/system/es-lab-log-generator.timer` | service を定期実行する unit |

## 6. ログ生成スクリプト設計

### 6.1 配置先

```text
/usr/local/bin/es-lab-log-generator.sh
```

### 6.2 権限

```text
owner: root
group: root
mode: 0755
```

### 6.3 処理内容

スクリプトは 1 回の実行で、ログファイルに JSON 形式のログを 1 行追記する。

処理の流れ:

1. ログ出力先ディレクトリを作成する
2. ホスト名を取得する
3. UTC 時刻を取得する
4. ログレベルを疑似的に決定する
5. ログレベルに応じて HTTP ステータスとメッセージを決定する
6. 処理時間を疑似的に生成する
7. JSON Lines 形式でログファイルに 1 行追記する

### 6.4 スクリプト例

```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/es-lab"
LOG_FILE="${LOG_DIR}/app.log"
SERVICE_NAME="dummy-app"

mkdir -p "${LOG_DIR}"

HOST_NAME="$(hostname)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

LEVELS=("INFO" "INFO" "INFO" "WARN" "ERROR")
LEVEL="${LEVELS[$RANDOM % ${#LEVELS[@]}]}"

STATUS=200
MESSAGE="request completed"

if [ "${LEVEL}" = "WARN" ]; then
  STATUS=429
  MESSAGE="request retry required"
elif [ "${LEVEL}" = "ERROR" ]; then
  STATUS=500
  MESSAGE="internal error occurred"
fi

DURATION_MS=$((RANDOM % 900 + 10))

cat >> "${LOG_FILE}" <<EOF
{"timestamp":"${TIMESTAMP}","level":"${LEVEL}","service":"${SERVICE_NAME}","host":"${HOST_NAME}","message":"${MESSAGE}","status":${STATUS},"duration_ms":${DURATION_MS}}
EOF
```

## 7. ログ形式

ログは JSON Lines 形式とする。

1 行が 1 イベントを表す。

例:

```json
{"timestamp":"2026-06-09T02:00:00Z","level":"INFO","service":"dummy-app","host":"vm-source-01","message":"request completed","status":200,"duration_ms":42}
```

### 7.1 フィールド定義

| フィールド | 型 | 内容 |
|---|---|---|
| `timestamp` | string | ログ生成時刻。UTC ISO 8601 形式 |
| `level` | string | ログレベル。`INFO`、`WARN`、`ERROR` のいずれか |
| `service` | string | サービス名。初期値は `dummy-app` |
| `host` | string | VM の hostname |
| `message` | string | ログメッセージ |
| `status` | number | 疑似 HTTP ステータス |
| `duration_ms` | number | 疑似処理時間。ミリ秒 |

### 7.2 ログレベルの比率

初期構成では、以下のような比率を想定する。

| level | 比率の目安 | 用途 |
|---|---:|---|
| `INFO` | 高 | 正常ログ |
| `WARN` | 中 | 遅延、リトライ、軽微な異常 |
| `ERROR` | 低 | 疑似障害 |

実装上は Bash 配列に `INFO` を多めに入れることで、簡易的に比率を調整する。

## 8. systemd service 設計

### 8.1 配置先

```text
/etc/systemd/system/es-lab-log-generator.service
```

### 8.2 役割

ログ生成スクリプトを 1 回実行する。

この service は常駐しない。

### 8.3 unit ファイル例

```ini
[Unit]
Description=Generate Elasticsearch lab log

[Service]
Type=oneshot
ExecStart=/usr/local/bin/es-lab-log-generator.sh
```

### 8.4 設計意図

`Type=oneshot` を指定することで、スクリプトを 1 回実行して終了する service として扱う。

定期実行のタイミングは service ではなく、timer 側で管理する。

## 9. systemd timer 設計

### 9.1 配置先

```text
/etc/systemd/system/es-lab-log-generator.timer
```

### 9.2 役割

`es-lab-log-generator.service` を定期実行する。

### 9.3 unit ファイル例

```ini
[Unit]
Description=Run Elasticsearch lab log generator every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Unit=es-lab-log-generator.service

[Install]
WantedBy=timers.target
```

### 9.4 設定値の意味

| 設定 | 意味 |
|---|---|
| `OnBootSec=30s` | OS 起動後 30 秒で初回実行する |
| `OnUnitActiveSec=60s` | 前回実行から 60 秒後に再実行する |
| `Unit=es-lab-log-generator.service` | 実行対象の service を指定する |
| `WantedBy=timers.target` | timer を有効化できるようにする |

## 10. Ansible で管理する内容

Ansible では以下を行う。

1. ログ出力ディレクトリを作成する
2. Bash スクリプトを VM に配置する
3. systemd service unit を配置する
4. systemd timer unit を配置する
5. `systemd daemon-reload` を実行する
6. timer を enable / start する

### 10.1 Ansible タスク例

```yaml
- name: ログ出力ディレクトリを作成
  ansible.builtin.file:
    path: /var/log/es-lab
    state: directory
    owner: root
    group: root
    mode: "0755"
  become: true

- name: ログ生成スクリプトを配置
  ansible.builtin.copy:
    src: es-lab-log-generator.sh
    dest: /usr/local/bin/es-lab-log-generator.sh
    owner: root
    group: root
    mode: "0755"
  become: true

- name: systemd service を配置
  ansible.builtin.copy:
    src: es-lab-log-generator.service
    dest: /etc/systemd/system/es-lab-log-generator.service
    owner: root
    group: root
    mode: "0644"
  become: true

- name: systemd timer を配置
  ansible.builtin.copy:
    src: es-lab-log-generator.timer
    dest: /etc/systemd/system/es-lab-log-generator.timer
    owner: root
    group: root
    mode: "0644"
  become: true

- name: systemd unit を再読み込み
  ansible.builtin.systemd:
    daemon_reload: true
  become: true

- name: ログ生成 timer を有効化して起動
  ansible.builtin.systemd:
    name: es-lab-log-generator.timer
    enabled: true
    state: started
  become: true
```

## 11. 動作確認

### 11.1 timer の状態確認

```bash
systemctl status es-lab-log-generator.timer
```

### 11.2 timer 一覧の確認

```bash
systemctl list-timers
```

### 11.3 service の実行ログ確認

```bash
journalctl -u es-lab-log-generator.service
```

### 11.4 ログファイルの確認

```bash
sudo tail -f /var/log/es-lab/app.log
```

期待される出力:

```json
{"timestamp":"2026-06-09T02:00:00Z","level":"INFO","service":"dummy-app","host":"vm-source-01","message":"request completed","status":200,"duration_ms":42}
{"timestamp":"2026-06-09T02:01:00Z","level":"WARN","service":"dummy-app","host":"vm-source-01","message":"request retry required","status":429,"duration_ms":812}
```

## 12. Filebeat 側の想定

Filebeat は以下のログファイルを監視する。

```text
/var/log/es-lab/app.log
```

JSON Lines 形式で出力するため、Filebeat 側では JSON パースを有効にする想定とする。

設定例:

```yaml
filebeat.inputs:
  - type: filestream
    id: es-lab-app-log
    enabled: true
    paths:
      - /var/log/es-lab/app.log
    parsers:
      - ndjson:
          target: ""
          overwrite_keys: true
```

## 13. VM ごとの差分

初期構成では、スクリプト内で `hostname` を取得することで VM ごとの差分を表現する。

例:

- `vm-source-01`
- `vm-source-02`

必要に応じて、Ansible 変数で以下を VM ごとに変える。

- `SERVICE_NAME`
- ログ出力パス
- ログレベル比率
- 疑似ステータスコード
- 疑似メッセージ

## 14. スコープ外

初期構成では以下は対象外とする。

- 実アプリケーションの導入
- nginx アクセスログ生成
- 1 分未満の高頻度ログ生成
- 大量ログ負荷試験
- ログローテーションの詳細設計
- 障害注入の本格実装

## 15. 今後の拡張候補

必要に応じて以下を追加する。

- nginx を導入してアクセスログを収集する
- Python 版ログ生成スクリプトを追加する
- ログローテーション設定を追加する
- VM ごとに異なる service 名を持たせる
- ERROR ログを意図的に増やすシナリオを追加する
- systemd timer の実行間隔を Ansible 変数化する
- Filebeat ingest pipeline と連携する

## 16. 完了条件

本機構の初期実装完了条件は以下とする。

- 各 VM に `/usr/local/bin/es-lab-log-generator.sh` が配置されている
- 各 VM に systemd service / timer が配置されている
- `es-lab-log-generator.timer` が enabled / started になっている
- `/var/log/es-lab/app.log` に定期的に JSON ログが追記される
- Filebeat が `/var/log/es-lab/app.log` を読み取れる
- Elasticsearch 側で VM ごとのログを確認できる
