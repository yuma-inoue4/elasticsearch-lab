---
marp: true
theme: gaia
paginate: true
size: 16:9
backgroundColor: #ffffff
color: #333333
style: |
  section {
    background-color: #ffffff !important;
    color: #333333;
  }
  section.lead {
    background-color: #ffffff !important;
    color: #333333;
  }
---

<!-- _class: lead -->

# Elasticsearch 基礎

---

# Elasticsearch とは何か

- オープンソースの **検索エンジン**（全文検索向け）
- 大量データから、条件に合うものを **素早く探す** 仕組み
- **検索**: 商品検索、アプリ内キーワード検索
- **分析**: エラーログ件数の推移、メトリクスのグラフ表示
- 本質は **検索**。分析・可視化はその延長

---

# なぜ Elasticsearch が必要か

- データが増えると、単純な検索では **遅くなる**
- RDB の `LIKE '%error%'` では、ログ全文検索・複数条件が **弱い**
- 例: 数百万件のログから、直近1時間の ERROR を **数秒で** 探したい
- **条件を渡して機械に探してもらう** ときに向いている
- RDB の **代替ではなく**、検索が苦手な部分を **補う** 用途が多い

---

# どんな場面で使われるか

| 用途 | 例 |
| --- | --- |
| Web・アプリ内検索 | 商品名・記事本文の検索 |
| ログ検索 | エラーメッセージ、特定ホストのログ |
| 障害調査 | 大量ログから原因を絞り込む |
| ダッシュボード | 件数推移・メトリクスのグラフ表示 |

- 死活監視の代替ではない → Zabbix / CloudWatch と **役割分担**

---

# データの持ち方

## index / document / field

| 用語 | 意味 | RDB で言うと |
| --- | --- | --- |
| **index** | 同種データの入れ物 | テーブル |
| **document** | 1件分のデータ | 1行（レコード） |
| **field** | document 内の項目 | 列（カラム） |

```json
{ "message": "error occurred", "level": "ERROR",
  "@timestamp": "2026-06-09T10:00:00Z" }
```

---

# RDB との違い

| | RDB（MySQL 等） | Elasticsearch |
| --- | --- | --- |
| 得意 | 登録・更新・取引 | **検索・全文検索・絞り込み** |
| 持ち方 | 正規化・リレーション | 非正規化・1 document に集約 |
| 検索 | `WHERE` で完全一致が基本 | 「含む」「範囲」も速い |

- ES は検索時に **JOIN しない** → 必要な情報を1 document に入れる
- 実務: **RDB に本データ、ES に検索用コピー** という構成も多い

---

# 全体構成

## 収集 → Elasticsearch → Kibana

```
サーバー（ログ / メトリクス）
    ↓  Beats（Filebeat 等）
    ↓  Logstash（任意・加工）
Elasticsearch … 保存・検索・集計
    ↑
Kibana … 検索 UI・グラフ表示
```

| コンポーネント | 役割 |
| --- | --- |
| **Beats** | 各サーバーからデータを集めて ES へ送る |
| **Elasticsearch** | データの置き場。検索・集計の中心 |
| **Kibana** | 見る・探す UI |

---

# 検索の基本

- 操作は **REST API**（HTTP + JSON）
- よく使うメソッド: **GET** 検索 / **POST** 検索・登録 / **PUT** 更新 / **DELETE** 削除

| クエリ | 用途 |
| --- | --- |
| `match_all` | 全件取得 |
| `match` | キーワード検索 |
| `range` | 範囲検索（例: 直近1時間） |
| `from` / `size` | ページング |

```json
GET /logs/_search
{ "query": { "match": { "message": "error" } } }
```

---

# 注意点

- ES は **万能 DB ではない**
- **mapping（フィールド型）** の設計が重要
- 更新が激しいデータ（取引台帳等）の主置き場には向かない
- 深いページング（数万件目以降）は重くなりやすい
- 監視ツールの代替ではなく **ログ検索・横断調査** で力を発揮

---

<!-- _class: lead -->

# まとめ

- **大量データを高速に検索する** 検索エンジン
- 基本用語: **index / document / field / query**
- RDB と得意分野が違う → **役割分担** して使う
- まずは `match_all` `match` `range` から試す

**ご清聴ありがとうございました**
