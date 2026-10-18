# git リポジトリを初期化し、git hooks（pre-push の機密情報チェック）を登録する

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== git 初期化 ===" -ForegroundColor Cyan

if (-not (Test-Path ".git")) {
    Write-Host "git リポジトリが見つかりません。git init を実行します..." -ForegroundColor Yellow
    git init -b main
    if (-not $?) {
        Write-Host "ERROR: git init に失敗しました。git がインストールされているか確認してください。" -ForegroundColor Red
        exit 1
    }
}

git config core.hooksPath .claude/hooks
if (-not $?) {
    Write-Host "ERROR: core.hooksPath の設定に失敗しました。git リポジトリか確認してください。" -ForegroundColor Red
    exit 1
}

Write-Host "git リポジトリを初期化し、git hooks を登録しました（.claude/hooks）。" -ForegroundColor Green
