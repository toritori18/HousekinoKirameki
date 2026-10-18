param(
    # 既定は一覧表示のみ。削除は明示的に指定された場合しか行わない。
    # git/merge.md の「ブランチ削除はユーザーに確認してから別途行う」という方針に合わせ、
    # 引数なしで呼び出された場合に削除が起きないことをスクリプト側で保証する。
    [ValidateSet("None", "Local", "LocalAndRemote")]
    [string] $Delete = "None"
)

# main にマージ済みのローカルブランチを一覧表示・削除する。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# git リポジトリでなければ中止する（/git:init 前の状態）
$null = git rev-parse --git-dir 2>$null
if (-not $?) {
    Write-Host "ERROR: git リポジトリではありません。先に /git:init を実行してください。" -ForegroundColor Red
    exit 1
}

# マージ済み判定の基準を決める。
# /git:merge は GitHub 上でマージするため、ローカルの main は誰かが明示的に pull しない限り
# 更新されず古いままになりやすい。古い main を基準にすると、実際にはマージ済みのブランチが
# 一覧から漏れる。そのため origin/main を優先し、無い場合のみローカル main にフォールバックする。
$baseRef = $null
git show-ref --verify --quiet refs/remotes/origin/main
if ($?) {
    $baseRef = "origin/main"
}
else {
    git show-ref --verify --quiet refs/heads/main
    if (-not $?) {
        Write-Host "ERROR: origin/main もローカルの main も見つかりませんでした。マージ済みブランチを判定できません。" -ForegroundColor Red
        Write-Host "  対応方法: git fetch origin を実行するか、main ブランチがあるか確認してください。" -ForegroundColor Red
        exit 1
    }
    $baseRef = "main"
    Write-Host "WARNING: origin/main が見つかりません。ローカルの main を基準にします（実際よりマージ済みが少なく出ることがあります）。" -ForegroundColor Yellow
}

$current = git rev-parse --abbrev-ref HEAD

# 基準ブランチにマージ済みのローカルブランチを列挙する。
# git branch --merged の出力には、現在のブランチに '*'、別のワークツリーで
# チェックアウト中のブランチに '+' が付くため、記号と空白を除去してから比較する。
$merged = @(
    git branch --merged $baseRef |
        ForEach-Object { $_.TrimStart('*', '+', ' ').Trim() } |
        Where-Object { $_ -ne 'main' -and $_ -ne $current -and $_ -ne '' }
)

if ($merged.Count -eq 0) {
    Write-Host "削除できるマージ済みブランチはありません。" -ForegroundColor Green
    Write-Host "  （対象外: main、現在のブランチ '$current'）"
    exit 0
}

# リモート追跡ブランチの一覧。'origin/HEAD -> origin/main' のような記号参照の行は除外する。
$remotes = @(
    git branch -r |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch '->' }
)

# --- 一覧表示のみ（既定） ---
if ($Delete -eq "None") {
    Write-Host "マージ済みブランチ（$($merged.Count) 件）:" -ForegroundColor Cyan
    foreach ($branch in $merged) {
        if ($remotes -contains "origin/$branch") {
            Write-Host ("  {0,-45} (origin にも存在)" -f $branch)
        }
        else {
            Write-Host ("  {0,-45} (ローカルのみ)" -f $branch)
        }
    }
    Write-Host ""
    Write-Host "基準: $baseRef  /  対象外: main、現在のブランチ '$current'"
    # origin/main は最後に fetch した時点の内容であり、実際のリモートより古い可能性がある
    Write-Host "  （一覧が少ないと感じる場合は git fetch origin を実行してから再実行してください）"
    Write-Host "何も削除していません。削除するには -Delete Local または -Delete LocalAndRemote を付けて再実行してください。" -ForegroundColor Yellow
    exit 0
}

# --- 削除 ---
$failed = 0
foreach ($branch in $merged) {
    # -d はマージ済みブランチしか削除しない（-D による強制削除は行わない）
    git branch -d $branch
    if (-not $?) {
        Write-Host "WARNING: ローカルブランチ '$branch' の削除に失敗しました。" -ForegroundColor Yellow
        $failed++
        continue
    }

    if ($Delete -eq "LocalAndRemote" -and $remotes -contains "origin/$branch") {
        git push origin --delete $branch
        if (-not $?) {
            Write-Host "WARNING: リモートブランチ 'origin/$branch' の削除に失敗しました。" -ForegroundColor Yellow
            $failed++
        }
    }
}

if ($failed -gt 0) {
    Write-Host "$failed 件の失敗がありました。上記のログを確認してください。" -ForegroundColor Yellow
    exit 1
}

Write-Host "マージ済みブランチ $($merged.Count) 件を削除しました。" -ForegroundColor Green
