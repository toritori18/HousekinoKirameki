# /check（プッシュ前の総点検）の実体。
#
# 実行するステップと各ステップのコマンドは .claude/project.json が持つ。
# このスクリプトは project.json の check 配列を上から順に実行し、途中で失敗したら
# 後続を実行せず exit 1 する。
# check.md に複数のコマンドを自然言語で並べる形にすると「1つ目の失敗を無視して2つ目が走る」
# 問題が起き得るため、スクリプト側で確実に止める。
#
# project.json が無い場合（/setup 前）は、言語に依存しないドキュメント検査だけを行う。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'lib\project-config.ps1')

$RepoRoot = Get-RepoRoot
$config = Get-ProjectConfig

# ステップ名 → 画面に出す表示名。project.json の check 配列に書ける名前でもある。
$stepLabels = @{
    'verify-docs' = 'ドキュメントの参照先検査'
    'lint'        = '静的解析'
    'format'      = 'コード整形'
    'typecheck'   = '型検査'
    'test'        = 'テスト'
    'build'       = '本番ビルド'
}

if ($null -eq $config) {
    Write-Host "WARNING: .claude/project.json がないため、ドキュメントの参照先検査のみ実行します。" -ForegroundColor Yellow
    Write-Host "  静的解析・テスト・ビルドも実行するには /setup <スタック名> を実行してください。" -ForegroundColor Yellow
    Write-Host ""
    $steps = @('verify-docs')
}
else {
    $steps = @(Get-ConfigProperty -Object $config -Name 'check')
    if ($steps.Count -eq 0 -or $null -eq $steps[0]) {
        Write-Host "ERROR: .claude/project.json に check（実行するステップの一覧）がありません。" -ForegroundColor Red
        Write-Host "  対応方法: check に実行したいステップ名の配列を設定してください（例: [\"verify-docs\", \"lint\", \"test\", \"build\"]）。" -ForegroundColor Red
        exit 1
    }
}

$total = $steps.Count
$index = 0
$skipped = New-Object System.Collections.Generic.List[string]

foreach ($step in $steps) {
    $index++

    $label = $stepLabels[$step]
    if ($null -eq $label) {
        # project.json 側で独自のステップ名を足せるよう、未知の名前もそのまま表示して実行する
        $label = $step
    }

    # ドキュメント検査だけは言語に依存しないため、project.json のコマンド定義ではなく
    # 同梱スクリプトを直接呼ぶ
    if ($step -eq 'verify-docs') {
        Write-Host "[$index/$total] $label を実行しています..." -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot 'verify-docs.ps1')
        # $? と $LASTEXITCODE の両方を見て、呼び出した .ps1 の失敗を確実に止める
        if (-not $? -or $LASTEXITCODE -ne 0) {
            Write-Host "ERROR: $label に失敗しました。上記のログを確認してください。" -ForegroundColor Red
            exit 1
        }
        continue
    }

    $command = Get-ProjectCommand -Config $config -Name $step
    if ($null -eq $command) {
        Write-Host "[$index/$total] $label はコマンド未設定のためスキップします（.claude/project.json の commands.$step が未設定）。" -ForegroundColor Yellow
        $skipped.Add($label)
        continue
    }

    Write-Host "[$index/$total] $label を実行しています（$command）..." -ForegroundColor Cyan
    if (-not (Invoke-ProjectCommand -Command $command -WorkingDirectory $RepoRoot)) {
        Write-Host "ERROR: $label（$command）に失敗しました。上記のログを確認してください。" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
if ($skipped.Count -gt 0) {
    Write-Host "OK: チェックが完了しました。プッシュ可能です（未設定のためスキップ: $($skipped -join '、')）。" -ForegroundColor Green
}
else {
    Write-Host "OK: チェックが完了しました。プッシュ可能です。" -ForegroundColor Green
}
exit 0
