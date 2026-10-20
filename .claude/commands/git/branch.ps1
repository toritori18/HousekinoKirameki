param(
    [Parameter(Mandatory = $true)]
    [string] $Name
)

# 命名規約に沿ったブランチを、最新の origin/main から作成してチェックアウトする。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ブランチ名の規則チェック（feature/ fix/ docs/ のみ許可）
if ($Name -notmatch '^(feature|fix|docs)/.+') {
    Write-Host "ERROR: ブランチ名は feature/<機能名>、fix/<バグ名>、docs/<ドキュメント名> のいずれかの形式にしてください。" -ForegroundColor Red
    Write-Host "  詳細は docs/git-rules.md を参照してください。" -ForegroundColor Red
    exit 1
}

# 「今いるブランチ」から分岐すると、マージ済みブランチや古い main を土台にしてしまう。
# そのため常に最新の origin/main を起点にする。
git fetch origin main
if (-not $?) {
    Write-Host "WARNING: git fetch origin main に失敗しました（オフライン等）。手元の origin/main で続行します。古い可能性があります。" -ForegroundColor Yellow
}

$null = git rev-parse --verify --quiet refs/remotes/origin/main
if ($LASTEXITCODE -eq 0) {
    # --no-track: upstream を origin/main にしない（誤って main へ push しかねない状態を避ける）
    # 未コミットの変更は新ブランチへそのまま持っていかれる。衝突する場合は switch が失敗する
    # 出典: https://git-scm.com/docs/git-switch（-c / --no-track / <start-point>）
    git switch --no-track -c $Name origin/main
    if (-not $?) {
        Write-Host "ERROR: ブランチ '$Name' の作成に失敗しました。" -ForegroundColor Red
        Write-Host "  ブランチ名がすでに存在するか、未コミットの変更が origin/main との差分と衝突している可能性があります。" -ForegroundColor Red
        Write-Host "  対応方法: 別のブランチ名にするか、変更をコミットまたは git stash で退避してから再実行してください。" -ForegroundColor Red
        exit 1
    }
    Write-Host "origin/main を起点にブランチ '$Name' を作成してチェックアウトしました" -ForegroundColor Green
}
else {
    # リモート未設定のひな形状態など。従来どおり現在の HEAD から作成する
    Write-Host "WARNING: origin/main が見つからないため、現在の HEAD からブランチを作成します。" -ForegroundColor Yellow
    git switch -c $Name
    if (-not $?) {
        Write-Host "ERROR: ブランチ '$Name' の作成に失敗しました。" -ForegroundColor Red
        Write-Host "  対応方法: ブランチ名がすでに存在しないか確認してください。" -ForegroundColor Red
        exit 1
    }
    Write-Host "ブランチ '$Name' を作成してチェックアウトしました" -ForegroundColor Green
}
