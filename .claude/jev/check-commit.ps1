param(
    # これからコミットするメッセージ
    [Parameter(Mandatory = $true)]
    [string] $Message
)

# コミット直前に jev で次の2点を判定する（/git:push から呼ばれる。単体でも実行できる）。
#   2. テスト追加漏れ: ソースが変わっているのにテストが1つも変わっていない場合に、挙動が変わる変更かを問う
#   3. コミットの種類: メッセージ先頭のプレフィックス（feat 等）が変更内容と合っているかを問う
# 「コードの条件 AND jev の判定がそろったときだけ指摘する」方針。
#
# 終了コード: 0 = 続行してよい（スキップ・問題なし・shadow での通知を含む）/ 2 = enforce で止めるべき指摘あり
# キーが無い・対象外のときは何も表示せず 0 で終わる（jev を使わないプロジェクトの邪魔をしない）。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'lib\jev-client.ps1')

# 判定のしきい値（threshold）は出典の無い暫定値。config.json の既定が読めない場合の保険として同じ値を置く。
$DefaultTestsThreshold = 0.7
$DefaultCommitTypeThreshold = 0.8
$DiffMaxLines = 200
$StateMaxChars = 20000

<#
.SYNOPSIS
    パスが、-like ワイルドカードのパターンのいずれかに一致するかを返す。
#>
function Test-AnyLike {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [AllowNull()]
        [string[]] $Patterns
    )

    foreach ($pattern in $Patterns) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and $Path -like $pattern) {
            return $true
        }
    }
    return $false
}

# キーが無ければ何もしない（質問の準備や git の呼び出しもしない）
if ($null -eq (Get-JevApiKey)) {
    exit 0
}

$RepoRoot = Get-RepoRoot
$questions = [ordered]@{}
$stateParts = New-Object System.Collections.Generic.List[string]

# --- 2. テスト追加漏れの対象判定（コードの条件） ---
$testsMode = Get-JevMode -Feature 'tests'
$testsActive = $false
$testsThreshold = [double](Get-JevFeatureSetting -Feature 'tests' -Name 'threshold' -Default $DefaultTestsThreshold)
$sourceFiles = @()

