# Kibana Saved Objects（Git 管理メモ）

Kibana UI で作ったデータビュー等を NDJSON で Git 管理し、playbook から import するための置き場。

- **export 置き場**: `exports/*.ndjson`
- **import playbook**: `playbook/kibana_saved_objects_import.yaml`（`site.yaml` から呼ばれる）
- NDJSON が無い場合は import はスキップされる

## どこに保存されるか（UI で作ったもの）

データビュー・ダッシュボード等は **VM 上のファイルではなく Elasticsearch 内**（`.kibana*` 系インデックス）に保存される。  
`kibana.yml`（ポート・言語など）は Ansible テンプレート、`exports/*.ndjson` は **Saved Objects 用**。

## Export のおすすめ（lab）

Kibana → **Stack Management** → **保存オブジェクト** → Export

| オブジェクト | export する？ | 理由 |
|-------------|---------------|------|
| **データビュー**（例: `filebeat` / `filebeat-*`） | **する** | Discover で使う。Git 管理の主目的 |
| ダッシュボード・可視化・保存済み検索 | 作ったらする | 分析 UI の再現用。データビューと一緒に export 可 |
| **Advanced Settings** | **しない** | 環境依存・Kibana 全体設定。import で意図しない差分が出やすい |
| **Global Settings** | **しない** | 同上。全 Space に影響する |

**今の段階**: データビューだけ export で十分。  
**Dashboard 等を作った後**: それら + データビュー（「関連オブジェクトを含める」にチェック）。

Settings 系は基本 export しない。

## ファイル名の例

```
exports/filebeat-data-view.ndjson
exports/dashboards.ndjson
```

## 反映手順

1. UI でデータビュー等を作成
2. Stack Management から NDJSON を export
3. `exports/` に保存して commit
4. playbook 再実行

```bash
bash scripts/controller-ansible-run.sh
# または import のみ
bash scripts/controller-ansible-run.sh playbook/kibana_saved_objects_import.yaml
```

import は `overwrite=true` のため、同名オブジェクトは上書きされる。

## 取り込んだログ本体について

`filebeat-*` 等の **ログデータ** は Elasticsearch の通常インデックスに入る。Git 管理の対象外（データは ES 側）。
