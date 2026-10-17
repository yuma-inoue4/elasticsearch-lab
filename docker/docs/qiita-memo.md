# Qiita 作業手順メモ（下書き）

**進捗:** 教材セクション5・ネットワーク（ホスト↔コンテナのポート／`network inspect`）まで。次回は続きから。

---

## Docker の概要

- **イメージ**を基に **コンテナ** を作成する
- イメージは Docker Hub 等から取得、または自作する
- バージョンはレジストリの Web ページで確認する

---

## 基礎コマンド

### イメージ

```bash
docker image pull {image}            # 取得
docker image ls                      # 一覧
docker image inspect {image}         # 詳細（Config → Cmd など）
docker image history {image}         # レイヤー履歴
docker image rm {image}              # 削除
docker image build {context_path}    # ビルド
docker image build -t {tag} {path}   # タグ付きビルド
```

### コンテナ（起動・停止・削除）

```bash
docker container run {image}         # 作成・起動
docker container ls                  # 稼働中一覧
docker container stop {container}    # 停止
docker container restart {container} # 再起動
docker container rm {container}      # 削除（exited のみ。先に stop）
docker container rm -f {container}   # 稼働中でも強制削除
docker container prune               # exited を一括削除
```



### ログ・実行・アタッチ

```bash
docker container logs {container}
docker container exec {container} {command}
docker container exec -it {container} bash
docker container attach {container}
```



### よく使う run

```bash
docker container run -it {image}
docker container run -d --rm {image}
docker run --rm hello-world
```

---



## よく使うオプション


| オプション  | 意味                               |
| ------ | -------------------------------- |
| `-i`   | 標準入力を有効                          |
| `-t`   | TTY 割り当て（`run`）／タグ付け（`build -t`） |
| `-d`   | デタッチド起動                          |
| `--rm` | 終了後にコンテナを自動削除                    |
| `-f`   | 強制（`rm -f` で稼働中も削除）              |
| `-v`   | ボリューム／バインドマウント                   |
| `-p`   | ホスト:コンテナのポート紐付け                  |


---



## 環境セットアップ



### Windows（WSL2 + Docker CLI）

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

グループ反映のため、一度 WSL を終了して開き直す。

### Mac（OrbStack）

Docker Desktop の代わり。操作は `docker` / `docker compose`。

前提: `brew -v`

```bash
brew install --cask orbstack
orb start
```

トラブル時: `orb start` / ターミナル開き直し / `which docker` / `brew upgrade --greedy orbstack`

### 動作確認（共通）

```bash
docker version
docker compose version
docker run --rm hello-world
```



### ビルド時の debconf（参考）

`debconf: delaying package configuration, since apt-utils is not installed` は **エラーではない**。`Successfully built` なら成功。

抑制したい場合:

```dockerfile
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y curl
```

---



## Dockerfile

レジストリのイメージは最小構成のため、カスタマイズが必要になることが多い。

### COPY / CMD

```dockerfile
COPY {追加元} {追加先}   # 無いディレクトリはコンテナ側で作成される

CMD ["実行ファイル", "引数1", "引数2"]   # デフォルトコマンド（複数ある場合は最後のみ有効）
```



### ビルドコンテキスト / `.dockerignore`

- **ビルドコンテキスト:** `docker image build` で送る素材一式（Dockerfile も含む）
- `**.dockerignore`:** コンテキストから除外（大容量・秘密情報など）

```bash
docker image build .
touch .dockerignore
```

---



## レイヤーとキャッシュ

- 各命令（`RUN` など）が **レイヤー**になる
- 確認: `docker image history {image}`
- `&&` で1つの `RUN` にまとめるとレイヤー数・容量を減らせる
- まとめた `RUN` を変更すると、そのレイヤー以降のキャッシュが無効になる  
→ 変更頻度の低い処理と高い処理は分けた方がよい

---



## 環境変数: `ARG` と `ENV`


| 指令                  | 有効なタイミング       | 用途           |
| ------------------- | -------------- | ------------ |
| `ARG {key}={value}` | **ビルド時のみ**     | ビルド時の一時パラメータ |
| `ENV {key}={value}` | **ビルド時 + 実行時** | コンテナ内で使う値    |


