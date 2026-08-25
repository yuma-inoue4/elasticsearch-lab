# フェーズ A 詳細手順: セキュリティ + Fleet の準備

対象: `agent-osquery-tejun.md` のフェーズ A を、画面・コマンド単位で進める人向け。  
前提 VM: `es-stack` / `es-target-*` / `es-controller`（改訂案の Multipass 構成）

**ゴール:** Kibana にログインでき、**Fleet** 画面が使え、**Fleet Server** が動き、あとで Agent を登録するための **Enrollment token** と **Fleet URL** が控えてある状態。

**同一内容の控え（setup-memo にも追記あり）:** [`setup-memo.md`](./setup-memo.md) の「フェーズ A 詳細手順」節。

### パート構成

| パート | やること |
|--------|----------|
| **0** | 事前確認・Filebeat 停止の了承・`<ES_STACK_IP>` 控え |
| **A1** | ES に認証 + TLS。`elastic` パスワード設定 |
| **A2** | Kibana を https ES に接続。ブラウザで `elastic` ログイン |
| **A3** | Fleet → Fleet Server（es-stack・追加 VM 不要）→ token / URL 控え |
| **A4** | Filebeat が 401 等で止まっていることを確認（予想どおり） |

---

## 0. 始める前に読むこと

### 0-1. 何が変わるか

| いま | フェーズ A のあと |
|------|-------------------|
| ES にパスワードなしで接続 | ユーザー / パスワード（や証明書）が必要 |
| Kibana も実質だれでも開けることが多い | Kibana ログインが必要 |
| Filebeat が `http://es-stack:9200` に直送 | **認証なしでは送れなくなる**（疑似ログが止まる） |
| Fleet 未使用 | Fleet / Fleet Server を使う土台ができる |

**何をしているか:**  
Agent / Fleet は「誰でも書き込める ES」を前提にしない。だから先に扉に鍵（セキュリティ）を付け、その鍵付きの玄関に Fleet の受付（Fleet Server）を置く。

### 0-2. すすめる前の確認（必須）

WSL で:

```bash
multipass.exe list
multipass.exe exec es-stack -- curl -sS --max-time 5 http://127.0.0.1:9200
multipass.exe exec es-stack -- curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

- `es-stack` が Running  
- ES が JSON を返す  
- Kibana が `200` など応答する  

ここまでできてから先へ。

### 0-3. 意思決定（ここで止めて考えてよい）

次のどちらにするか決める。

1. **疑似ログ（Filebeat）は一時停止してよい** → この手順どおり A を進める  
2. **疑似ログを絶対に止めたくない** → 先に Filebeat 用ユーザー設計や、別 ES を用意する必要がある（難易度が上がる）

この手順は **1 を選んだ人向け**（学習用）。Filebeat は A のあとで認証付きに直す別作業になる。

### 0-4. IP を控える

```bash
multipass.exe list
```

`es-stack` の IPv4 をメモする（例: `172.26.x.x`）。  
以降 `<ES_STACK_IP>` と書く。

---

## パート A1: Elasticsearch のセキュリティを有効にする

**やること:** `es-stack` 上の Elasticsearch に認証と HTTPS（TLS）を入れる。  
**何をしているか:** 「誰でも 9200 に入れる」状態をやめ、正規のユーザーだけが入れるようにする。Fleet の前提条件。

作業は **es-stack の中**で行う。

```bash
multipass.exe shell es-stack
```

（以降、プロンプトが `ubuntu@es-stack` になった前提）

### A1-1. サービスを止める

```bash
sudo systemctl stop kibana
sudo systemctl stop elasticsearch
```

**何をしているか:** 設定ファイルと証明書を入れ替える間、書き込みを止める。

### A1-2. 証明書用ディレクトリを用意する

```bash
sudo mkdir -p /etc/elasticsearch/certs
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/certs
```

### A1-3. CA とノード証明書を作る

```bash
cd /tmp
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil ca --out /tmp/elastic-stack-ca.p12 --pass ""
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
  --ca /tmp/elastic-stack-ca.p12 --ca-pass "" \
  --name es-stack \
  --dns es-stack \
  --ip 127.0.0.1 \
  --ip "$(hostname -I | awk '{print $1}')" \
  --out /tmp/elastic-certificates.p12 --pass ""

