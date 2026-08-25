# Mac

## Multipass

```bash
# インストール
brew install --cask multipass

# バージョン確認
multipass version

# 動作テスト
multipass launch -n test-vm -c 1 -m 1G -d 5G
multipass list
multipass shell test-vm

# 削除
multipass delete --purge test-vm
```

## Ansible

```bash
# インストール
sudo apt update
sudo apt install ansible
ansible --version

# 動作テスト
ansible localhost -m ping -c local
```

## WSL（Ubuntu 22.04）

apt の Ansible は 2.10 のままなので、作り込みには使わない。ホスト用に 2.17 をユーザー領域へ入れてある。

```bash
python3 -m pip install --user 'ansible-core>=2.17.0,<2.18.0'
export PATH="$HOME/.local/bin:$PATH"
ansible --version   # ansible [core 2.17.x] であること
```

作り込みの実行場所は `es-controller`（`bash scripts/controller-ansible-run.sh`）。WSL の Ansible は VM 作成などホスト作業用。

---



## 次の進め方の目安（Agent → メトリクス → Osquery → 資産台帳）

いまの疑似ログ + Filebeat + Kibana グラフまで一段落したあとの拡張ルート。  
方針: **Elastic Agent + Osquery** で版つき資産台帳を目指す。学習順はメトリクスを先に通す。

### 1. Agent / メトリクス（土台）

1. **es-stack 側で Fleet / セキュリティの準備**
  - いまの lab は検証用にセキュリティ off。Fleet / Agent 利用時は有効化がほぼ必要  
  - Fleet Server・Enrollment（登録）の準備
2. **target（または es-stack）に Agent を入れてメトリクス**
  - System などの Integration で CPU / メモリ等を収集
3. **Kibana でホストの CPU などが見えることを確認**
  - Agent → ES の経路が通ったことの確認（ここで一度区切る）



### 2. Osquery（版情報の収集）

1. **同じ Agent に Osquery Integration を追加**
2. パッケージ一覧クエリ（例: `deb_packages`）で name / version が取れることを確認
3. 結果が Elasticsearch に入ること・Kibana Discover で見えることを確認



### 3. 資産管理台帳（そのあと）

1. **台帳用のデータの形を決める**
  - 例: ホスト / ソフトウェア名 / バージョン / 取得時刻  
  - 全部のパッケージか、監視対象リストだけか（最初は対象を絞ると見やすい）
2. **Osquery の定期実行・保存先インデックスを整える**
  - ログ用 `filebeat-*` とは別に、台帳用の見え方（Data view）を用意
3. **Kibana で「一目でわかる」表示を作る**
  - Discover の表、または Lens / Dashboard  
  - 例: ホスト別ソフト一覧、ソフト別バージョン一覧
4. **運用ルールを決める**
  - 更新頻度（1日1回など）  
    - IP 変更時は Agent / Fleet の接続先も見直す（Filebeat と同様の注意）



### 補足

- メトリクス = Agent 向き。版つき台帳 = Agent だけでは不足しやすく、Osquery（またはスクリプト等）が必要  
- Ansible でも台帳は作れるが、本メモの方針は Agent + Osquery  
- 台帳だけ最短で欲しい場合の代替: target 上のスクリプトで `dpkg-query` → ES（Agent なし）

**手順と「何をしているか」の説明:** [`agent-osquery-tejun.md`](./agent-osquery-tejun.md)  
**フェーズ A の詳細（このファイル下部）と単体メモ:** [`phase-a-fleet-security.md`](./phase-a-fleet-security.md)

---



## フェーズ A 詳細手順（セキュリティ + Fleet）

**ゴール:** Kibana にログインでき、Fleet が使え、Fleet Server が動き、Enrollment token と Fleet URL を控えた状態。  
**Fleet 用の追加 VM は不要**（Fleet Server は既存の `es-stack` に置く）。

単体メモ（内容はこちらと揃える想定）: [`phase-a-fleet-security.md`](./phase-a-fleet-security.md)

### パート構成

| パート | やること |
|--------|----------|
| **用語** | 先に読むと後が楽になる言葉の整理 |
| **0** | 事前確認・Filebeat 停止の了承・`<ES_STACK_IP>` 控え |
| **A1** | ES に認証 + TLS。`elastic` パスワード設定 |
| **A2** | Kibana を https ES に接続。ブラウザで `elastic` ログイン |
| **A3** | Fleet → Fleet Server（es-stack）→ token / URL 控え |
| **A4** | Filebeat が 401 等で止まっていることを確認（予想どおり） |

