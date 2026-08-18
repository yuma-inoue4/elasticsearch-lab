# Mac

## Multipass

```bash
# インストール
brew install --cask multipass

# バージョン確認
multipass version

# 動作テスト
multipass launch -n test-vm -c 1 -m 1G -d 5G
multipass list
multipass shell test-vm

# 削除
multipass delete --purge test-vm
```

## Ansible

```bash
# インストール
sudo apt update
sudo apt install ansible
ansible --version

# 動作テスト
ansible localhost -m ping -c local
```

## WSL（Ubuntu 22.04）

apt の Ansible は 2.10 のままなので、作り込みには使わない。ホスト用に 2.17 をユーザー領域へ入れてある。

```bash
python3 -m pip install --user 'ansible-core>=2.17.0,<2.18.0'
export PATH="$HOME/.local/bin:$PATH"
ansible --version   # ansible [core 2.17.x] であること
```

作り込みの実行場所は `es-controller`（`bash scripts/controller-ansible-run.sh`）。WSL の Ansible は VM 作成などホスト作業用。

