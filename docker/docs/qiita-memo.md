# Qiita 作業手順メモ（下書き）

**進捗:** セクション5の32まで完了。レイヤー / `ENV`・`ARG` / `WORKDIR` まで追記済み。次回は教材の続きから。

---

## Docker の概要

- **イメージ**（ファイル）を基に **コンテナ** を作成する
- イメージは Docker Hub 等のレジストリから入手、または自作する
- 利用可能なバージョンはレジストリの Web ページから確認する

---

## 基礎コマンド（用途別）

### イメージ操作

```bash
docker image pull {image}            # レジストリから取得
docker image ls                      # 一覧
docker image inspect {image}         # 詳細（Config → Cmd など）
docker image history {image}       # レイヤー履歴を表示
docker image rm {image}              # 削除
docker image build {context_path}    # Dockerfile からビルド
docker image build -t {tag} {path}   # タグ付きビルド
```



### コンテナの起動・停止・削除

```bash
docker container run {image}         # 新規作成・起動
docker container ls                  # 一覧（稼働中）
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



### 動作確認（よく使う run）

```bash
docker container run -it {image}
docker container run -d --rm {image}
docker run --rm hello-world
```

---



## よく使うオプション


| オプション  | 意味                                |
| ------ | --------------------------------- |
| `-i`   | 標準入力を有効                           |
| `-t`   | TTY を割り当て（`run`）／タグ付け（`build -t`） |
| `-d`   | デタッチドで起動                          |
| `--rm` | 終了後にコンテナを自動削除                     |
| `-f`   | 強制（`rm -f` で稼働中も削除）               |


---



## 環境セットアップ



### Windows（WSL2 + Docker CLI）

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

グループ反映のため、一度 WSL を終了してから開き直す。

### Mac（OrbStack）

Docker Desktop の代わりに OrbStack。操作は `docker` / `docker compose`。

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



### ビルド時の debconf メッセージ（参考）

`debconf: delaying package configuration, since apt-utils is not installed` は **エラーではない**（最小 Ubuntu イメージでよく出る）。`Successfully built` なら成功。

静かにしたい場合:

```dockerfile
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y curl
```

---



## Dockerfile

レジストリのイメージは最小構成のため、カスタマイズが必要になることが多い。

### COPY / CMD

```dockerfile
COPY {追加元} {追加先}   # 無いディレクトリはコンテナ側で作成される

CMD ["実行ファイル", "パ1", "パ2"]   # デフォルトコマンド（複数行あっても最後の CMD のみ有効）
```



### ビルドコンテキスト / `.dockerignore`

- **ビルドコンテキスト:** `docker image build` で Docker に送る素材一式（Dockerfile もこの配下）
- `**.dockerignore`:** コンテキストから除外（大容量・秘密情報など）

```bash
docker image build .
touch .dockerignore
```

---



## レイヤーとキャッシュ

- レイヤーは普段意識しにくいが、**イメージの各命令（**`RUN` **など）がレイヤー**になる
- `docker image history {image}` で確認できる
- `**&&` で1つの `RUN` にまとめる**とレイヤー数・容量を減らせる
- ただし **まとめた** `RUN` **全体を変更すると、そのレイヤー以降のキャッシュが無効**になる  
→ `apt update` などは毎回走り直し。初期構築では **変更頻度の低い塊と高い塊を分ける**とよい

---



## 環境変数: `ARG` と `ENV`


| 指令                  | 有効なタイミング               | 用途                  |
| ------------------- | ---------------------- | ------------------- |
| `ARG {key}={value}` | **ビルド時のみ**（コンテナ実行時は無効） | ビルド時の一時パラメータ        |
| `ENV {key}={value}` | **ビルド時 + コンテナ実行時**     | コンテナ内で参照・動的に書き換えたい値 |


**使い分け（結論）:** コンテナ実行中も使う／中身を動的に変えたい → `ENV`。イメージ作成時だけ → `ARG`。

```dockerfile
ARG message="Hello, World!"
RUN echo $message > message.txt

CMD ["cat", "message.txt"]
```

---



## `WORKDIR`

`RUN` / `CMD` などの **作業ディレクトリ**を指定する。未指定時は `/`。

```dockerfile
# 未指定 → / に 1.txt
RUN touch 1.txt

# /app/my_dir に 2.txt
WORKDIR /app/my_dir
RUN touch 2.txt

# /app に 3.txt（一つ上の ..）
WORKDIR ..
RUN touch 3.txt
```

---

## マルチステージビルド

段階を分けて imageのビルドを実行する機能で、最終的な image の容量を軽量化できる

ステージは、FROM で区切るように書く。

また、ステージ単位で命名が可能 例 : FROM {OS-name} AS {stage-name}

他のステージのファイルを引用したいなら、 COPY --from={stage-name} {directory-path}

また、開発環境、本番環境を1つのDockerfileで管理可能になる

その際、作成したいステージ(=環境) だけのイメージを作成可能 -> docker image build --target {stage-name} {build-context}



ストレージ

docker のストレージは揮発性(=コンテナ破棄時に消滅)、

永続化させる方法が次の2つ、ボリューム、バインドマウント



関連コマンド

docker volume create {volume-name}

docker volume ls

docker volume inspect {volume-name}

docker volume rm {volume-name}

// ボリュームに接続しながらコンテナを作成する ( container-absolute-path のコンテナのパスにボリュームを接続する )

docker container run -v {volume-name}:{container-absolute-path} {image-name}