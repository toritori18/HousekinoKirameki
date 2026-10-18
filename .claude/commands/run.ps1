param(
    # 実行するステップ名。.claude/project.json の commands のキーを指定する（lint / format / test / typecheck / build 等）。
    [Parameter(Mandatory = $true)]
    [string] $Step
)

# .claude/project.json の commands.<Step> に定義されたコマンドを実行する汎用ランナー。
# /lint・/format・/test・/typecheck・/build の実体。
#
# コマンドが未設定（null）の場合は、失敗ではなく「未導入」として終了コード 0 で終わる。
# ツールを導入していない段階のプロジェクトでも、コマンドを呼べば状況が分かるようにするため。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'lib\project-config.ps1')

$RepoRoot = Get-RepoRoot
$config = Get-ProjectConfig

if ($null -eq $config) {
    Write-ProjectConfigMissing
    exit 1
}

$command = Get-ProjectCommand -Config $config -Name $Step
if ($null -eq $command) {
    Write-Host "このプロジェクトには $Step のコマンドが設定されていません（.claude/project.json の commands.$Step）。" -ForegroundColor Yellow
    Write-Host "  導入する場合は、ツールをユーザーに確認したうえで commands.$Step にコマンドを設定してください。" -ForegroundColor Yellow
    exit 0
}

Write-Host "$Step を実行しています（$command）..." -ForegroundColor Cyan
if (-not (Invoke-ProjectCommand -Command $command -WorkingDirectory $RepoRoot)) {
    Write-Host "ERROR: $Step（$command）に失敗しました。上記のログを確認してください。" -ForegroundColor Red
    exit 1
}

Write-Host "OK: $Step が完了しました。" -ForegroundColor Green
exit 0
