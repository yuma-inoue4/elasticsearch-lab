# Agent → メトリクス → Osquery → 資産台帳 手順（解説つき）

対象読者: Filebeat の疑似ログと Kibana グラフまで終わった人。  
方針: **Elastic Agent でメトリクスを先に通し、その後 Osquery で版つき台帳**。

このドキュメントは「何をするか」と「なぜそれをするか」をセットで書く。  
いまの lab はセキュリティ off + Filebeat 直送なので、**ここから先は設定が大きく変わる**。一度に全部やらず、区切りごとに確認すること。

関連: `setup-memo.md` の「次の進め方の目安」

---

## 登場人物（用語）

| 名前 | 何ものか |
|------|----------|
| **Elasticsearch (ES)** | データを保管・検索する箱 |
| **Kibana** | ES の中身をブラウザで見る UI |
| **Filebeat** | いま使っている「ログファイル送信係」（疑似ログ用）。当面残してよい |
| **Elastic Agent** | 新しい「総合収集係」。メトリクスや Osquery を載せる土台 |
| **Fleet** | Kibana 上の司令塔。Agent に「何を集めろ」と指示する |
| **Fleet Server** | Agent が実際に接続する受付係（だいたい es-stack 上） |
| **Integration** | Agent に足す機能パック（System=メトリクス、Osquery=問い合わせ など） |
| **Osquery** | OS に SQL っぽく質問して、パッケージ一覧などを取る仕組み |
| **Enrollment** | Agent を Fleet に「登録」する手続き（合言葉がトークン） |

いまの流れと、目指す流れ:

```text
【いま】
疑似ログ → Filebeat → ES → Kibana

【これから足す】
CPU など → Agent(System) → ES → Kibana
パッケージ版 → Agent(Osquery) → ES → Kibana（台帳）
```

---

## 全体の地図（何回に分けるか）

| フェーズ | ゴール | できたと言える状態 |
|----------|--------|-------------------|
| A | セキュリティ + Fleet の土台 | Kibana の Fleet 画面が使える |
| B | Agent + メトリクス | あるホストの CPU が Kibana で見える |
| C | Osquery | パッケージ名とバージョンが Discover で見える |
| D | 資産台帳 | ホスト×ソフト×版が一覧・ダッシュボードになる |

**A が一番つまずきやすい。** ここを飛ばして Agent だけ入れても、Fleet なし運用は別ルートになり、この方針とはずれる。

---

# フェーズ A: es-stack で Fleet / セキュリティの準備

**細かい手順（コマンド・画面操作・解説）:** [`phase-a-fleet-security.md`](./phase-a-fleet-security.md)

## A-1. なぜセキュリティを入れるのか

**やること:** Elasticsearch / Kibana の認証（ログイン）や通信の保護を有効にする方向へ進める。

**何をしているか:**  
Fleet と Agent は、だいたい「誰でも ES に書き込める」状態を前提にしない。パスワードや証明書がある前提で設計されている。いまの lab は学習しやすくするため `elasticsearch_lab_security_enabled: false`（認証オフ）なので、**Agent 本線に進むにはここを変える必要がある**。

**注意:**  
セキュリティを on にすると、いま動いている **Filebeat も認証付き接続に切り替えが必要**になる。疑似ログが一時的に止まったり、再設定が必要になったりする。壊したくない場合は、作業前に VM のスナップショット相当（作り直し手順の把握）をしておく。

**このリポジトリの現状:**  
`group_vars` の `elasticsearch_lab_security_enabled` / `fleet_enable` と `playbook/setup-fleet.yaml` はあるが、Fleet の自動構築は**案内レベル**。A フェーズは Kibana 画面操作と公式手順を見ながらの作業が中心になる。

### 手順の骨格

1. `ansible/inventory/group_vars/all.yaml` で方針を決める  
   - `elasticsearch_lab_security_enabled: true`  
   - 後で `fleet_enable: true` も視野に入れる  
2. Elasticsearch / Kibana をセキュリティ有効で作り直す（または公式のセキュリティ有効化手順に従う）  
3. Kibana にログインできるようにする（elastic ユーザーなど）  
4. ブラウザで Kibana → **Management（管理）** → **Fleet** を開く  