---

### 用語と全体像（ここを読んでから手を動かす）

いまの lab は「9200 / 5601 に誰でも届く」状態に近い。フェーズ A では次の **2 層**を入れる。

```text
【層1】認証（Authentication）
  「あなたは誰？ パスワードは？」
  → elastic / kibana_system などのユーザーとパスワード

【層2】暗号化（TLS / HTTPS）
  「通信の途中で覗かれないようにする」
  → 証明書（身分証）を使って https:// で話す
```

Fleet / Agent はだいたいこの 2 層がある前提で設計されている。だから「Agent だけ先に入れる」より、**先に ES 側の扉を整える**のがフェーズ A。

| 言葉 | たとえ | この手順での意味 |
|------|--------|------------------|
| **認証** | マンションのオートロック | ユーザー名とパスワードがないと ES に入れない |
| **TLS / SSL / HTTPS** | 封筒に入れて郵便を出す | `http://` ではなく `https://`。中身が暗号化される |
| **証明書（certificate）** | 身分証 | 「このサーバは本当に es-stack の ES です」と主張する電子ファイル |
| **CA（Certificate Authority）** | 身分証の発行元・印鑑 | ラボ専用の「偽の役所」。自分で作った CA がノード証明書に署名する |
| **ノード証明書** | 各サーバの身分証 | この手順では ES 用に 1 枚作る（単一ノード lab） |
| **`.p12` / PKCS#12** | 身分証と印鑑をまとめた金庫ファイル | 秘密鍵＋証明書が一つのファイルに入っている形式。Elastic がよく使う |
| **keystore** | 「自分の身分証を出す引き出し」 | ES がクライアントに「これが私の証明書です」と見せるときに読む |
| **truststore** | 「誰の身分証を信じるかのリスト」 | 相手の証明書が信頼できるか判定するときに読む。lab では同じ `.p12` を兼用することが多い |
| **HTTP SSL** | ブラウザや curl・Kibana・Filebeat が 9200 に来る道 | 外から ES に来る通信の暗号化 |
| **Transport SSL** | ES ノード同士が話す道 | 複数ノード用。単一ノードでもセキュリティ有効時は設定が必要になりやすい |
| **自己署名（self-signed）** | 自分で作った身分証 | 公的な認証局ではなく自前 CA。ブラウザや curl は「知らない発行元」と警告する → lab では `-k` などで例外扱い |
| **`elastic` ユーザー** | 管理人のマスターキー | 管理用スーパーユーザー。ブラウザで Kibana に入るときなど |
| **`kibana_system` ユーザー** | Kibana サーバ専用の社員証 | **人が**ログインする用ではない。Kibana プロセスが裏で ES に繋ぐとき専用 |
| **Fleet** | 司令塔の事務室（Kibana 画面） | Agent の名簿と「何を集めろ」の指示書（ポリシー）を置く |
| **Fleet Server** | 受付窓口 | Agent が実際に接続する先（ポート 8220 が多い）。中身は Elastic Agent の一種 |
| **Enrollment token** | 入館パス（合言葉） | 「このラボの Fleet に入ってよい」という一時的な許可証 |

証明書まわりの流れ（A1-3 でやること）:

```text
1. CA を作る          → elastic-stack-ca.p12
2. CA がノード証明書に署名 → elastic-certificates.p12
3. 両方を /etc/elasticsearch/certs/ に置く
4. elasticsearch.yml で「この .p12 を使え」と指定
5. ES 起動 → https://9200 で待ち受け
```

**パスワードと証明書は別物:**

- 証明書 / TLS → 「通信路が暗号化されているか・相手は本物か」
- パスワード → 「その通信路の先で、誰として操作するか」

両方そろって初めて「鍵のかかった扉＋誰か分かる入室」になる。

---

### 0. 始める前

#### 0-1. 何が変わるか

| いま | フェーズ A のあと |
|------|-------------------|
| ES にパスワードなしで接続 | ユーザー / パスワード（や証明書）が必要 |
| Kibana も実質だれでも開けることが多い | Kibana ログインが必要 |
| Filebeat が `http://es-stack:9200` に直送 | **認証なしでは送れなくなる**（疑似ログが止まる） |
| Fleet 未使用 | Fleet / Fleet Server を使う土台ができる |

