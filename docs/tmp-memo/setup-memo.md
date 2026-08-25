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

**手順と「何をしているか」の説明:** `[agent-osquery-tejun.md](./agent-osquery-tejun.md)`  
**フェーズ A の詳細手順（同一内容の単体メモ）:** `[phase-a-fleet-security.md](./phase-a-fleet-security.md)`

---



## フェーズ A 詳細手順（セキュリティ + Fleet）

**ゴール:** Kibana にログインでき、Fleet が使え、Fleet Server が動き、Enrollment token と Fleet URL を控えた状態。  
**Fleet 用の追加 VM は不要**（Fleet Server は既存の `es-stack` に置く）。

### パート構成


| パート    | やること                                           |
| ------ | ---------------------------------------------- |
| **0**  | 事前確認・Filebeat 停止の了承・`<ES_STACK_IP>` 控え         |
| **A1** | ES に認証 + TLS。`elastic` パスワード設定                 |
| **A2** | Kibana を https ES に接続。ブラウザで `elastic` ログイン     |
| **A3** | Fleet → Fleet Server（es-stack）→ token / URL 控え |
| **A4** | Filebeat が 401 等で止まっていることを確認（予想どおり）            |


---



### 0. 始める前



#### 0-1. 何が変わるか


| いま                                    | フェーズ A のあと                     |
| ------------------------------------- | ------------------------------ |
| ES にパスワードなしで接続                        | ユーザー / パスワード（や証明書）が必要          |
| Kibana も実質だれでも開けることが多い                | Kibana ログインが必要                 |
| Filebeat が `http://es-stack:9200` に直送 | **認証なしでは送れなくなる**（疑似ログが止まる）     |
| Fleet 未使用                             | Fleet / Fleet Server を使う土台ができる |


**何をしているか:** Agent / Fleet は「誰でも書き込める ES」を前提にしない。先に鍵を付け、Fleet の受付を置く。

#### 0-2. すすめる前の確認（必須）

```bash
multipass.exe list
multipass.exe exec es-stack -- curl -sS --max-time 5 http://127.0.0.1:9200
multipass.exe exec es-stack -- curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

- `es-stack` が Running / ES が JSON / Kibana が応答 → ここまでできてから先へ



#### 0-3. 意思決定

1. **疑似ログ（Filebeat）は一時停止してよい** → この手順どおり進める
2. **疑似ログを絶対に止めたくない** → Filebeat 用ユーザー設計などが先（難易度↑）

この手順は **1 向け**。Filebeat 復旧は A のあと別作業。

#### 0-4. IP を控える

```bash
multipass.exe list
```

`es-stack` の IPv4 をメモ（以降 `<ES_STACK_IP>`）。

---



### パート A1: Elasticsearch のセキュリティを有効にする

**やること:** `es-stack` 上の ES に認証と HTTPS（TLS）を入れる。  
**何をしているか:** 「誰でも 9200」をやめ、正規ユーザーだけにする（Fleet の前提）。

```bash
multipass.exe shell es-stack
```

（以降 `ubuntu@es-stack` 前提）

#### A1-1. サービスを止める

```bash
sudo systemctl stop kibana
sudo systemctl stop elasticsearch
```



#### A1-2. 証明書用ディレクトリ

```bash
sudo mkdir -p /etc/elasticsearch/certs
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/certs
```



#### A1-3. CA とノード証明書を作る

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

**何をしているか:** CA＝ラボ用の印鑑、ノード証明書＝正規 ES の身分証。

#### A1-4. elasticsearch.yml を編集

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak.phase-a
sudo nano /etc/elasticsearch/elasticsearch.yml
```

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

`cluster.name` / `node.name` / `network.host` / `http.port` / `discovery.type` / `path.data` / `path.logs` は残してよい。  
保存: Ctrl+O → Enter → Ctrl+X。

#### A1-5. Elasticsearch 起動

```bash
sudo systemctl start elasticsearch
sudo systemctl status elasticsearch --no-pager
```

失敗時: `sudo journalctl -u elasticsearch -n 80 --no-pager`

```bash
sleep 20
curl -sk https://127.0.0.1:9200
```



#### A1-6. elastic ユーザーのパスワード

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

