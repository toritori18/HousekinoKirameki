param(
    [Parameter(Mandatory = $true)]
    [string] $Name
)

# 命名規約に沿ったブランチを作成してチェックアウトする。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ブランチ名の規則チェック（feature/ fix/ docs/ のみ許可）
if ($Name -notmatch '^(feature|fix|docs)/.+') {
    Write-Host "ERROR: ブランチ名は feature/<機能名>、fix/<バグ名>、docs/<ドキュメント名> のいずれかの形式にしてください。" -ForegroundColor Red
    Write-Host "  詳細は docs/git-rules.md を参照してください。" -ForegroundColor Red
    exit 1
}

git checkout -b $Name
if (-not $?) {
    Write-Host "ERROR: ブランチ '$Name' の作成に失敗しました。" -ForegroundColor Red
    exit 1
}

Write-Host "ブランチ '$Name' を作成してチェックアウトしました" -ForegroundColor Green