$config = Get-ProjectConfig
$testing = Get-ConfigProperty -Object $config -Name 'testing'
if ($testsMode -ne 'off' -and $null -ne $testing) {
    $sourcePatterns = @(Get-ConfigProperty -Object $testing -Name 'sourcePatterns')
    $testPatterns = @(Get-ConfigProperty -Object $testing -Name 'testPatterns')

    $global:LASTEXITCODE = 0
    $staged = @(git -C $RepoRoot -c core.quotepath=false diff --cached --name-only)
    if ($LASTEXITCODE -eq 0) {
        $staged = @($staged | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $sourceFiles = @($staged | Where-Object { Test-AnyLike -Path $_ -Patterns $sourcePatterns })
        $testFiles = @($staged | Where-Object { Test-AnyLike -Path $_ -Patterns $testPatterns })
        if ($sourceFiles.Count -gt 0 -and $testFiles.Count -eq 0) {
            $testsActive = $true
        }
    }
}

if ($testsActive) {
    # 質問定義が読めない・差分が取れない場合は、この機能だけ静かにスキップする
    $testQuestions = Get-JevQuestionDefinition -Name 'tests'
    $testQuestion = Get-ConfigProperty -Object $testQuestions -Name 'changesBehavior'
    $global:LASTEXITCODE = 0
    $diffLines = @(git -C $RepoRoot -c core.quotepath=false diff --cached -- $sourceFiles)
    if ($null -eq $testQuestion -or $LASTEXITCODE -ne 0) {
        $testsActive = $false
    }
    else {
        $diffText = (@($diffLines | Select-Object -First $DiffMaxLines) -join "`n")
        if ($diffText.Length -gt $StateMaxChars) {
            $diffText = $diffText.Substring(0, $StateMaxChars)
        }
        $stateParts.Add("## 差分（先頭 $DiffMaxLines 行）`n$diffText")
        $questions['changesBehavior'] = $testQuestion
    }
}

# --- 3. コミットの種類の対象判定（コードの条件） ---
$typeMode = Get-JevMode -Feature 'commitType'
$typeActive = $false
$typeThreshold = [double](Get-JevFeatureSetting -Feature 'commitType' -Name 'threshold' -Default $DefaultCommitTypeThreshold)
$declaredType = $null

if ($typeMode -ne 'off' -and $Message -match '^(feat|fix|refactor|docs|chore):') {
    $declaredType = $Matches[1]
    $typeActive = $true
}

if ($typeActive) {
    $typeQuestions = Get-JevQuestionDefinition -Name 'commit-type'
    $typeQuestion = Get-ConfigProperty -Object $typeQuestions -Name 'commitType'
    $global:LASTEXITCODE = 0
    $statLines = @(git -C $RepoRoot -c core.quotepath=false diff --cached --stat)
    if ($null -eq $typeQuestion -or $LASTEXITCODE -ne 0) {
        $typeActive = $false
    }
    else {
        $statText = ($statLines -join "`n")
        if ($statText.Length -gt $StateMaxChars) {
            $statText = $statText.Substring(0, $StateMaxChars)
        }
        $stateParts.Insert(0, "## コミットメッセージ`n$Message`n`n## 変更の統計`n$statText")
        $questions['commitType'] = $typeQuestion
    }
}

if ($questions.Count -eq 0) {
    exit 0
}

# --- jev への問い合わせ（②③が両方該当するときは1リクエスト） ---
# どちらかが off の場合はその質問を含めていない。残った機能の mode は off ではないので shadow を渡して呼ぶ。
$featureLabel = (@(
        if ($testsActive) { 'tests' }
        if ($typeActive) { 'commitType' }
    ) -join '+')
$result = Invoke-Jev -Feature $featureLabel -State ($stateParts -join "`n`n") -Questions $questions -Mode 'shadow'

$stopMessages = New-Object System.Collections.Generic.List[string]

if ($result.Skipped) {
    # キーはある状態で失敗した場合のみ通知する（コミットは続行）
    Write-Host "WARNING: jev による判定をスキップしました（$($result.Reason)）。コミットは続行します。" -ForegroundColor Yellow
    if ($testsActive) {
        Write-JevLog -Feature 'tests' -Mode $testsMode -Result $result -Decision 'skipped' -AnswerIds @('changesBehavior')
    }
    if ($typeActive) {
        Write-JevLog -Feature 'commitType' -Mode $typeMode -Result $result -Decision 'skipped' -AnswerIds @('commitType')
    }
    exit 0
}

# --- 2. テスト追加漏れの判定 ---
if ($testsActive) {
    # 数値でない・0〜1 の範囲外の値は $null になり no-answer 扱い
    $probability = Get-JevNoulValue -Answers $result.Answers -Id 'changesBehavior'
    $decision = 'pass'
    if ($null -eq $probability) {
        $decision = 'no-answer'
    }
    elseif ([double]$probability -ge $testsThreshold) {
        $percent = ([double]$probability).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($testsMode -eq 'enforce') {
            $decision = 'flagged-stop'
            $stopMessages.Add("テストが追加・更新されていませんが、挙動を変える変更の可能性が高いです（確率 $percent、しきい値 $testsThreshold）。`n  対応方法: 対応するテストを追加してステージしてください。テスト不要と判断する場合は -SkipJev を付けて続行できます。")
        }
        else {
            $decision = 'flagged-shadow'
            Write-Host "WARNING: jev(shadow): テスト追加漏れの疑いがあります（挙動を変える確率 $percent）。記録のみ（shadow）でコミットは止めません。止めたい場合は環境変数 JEV_MODE_TESTS=enforce（または .claude/jev/config.json の features.tests.mode）を設定してください。" -ForegroundColor Yellow
        }
    }
    Write-JevLog -Feature 'tests' -Mode $testsMode -Result $result -Decision $decision -AnswerIds @('changesBehavior')
}

# --- 3. コミットの種類の判定 ---
if ($typeActive) {
    $typeAnswer = Get-JevChoiceValue -Answers $result.Answers -Id 'commitType'
    $decision = 'pass'
    if ($null -eq $typeAnswer) {
        $decision = 'no-answer'
    }
    elseif ($typeAnswer.Choice -ne $declaredType -and $typeAnswer.Confidence -ge $typeThreshold) {
        $choice = $typeAnswer.Choice
        $percent = ($typeAnswer.Confidence).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($typeMode -eq 'enforce') {
            $decision = 'flagged-stop'
            $stopMessages.Add("コミットの種類が変更内容と合っていない可能性があります（メッセージ: ${declaredType}:、jev の判定: ${choice}:、確信度 $percent、しきい値 $typeThreshold）。`n  対応方法: プレフィックスを ${choice}: に直すか、コミットを分けてください。このままでよい場合は -SkipJev を付けて続行できます。")
        }
        else {
            $decision = 'flagged-shadow'
            Write-Host "WARNING: jev(shadow): コミットの種類が ${declaredType}: ですが、変更内容は ${choice}: に近い判定です（確信度 $percent）。記録のみ（shadow）でコミットは止めません。止めたい場合は環境変数 JEV_MODE_COMMITTYPE=enforce（または .claude/jev/config.json の features.commitType.mode）を設定してください。" -ForegroundColor Yellow
        }
    }
    Write-JevLog -Feature 'commitType' -Mode $typeMode -Result $result -Decision $decision -AnswerIds @('commitType')
}

if ($stopMessages.Count -gt 0) {
    Write-Host "ERROR: jev の判定によりコミットを止めました（ステージはそのまま残してあります）。" -ForegroundColor Red
    foreach ($text in $stopMessages) {
        Write-Host "  - $text" -ForegroundColor Red
    }
    exit 2
}

exit 0
