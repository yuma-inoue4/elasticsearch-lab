# elasticsearch-lab

Elasticsearch の試験・検証用リポジトリ。

## 直下の構成

| パス                   | 役割                                                           |
| -------------------- | ------------------------------------------------------------ |
| [`docker/`](docker/) | **本線。** Docker Compose で ES / Kibana などを構築（Mac / Windows 共通） |
| [`vm/`](vm/)         | **横置き。** Multipass VM + Ansible による旧構成                       |

## FAQ

### ES コンテナがすぐ落ちる（Exited 78）

**ホスト側のカーネル設定**が原因

WSL2 / Linux での対処:

```bash
# 一時（再起動で戻る）
sudo sysctl -w vm.max_map_count=262144

# 永続化
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

確認後にスタックを起動し直す:

```bash
cat /proc/sys/vm/max_map_count   # 262144 であること
cd docker/containers/el-stack
docker compose up -d
```