**何をしているか:** Agent / Fleet は「誰でも書き込める ES」を前提にしない。先に鍵を付け、Fleet の受付を置く。

#### 0-2. すすめる前の確認（必須）

変更前に「いま動いている」ことを確認する。壊れたあとに「もともと死んでいたのか、自分が壊したのか」が分からなくなるのを防ぐ。

```bash
multipass.exe list
multipass.exe exec es-stack -- curl -sS --max-time 5 http://127.0.0.1:9200
multipass.exe exec es-stack -- curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

| コマンドの意味 | |
|----------------|--|
| `multipass.exe list` | VM が Running か、IP は何か |
| `curl ... 9200` | ES が応答するか（いまは http で JSON が返る想定） |
| `curl ... 5601` の `%{http_code}` | Kibana の HTTP ステータス（200 など）だけ表示 |

- `es-stack` が Running / ES が JSON / Kibana が応答 → ここまでできてから先へ

#### 0-3. 意思決定

1. **疑似ログ（Filebeat）は一時停止してよい** → この手順どおり進める  
2. **疑似ログを絶対に止めたくない** → Filebeat 用ユーザー設計などが先（難易度↑）

この手順は **1 向け**。セキュリティを入れると Filebeat の「認証なし http」は通らなくなる。復旧は A のあと別作業（ユーザー作成＋Filebeat 設定変更）。

#### 0-4. IP を控える

```bash
multipass.exe list
```

`es-stack` の IPv4 をメモ（以降 `<ES_STACK_IP>`）。  
Windows ブラウザから Kibana を開くとき、target の Agent が Fleet に繋ぐときに使う。  
`multipass stop` / 再起動のあと **IP が変わる**ことがあるので、止まるたびに `list` で見直す。

---

### パート A1: Elasticsearch のセキュリティを有効にする

**やること:** `es-stack` 上の ES に認証と HTTPS（TLS）を入れる。  
**何をしているか:** 「誰でも 9200」をやめ、正規ユーザーだけにする（Fleet の前提）。

```bash
multipass.exe shell es-stack
```

`shell` = その VM の中に入って Ubuntu のシェルを使う。以降は `ubuntu@es-stack` 前提。

#### A1-1. サービスを止める

```bash
sudo systemctl stop kibana
sudo systemctl stop elasticsearch
```

**なぜ止めるか:** 動いたまま設定ファイルや証明書を差し替えると、途中状態で読み込まれたり起動に失敗したりする。Kibana は ES に依存するので先に止める。

`systemctl` = Linux のサービス管理。`stop` で停止、あとで `start` / `status` を使う。

#### A1-2. 証明書用ディレクトリ

```bash
sudo mkdir -p /etc/elasticsearch/certs
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/certs
```

| 操作 | 意味 |
|------|------|
| `mkdir -p` | ディレクトリ作成（既にあってもエラーにしない） |
| `/etc/elasticsearch/certs` | ES の設定の近くに証明書を置く定番の場所 |
| `chown elasticsearch:elasticsearch` | 所有者を ES の実行ユーザーにする |

Elasticsearch は専用ユーザー `elasticsearch` で動く。権限が足りないと「証明書が読めない」で起動失敗する。

#### A1-3. CA とノード証明書を作る

ここが一番「何をしているか」が分かりにくいところ。順に読む。

**道具:** `elasticsearch-certutil`  
Elastic 公式の証明書作成ツール。OpenSSL を手で叩かなくても、ES が欲しがる形式（`.p12`）を出しやすい。

```bash
cd /tmp
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil ca --out /tmp/elastic-stack-ca.p12 --pass ""
```

| 引数 | 意味 |
|------|------|
| `ca` | 「認証局（CA）を作れ」 |
| `--out ...` | 出力ファイル名 |
| `--pass ""` | CA ファイル自体のパスワードを空にする（lab 簡易。本番では強いパスを付ける） |

これで **ラボ専用の印鑑（CA）** ができる。まだ「どのサーバの身分証」ではない。

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
  --ca /tmp/elastic-stack-ca.p12 --ca-pass "" \
  --name es-stack \
  --dns es-stack \
  --ip 127.0.0.1 \
  --ip "$(hostname -I | awk '{print $1}')" \
  --out /tmp/elastic-certificates.p12 --pass ""
```