sudo cp /tmp/elastic-stack-ca.p12 /tmp/elastic-certificates.p12 /etc/elasticsearch/certs/
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/certs/*.p12
sudo chmod 600 /etc/elasticsearch/certs/*.p12
```

**何をしているか:**  
- **CA** = 証明書の発行元（このラボ用の印鑑）  
- **ノード証明書** = 「このサーバは正規の ES です」という身分証  
HTTPS で ES に繋ぐときに使う。

### A1-4. elasticsearch.yml を編集する

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak.phase-a
sudo nano /etc/elasticsearch/elasticsearch.yml
```

**セキュリティ関連を次の方針にする**（既存の `xpack.security.enabled: false` などは削除または上書き）。

最低限、次が入っていること:

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

もともとある次は残してよい:

- `cluster.name` / `node.name` / `network.host` / `http.port` / `discovery.type` / `path.data` / `path.logs`

**何をしているか:**  
「セキュリティ機能を使う」「HTTP もノード間も TLS で保護する」と ES に宣言している。

保存して nano を抜ける（Ctrl+O → Enter → Ctrl+X）。

### A1-5. Elasticsearch を起動して状態確認

```bash
sudo systemctl start elasticsearch
sudo systemctl status elasticsearch --no-pager
```

起動に失敗したら:

```bash
sudo journalctl -u elasticsearch -n 80 --no-pager
```

証明書パスや yml のインデントミスが多い。

成功確認（まだパスワード未設定だと挙動が版により違う。起動していれば先へ）:

```bash
sleep 20
curl -sk https://127.0.0.1:9200
```

### A1-6. elastic ユーザーのパスワードを設定する

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

対話でパスワードを入力する。**必ず控える**（以降 `<ELASTIC_PASSWORD>`）。

自動生成に任せる場合:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b
```

表示されたパスワードを控える。

確認:

```bash
curl -sk -u elastic:'<ELASTIC_PASSWORD>' https://127.0.0.1:9200
```

クラスタ名などが JSON で返れば **A1 完了**。

**何をしているか:**  
管理者ユーザー `elastic` の鍵を決めた。これ以降の操作・Kibana・（将来の）Filebeat はこの鍵を使う。

---

## パート A2: Kibana をセキュリティ付き ES に繋ぐ

**やること:** Kibana が HTTPS + 認証付きの ES を見に行くようにする。  
**何をしているか:** ブラウザ用 UI も、鍵なしでは ES を読めない状態に合わせる。

### A2-1. kibana.yml を編集する

まだ `multipass.exe shell es-stack` の中で:

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak.phase-a
sudo nano /etc/kibana/kibana.yml
```

次を反映する（既存の `elasticsearch.hosts: ["http://..."]` は置き換え）:

```yaml
server.host: "0.0.0.0"
server.port: 5601

elasticsearch.hosts: ["https://127.0.0.1:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.ssl.verificationMode: none

i18n.locale: "ja-JP"
```

`kibana_system` のパスワードも設定する:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

控えたパスワードを `<KIBANA_SYSTEM_PASSWORD>` とする。

kibana.yml に追加:

```yaml
elasticsearch.password: "<KIBANA_SYSTEM_PASSWORD>"
```

**何をしているか:**  
Kibana 専用ユーザーで ES にログインさせる。ブラウザで Kibana を開く人と、Kibana サーバ自身が ES に繋ぐ人は別、という役割分担。

（Enrollment token で Kibana を設定する方法もあるが、lab では上記の明示設定の方が追いやすい。）

### A2-2. Kibana を起動する

```bash
sudo systemctl start kibana
sudo systemctl status kibana --no-pager
```

待ち時間は長いことがある（1〜3 分）:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

`200` や `302` が出るまで待つ。

### A2-3. ブラウザでログインする

Windows のブラウザで:

```text
http://<ES_STACK_IP>:5601
```

- ユーザー: `elastic`  
- パスワード: `<ELASTIC_PASSWORD>`  

ホーム画面が出れば **A2 完了**。

---

## パート A3: Fleet を開き、Fleet Server を立てる

**やること:** Kibana の Fleet で受付係（Fleet Server）を用意する。  
**何をしているか:** あとで各 VM の Agent が「登録しに来る先」を作る。Filebeat のように各ホストが勝手に設定ファイルだけで完結するのではなく、**中央（Fleet）が指示を出す**形にする。

### A3-1. Fleet 画面を開く

Kibana（ログイン済み）で:

1. 左メニュー（三本線）  
2. **Management（管理）**  
3. **Fleet**

初回は案内が出ることがある。進める。

**何をしているか:** Agent の名簿とポリシー（指示書）を管理する画面に入った。

### A3-2. Fleet Server を追加する

画面の案内に近い流れ（版で文言が多少違う）:

1. **Add Fleet Server**（Fleet Server を追加）  
2. 配置先は **Quick start**（同一ホスト簡易）でよい（lab）  
3. ホスト名 / IP には **`<ES_STACK_IP>`** が使われる想定で進める  
4. 表示された **Elastic Agent のインストールコマンド**を控える  

そのコマンドは **es-stack 上で**実行する（Fleet Server は es-stack に置く）:

```bash
# WSL から入り直してもよい
multipass.exe shell es-stack
# 画面に出た install コマンドを貼り付けて実行（sudo 付きのことが多い）
```

**何をしているか:**  
es-stack に「Fleet Server 役の Agent」を入れ、他の Agent の受付窓口（通常ポート **8220**）を開いている。

### A3-3. 健全性を確認する

Fleet 画面で:

- Fleet Server が **Healthy**（または Connected）  
- Agents に fleet-server 相当が見える  

確認コマンド例（es-stack 上）:

```bash
sudo elastic-agent status
# または
sudo systemctl status elastic-agent --no-pager
```

ポート確認:

```bash
ss -lntp | grep 8220 || sudo ss -lntp | grep 8220
```

### A3-4. Enrollment 情報を控える（フェーズ B で使う）

Fleet → **Enrollment tokens**（または Add agent 画面）で:

| 項目 | 例 | メモ欄 |
|------|-----|--------|
| Fleet URL | `https://<ES_STACK_IP>:8220` | IP 変更に注意 |
| Enrollment token | 長い文字列 | 期限がある場合あり |

リポジトリに残すなら（後で Ansible 化するとき用）:

`ansible/inventory/group_vars/all.yaml` のイメージ:

```yaml
elasticsearch_lab_security_enabled: true
fleet_enable: true
fleet_url: "https://<ES_STACK_IP>:8220"
fleet_enrollment_token: "<TOKEN>"
```

**いまは控えるだけでよい。** playbook の自動適用は未整備でもフェーズ A のゴールは達成できる。

---

## パート A4: 副作用の確認（Filebeat）

target で Filebeat がエラーになっていないか（なっている想定）:

```bash
multipass.exe exec es-target-01 -- sudo bash -lc 'tail -n 20 $(ls -t /var/log/filebeat/*.ndjson | head -1)'
```

`401` / `unauthorized` / TLS エラーなどが出ていれば、**予想どおり**。  
疑似ログの復旧はフェーズ A の外（認証付き `output.elasticsearch` への変更）で行う。

---

## フェーズ A の完了チェックリスト

全部 Yes ならフェーズ A 完了 → フェーズ B（Agent + メトリクス）へ。

- [ ] `curl -sk -u elastic:'...' https://127.0.0.1:9200` が ES 情報を返す  
- [ ] ブラウザで Kibana に `elastic` でログインできる  
- [ ] Kibana に **Fleet** メニューがある  
- [ ] Fleet Server が Healthy（近い状態）  
- [ ] Fleet URL と Enrollment token を控えた  
- [ ] （任意）group_vars に方針をメモした  

---

## うまくいかないとき

| 症状 | まず疑うこと |
|------|----------------|
| elasticsearch が起動しない | `journalctl -u elasticsearch`、証明書パス、yml の字下げ |
| curl https が失敗 | `-k`（自己署名のため）を付けたか、ssl 設定ミス |
| Kibana が赤 / 起動しない | kibana_system のパスワード、`elasticsearch.hosts` が https か |
| Fleet が出ない | ライセンス表示やログインユーザー権限。一度ログアウトして `elastic` で再ログイン |
| Fleet Server が Unhealthy | 8220、ES への認証、インストールコマンドを es-stack で実行したか |
| ブラウザで Kibana に届かない | `<ES_STACK_IP>` が `multipass.exe list` の最新か |

詰まったら、**どのパートの何番まで終わったか**と、エラー全文を残す。

---

## ロールバックの考え方（概要）

完全に戻すなら:

1. バックアップした `elasticsearch.yml.bak.phase-a` / `kibana.yml.bak.phase-a` を戻す  
2. セキュリティ off の設定に戻してサービス再起動  

または Multipass VM を作り直し:

```bash
bash scripts/vms-delete.sh
bash scripts/vms-create.sh
bash scripts/controller-ansible-run.sh
```

（セキュリティ off の初期 lab に戻る）

---

## 次のフェーズ

A 完了後は `agent-osquery-tejun.md` の **フェーズ B**（ポリシー作成 → target に Agent → CPU 確認）。  
B の細かい手順は、A が通ってから同じ粒度で切り出す。