**使い分け:** 実行時も使う → `ENV`。ビルド時だけ → `ARG`。

```dockerfile
ARG message="Hello, World!"
RUN echo $message > message.txt
CMD ["cat", "message.txt"]
```

---



## `WORKDIR`

`RUN` / `CMD` などの作業ディレクトリ。未指定時は `/`。

```dockerfile
RUN touch 1.txt              # / に作成

WORKDIR /app/my_dir
RUN touch 2.txt              # /app/my_dir に作成

WORKDIR ..
RUN touch 3.txt              # /app に作成
```

---



## マルチステージビルド

段階を分けてビルドし、最終イメージを軽量化できる。

- ステージは `FROM` で区切る
- 命名: `FROM {image} AS {stage-name}`
- 他ステージからコピー: `COPY --from={stage-name} {path}`
- 開発／本番を1ファイルで管理できる
- 特定ステージだけビルド: `--target`

```dockerfile
FROM ubuntu:22.04 AS base
# ...

FROM base AS dev
# ...

FROM base AS prod
# ...
```

```bash
docker image build --target {stage-name} {build-context}
```

---



## ストレージ

コンテナのファイルシステムは **揮発性**（破棄時に消える）。永続化は次の2つ。


| 方式           | 共有の範囲      | 特徴                             |
| ------------ | ---------- | ------------------------------ |
| **ボリューム**    | 主にコンテナ間    | Docker が管理。ホスト差の影響を受けにくい       |
| **バインドマウント** | ホスト ↔ コンテナ | ホストのパスを直接マウント。開発向きだが OS／パス差に注意 |


**方針（教材寄り）:** 本番・可搬性を意識するなら **ボリューム**。ホストで直接編集したい開発用途ならバインドマウントも使う。

### ボリューム

```bash
docker volume create {volume-name}
docker volume ls
docker volume inspect {volume-name}
docker volume rm {volume-name}

# マウントして起動
docker container run -v {volume-name}:{container-abs-path} {image-name}

# 例
docker run -it -v my-volume:/app1 --name container-1 ubuntu:22.04
```



### バインドマウント

```bash
docker container run -v {host-abs-path}:{container-abs-path} {image-name}

# 例（カレント配下をマウント）
docker run -it -v "$(pwd)/my-dir:/app" --name app-container ubuntu:22.04
```

**注意:** ホストパスにスペースがある場合は必ずクォートする。

```bash
# NG: Google Drive のスペースで引数が割れ、invalid reference format になる
docker run -itv /Users/.../Google Drive/...:/app3 ubuntu:22.04

# OK
docker run -it -v "/Users/.../Google Drive/...:/app3" ubuntu:22.04
# または
docker run -it -v "$(pwd):/app3" ubuntu:22.04
```

---



## ネットワーク

接続の型は大きく2つ。

1. **ホスト ↔ コンテナ** … ポート紐付け（`-p`）が必要
2. **コンテナ ↔ コンテナ** … 同一ネットワーク上で名前解決など

### ホスト ↔ コンテナ（ポート公開）

```bash
#---------------------------
# ホスト - コンテナ間のポートを紐付け
#---------------------------
docker container run -p {host-port}:{container-port} {image-name}

# 例: ホスト 3000 → コンテナ 80
docker run -p 3000:80 nginx
```

```bash
#---------------------------
# 確認
#---------------------------
docker network ls
docker network inspect {network-name}

# 補足: inspect の 項目Containers に、その NW へ接続中のコンテナ（Name / IP など）が載る。
docker network inspect bridge | grep Containers -A 10

#---------------------------
# 作成
#---------------------------
docker network create {network-name}

# 指定NWにコンテナを作成 
docker run --name {cont-name} --network {nw-name}

# 指定NWにコンテナを作成する例
dc run -itd --rm --name my-nginx-2 --network my-net nginx
```

#異なるdocker network 同士のコンテナは疎通できない (orbstack のエンジンのコンテナは例外)



tips

#既存のコンテナに入るには？

docker container exec -it {cont-name} bash