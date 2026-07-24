# JSON / Jinja2 フィルタメモ

## 全体の流れ

1. コマンド結果は「文字列」として来る（`register.stdout`）
2. `from_json` でオブジェクトに変換
3. `.key` / `[0]` で特定の場所へ進む
4. `map` でリスト各要素から同じキーを取る
5. `list` で結果をリスト型に確定

---

## `from_json`

JSON 文字列 → dict / list などのオブジェクトに変換する。

変換前は文字列なので、`.list` や `['name']` は使えない。

```jinja
'{"list":[{"name":"a"}]}' | from_json
→ {"list": [{"name": "a"}]}
```

---

## `map(attribute='name')`

dict のリストから、各要素の特定キーの値だけを取り出す。

```jinja
[
  {"name": "vm-1", "cpus": 1},
  {"name": "vm-2", "cpus": 2}
] | map(attribute='name')
→ ["vm-1", "vm-2"] 相当
```

---

## `list`

`map` などの結果を本当のリスト型に確定させる。

`in` 判定などで失敗しやすいので、実務では `| list` を付ける。

```jinja
... | map(attribute='name') | list
→ ["vm-1", "vm-2"]
```

---



## JSON から特定の値を取る例

前提データ:

```json
{
  "list": [
    {"name": "vm-worker-1", "ipv4": ["192.168.64.2"]},
    {"name": "vm-worker-2", "ipv4": ["192.168.64.3"]}
  ]
}
```


| 欲しいもの       | 書き方      |
| ----------- | -------- |
| 全体をオブジェクトに  | `stdout  |
| `list` 配列全体 | `(stdout |
| 全 VM の名前一覧  | `(stdout |
| 先頭の VM 名    | `(stdout |
| 先頭の IP      | `(stdout |
| 特定名の VM だけ  | `(stdout |




### playbook での `when` 例

```yaml
when: item.name not in (current_vms_names | map(attribute='name') | list)
```

---

## SSH / 鍵まわり（2026-07-24）

この lab は **WSL2 上で Ansible**、VM は **Windows 版 Multipass（Hyper-V）**。  
ネットワークが別なので、SSH 経路に注意が必要。

### 症状と原因

| 症状 | 原因 |
|------|------|
| WSL から `ping` / `ssh` がハング・不通 | WSL2 と Multipass VM（172.x）が別ネットワーク |
| `mp shell` / `mp exec` は通る | Multipass デーモン経由なのでネットワーク問題を回避できる |
| `C:\ProgramData\Multipass\data\ssh-keys\id_rsa` が読めない | ProgramData は一般ユーザー不可。WSL からも Permission denied |
| PowerShell で `Identity file ... not accessible` | Windows 側に秘密鍵が無い（WSL の `~/.ssh` にしか無い） |
| `Load key ... Permission denied`（Windows） | 秘密鍵の ACL が壊れている（`----------` 相当） |

### 採用した解決策

1. **Multipass 標準鍵は使わない**（読めないため）
2. WSL で自前鍵を作成

```bash
ssh-keygen -t ed25519 -f ~/.ssh/elastic_ed25519 -N ""
chmod 600 ~/.ssh/elastic_ed25519
```

3. **公開鍵**を VM に配布（秘密鍵は VM に置かない）

```bash
PUB=$(cat ~/.ssh/elastic_ed25519.pub)
# 改行せず 1 行で（authorized_keys が a / uthorized_keys に割れないよう注意）
mp exec vm-target-01 -- bash -lc "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
mp exec vm-target-02 -- bash -lc "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

4. 秘密鍵を Windows ユーザー `.ssh` にコピーし、ACL を修正

```powershell
# PowerShell（必要なら管理者）
icacls $env:USERPROFILE\.ssh\elastic_ed25519 /inheritance:r
icacls $env:USERPROFILE\.ssh\elastic_ed25519 /grant:r "$($env:USERNAME):(R)"
```

5. PowerShell で疎通確認（成功済み）

```powershell
ssh -i $env:USERPROFILE\.ssh\elastic_ed25519 `
  -o StrictHostKeyChecking=no `
  ubuntu@172.19.28.56
```

6. Ansible は **Windows の ssh.exe** を使う（WSL の ssh では VM に届かない）

```yaml
# inventory/group_vars/all.yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: /mnt/c/Users/y.inoue/.ssh/elastic_ed25519
ansible_ssh_executable: /mnt/c/Windows/System32/OpenSSH/ssh.exe
ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

### 覚え方

| 鍵 | 置く場所 |
|----|----------|
| 公開鍵 `.pub` | VM の `~/.ssh/authorized_keys` |
| 秘密鍵 | 接続元（Windows `.ssh`）。**VM には配らない** |

### 次回（Play 3）

`docs/progress.md` の「次回はここから」を参照。  
`create-vms.yaml` に `hosts: "{{ vm_group }}"` の Play を完成させ、`wait_for_connection` + `ping`。