| 引数 | 意味 |
|------|------|
| `cert` | 「ノード用証明書を作れ」 |
| `--ca` / `--ca-pass` | さっきの CA で署名する（空パス） |
| `--name es-stack` | 証明書の名前（識別用） |
| `--dns es-stack` | 「ホスト名 es-stack でもアクセスしてよい」と証明書に書く（SAN） |
| `--ip 127.0.0.1` | localhost 向け |
| `--ip "$(hostname -I ...)"` | いまの VM の実 IP も証明書に載せる |
| `--out` / `--pass ""` | 出力とパスワード（lab は空） |

**SAN（Subject Alternative Name）とは:**  
証明書に「この名前／この IP なら正規」と書いておく欄。接続先（`https://127.0.0.1` や `https://172.x.x.x`）が証明書の記載と食い違うと、クライアントが「別人の可能性がある」と拒否することがある。だから DNS 名と IP を両方書いておく。

**なぜ CA とノード証明書の 2 つ？**

```text
CA          … 「この印鑑で押した身分証は信じる」というルールの元
ノード証明書 … 実際に ES が提示する身分証（CA が署名済み）
```

本番では社内 CA や公開 CA を使うことが多い。lab では自分で両方作る。

配置:

```bash
sudo cp /tmp/elastic-stack-ca.p12 /tmp/elastic-certificates.p12 /etc/elasticsearch/certs/
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/certs/*.p12
sudo chmod 600 /etc/elasticsearch/certs/*.p12
```

| 操作 | 意味 |
|------|------|
| `cp` | `/tmp`（作業場）から正式な置き場へコピー |
| `chown` | ES が読める所有者に |
| `chmod 600` | 所有者だけ読み書き。秘密鍵入りなので他ユーザーに読ませない |

#### A1-4. elasticsearch.yml を編集

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak.phase-a
sudo nano /etc/elasticsearch/elasticsearch.yml
```

**バックアップの意味:** 失敗したとき `.bak.phase-a` に戻せる。ロールバック用。

既存の `xpack.security.enabled: false` などは削除または上書き。最低限:

```yaml
xpack.security.enabled: true
xpack.security.enrollment.enabled: true

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: certs/elastic-certificates.p12

xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12
```

| 設定 | 意味 |
|------|------|
| `xpack.security.enabled: true` | セキュリティ機能をオン（認証などが有効） |
| `enrollment.enabled: true` | ノードや Kibana を「登録トークン」で繋ぎやすくする（公式の簡易導線） |
| `http.ssl.enabled: true` | 9200 を HTTPS にする |
| `http.ssl.keystore.path` | クライアントに見せる証明書の場所（`/etc/elasticsearch/` からの相対パス） |
| `http.ssl.truststore.path` | 信頼判定用。lab では同じファイルを指定することが多い |
| `transport.ssl.*` | ノード間通信用 TLS。単一ノードでも有効化することが多い |
| `verification_mode: certificate` | 相手証明書の検証の厳しさ（certificate = 証明書の妥当性を見るレベル） |

`cluster.name` / `node.name` / `network.host` / `http.port` / `discovery.type` / `path.data` / `path.logs` は残してよい（クラスタ名・待ち受け・データ場所など、セキュリティ以外の基本設定）。

YAML は字下げが意味を持つ。スペースの揃えを崩さないこと。  
nano の保存: Ctrl+O → Enter → Ctrl+X。

#### A1-5. Elasticsearch 起動

```bash
sudo systemctl start elasticsearch
sudo systemctl status elasticsearch --no-pager
```

`--no-pager` = 画面いっぱいのページャーに入らず、そのまま表示して終わる（コピペしやすい）。

失敗時:

```bash
sudo journalctl -u elasticsearch -n 80 --no-pager
```

`journalctl` = サービスのログ。証明書パス違い・権限・yml の字下げミスがここに出やすい。

```bash
sleep 20
curl -sk https://127.0.0.1:9200
```

| オプション | 意味 |
|------------|------|
| `-s` | 進捗メーターを出さない |
| `-k` | 証明書の検証を緩める（自己署名 CA を「知らない」と拒否されないようにする） |
| `https://` | もう http ではない |

この時点ではパスワード未設定だと「認証が必要」系の応答になることがある。**プロセスが落ちていなければ**次へ進んでよい。

