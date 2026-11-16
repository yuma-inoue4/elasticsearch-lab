# elasticsearch-lab

Elasticsearch の試験・検証用リポジトリ。

## 直下の構成

| パス | 役割 |
|------|------|
| [`docker/`](docker/) | **本線。** Docker Compose で ES / Kibana などを構築（Mac / Windows 共通） |
| [`vm/`](vm/) | **横置き。** Multipass VM + Ansible による旧構成 |
| `README.md` | このファイル |

## 本線（Docker）

方針・要件: [`docker/docs/zentai-keikaku.md`](docker/docs/zentai-keikaku.md)  
手順書: [`docker/docs/el-setup-manual.md`](docker/docs/el-setup-manual.md)  
スタック作業ディレクトリ: [`docker/el-stack/`](docker/el-stack/)

実行環境の目安:

- Windows: WSL2 + Docker Engine（CLI）
- Mac: OrbStack（CLI 中心）

## 旧構成（VM / Multipass）

詳細は [`vm/README.md`](vm/README.md) と [`vm/scripts/README.md`](vm/scripts/README.md)。

```bash
bash vm/scripts/vms-create.sh
bash vm/scripts/controller-ansible-run.sh
```
