# qiita 作業手順をアップするための下書きをこちらに追記する

進捗
セクション5の20まで進行、21から再開

# Dockerの概要について軽く

イメージ(=ファイル)を基にコンテナを作成する
イメージはDockerHub等のレジストリから入手もしくは自作する
イメージの利用可能バージョンはレジストリのWebページから確認する

# 基礎的なコマンド

docker image pull {image}
docker image ls
docker image rm {image}
docker image inspect {image} # imageの詳細名設定を一覧(config -> cmd　のデフォルトコマンドの確認等)

docker container run {image} # イメージからコンテナを新規作成
docker container ls

docker container stop {container}
docker container restart {container}
docker container logs {container}
docker container rm {container} # exited のコンテナにのみ有効(削除する際はstopを)
docker container prune # exitedのコンテナ全削除
docker container exec {container} {command} # up状態のコンテナにコマンド実行させる
docker container -it exec {container} bash  # up状態のコンテナにbashでアクセス

# オプションに関して
docker container run -it {image}
-i -> 標準流力を有効
-t -> フォーマットを成形

# Windows

## Docker CLIのインストール

sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systmectl enable --now docker
sudo usermod -aG docker "$USER"
(一度、WSLを終了する。グループ反映のため)

## 動作確認

docker version
docker compose version
docker run --rm hello-world

# Mac

Orbstack CLIのインストール