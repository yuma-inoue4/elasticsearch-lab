# elasticsearch-lab

Multipass VM 4 台の Elasticsearch 検証環境。

- **VM 作成・削除・鍵配布**: ホスト（Mac / WSL2）から実行する
- **ES / Kibana などの作り込み**: 必ず `es-controller` 上の Ansible で実行する（`bash scripts/controller-ansible-run.sh`）

WSL の Ansible は 2.17 系にしてあるが、作り込みはホストの `ap` ではなく controller 経由が正式手順。

スクリプトの一覧・対象・使い方は [`scripts/README.md`](scripts/README.md) を見る。

## 構成

| VM | 役割 | 目安 |
|---|---|---|
| `es-controller` | Ansible 制御ノード | 2G / 2CPU |
| `es-stack` | Elasticsearch / Kibana | 4G / 2CPU |
| `es-target-01` | ログ送信元 | 1G / 1CPU |
| `es-target-02` | ログ送信元 | 1G / 1CPU |

## 手順

Windows はホストに Multipass を入れ、WSL2 から実行する。旧 VM（`vm-target-*` / `vm-es-stack`）が残っている場合は先に消す。

```bash
bash scripts/vms-delete.sh --legacy          # 旧構成の VM を削除（任意）
bash scripts/vms-create.sh                   # 4 台起動 + controller に Ansible を入れる
bash scripts/controller-ansible-run.sh       # bootstrap + ES/Kibana + ログ生成/Filebeat
```

Multipass が無応答なら `bash scripts/support/multipass-daemon-fix.sh`。

## まだ未実装

- Elastic Agent / Fleet（`playbook/elastic_agent.yaml`）
