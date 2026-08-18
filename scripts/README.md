# scripts 説明書

このディレクトリは、**ホスト（Mac 本体、または Windows では WSL2）から叩く Bash** です。  
名前は **「対象-すること」** です。

- **直接実行する入口** … この直下の 3 ファイル
- **単体では実行しないもの・障害時だけ使うもの** … [`support/`](support/)

Ansible の Playbook 本体は `ansible/playbook/` にあります。

```bash
bash scripts/vms-create.sh
```

---

## 直接実行する（この直下）

| ファイル | 対象 | すること |
|---|---|---|
| `vms-create.sh` | Multipass VM 4 台 | 起動する（中身は入れない） |
| `vms-delete.sh` | Multipass VM | 削除する |
| `controller-ansible-run.sh` | es-controller 上の Ansible | Playbook を実行する |

```bash
bash scripts/vms-delete.sh --legacy     # 旧 VM（vm-target-* 等）があるときだけ
bash scripts/vms-create.sh
bash scripts/controller-ansible-run.sh
```

SSH で controller に入る必要はありません。`controller-ansible-run.sh` が `multipass exec` で中の `ansible-playbook` を起動します。

特定の Playbook だけ回すとき:

```bash
bash scripts/controller-ansible-run.sh playbook/elastic_stack.yaml
```

### `vms-create.sh`

- **すること:** Multipass で VM を起動する
- **しないこと:** Elasticsearch のインストールなど、VM 内部の作り込み
- **ついでにやること:** inventory 生成、controller への SSH 鍵と Ansible 一式の配置、`ansible-core` の導入

すでに Running で IP がある VM は作り直しません。

### `vms-delete.sh`

```bash
bash scripts/vms-delete.sh              # 改訂案の 4 台だけ
bash scripts/vms-delete.sh --legacy     # 旧名 vm-target-01 なども消す
```

### `controller-ansible-run.sh`

- **すること:** inventory を更新してから、controller 上で Playbook を実行する
- **引数なし:** `playbook/site.yaml`（bootstrap + Elasticsearch / Kibana）

ホストの `ap`（WSL の Ansible）では作り込みしません。

---

## 役割の切り分け

```text
[ホスト: Mac または WSL2]
    vms-create.sh / vms-delete.sh     … 箱（VM）の作成・削除
    controller-ansible-run.sh         … controller へ「Playbook を実行して」と頼む
            │
            ▼  multipass exec（ログインしない）
[es-controller]
    ansible-playbook
            │
            ▼  SSH
[es-stack] [es-target-01] [es-target-02]
```

障害時の直し方は [`support/README.md`](support/README.md) を見る。
