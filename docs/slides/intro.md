# Elasticsearch 初心者向けスライド構成メモ

## 目的

Elasticsearch を全く知らない人に向けて、以下を理解してもらう。

- Elasticsearch が何をするものか
- どういう場面で使われるか
- 基本的な構成要素は何か
- RDB との違いは何か
- 基本的な検索クエリの考え方
- ログ検索やアプリ検索でどう使えるか

## 想定対象者

- Elasticsearch を初めて学ぶ人
- 検索エンジンやログ分析基盤に詳しくない人
- RDB は少し知っているが、Elasticsearch の用語は知らない人

## 全体の説明方針

いきなり shard や replica などの内部構造から入らない。

最初は「なぜ必要か」「何が便利か」から入り、次に全体構成、基本用語、検索例へ進める。

おすすめの流れ:

```text
概念
↓
使い道
↓
基本構成
↓
基本用語
↓
検索クエリ例
↓
注意点
↓
まとめ
```

## スライド構成案

### 1. タイトル

タイトル例:

```text
Elasticsearch 入門
大量データを高速に検索する仕組み
```

入れる内容:

- Elasticsearch の初心者向け説明であること
- 検索、ログ分析、データ探索に使う技術であること

### 2. Elasticsearch とは何か

一言説明:

```text
Elasticsearch は、大量のデータの中から必要な情報を高速に探すための検索エンジン。
```

入れる内容:

- 全文検索が得意
- 条件検索が得意
- 集計や分析にも使える
- ログ検索、アプリ内検索、監視などで使われる

### 3. なぜ Elasticsearch が必要か

入れる内容:

- データが増えると、単純な検索では遅くなる
- RDB の `LIKE` 検索だけでは柔軟な検索が難しい
- 大量ログからエラーをすぐ探したい
- キーワード、時間範囲、ステータス、ホスト名などで高速に絞り込みたい

例:

```text
数百万件のログから、直近1時間の ERROR だけを探したい
```

### 4. 代表的な利用例

入れる内容:

- Web サイトやアプリの検索機能
- サーバログ、アプリログの検索
- 障害調査
- 監視ダッシュボード
- セキュリティログ分析
- 商品検索、ドキュメント検索

### 5. 基本構成

構成例:

```text
アプリ / サーバ / ログファイル
        ↓
Filebeat / Logstash
        ↓
Elasticsearch
        ↓
Kibana
```

入れる内容:

- Elasticsearch: データを保存し、検索する
- Kibana: データを画面で検索・可視化する
- Filebeat: ログファイルを収集して送る
- Logstash: データを加工して送る

### 6. Elasticsearch の基本用語

入れる内容:

- index: データの入れ物
- document: 1件のデータ
- field: データの項目
- mapping: field の型定義
- query: 検索条件
- shard: データの分割単位
- replica: shard のコピー

初心者向けには、まず以下を重点的に説明する。

```text
index / document / field / query
```

### 7. RDB との違い

入れる内容:

```text
RDB:
  正確な更新、取引処理、整合性が得意

Elasticsearch:
  検索、全文検索、絞り込み、集計が得意
```

補足:

- Elasticsearch は RDB の完全な置き換えではない
- 用途に応じて使い分ける
- アプリの主データは RDB、検索用データは Elasticsearch に持たせる構成も多い

### 8. データのイメージ

ドキュメント例:

```json
{
  "title": "Elasticsearch 入門",
  "category": "study",
  "created": "2026-06-09",
  "tags": ["search", "log", "infra"]
}
```

説明:

- 1つの JSON が 1 document
- `title`、`category`、`created`、`tags` が field
- 複数の document が index に入る

### 9. 検索クエリの基本

入れる内容:

- `match_all`: 全件検索
- `match`: 文章やキーワード検索
- `term`: 完全一致検索
- `range`: 範囲検索
- `sort`: 並び替え
- `from` / `size`: ページング

### 10. クエリ例: 全件検索

例:

```json
GET /logs/_search
{
  "query": {
    "match_all": {}
  }
}
```

説明:

- `logs` index を検索する
- `match_all` は全件取得
- `{}` は追加条件なしを表す

### 11. クエリ例: 条件検索

例:

```json
GET /logs/_search
{
  "query": {
    "match": {
      "message": "error"
    }
  }
}
```

説明:

- `message` フィールドに `error` を含むデータを探す
- ログ検索や文書検索でよく使う

### 12. クエリ例: 時間範囲で絞る

例:

```json
GET /logs/_search
{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-1h",
        "lte": "now"
      }
    }
  }
}
```

説明:

- 直近1時間のログを検索する
- 障害調査でよく使う考え方

### 13. クエリ例: ソート

例:

```json
GET /logs/_search
{
  "query": {
    "match_all": {}
  },
  "sort": [
    { "@timestamp": "desc" }
  ]
}
```

説明:

- `@timestamp` の新しい順に並べる
- `desc` は降順
- `asc` は昇順

### 14. クエリ例: ページング

例:

```json
GET /logs/_search
{
  "from": 20,
  "size": 10,
  "query": {
    "match_all": {}
  }
}
```

説明:

- `from`: 何件目から返すか
- `size`: 何件返すか
- `from: 20, size: 10` は 21 件目から 10 件返す

ページ数の計算:

```text
total_pages = ceil(total_hits / page_size)
```

### 15. JSON の括弧の見方

入れる内容:

```text
[ ] = 配列。複数の値や条件を並べる。
{ } = オブジェクト。中身、設定、条件を書く箱。
```

例:

```json
"sort": [
  { "created": "desc" }
]
```

説明:

- `sort` は複数条件を指定できるため配列
- `{ "created": "desc" }` は 1つのソート条件

### 16. ログ検索での使い方

検索例:

- `ERROR` ログだけ探す
- 特定ホストのログだけ探す
- 直近1時間のログだけ見る
- 新しい順に並べる
- 件数を集計する

説明:

```text
障害発生時に、大量ログの中から必要な情報を短時間で探せる。
```

### 17. 注意点

入れる内容:

- Elasticsearch は万能なデータベースではない
- mapping 設計が重要
- 大量データではメモリ、ディスク、shard 設計が重要
- 深いページングは重くなりやすい
- 更新頻度が高すぎるデータには向かない場合がある
- RDB と役割分担して使うことが多い

### 18. まとめ

入れる内容:

- Elasticsearch は大量データを高速に検索するための検索エンジン
- ログ検索、全文検索、分析、監視でよく使われる
- 基本は `index`、`document`、`field`、`query` を押さえる
- RDB とは得意分野が違う
- まずは簡単なクエリから試すのがよい

## 1枚目に置く短い説明

```text
Elasticsearch は、大量のデータを高速に検索・分析するための検索エンジンです。
ログ検索、アプリ内検索、監視、セキュリティ分析などで使われます。
```

## 初心者向けに強調したいこと

- Elasticsearch は検索が得意な仕組み
- RDB と競合するものではなく、得意分野が違う
- JSON 形式でデータを扱う
- クエリも JSON で書く
- まずは `match_all`、`match`、`range`、`sort`、`from` / `size` を理解すればよい

## スライド生成時の指示文例

```text
以下のメモをもとに、Elasticsearch を全く知らない初心者向けの説明スライドを作成してください。
対象者は RDB は少し知っているが、Elasticsearch は初めて学ぶ人です。
専門用語はできるだけ噛み砕き、概念、使い道、基本構成、用語、検索クエリ例、注意点、まとめの順で構成してください。
1スライド1テーマにし、図解できる箇所は構成図や比較表として表現してください。
```
