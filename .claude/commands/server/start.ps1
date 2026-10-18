# 開発サーバーを起動する（既存プロセスがあれば停止してから、バックグラウンドで起動する）。
#
# 起動コマンドと待ち受けポートは .claude/project.json の devServer が持つ。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '..\lib\project-config.ps1')

$RepoRoot = Get-RepoRoot
$config = Get-ProjectConfig

if ($null -eq $config) {
    Write-ProjectConfigMissing
    exit 1
}

$devServer = Get-ConfigProperty -Object $config -Name 'devServer'
$command = Get-ConfigProperty -Object $devServer -Name 'command'
$port = Get-ConfigProperty -Object $devServer -Name 'port'

if ([string]::IsNullOrWhiteSpace($command)) {
    Write-Host "このプロジェクトには開発サーバーの起動コマンドが設定されていません（.claude/project.json の devServer.command）。" -ForegroundColor Yellow
    Write-Host "  開発サーバーを使う構成であれば、devServer.command と devServer.port を設定してください。" -ForegroundColor Yellow
    exit 0
}

# 既存の開発サーバーがあれば停止する（ポートが分かる場合のみ判定できる）
if ($null -ne $port) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) {
        $procId = $conn.OwningProcess
        Stop-Process -Id $procId -Force
        Write-Host "既存の開発サーバー (PID: $procId) を停止しました" -ForegroundColor Yellow

        # ポートが解放される前に新しいインスタンスを起動すると、後段の起動確認が古い待ち受けを拾って
        # 「起動成功」と誤判定するため、解放を待ってから起動する（最大10秒）
        $released = $false
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
                $released = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $released) {
            Write-Host "ERROR: ポート $port が10秒以内に解放されませんでした。ポートを使用しているプロセスを手動で停止してから再実行してください。" -ForegroundColor Red
            exit 1
        }
    }
}

# ログの出力先（.gitignore の logs/ で除外済み）。.claude/ は版管理する設定の置き場なので、
# 実行時の生成物であるログは logs/ に分ける
$logDir = Join-Path $RepoRoot 'logs'
# Start-Process のリダイレクト先は、ディレクトリが無いと起動そのものが失敗するため先に作る
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$log = Join-Path $logDir 'dev-server.log'
$errorLog = Join-Path $logDir 'dev-server.err.log'
Remove-Item -LiteralPath $log, $errorLog -Force -ErrorAction SilentlyContinue

# npm のようにシェル経由でないと解決できないコマンド（npm.cmd 等）があるため cmd /c で起動する。
# Start-Process のリダイレクト先は呼び出し元のカレントディレクトリを基準に解決されるため、
# ログのパスは絶対パスで渡している。
$process = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", $command `
    -WorkingDirectory $RepoRoot `
    -RedirectStandardOutput $log -RedirectStandardError $errorLog `
    -WindowStyle Hidden -PassThru

if ($null -eq $port) {
    # ポートが分からない構成では待ち受けを確認できないため、プロセスの起動だけを報告する
    Write-Host "開発サーバーを起動しました（PID: $($process.Id)、コマンド: $command）" -ForegroundColor Green
    Write-Host "  ログ: $log"
    exit 0
}

# 起動確認: 最大30秒待つ
$started = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        $started = $true
        break
    }
    # プロセスが即死した場合は待たずに打ち切る
    if ($process.HasExited) {
        break
    }
}

if ($started) {
    Write-Host "開発サーバーを起動しました: http://localhost:$port/ （ログ: $log）" -ForegroundColor Green
}
else {
    Write-Host "ERROR: 開発サーバーの起動を確認できませんでした。ログを確認してください。" -ForegroundColor Red
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log -Tail 20
    }
    if ((Test-Path -LiteralPath $errorLog) -and (Get-Item -LiteralPath $errorLog).Length -gt 0) {
        Write-Host "--- 標準エラー出力（$errorLog） ---" -ForegroundColor Red
        Get-Content -LiteralPath $errorLog -Tail 20
    }
    exit 1
}