**何をしているか（画面）:**  
Fleet は「Agent の名簿と、各 Agent への指示書（ポリシー）」を置く場所。まだ Agent がいなくても、受付（Fleet Server）の準備をここから始める。

5. Fleet の案内に従い **Fleet Server** を追加する（ホストは原則 `es-stack`）  
6. 表示される **Enrollment token（登録用トークン）** と **Fleet URL**（例: `https://<es-stackのIP>:8220`）を控える  

**何をしているか:**  
トークン = 「このラボの Fleet に入ってよい」という合言葉。  
Fleet URL = Agent が司令塔に繋ぐ住所。Filebeat の「ES の IP が変わると届かない」と同じで、**IP が変わったらここも見直し**が必要。

7. 控えた値を後で使う（手作業インストール時のコマンド、または group_vars の `fleet_url` / `fleet_enrollment_token`）

**このフェーズの完了条件:**  
Kibana の Fleet で Fleet Server が Healthy（または少なくとも追加済み）で、Enrollment token が発行できる。

---

# フェーズ B: Agent を入れてメトリクスを見る

## B-1. ポリシー（指示書）を作る

**やること:** Fleet で「Agent ポリシー」を作り、**System** Integration を入れる。

**何をしているか:**  
ポリシー = 「この Agent は何を集めるか」の設定セット。  
System Integration = CPU・メモリ・ディスクなどの**メトリクス**を集める機能パック。  
ここでメトリクスを先に入れるのは、「Agent → ES のパイプが通ったか」を CPU グラフで確認しやすくするため。

### 手順の骨格

1. Fleet → Agent policies → Create policy（例: `lab-targets`）  
2. Add integration → **System** を追加して保存  
3. ポリシーに紐づく **Enrollment token** を確認（A で控えたものと別の場合あり）

## B-2. target に Elastic Agent を入れる

**やること:** `es-target-01`（慣れたら `es-target-02` も）に Agent をインストールし、Fleet に登録（enroll）する。

**何をしているか:**  
各サーバに常駐プログラムを置き、「これからこのサーバの状態を送る」と Fleet に自己紹介させる。  
インストールコマンドは、Fleet 画面の **Add agent** に OS 向けのコピペ用が出る。それを VM 上で実行する。

### 手順の骨格

1. `multipass.exe list` で es-stack / target の IP を確認  
2. Fleet → Add agent → ポリシー `lab-targets` を選ぶ  
3. 表示された install コマンドを、target 上で実行  
   - 例: `multipass.exe shell es-target-01` の中、または `multipass.exe exec ...`  
4. Fleet の Agents 一覧にホストが出て **Healthy** になるまで待つ  

**何をしているか（Healthy）:**  
Agent が Fleet Server と会話でき、指示どおり動いている状態。ここが Failed なら、トークン・URL・ファイアウォール・IP 変更を疑う。

## B-3. Kibana でメトリクスを確認

**やること:** Observability や Dashboard、Discover で CPU などが見えるか確認する。

**何をしているか:**  
Agent が集めた数値が ES に入り、Kibana がその数値をグラフにしている。  
疑似ログ（`lab.*`）とは別データ。見え方が違うのは正常。

### 手順の骨格

1. Kibana で Infrastructure / Hosts、または関連 Dashboard を開く  
2. `es-target-01` 相当のホスト名が出るか見る  
3. CPU やメモリの推移が出れば **フェーズ B 完了**  

**ここで一度区切る。** 通ってから Osquery に進む。

---

# フェーズ C: 同じ Agent に Osquery を足す

## C-1. Osquery Integration を追加

**やること:** さきほどの Agent ポリシーに **Osquery Manager**（名称は版により多少違う）を追加する。

**何をしているか:**  
すでに入っている Agent に「OS に質問する能力」を足す。新しい Agent を入れ直す必要は基本ない（ポリシー更新で配られる）。

### 手順の骨格

1. Fleet → ポリシー `lab-targets` → Add integration  
2. Osquery 関連を追加して Save  
3. Agent がポリシーを取り込み直すまで少し待つ（Agents 画面で更新を確認）

## C-2. パッケージ一覧を問い合わせる

**やること:** Kibana の Osquery 画面（または Integration の案内）から、インストール済みパッケージを聞く。

**何をしているか:**  
ログを読むのではなく、OS のパッケージデータベースに問い合わせている。Ubuntu ならイメージとしては:

