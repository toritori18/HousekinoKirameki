param(
    [Parameter(Mandatory = $true)]
    [string] $Message
)

# 追跡済みファイルをステージングし、シークレットの混入とブランチ名を確認してからコミット・プッシュする。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# .env.local などシークレットファイルが追跡されていないか確認
$secrets = git ls-files --error-unmatch .env.local 2>$null
if ($secrets) {
    Write-Host "ERROR: .env.local が git の追跡対象になっています。" -ForegroundColor Red
    Write-Host "  対応方法: git rm --cached .env.local で追跡から外してから再実行してください。" -ForegroundColor Red
    exit 1
}

# 追跡済みファイルのみステージング（未追跡の新規ファイルは含めない）
git add -u
if (-not $?) {
    Write-Host "ERROR: git add に失敗しました。" -ForegroundColor Red
    exit 1
}

# 新規ファイル（未追跡）があれば警告して表示
$untracked = git ls-files --others --exclude-standard
if ($untracked) {
    Write-Host "WARNING: 以下の新規ファイルはステージングされていません（必要なら git add で追加してください）:" -ForegroundColor Yellow
    $untracked | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

# コミット
git commit -m $Message
if (-not $?) {
    Write-Host "ERROR: git commit に失敗しました。" -ForegroundColor Red
    exit 1
}

# 現在のブランチを取得
$branch = git rev-parse --abbrev-ref HEAD

# main への直接プッシュは git-rules.md により禁止（すべて PR 経由でマージする）
if ($branch -eq "main") {
    Write-Host "ERROR: main への直接プッシュは禁止されています（docs/git-rules.md）。" -ForegroundColor Red
    Write-Host "  対応方法: feature/<機能名> または fix/<バグ名> ブランチで作業し、PR 経由でマージしてください。" -ForegroundColor Red
    exit 1
}

git push origin $branch
if (-not $?) {
    Write-Host "ERROR: git push に失敗しました。" -ForegroundColor Red
    exit 1
}

Write-Host "origin/$branch にプッシュしました" -ForegroundColor Green
