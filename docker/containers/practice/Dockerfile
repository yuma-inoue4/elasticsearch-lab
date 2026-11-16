#---------------------
# 基礎的な構成
#---------------------
FROM ubuntu:22.04
RUN apt update
RUN apt install -y curl
COPY ./ /app/
CMD ["ls", "-la"]

#---------------------
# ENV と ARG
#---------------------
# ENV は、コンテナ内でのみ有効
ENV hoge="hoge"
ENV fuga="fuga"

# ARG は、ビルド時にのみ有効 -> コンテナ内では使用できない
ARG message="Hello, World!"
RUN echo $message > message.txt
CMD ["cat", "message.txt"]

#---------------------
# WORKDIR
#---------------------
# 未指定 -> / に 1.txt が作成される
RUN touch 1.txt

# /app/my_dir に移動して 2.txt を作成
WORKDIR /app/my_dir
RUN touch 2.txt

# 親ディレクトリに移動して 3.txt を作成
WORKDIR ..
RUN touch 3.txt
CMD ["bash"]

#---------------------
# マルチステージビルド
#---------------------
# base
FROM ubuntu:22.04 AS base
RUN apt update
CMD ["sh", "-c", "echo $environment"]

# dev
FROM base AS dev
ENV environment=dev

# prod
FROM base AS prod
ENV environment=prod