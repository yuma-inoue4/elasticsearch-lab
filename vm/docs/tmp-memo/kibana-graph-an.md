# Kibana グラフ案（現状の取り込みデータ向け）

Filebeat 経由で入っている `lab.*` フィールドを前提にした可視化のメモ。  
作成場所の目安は Kibana **Lens**。

## 使える主なフィールド

| フィールド | 中身 |
|---|---|
| `@timestamp` | 時刻（Discover / Lens の時間軸） |
| `lab.level` | INFO / WARN / ERROR |
| `lab.service` | dummy-shop / dummy-pay |
| `lab.host` | es-target-01 / es-target-02 |
| `lab.path` | `/api/orders` など |
| `lab.status` | 200 / 429 / 500 |
| `lab.duration_ms` | 処理時間（数値） |
| `lab.message` | メッセージ文字列 |

補足: Filebeat 付与の `host.hostname` もあるが、アプリログのホスト差分は `lab.host` を使う。

---

## おすすめグラフ案

### 1. レベル別の件数（折れ線）★最初はこれ

- **目的:** 正常・警告・エラーが時間でどう増えるか
- **種類:** 折れ線（または積み上げ棒）
- **横軸:** `@timestamp`
- **縦軸:** 件数（Count）
- **色分け:** `lab.level`

#### 作成手順（Lens・初回向け）

前提: Data view `filebeat`（Index pattern `filebeat-*`）が作成済みであること。

1. Kibana を開く（`http://<es-stackのIP>:5601`）
2. 左メニュー（三本線）→ **Analytics** → **Lens**  
   （日本語 UI なら「分析」→「Lens」）
3. 開いたら右上の時間範囲を **「今日」** または **「過去1時間」** にする  
   （データが無いとグラフが真っ白になる）
4. 左上あたりの Data view が **`filebeat`** になっているか確認する  
   （違っていたら選ぶ）
5. 画面中央の「チャートの種類」から **折れ線（Line）** を選ぶ  
   （最初は棒でも可。後から変えられる）
6. 左のフィールド一覧から **`@timestamp`** を、グラフの横軸エリアへドラッグする  
   - 場所の名前は「Horizontal axis」「横軸」「X軸」など
7. 左のフィールド一覧から **件数用の集計** を縦軸へ置く  
   - いちばん簡単: 左上の **「Records」**（または「レコード数」「Count of records」）を縦軸へドラッグ  
   - これで「何件あったか」が縦に並ぶ
8. 左のフィールド一覧から **`lab.level`** を、色分け（Break down / 内訳）へドラッグする  
   - 場所の名前は「Break down by」「内訳」「色分け」など
9. 右側または下部に INFO / WARN / ERROR の線が分かれて出れば成功
10. 右上の **Save**（保存）を押し、名前例: `level-over-time`  
    （任意で Dashboard に追加してもよい）

うまくいかないとき:

- グラフが空 → 時間範囲を広げる / Discover で同じ時間にデータがあるか確認
- `lab.level` が見つからない → Data view を開き直すか、フィールド一覧の検索窓に `lab.level` と入力
- 線が1本だけ → Break down に `lab.level` が入っていない

### 2. ホスト別の件数（棒）

- **目的:** どの VM から何件来ているか（マルチホスト収集の確認）
- **種類:** 棒グラフ
- **横軸:** `lab.host`
- **縦軸:** 件数

### 3. サービス別の件数（円 or 棒）

- **目的:** shop と pay の比率
- **種類:** 円グラフ or 棒
- **分割:** `lab.service`
- **値:** 件数

### 4. HTTP ステータス別（棒）

- **目的:** 200 / 429 / 500 の分布
- **種類:** 棒グラフ
- **横軸:** `lab.status`
- **縦軸:** 件数

### 5. 遅いリクエスト（棒 or ヒストグラム）

- **目的:** 処理時間の傾向
- **種類:** 棒（平均）またはヒストグラム
- **縦軸:** `lab.duration_ms` の平均 / 最大
- **横軸:** `@timestamp` または `lab.path`

### 6. パス別 Top（横棒）

- **目的:** どの API が多いか
- **種類:** 横棒
- **横軸:** 件数
- **縦軸:** `lab.path`（上位 5〜10）

### 7. エラーだけ時系列（折れ線）★実務っぽい

- **目的:** ERROR の増減だけ追う
- **種類:** 折れ線
- **フィルタ（KQL）:** `lab.level: "ERROR"`
- **横軸:** `@timestamp`
- **縦軸:** 件数
- **色分け（任意）:** `lab.host`

---

## 最初に作るならこの 3 つ

1. **レベル別の時系列**（全体の様子）
2. **ホスト別の件数**（2台から取れている確認）
3. **ERROR だけの時系列**（障害っぽい見方）

---

## 関連メモ

- Data view 名の目安: `filebeat`（Index pattern: `filebeat-*`）
- 時間範囲で 0 件のときは「今日」「過去1時間」などを確認
- Multipass IP 変更後は Filebeat の送り先が古くなることがある  
  → `bash scripts/controller-ansible-run.sh playbook/sample_workload.yaml`
