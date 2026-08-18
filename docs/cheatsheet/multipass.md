# Multipass チートシート

elasticsearch-lab 向け。WSL2 + Windows 版 Multipass の導入から、ログ送信元 VM の手動操作まで。

---

## 導入手順（0 から WSL2 連携まで）

### 前提


| 項目              | 内容                                  |
| --------------- | ----------------------------------- |
| ホスト OS          | Windows ラップトップ                      |
| Linux 環境        | WSL2（Ubuntu 22.04 推奨）               |
| Multipass の置き場所 | **Windows 側**（WSL2 内ではなくホストにインストール） |
| バックエンド          | Hyper-V（Windows 版 Multipass が利用）    |


> **注意:** `apt install multipass` は使えない。Ubuntu の apt リポジトリに `multipass` パッケージはない。Linux ネイティブ向けは `snap install multipass` が公式手順だが、本 lab では **Windows 版 + WSL2 から呼び出す** 構成を採用する。

---

### Step 1: Windows の仮想化を有効化

Multipass（Windows 版）は Hyper-V を使う。

1. **設定 → プライバシーとセキュリティ → Windows のセキュリティ → デバイスのセキュリティ → コアの分離**
  - メモリの整合性が **オン** になっていること（Hyper-V と共存要件）
2. **Windows の機能の有効化または無効化**
  - 「Hyper-V」にチェック（Pro / Enterprise 等で利用可能）
  - 「Windows ハイパーバイザー プラットフォーム」にチェック
3. 必要なら PC を再起動

BIOS/UEFI で仮想化支援（Intel VT-x / AMD-V）が有効であることも確認する。

---



### Step 2: Multipass を Windows にインストール

