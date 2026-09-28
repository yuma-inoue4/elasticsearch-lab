# qiita 作業手順をアップするための下書きをこちらに追記する

進捗  
セクション5の32まで進行、33 レイヤー構造から再開

# Dockerの概要について軽く

イメージ(=ファイル)を基にコンテナを作成する  
イメージは Docker Hub 等のレジストリから入手もしくは自作する  
イメージの利用可能バージョンはレジストリの Web ページから確認する

# 基礎的なコマンド

```bash
docker image pull {image}
docker image ls
docker image rm {image}
docker image inspect {image} # image の詳細な設定を一覧（config → cmd のデフォルトコマンドの確認等）

docker container run {image} # イメージからコンテナを新規作成
docker container ls

docker container stop {container}
docker container restart {container}
docker container logs {container}
docker container rm {container} # exited のコンテナにのみ有効（削除する際は stop を）
docker container prune # exited のコンテナ全削除
docker container exec {container} {command} # up 状態のコンテナにコマンド実行させる
docker container exec -it {container} bash  # up 状態のコンテナに bash でアクセス
docker container rm -f {container} # up 状態のコンテナを直ちに削除
docker container attach {container} # デタッチのコンテナにアタッチする

docker image build {directory path}
```

# オプションに関して

```bash
docker container run -it {image}
```

- `-i` → 標準入力を有効
- `-t` → 疑似端末（TTY）を割り当て
- `--rm` → 動作実行後、直ちにコンテナを削除する（よく使う）
- `-f` → 強制（`rm` に合わせることで、up 状態のコンテナも削除可能）
- `-d` → デタッチドモードでコンテナ起動
- （`docker image build` 時）`-t` → 任意の文字列のタグをつける

# Windows

## Docker CLIのインストール

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

（一度、WSL を終了する。グループ反映のため）

## 動作確認

```bash
docker version
docker compose version
docker run --rm hello-world
```

# Mac

## OrbStack のインストール（Homebrew cask）

（Docker Desktop の代わり。入れるのは OrbStack。操作は `docker` / `docker compose`）

前提: Homebrew が入っていること（`brew -v` で確認）

```bash
brew install --cask orbstack
orb start # orbstack のエンジン起動
```

## 動作確認

```bash
docker version
docker compose version
docker run --rm hello-world
```

うまくいかないとき:

- `orb start` 済みか
- ターミナルを開き直す（PATH 反映）
- `which docker` で OrbStack 配下を指しているか確認
- 更新: `brew upgrade --greedy orbstack`

# Dockerfile に関して

レジストリから入手可能なイメージは、動作に必要最低限しか入っていないため、カスタマイズが必須

```dockerfile
COPY {追加元} {追加先}
```

`COPY`: ホスト上のファイルをコンテナに配置できる

なお、コンテナ側に存在しないディレクトリをした際は、新規作成される



ビルドコンテキスト -> image build 時にコンテナ作成のための素材をひとまとめに送る仕組み

dockerfile も ファイル群も全て、この配下に格納すること

docker image build {ビルドコンテキストパス}



.dockerignore

大容量やパスワードファイルなど、コンテキストに含めたくないファイルを記載する

ignoreファイル自体はtouch で作成したらいい



デフォルトコマンドの設定  
CMD ["実行ファイル", "パラメータ1", "パラメータ2"]

コンテナ実行時のデフォルトコマンド

複数行書いても、最後に書かれたものしか実行されない