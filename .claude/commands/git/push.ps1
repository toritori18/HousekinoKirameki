param(
    [Parameter(Mandatory = $true)]
    [string] $Message,

    # jev によるコミット前の判定（テスト追加漏れ・コミットの種類）を行わない
    [switch] $SkipJev
)

# 追跡済みファイルをステージングし、シークレットの混入・ブランチ名・マージ済みブランチでないことを確認してからコミット・プッシュする。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# .env.local などシークレットファイルが追跡されていないか確認
$secrets = git ls-files --error-unmatch .env.local 2>$null
if ($secrets) {
    Write-Host "ERROR: .env.local が git の追跡対象になっています。" -ForegroundColor Red
    Write-Host "  対応方法: git rm --cached .env.local で追跡から外してから再実行してください。" -ForegroundColor Red
    exit 1
}

<#
.SYNOPSIS
    ブランチを head とする PR が「マージ済みで、OPEN な PR が無い」かを調べ、該当する場合はマージ済み PR の URL を返す。
    該当しない場合・判定できない場合は $null を返す（判定不能時は WARNING を出す。ガードは補助なので作業は止めない）。
#>
function Get-MergedPrUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Branch
    )

    if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "WARNING: gh コマンドが無いため、マージ済みブランチかどうかを判定できませんでした（続行します）。" -ForegroundColor Yellow
        return $null
    }

    # gh pr list: --head でブランチを絞り、--state all で OPEN/MERGED/CLOSED をまとめて取得する
    # 出典: https://cli.github.com/manual/gh_pr_list
    $json = gh pr list --head $Branch --state all --limit 100 --json number,state,url
    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "WARNING: gh pr list に失敗したため（未認証・オフライン等）、マージ済みブランチかどうかを判定できませんでした（続行します）。" -ForegroundColor Yellow
        return $null
    }

    $raw = ($json -join "`n")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Host "WARNING: gh pr list の出力が空だったため、マージ済みブランチかどうかを判定できませんでした（続行します）。" -ForegroundColor Yellow
        return $null
    }
    try {
        $prs = @(ConvertFrom-Json -InputObject $raw)
    }
    catch {
        Write-Host "WARNING: gh pr list の出力を解析できなかったため、マージ済みブランチかどうかを判定できませんでした（続行します）。" -ForegroundColor Yellow
        return $null
    }
    if (@($prs | Where-Object { $_.state -eq 'OPEN' }).Count -gt 0) {
        return $null
    }
    $merged = @($prs | Where-Object { $_.state -eq 'MERGED' })
    if ($merged.Count -gt 0) {
        return [string] $merged[0].url
    }
    return $null
}

# ブランチ名の判定は、ステージング・コミットより前に行う（止める場合にローカルへ何も残さないため）
$branch = git rev-parse --abbrev-ref HEAD
if (-not $?) {
    Write-Host "ERROR: 現在のブランチを取得できませんでした。" -ForegroundColor Red
    exit 1
}

# main への直接プッシュは git-rules.md により禁止（すべて PR 経由でマージする）
if ($branch -eq "main") {
    Write-Host "ERROR: main への直接プッシュは禁止されています（docs/git-rules.md）。" -ForegroundColor Red
    Write-Host "  対応方法: /git:branch feature/<機能名> で最新の main から作業ブランチを作り、そこで /git:push し直してください（未コミットの変更はそのまま持っていけます）。" -ForegroundColor Red
    exit 1
}

# マージ済みの PR だけが残っているブランチへ積んでも、変更は PR に乗らない
$mergedUrl = Get-MergedPrUrl -Branch $branch
if ($mergedUrl) {
    Write-Host "ERROR: ブランチ '$branch' の PR はすでにマージ済みです（$mergedUrl）。ここへプッシュしても変更は main に入りません。" -ForegroundColor Red
    Write-Host "  対応方法: /git:branch <新しいブランチ名> で最新の main から新しいブランチを作り、そこで /git:push し直してください（未コミットの変更はそのまま持っていけます）。" -ForegroundColor Red
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

# jev による判定（キーが無い・jev を導入していないプロジェクトでは何もせず通過する）。
# 終了コード 2 は「enforce モードで止めるべき指摘あり」。ステージはそのまま残してコミットせずに終了する。
$checkCommit = Join-Path $PSScriptRoot '..\..\jev\check-commit.ps1'
if ((-not $SkipJev) -and (Test-Path -LiteralPath $checkCommit)) {
    & $checkCommit -Message $Message
    $jevOk = $?
    $jevExit = $LASTEXITCODE
    if ($jevExit -eq 2) {
        Write-Host "ERROR: jev の指摘によりコミットしませんでした（変更はステージされたままです）。" -ForegroundColor Red
        Write-Host "  対応方法: 上の指摘に沿って直し、git add で再ステージしてから再実行してください。" -ForegroundColor Red
        Write-Host "  指摘を承知で続行する場合は -SkipJev を付けて再実行してください（例: .\.claude\commands\git\push.ps1 `"メッセージ`" -SkipJev）。" -ForegroundColor Red
        exit 1
    }
    # 0・2 以外は check-commit 自体の異常終了。jev は補助機能なので止めずに続行するが、無言で素通りしないよう警告する
    if ((-not $jevOk) -or $jevExit -ne 0) {
        Write-Host "WARNING: jev の判定を実行できませんでした（コミットは続行します）。" -ForegroundColor Yellow
    }
}

# コミット
git commit -m $Message
if (-not $?) {
    Write-Host "ERROR: git commit に失敗しました。" -ForegroundColor Red
    exit 1
}

git push origin $branch
if (-not $?) {
    Write-Host "ERROR: git push に失敗しました。" -ForegroundColor Red
    Write-Host "  pre-push フックの機密情報チェックまたは /check でブロックされた可能性があります。上のログのエラーを直してから、再度 /git:push してください（追加コミットになります）。" -ForegroundColor Red
    Write-Host "  誤検出と確認できた場合のみ git push --no-verify を使ってください（機密情報チェックも飛ばされます）。" -ForegroundColor Red
    exit 1
}

Write-Host "origin/$branch にプッシュしました" -ForegroundColor Green