1. 公式サイトから `.msi` を取得
  [https://canonical.com/multipass/install](https://canonical.com/multipass/install)
2. インストーラを **管理者権限** で実行
3. インストール先（デフォルト）:
  ```text
   C:\Program Files\Multipass\bin\multipass.exe
  ```
4. **PowerShell** で確認:
  ```powershell
   multipass version
  ```
   例:

---



### Step 3: WSL2 を用意する

WSL2 + Ubuntu が未導入の場合（PowerShell を管理者で）:

```powershell
wsl --install
```

すでに入っている場合はバージョン確認:

```powershell
wsl -l -v
```

`VERSION` が `2` であること。Ubuntu ディストリビューションを起動し、初期ユーザー設定を済ませる。

WSL2 内での確認:

```bash
cat /etc/os-release   # Ubuntu 22.04 など
uname -a              # microsoft-standard-WSL2 と出れば WSL2
```

---



### Step 4: WSL2 から Multipass を呼べるようにする

WSL2 のターミナル（bash）でエイリアスを設定する。

```bash
# ~/.bashrc に追記
echo 'alias multipass="/mnt/c/Program\ Files/Multipass/bin/multipass.exe"' >> ~/.bashrc
echo 'alias mp="/mnt/c/Program\ Files/Multipass/bin/multipass.exe"' >> ~/.bashrc
source ~/.bashrc
```

`multipassd` が詰まったとき用に `mp-fix` も `~/.bashrc` に定義しておく（詳細は下記「mp-fix」参照）。

```bash
# multipassd 詰まり時: UAC 承認後に Windows 側で強制再起動
mp-fix() {
  powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Public\fix-multipass-windows.ps1'"
  echo "UAC を承認してください。完了後: cat /mnt/c/Users/Public/multipass-fix-result.txt"
}
```

Windows 側の修復スクリプト `C:\Users\Public\fix-multipass-windows.ps1` を用意しておく（初回セットアップ時に配置）。


| 呼び方         | 説明                     |
| ----------- | ---------------------- |
| `multipass` | 正式名                    |
| `mp`        | 短い別名（このチートシートではどちらも同義） |
| `mp-fix`    | multipassd 詰まり時の修復コマンド |


動作確認:

```bash
multipass version
# または
mp version
```

PowerShell から使う場合はエイリアス不要。`multipass` をそのまま実行する。

---



### Step 5: 初回 VM 起動と動作確認

```bash
# VM 作成（初回はイメージ DL のため数分かかる）
mp launch --name test-vm --memory 1G --cpus 1

# 一覧（Running と IPv4 が出れば OK）
mp list

# 詳細
mp info test-vm

# VM に入る
mp shell test-vm
```

VM 内で最低限確認:

```bash
whoami          # ubuntu
hostname        # test-vm
uname -n
cat /etc/os-release
ping -c 3 8.8.8.8
exit            # ホスト（WSL2）に戻る
```

ホスト側からシェルに入らず実行:

```bash
mp exec test-vm -- hostname
mp exec test-vm -- ping -c 3 8.8.8.8
```

JSON で IP 確認（Ansible が後で使う形式）:

```bash
mp list --format json
```

---



### Step 6: ライフサイクル操作の確認

```bash
mp stop test-vm
mp list                    # State: Stopped

mp start test-vm
mp list                    # State: Running（IP は多くの場合同じだが固定ではない）
```

---



### 導入完了チェックリスト

- [ ] Windows に Multipass が入り、`multipass version` が通る
- [ ] WSL2（Ubuntu）が動く
- [ ] WSL2 から `mp version` が通る
- [ ] `mp launch` で VM が **Running** になる
- [ ] `mp list` で **IPv4** が表示される
- [ ] `mp shell` で VM に入れる
- [ ] `mp exec` でホストからコマンド実行できる
- [ ] VM 内から `ping 8.8.8.8` が通る

ここまでできれば、WSL2 と Multipass の連携は完了。

---



### 補足: WSL2 内に snap 版を入れる場合（非推奨）

```bash
sudo apt update
sudo apt install snapd
sudo systemctl enable --now snapd
sudo snap install multipass
```

WSL2 上の snap 版はネットワークや snapd 周りでつまずきやすい。**検証 lab では Windows 版を使う方が安定**する。

---



### 補足: IP アドレスについて

- VM の IPv4 は Multipass の仮想ネットワーク（DHCP）から割り当て
- `stop` / `start` では **だいたい同じ IP のまま** だが、保証はない
- `delete` → `launch` や PC 再起動後は **変わることがある**
- 手書き inventory に IP を直書きしない。Ansible では `mp list --format json` で都度取得する

---



## VM の作成・起動

```bash
# 基本（名前・メモリ・CPU を指定）
mp launch --name vm-source-01 --memory 1G --cpus 1

# 2 台目（仕様書の初期構成）
mp launch --name vm-source-02 --memory 1G --cpus 1

# イメージ（Ubuntu バージョン）を指定
mp launch 24.04 --name test-vm --memory 1G --cpus 1

# ディスクサイズを指定（デフォルト 5GB）
mp launch --name test-vm --disk 10G
```



## 状態確認

```bash
# 一覧（名前・状態・IP）
mp list

# JSON 出力（Ansible で IP 取得するときと同形式）
mp list --format json

# 詳細（IP、CPU、メモリ、ディスク、マウントなど）
mp info vm-source-01

# Multipass 本体のバージョン
mp version

# 利用可能な Ubuntu イメージ一覧
mp find
```



## VM への接続

```bash
# VM にシェルで入る
mp shell vm-source-01

# コマンドを 1 回だけ実行（シェルに入らない）
mp exec vm-source-01 -- hostname
mp exec vm-source-01 -- ip -4 addr show
mp exec vm-source-01 -- cat /etc/os-release
```



## 停止・再起動

```bash
mp stop vm-source-01
mp start vm-source-01
mp restart vm-source-01
```



## 削除

```bash
# 削除マーク（一覧には残る。State: Deleted）
mp delete vm-source-01

# 完全削除（delete 後に実行。Deleted 状態の VM だけ消える）
mp purge

# 停止してから削除
mp stop vm-source-01 && mp delete vm-source-01 && mp purge

# 一発で完全削除（推奨）
mp stop --force vm-source-01
mp delete --purge vm-source-01
```

> **注意:** `mp purge` だけでは **Running / Stopped の VM は消えない**。先に `mp delete`（または `mp delete --purge`）が必要。



### 壊れた VM（IPv4 が N/A、`mp launch` 中断後など）

起動は `Running` だが IP が `N/A` のまま、`mp info` が `ssh connection failed` / `test-vm.mshome.net` 解決失敗になる VM は **作成が中途半端に終わった状態**。

```bash
# 1. 強制停止 → 完全削除
mp stop --force test-vm
mp delete --purge test-vm
mp list    # No instances found. なら OK

# 2. 10 秒以上返らなければ Ctrl+C → mp-fix（multipassd 詰まり）
mp-fix
```

削除後、**`mp-fix` でネットワークを直してから** 作り直す（詳細は下記「mp-fix」参照）。

## ファイル共有（参考）

```bash
# ホストのディレクトリを VM にマウント
mp mount /path/on/host vm-source-01:/path/on/vm

# マウント解除
mp umount vm-source-01:/path/on/vm
```



## よく使う確認コマンド（VM 内）

`mp shell` で入ったあと:

```bash
hostname
ip -4 addr show
ping -c 3 8.8.8.8          # 外向き通信確認
systemctl status ssh         # SSH サービス確認
```



## elasticsearch-lab 用クイックスタート

```bash
mp launch --name vm-source-01 --memory 1G --cpus 1
mp launch --name vm-source-02 --memory 1G --cpus 1
mp list
mp shell vm-source-01
```



## トラブルシュート

```bash
# 詳細ログ（サポート・調査用）
mp launch -vvv --name debug-vm
```



### mp-fix（multipassd 詰まり時）

WSL2 から `mp version` や `mp list` が **10 秒以上返らない**（ハングする）とき、Windows 側の `multipassd` が応答不能になっている可能性が高い。サービスは `Running` でも CLI が固まることがある。

**症状の例:**

- `mp version` / `mp list` が無限に待つ（数分待っても返らない）
- `mp launch` を Ctrl+C で中断したあと、以降すべての `mp` コマンドが遅くなる・固まる
- IPv4 が `N/A` の VM が残っている

**修復手順:**

```bash
mp-fix
# UAC ダイアログが出たら「はい」をクリック

# 完了確認（SUCCESS と出れば OK）
cat /mnt/c/Users/Public/multipass-fix-result.txt

mp version   # 数秒以内に返れば復旧
mp list
```

`scripts/support/multipass-daemon-fix.sh` が行うこと（`multipass-daemon-fix.ps1`）:

1. `multipass.exe` / `multipassd.exe` プロセスを強制終了
2. Multipass Windows サービスを停止 → 再起動
3. `C:\ProgramData\Multipass\cache\network-cache` を削除
4. `multipass version` / `multipass list` で動作確認し、結果をログに書き出す

**修復後の追加作業（IPv4 が N/A の VM がある場合）:**

```bash
mp stop --force <name>
mp delete --purge <name>
mp list    # 問題の VM が消えていることを確認してから作り直す
```

**再発を減らすコツ:**

- `mp launch` 実行中は Ctrl+C で中断しない（Ansible playbook 実行中も同様）
- 連続 `launch` のあとは playbook 同様 `sleep 5` 程度空ける
- 頻発する場合は Windows の「高速スタートアップ」を無効化する

**それでも直らない場合:**

- Windows を再起動
- PowerShell（管理者）から `scripts/support/multipass-daemon-fix.ps1` を直接実行
- WSL interop 問題の疑いがある場合: `sudo bash scripts/support/wsl-exe-launch-fix.sh` のあと `wsl --shutdown`（PowerShell 側）→ WSL を開き直す


| 症状                                    | 確認すること                                |
| ------------------------------------- | ------------------------------------- |
| `mp` コマンドが 10 秒以上返らない / ハングする      | `mp-fix` → ログで `=== SUCCESS ===` を確認 |
| WSL2 で `multipass: command not found` | `~/.bashrc` のエイリアス、`source ~/.bashrc` |
| `multipass.exe` が見つからない               | Windows 側にインストール済みか、パスが正しいか           |
| `apt install multipass` が失敗する         | apt にパッケージはない。Windows 版を使う            |
| VM が起動しない                             | Hyper-V 有効か、メモリ不足でないか                 |
| VM からネットに出られない                        | `mp exec <name> -- ping -c 3 8.8.8.8` |
| IP がわからない                             | `mp list` または `mp info <name>`        |
| IP が変わった                              | 正常。`mp list --format json` で再取得       |
| IPv4 が N/A のまま                        | VM を `--purge` 削除 → `mp-fix` → 作り直し |