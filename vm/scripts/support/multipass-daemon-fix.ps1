# 対象: Windows 側の Multipass デーモン（multipassd）
# すること: プロセス停止・サービス再起動・list 確認
# WSL からは scripts/support/multipass-daemon-fix.sh 経由で実行する。
$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Public\multipass-fix-result.txt'
$mp = 'C:\Program Files\Multipass\bin\multipass.exe'

function Write-Log([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    $line | Tee-Object -FilePath $log -Append
}

Set-Content -Path $log -Value '' -Encoding UTF8
Write-Log '=== START ==='

Get-Process -Name multipass,multipassd -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Log ("Stop-Process " + $_.ProcessName + " pid=" + $_.Id)
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 2

Write-Log 'Stop-Service Multipass'
Stop-Service -Name Multipass -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$cache = 'C:\ProgramData\Multipass\cache\network-cache'
if (Test-Path $cache) {
    Write-Log "Remove $cache"
    Remove-Item -Path $cache -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Log 'Start-Service Multipass'
Start-Service -Name Multipass
Start-Sleep -Seconds 5

$svc = Get-Service -Name Multipass
Write-Log ("Service status: " + $svc.Status)

if ($svc.Status -ne 'Running') {
    Write-Log '=== FAIL (service not running) ==='
    exit 1
}

Write-Log 'multipass version'
$ver = & $mp version 2>&1 | Out-String
Write-Log $ver.Trim()

Write-Log 'multipass list'
$list = & $mp list 2>&1 | Out-String
Write-Log $list.Trim()

if ($LASTEXITCODE -eq 0) {
    Write-Log '=== SUCCESS ==='
    exit 0
}

Write-Log ("=== FAIL (exit=" + $LASTEXITCODE + ") ===")
exit 1
