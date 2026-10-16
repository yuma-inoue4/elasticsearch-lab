# Elasticsearch / Kibana セットアップ手順書（Docker Compose・フェーズ1）

対象: Compose 基礎を終えた人向け。**写経ではなく理解しながら進める**ための手順書。  
要件の正本: [`zentai-keikaku.md`](./zentai-keikaku.md) の §5。

参考（情報が古い／構成が違う場合あり。コピー元ではなく「なぜそうするか」の補助）:

- [ElasticsearchをDockerで動かす（Qiita）](https://qiita.com/potofo/items/8cb74cc7500a4fb97b70)
- [v8.6 ES/Kibana を docker-compose で（Qiita・試用）](https://qiita.com/takeo-furukubo/items/c2f194679afadc06a4e9)
- 公式: [Install Elasticsearch with Docker](https://www.elastic.co/guide/en/elasticsearch/reference/8.5/docker.html)

---

## 0. この手順書でやること／やらないこと

### やること（フェーズ1）

- Elasticsearch **3ノード** + Kibana を **Docker Compose** で起動する
- 版は本番 Cloud に合わせ **8.5.2**
- **Windows（WSL2 + Docker CLI）** と **Mac（OrbStack + Docker CLI）** の両方で、同じ定義ファイルが動くようにする
- 「なぜこの設定があるか」を追いながら、自分の手でファイルを置き、起動・確認する

### やらないこと（フェーズ2以降）

- **Security（認証・TLS）ON**
- **Fleet / Fleet Server / Elastic Agent**
- ILM・高度なアラート・Searchable Snapshots の本格構築

本番は Fleet を使っているが、最初から全部載せるとまたブラックボックス化しやすい。  
フェーズ1は **「3ノードのクラスタと Kibana が見える」** まで。

### 完了の定義（DoD）

次をすべて満たしたらフェーズ1完了。

1. `docker compose ps` で ES 3つ + Kibana が Up（または healthy）
2. `_cat/nodes` 相当で **ノードが3つ**見える
3. ブラウザで Kibana が開く
4. `docker compose down` → `up` で同じ状態に戻せる
5. （理想）WSL と Mac の両方で同じリポジトリの compose が動く

---

## 1. 全体像（何を起動するのか）

```text
        ブラウザ
           │
           ▼ :5601
        ┌─────────┐
        │  Kibana │
        └────┬────┘
             │ http://es01:9200  （compose 内部ネットワーク）
     ┌───────┼───────┐
     ▼       ▼       ▼
   es01    es02    es03     … 同じクラスタ名の3ノード
     │       │       │
   データ  データ  データ   … 名前付きボリュームで永続化
```

### 登場人物の意味

| 名前 | 役割 |
|------|------|
| **ノード（es01〜03）** | Elasticsearch の1プロセス＝1コンテナ。検索・保存の実働部隊 |
| **クラスタ** | 複数ノードが同じ `cluster.name` で協力している集団 |
| **Kibana** | ES をブラウザで見る UI。データ本体は持たない |
| **Compose ネットワーク** | コンテナ同士がサービス名（`es01` など）で名前解決できる仮想LAN |
| **名前付きボリューム** | コンテナを消してもデータが残る Docker 管理のディスク領域 |

### なぜ3ノードか

- 本番トレース・あとでノードを落として復旧を見る（カオス）ため
- 1ノードでも「ES + Kibana」は学べるが、**クラスタらしさ**は3ノードの方が体験できる
- レプリカ（コピー）を別ノードに置ける、など分散の話に進みやすい

### なぜセキュリティ OFF か

- 証明書・パスワード・Enrollment が一気に増える
- フェーズ1の目的は「Compose でクラスタを理解して安定起動」  
- ON はフェーズ2（Fleet とセット）で扱う

**注意:** セキュリティ OFF の ES をインターネットに晒さない。学習用・ローカルのみ。

---

## 2. メモリの考え方（ホスト32GBとの関係）

ホスト PC が 32GB でも、**全部を Elasticsearch に渡すわけではない。**

| 対象 | 推奨（フェーズ1） | 意味 |
|------|-------------------|------|
| 各 ES コンテナ | **2GB** 上限 | Docker がこのコンテナに許す上限 |
| 各 ES ヒープ | **1GB**（`-Xms1g -Xmx1g`） | Java が実際に使うヒープ。目安はコンテナの約半分 |
| Kibana | **1GB** 上限 | UI 用 |
| 合計の目安 | 約 **7GB** | 残りは OS / Docker / ブラウザ / IDE /（WSL なら GitLab 等） |

ヒープをコンテナ上限いっぱいにすると、OS やその他に足りず **突然落ちる**ことがある。  
「コンテナ 2GB・ヒープ 1GB」は学習用の安全寄りの定石に近い。

---

## 3. ホスト側の事前準備

### 3-1. Docker が使えること

**Windows（WSL Ubuntu）**

```bash
docker version
docker compose version
```

両方通ること。Compose が無い場合は以前入れた `docker-compose-v2` 等を確認。

**Mac（OrbStack）**

```bash
orb            # または orb start
docker version
docker compose version
```

### 3-2. `vm.max_map_count`（重要・なぜ必要か）

Elasticsearch は大量のメモリマップファイルを使う。  
Linux カーネルの `vm.max_map_count` が小さいと、**起動に失敗**したり不安定になる。

確認:

```bash
sysctl vm.max_map_count
```

`262144` 以上が目安。足りなければ（一時的）:

```bash
sudo sysctl -w vm.max_map_count=262144
```

永続化は OS によって違う（WSL は再起動で戻ることがある）。  
起動前に毎回確認する習慣が安全。

**Mac / OrbStack:** 裏側は Linux VM なので、OrbStack 側の設定やドキュメントに従い、同様に不足していないか確認する。値が足りないと ES だけ落ちる症状になりやすい。

公式解説: [vm.max_map_count](https://www.elastic.co/guide/en/elasticsearch/reference/8.5/vm-max-map-count.html)

### 3-3. 作業ディレクトリ（提案）

リポジトリ内の例:

```text
docker/stack/                 … フェーズ1用（名前は好みで可）
  docker-compose.yml
  .env
```

Compose 基礎練習の `compose-prac` とは分け、**本番トレース用スタック**として置くと後で迷わない。

---

## 4. 設定ファイルを書く前に理解すること

### 4-1. `.env` と compose の関係

- `.env` … 変数の置き場（版・メモリ・クラスタ名など）
- `docker-compose.yml` … `${STACK_VERSION}` のように変数を参照

**版を変えるとき**はイメージタグを compose に直書きするより、`.env` の `STACK_VERSION=8.5.2` を変える方が安全。

### 4-2. クラスタ形成に効く環境変数（ES）

| 変数 | 何をしているか |
|------|----------------|
| `node.name` | このノードの名前（es01 など） |
| `cluster.name` | 同じ名前同士だけが1つのクラスタになる |
| `discovery.seed_hosts` | 「最初に声をかける相手」の一覧 |
| `cluster.initial_master_nodes` | 初回クラスタ作成時にマスター候補と認めるノード（**初回だけ重要**） |
| `xpack.security.enabled=false` | 認証・TLS を使わない（フェーズ1） |
| `ES_JAVA_OPTS` | ヒープサイズなど JVM オプション |
| `bootstrap.memory_lock=true` | 可能ならメモリをロック（スワップ避け）。`ulimits.memlock` とセットで使うことが多い |

### 4-3. Kibana 側

| 変数 | 何をしているか |
|------|----------------|
| `ELASTICSEARCH_HOSTS` | どの ES に繋ぐか。compose 内なら `http://es01:9200` など |
| （Security OFF 時） | ユーザー／パスワードは基本不要 |

ブラウザから見るのは **ホストの 5601**。  
Kibana→ES の通信は **コンテナ間**なので、ブラウザ用 URL とは別物。

### 4-4. ポート

| ホスト側 | コンテナ側 | 用途 |
|----------|------------|------|
| 9200 | es01:9200 | ホストから ES を叩く（学習・curl） |
| 5601 | kibana:5601 | ブラウザで Kibana |

es02 / es03 の 9200 を全部ホストに出さなくても、クラスタ自体は内部ネットワークで動く。  
学習用に es01 だけホスト公開、で十分なことが多い。  
（WSL で **8080 が GitLab に取られる**ような話と同様、9200/5601 が空いているかは事前確認。）

### 4-5. ボリューム

- `esdata01` など … 各ノードのデータ永続化（名前付きボリューム）
- トップレベルの `volumes:` で名前を宣言し、各サービスで `名前:コンテナ内パス` をマウント

`docker compose down` ではデータは残り、`down -v` でボリュームも消える（Compose 基礎で学んだ通り）。

---

## 5. ファイル例（自分で作成・理解しながら調整）

以下は **ひな形**。そのまま盲目コピーせず、上記の表と対応づけて書くこと。  
（AI に丸投げせず、自分が `docker/stack/` 等に配置する。）

### 5-1. `.env` 例

```env
# 本番 Cloud に合わせた版（2026-10-16 時点）
STACK_VERSION=8.5.2

CLUSTER_NAME=es-lab

# ホストに出すポート
ES_PORT=9200
KIBANA_PORT=5601

# コンテナメモリ上限（Docker の mem_limit 用・バイトまたは 2g 形式は compose の書き方に合わせる）
# 例: 2g = 2147483648
MEM_LIMIT=2147483648
KIBANA_MEM_LIMIT=1073741824

# ヒープ（コンテナ2GBに対し1GB）
ES_JAVA_OPTS=-Xms1g -Xmx1g
```

### 5-2. `docker-compose.yml` の骨格（説明付き）

構成の要点だけ示す。完成形は公式 8.5 の Docker 章や、理解したうえで自分で3サービス分を並べる。

```yaml
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}
    container_name: es01
    environment:
      - node.name=es01
      - cluster.name=${CLUSTER_NAME}
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata01:/usr/share/elasticsearch/data
    ports:
      - ${ES_PORT}:9200
    mem_limit: ${MEM_LIMIT}
    # healthcheck は任意だが、Kibana の depends_on 条件に使える

  es02:
    # es01 と同様。node.name=es02、ports は省略可、volume は esdata02
    ...

  es03:
    # 同様に es03 / esdata03
    ...

  kibana:
    image: docker.elastic.co/kibana/kibana:${STACK_VERSION}
    container_name: kibana
    depends_on:
      - es01
    environment:
      - ELASTICSEARCH_HOSTS=http://es01:9200
      # Security OFF のためユーザー設定は基本不要
    ports:
      - ${KIBANA_PORT}:5601
    mem_limit: ${KIBANA_MEM_LIMIT}

volumes:
  esdata01:
  esdata02:
  esdata03:
```

**自分で書くときのチェックリスト**

- [ ] 3ノードとも同じ `cluster.name`
- [ ] `discovery.seed_hosts` に3つすべて
- [ ] `initial_master_nodes` に3つすべて（初回用）
- [ ] `xpack.security.enabled=false`（および http/transport ssl を無効にする必要がある場合あり）
- [ ] データ用ボリュームがノードごとに別
- [ ] Kibana のホストが `http://es01:9200`（https ではない）

公式の compose 例は **Security ON・証明書・setup コンテナ**付きが多い。  
フェーズ1ではそれを丸ごと使わず、**OFF 用に削った形**にする（takeo さんの Qiita は ON 寄りなので、証明書部分は今は追わない）。

---

## 6. 起動手順

作業ディレクトリ（compose がある場所）で実行。

### 6-1. 起動

```bash
# 推奨: 初回はログを見ながら
docker compose up
# またはバックグラウンド
docker compose up -d
```

**何が起きるか**

1. イメージが無ければ Docker Hub / Elastic レジストリから取得（大きい・回線次第で時間かかる）
2. ネットワーク・ボリューム作成
3. es01〜03 が起動し、互いに発見してクラスタ形成
4. Kibana が ES に接続

初回は特にイメージ取得がボトルネック。以前の `gradle` イメージと同様、**待ちと進捗の切り分け**を忘れない。

### 6-2. 状態確認

```bash
docker compose ps
docker compose logs -f es01
# 止めたいとき Ctrl+C（-d 起動なら logs だけ終了）
```

### 6-3. クラスタ確認（ES）

ホストから（es01 の 9200 を出している場合）:

```bash
curl -s http://127.0.0.1:9200
curl -s http://127.0.0.1:9200/_cat/nodes?v
curl -s http://127.0.0.1:9200/_cluster/health?pretty
```

期待:

- `nodes` に **3行**（es01, es02, es03）
- `status` が `green` またはしばらくして `green`／学習用なら `yellow` の意味も後で学ぶ

コンテナ内からでも可:

```bash
docker compose exec es01 curl -s http://localhost:9200/_cat/nodes?v
```

### 6-4. Kibana 確認

ブラウザ:

- 同じマシンなら `http://localhost:5601`
- WSL の場合、Windows 側ブラウザから見えることが多い（見えなければ WSL の IP や portproxy を疑う）

Security OFF のため、ログインを求められない／簡易な場合がある（版や設定による）。

### 6-5. 停止・削除

```bash
docker compose down          # コンテナ停止・削除。データボリュームは残る
docker compose down -v       # ボリュームも削除（データ消える・初期化やり直し向け）
```

---

## 7. つまずきやすい点

| 症状 | まず疑うこと |
|------|----------------|
| ES が即 Exit | `vm.max_map_count`、メモリ不足、`docker compose logs es01` |
| ノードが1つしか見えない | `cluster.name` の不一致、`seed_hosts` 誤記、起動タイミング |
| Kibana が ES に繋がらない | `ELASTICSEARCH_HOSTS` が `https` になっていないか、es01 未起動 |
| ポート already in use | 別プロセスが 9200/5601 を使用（以前の GitLab と 8080 の話と同種） |
| イメージ pull が極端に遅い | 回線・レジストリ。小さいイメージで切り分けてから再試行 |
| Mac と WSL で挙動差 | OrbStack 起動有無、`max_map_count`、メモリ割り当て |

メモリ不足の典型ログ例: `Elasticsearch exited unexpectedly`  
→ `MEM_LIMIT` / ヒープを見直すか、他の重いコンテナ（GitLab 等）を止める。

---

## 8. 学習の進め方（ブラックボックス防止）

1. **要件表**（`zentai-keikaku.md` §5）を見ながらファイルを書く  
2. 起動したら `_cat/nodes` で「3台いる」を自分の目で確認  
3. 意図的に `docker compose stop es03` し、ノード数がどう変わるか見る（カオスの予行）  
4. 分からない環境変数は、公式ドキュメントでそのキー名を検索してから残す  
5. Qiita の古い版・Security ON の手順と、自分のフェーズ1要件が食い違う箇所は **自分の要件を優先**

---

## 9. フェーズ1のあとにやること（予告のみ）

- Security ON（証明書・パスワード）
- Fleet（本番に近づける）
- ILM / アラート / 本格的なノード障害試験  

土台が「説明できる状態」になってから進む。

---

## 10. チェックリスト（印刷・コピー用）

- [ ] `docker` / `docker compose` が使える（WSL または OrbStack）
- [ ] `vm.max_map_count` ≥ 262144
- [ ] `.env` に `STACK_VERSION=8.5.2`
- [ ] compose に es01/es02/es03 + kibana
- [ ] Security 関連は OFF
- [ ] メモリ: ES 2GB/ヒープ1GB、Kibana 1GB 前後
- [ ] `docker compose up -d` 成功
- [ ] `_cat/nodes` で3ノード
- [ ] Kibana 表示
- [ ] `down` / `up` で再現確認

---

改訂履歴

- 2026-10-16 … フェーズ1要件確定に基づき初版（Security/Fleet 除外、8.5.2、3ノード）
