#--- 基礎的な構成
# FROM ubuntu:22.04
# RUN apt update
# RUN apt install -y curl
# COPY ./ /app/
# CMD ["ls", "-la"]

#--- ENV と ARG の違い
# ENV hoge="hoge"
# ENV fuga="fuga"
# ARG message="Hello, World!"
# RUN echo $message > message.txt
# CMD ["cat", "message.txt"]

#--- WORKDIR の使い方
# 未指定 -> / に 1.txt が作成される
# RUN touch 1.txt
# WORKDIR /app/my_dir
# RUN touch 2.txt
# WORKDIR ..
# RUN touch 3.txt
# CMD ["bash"]

# ---マルチステージビルド
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