控える（`<ELASTIC_PASSWORD>`）。自動生成なら `-b`。

```bash
curl -sk -u elastic:'<ELASTIC_PASSWORD>' https://127.0.0.1:9200
```

JSON が返れば **A1 完了**。

---



### パート A2: Kibana をセキュリティ付き ES に繋ぐ



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

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

控えた `<KIBANA_SYSTEM_PASSWORD>` を yml に:

```yaml
elasticsearch.password: "<KIBANA_SYSTEM_PASSWORD>"
```

**何をしているか:** Kibana 専用ユーザーで ES に繋ぐ（ブラウザの `elastic` とは別）。

#### A2-2. Kibana 起動

```bash
sudo systemctl start kibana
sudo systemctl status kibana --no-pager
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5601
```

`200` / `302` まで待つ（1〜3 分かかることがある）。

#### A2-3. ブラウザでログイン

`http://<ES_STACK_IP>:5601`  
ユーザー `elastic` / パスワード `<ELASTIC_PASSWORD>` → ホームが出れば **A2 完了**。

---



### パート A3: Fleet と Fleet Server



#### A3-1. Fleet を開く

Kibana → 左メニュー → **Management（管理）** → **Fleet**

#### A3-2. Fleet Server を追加

1. **Add Fleet Server**
2. **Quick start**（同一ホスト・lab 向け）
3. ホストは `<ES_STACK_IP>` 想定
4. 表示された **Agent インストールコマンド**を **es-stack 上**で実行

```bash
multipass.exe shell es-stack
# 画面の install コマンドを貼り付け
```

**何をしているか:** 受付窓口（通常 **8220**）を es-stack に開く。新 VM は不要。

#### A3-3. 健全性確認

Fleet で Fleet Server が Healthy / Connected。es-stack 上:

```bash
sudo elastic-agent status
# または
sudo systemctl status elastic-agent --no-pager
ss -lntp | grep 8220 || sudo ss -lntp | grep 8220
```



#### A3-4. Enrollment 情報を控える（フェーズ B 用）


| 項目               | 例                            |
| ---------------- | ---------------------------- |
| Fleet URL        | `https://<ES_STACK_IP>:8220` |
| Enrollment token | 長い文字列（期限に注意）                 |


任意で `group_vars` メモ例:

```yaml
elasticsearch_lab_security_enabled: true
fleet_enable: true
fleet_url: "https://<ES_STACK_IP>:8220"
fleet_enrollment_token: "<TOKEN>"
```

いまは控えるだけでよい（playbook 自動化は未整備でも A 完了可）。

---



### パート A4: Filebeat の副作用確認

```bash
multipass.exe exec es-target-01 -- sudo bash -lc 'tail -n 20 $(ls -t /var/log/filebeat/*.ndjson | head -1)'
```

`401` / `unauthorized` / TLS エラーなら **予想どおり**。復旧は認証付き Filebeat 設定の別作業。

---



### フェーズ A 完了チェックリスト

- [ ] `curl -sk -u elastic:'...' https://127.0.0.1:9200` が ES 情報を返す  
- [ ] ブラウザで Kibana に `elastic` ログインできる  
- [ ] Fleet メニューがある  
- [ ] Fleet Server が Healthy（近い状態）  
- [ ] Fleet URL と Enrollment token を控えた  

全部 Yes → フェーズ B（Agent + メトリクス）。

### うまくいかないとき


| 症状                     | まず疑うこと                                      |
| ---------------------- | ------------------------------------------- |
| elasticsearch が起動しない   | `journalctl -u elasticsearch`、証明書パス、yml 字下げ |
| curl https 失敗          | `-k`、ssl 設定                                 |
| Kibana が赤 / 起動しない      | kibana_system パスワード、hosts が https か         |
| Fleet が出ない             | `elastic` で再ログイン                            |
| Fleet Server Unhealthy | 8220、install を es-stack で実行したか              |
| ブラウザで届かない              | `<ES_STACK_IP>` が最新か                        |




### ロールバック（概要）

- yml の `.bak.phase-a` を戻して再起動  
- または `bash scripts/vms-delete.sh` → `vms-create.sh` → `controller-ansible-run.sh` で初期 lab に戻す