```sql
SELECT name, version FROM deb_packages LIMIT 50;
```

「このサーバに何が、どの版で入っているか」を SQL っぽく聞く。

### 手順の骨格

1. Kibana で Osquery の Live query / スケジュール画面を開く  
2. 対象 Agent（es-target-01）を選ぶ  
3. `deb_packages` から name / version を取得するクエリを実行  
4. 結果に `filebeat` や `python3` などが出るか確認  

最初は **全件ではなく LIMIT** や特定名前に絞ると見やすい。

## C-3. ES / Discover で結果を確認

**やること:** Osquery の結果がインデックスに残る設定なら、Discover で Data view を作り中身を見る。

**何をしているか:**  
一度きりの画面表示だけでなく、ES に溜めて Kibana の表・グラフに載せる準備。Filebeat の `filebeat-*` とは別系統になりやすい。

**このフェーズの完了条件:**  
「ホストでパッケージ名とバージョンが取れた」かつ「（可能なら）ES 上でも同じ系統のデータが見える」。

---

# フェーズ D: 資産管理台帳として整える

## D-1. 台帳の「行」の形を決める

**やること:** 1行に何を載せるかを決める。

**推奨（最初）:**

| 列 | 意味 |
|----|------|
| 取得時刻 | いつ調べたか |
| ホスト名 | どの VM か |
| ソフトウェア名 | 例: filebeat |
| バージョン | 例: 8.15.0 |

**何をしているか:**  
全部の deb を出すと行が多すぎて「一目」にならない。最初は:

- filebeat / elasticsearch / kibana / python3  
など **見たい名前だけ**に絞る方が台帳らしい。

## D-2. 定期実行にする

**やること:** Live query だけでなく、スケジュール（例: 1日1回）で同じ問い合わせを走らせる。

**何をしているか:**  
資産台帳はログのように毎分更新しなくてよい。「昨日時点の棚卸し」が残れば十分なことが多い。定期実行 = 自動棚卸し。

## D-3. Kibana で一覧を作る

**やること:**

1. 台帳用 Data view を作る  
2. Discover で表として見る  
3. 必要なら Lens や Dashboard に「ホスト別ソフト数」などを置く  

**何をしているか:**  
疑似ログのグラフ（案1: level 時系列）と同じ Kibana 操作だが、データが「イベント」ではなく「構成の記録」。

例:

- フィルタ: `host.name: "es-target-01"`  
- 表の列: ソフト名、バージョン  

## D-4. 運用ルールを決める

**やること:** 次をメモする（このファイルや runbook に残す）。

- 何日ごとに取り直すか  
- 対象ソフトのリスト  
- Multipass の IP が変わったときの確認（Fleet URL / Agent / 以前の Filebeat と同様）  
- セキュリティ有効化後の Filebeat 再設定（疑似ログを続ける場合）

---

## つまずきやすい点（先に知っておく）

1. **セキュリティ on で Filebeat が止まった**  
   → 認証情報付きの出力設定が必要。別作業として切り出す。  
2. **Enrollment が失敗する**  
   → Fleet URL の IP、トークン期限、target から es-stack:8220 へ届くかを確認。  
3. **メトリクスは見えるが Osquery が空**  
   → Integration 未追加、ポリシー未配信、クエリ対象ホスト違い。  
4. **台帳が一目でない**  
   → 全パッケージ表示のまま。名前で絞る。  

---

## いまの lab で「自動化済み」ではないこと

次は **方針と手作業の地図** であり、全部が Ansible 一発にはなっていない。

- セキュリティ有効化の完全自動 playbook  
- Fleet Server の完全自動構築  
- Agent の完全自動 enroll  
- Osquery スケジュールの完全自動  

実装を Ansible に落とすのは、フェーズ B が手動で一度成功してからの方が安全。

---

## 次に手を動かすなら（最短の最初の一歩）

1. この手順の **フェーズ A** だけを対象にする  
2. Kibana にログインし **Fleet メニューが使える状態**を目指す  
3. できた / 止まった画面を記録する  

A の具体的なクリック手順（セキュリティ有効化の詳細）は環境差が大きいので、A に入るタイミングで「今の ES を壊してよいか / Filebeat を維持したいか」を決めてから細分化するとよい。
