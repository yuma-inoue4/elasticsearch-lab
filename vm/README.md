# vm/ — Multipass + Ansible 構成（横置き）

Docker Compose 本線に移る前の、VM 4 台構成の資材。

| パス | 内容 |
|------|------|
| `ansible/` | Playbook・inventory・templates |
| `cloud-init/` | Multipass 起動時の cloud-init テンプレート |
| `scripts/` | VM 作成・削除・controller 上 Ansible 実行 |
| `state/` | 生成物（鍵・描画済み cloud-init 等）。Git 管理外 |
| `docs/` | 旧メモ・チートシート |

入口スクリプト:

```bash
bash vm/scripts/vms-create.sh
bash vm/scripts/controller-ansible-run.sh
bash vm/scripts/vms-delete.sh
```

一覧は [`scripts/README.md`](scripts/README.md)。