#### A1-6. elastic ユーザーのパスワード

セキュリティを有効にすると、組み込みユーザーのパスワードを決める必要がある。

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

| 引数 | 意味 |
|------|------|
| `-u elastic` | 対象ユーザー |
| `-i` | 対話で自分でパスワードを入力 |
| `-b` | 自動生成して画面に出す（控える） |

控えた値を `<ELASTIC_PASSWORD>` とする。忘れると Kibana ログインや管理操作ができなくなる（再実行でリセット可）。

確認:

```bash
curl -sk -u elastic:'<ELASTIC_PASSWORD>' https://127.0.0.1:9200
```

`-u user:pass` = HTTP Basic 認証（ユーザー名とパスワードを付ける）。  
クラスタ名などが JSON で返れば **A1 完了**（TLS の道＋認証の両方が通った）。

---

### パート A2: Kibana をセキュリティ付き ES に繋ぐ

**やること:** Kibana が「https + 認証付きの ES」を見に行くようにする。  
**何をしているか:** ブラウザ用 UI も、鍵なしでは ES を読めない状態に合わせる。

役割の分離（ここが混乱しやすい）:

```text
【人がブラウザでログイン】
  ユーザー: elastic（など）
  → Kibana の画面に入る

【Kibana サーバ自身が ES に繋ぐ】
  ユーザー: kibana_system
  → 設定ファイルに書いたパスワードで、裏で ES API を叩く
```

同じ「ログイン」でも、人が使う鍵とサーバが使う鍵は別。

#### A2-1. kibana.yml

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak.phase-a
sudo nano /etc/kibana/kibana.yml
```

```yaml
server.host: "0.0.0.0"
server.port: 5601

