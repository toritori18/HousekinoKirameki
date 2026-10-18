# 開発サーバーを停止する。待ち受けポートは .claude/project.json の devServer.port が持つ。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '..\lib\project-config.ps1')

$config = Get-ProjectConfig

if ($null -eq $config) {
    Write-ProjectConfigMissing
    exit 1
}

$devServer = Get-ConfigProperty -Object $config -Name 'devServer'
$port = Get-ConfigProperty -Object $devServer -Name 'port'

if ($null -eq $port) {
    Write-Host "このプロジェクトには開発サーバーの待ち受けポートが設定されていません（.claude/project.json の devServer.port）。" -ForegroundColor Yellow
    Write-Host "  停止するプロセスを特定できないため、何もしませんでした。" -ForegroundColor Yellow
    exit 0
}

$conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) {
    $procId = $conn.OwningProcess
    Stop-Process -Id $procId -Force
    Write-Host "開発サーバー (PID: $procId) を停止しました"
}
else {
    Write-Host "ポート $port で起動中のサーバーはありません"
}
