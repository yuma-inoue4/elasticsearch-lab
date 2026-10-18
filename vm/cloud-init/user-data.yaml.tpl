#cloud-config
# Multipass 起動時の最小初期化（SSH 公開鍵のみ）。中身の作り込みは Ansible 側。
ssh_authorized_keys:
  - __SSH_PUBLIC_KEY__