elasticsearch.hosts: ["https://127.0.0.1:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.ssl.verificationMode: none

i18n.locale: "ja-JP"
```

| 設定 | 意味 |
|------|------|
| `server.host: "0.0.0.0"` | VM の外（Windows ブラウザ）から 5601 に届くように全インタフェースで待つ |
| `elasticsearch.hosts` | Kibana が繋ぐ ES。**http → https** に変える |
| `elasticsearch.username` | 裏接続用ユーザー |
| `verificationMode: none` | 自己署名証明書を厳しく検証しない（lab 簡易。本番では CA を正しく信頼させる） |
| `i18n.locale` | 日本語 UI（既に入れているなら維持） |

`kibana_system` のパスワード:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

控えた `<KIBANA_SYSTEM_PASSWORD>` を yml に追加:

```yaml
elasticsearch.password: "<KIBANA_SYSTEM_PASSWORD>"
```

（Enrollment token で Kibana を設定する方法もあるが、lab では明示設定の方が追いやすい。）

#### A2-2. Kibana 起動

```bash
sudo systemctl start kibana
sudo systemctl status kibana --no-pager
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

Kibana は起動が遅く、1〜3 分かかることがある。`200` や `302`（リダイレクト）が出るまで待つ。  
ブラウザ向けの Kibana 自体は、この lab では当面 `http://` のままでよい（ES との間だけ https）。

#### A2-3. ブラウザでログイン

Windows のブラウザで `http://<ES_STACK_IP>:5601`

- ユーザー: `elastic`  
- パスワード: `<ELASTIC_PASSWORD>`（A1-6）  

ホーム画面が出れば **A2 完了**。  
ログイン画面が出ない・赤いエラーなら、Kibana → ES の裏接続（kibana_system / https）を疑う。

---

### パート A3: Fleet と Fleet Server

**やること:** Kibana の Fleet で受付係（Fleet Server）を用意する。  
**何をしているか:** あとで各 VM の Agent が「登録しに来る先」を作る。

Filebeat との違い:

```text
【Filebeat（いままで）】
  各 target の設定ファイルに「ES の住所」を直書き
  → 中央からの指示は弱い

【Fleet + Agent（これから）】
  Agent はまず Fleet Server に登録
  → Kibana の Fleet 画面で「何を集めろ」を変えられる
```

#### A3-1. Fleet を開く

Kibana（ログイン済み）→ 左メニュー（三本線）→ **Management（管理）** → **Fleet**

初回は案内ウィザードが出ることがある。進める。  
ここが「Agent の名簿とポリシー（指示書）の事務室」。

#### A3-2. Fleet Server を追加

1. **Add Fleet Server**（Fleet Server を追加）  
2. 配置は **Quick start**（同一ホスト簡易）でよい（lab）  
3. ホスト名 / IP は **`<ES_STACK_IP>`** が使われる想定  
4. 表示された **Elastic Agent のインストールコマンド**を控える  

そのコマンドは **es-stack 上で**実行する（Fleet Server は es-stack に置く。新 VM 不要）:

```bash
multipass.exe shell es-stack
# 画面に出た install コマンドを貼り付けて実行（sudo 付きのことが多い）
```

**何が起きるか:** es-stack に Elastic Agent が入る。その Agent が「Fleet Server」役になり、他の Agent 向けの受付（だいたいポート **8220**）を開く。

#### A3-3. 健全性確認

Fleet 画面で:

- Fleet Server が **Healthy**（または Connected）  
- Agents 一覧に fleet-server 相当が見える  

es-stack 上:

```bash
sudo elastic-agent status
# または
sudo systemctl status elastic-agent --no-pager
ss -lntp | grep 8220 || sudo ss -lntp | grep 8220
```

| 確認 | 意味 |
|------|------|
| `elastic-agent status` | Agent（＝Fleet Server 役）の内部状態 |
| `ss ... 8220` | 受付ポートが LISTEN しているか |

#### A3-4. Enrollment 情報を控える（フェーズ B 用）

Fleet → **Enrollment tokens**（または Add agent 画面）で控える。

| 項目 | 例 | 意味 |
|------|-----|------|
| Fleet URL | `https://<ES_STACK_IP>:8220` | Agent が繋ぐ受付の住所。IP 変更に注意 |
| Enrollment token | 長い文字列 | 入館パス。期限切れのことがある |

任意で `group_vars` メモ例（あとで Ansible 化するとき用）:

```yaml
elasticsearch_lab_security_enabled: true
fleet_enable: true
fleet_url: "https://<ES_STACK_IP>:8220"
fleet_enrollment_token: "<TOKEN>"
```

いまは控えるだけでよい。playbook の自動適用は未整備でもフェーズ A のゴールは達成できる。

---

### パート A4: Filebeat の副作用確認

セキュリティを入れた結果、古い Filebeat（認証なし http）は拒否される想定。

```bash
multipass.exe exec es-target-01 -- sudo bash -lc 'tail -n 20 $(ls -t /var/log/filebeat/*.ndjson | head -1)'
```

`401` / `unauthorized` / TLS エラーなら **予想どおり**（壊したというより、鍵を付けたので古い鍵なしクライアントが弾かれた）。  
疑似ログの復旧は、ES に書き込み可能なユーザーを用意し、Filebeat の `output.elasticsearch` にユーザー・パスワード・https を書く別作業。

---

### フェーズ A 完了チェックリスト

- [ ] `curl -sk -u elastic:'...' https://127.0.0.1:9200` が ES 情報を返す  
- [ ] ブラウザで Kibana に `elastic` ログインできる  
- [ ] Fleet メニューがある  
- [ ] Fleet Server が Healthy（近い状態）  
- [ ] Fleet URL と Enrollment token を控えた  

全部 Yes → フェーズ B（Agent + メトリクス）。

### うまくいかないとき

| 症状 | まず疑うこと |
|------|----------------|
| elasticsearch が起動しない | `journalctl -u elasticsearch`、証明書パス、`chown`/`chmod`、yml の字下げ |
| curl https 失敗 | `-k` を付けたか、まだ `http://` で叩いていないか、ssl 設定ミス |
| Kibana が赤 / 起動しない | kibana_system のパスワード、`hosts` が https か、verificationMode |
| Fleet が出ない | ライセンス表示や権限。一度ログアウトして `elastic` で再ログイン |
| Fleet Server Unhealthy | 8220、ES への認証、install を **es-stack** で実行したか |
| ブラウザで届かない | `<ES_STACK_IP>` が `multipass.exe list` の最新か |

詰まったら、**どのパートの何番まで終わったか**とエラー全文を残す。

### ロールバック（概要）

- `elasticsearch.yml.bak.phase-a` / `kibana.yml.bak.phase-a` を戻してサービス再起動  
- または `bash scripts/vms-delete.sh` → `vms-create.sh` → `controller-ansible-run.sh` でセキュリティ off の初期 lab に戻す

