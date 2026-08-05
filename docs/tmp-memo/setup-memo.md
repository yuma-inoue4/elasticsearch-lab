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

