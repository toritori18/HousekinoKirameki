param(
    # これからコミットするメッセージ
    [Parameter(Mandatory = $true)]
    [string] $Message
)

# コミット直前に jev で次の3点を判定する（/git:push から呼ばれる。単体でも実行できる）。
#   2. テスト追加漏れ: ソースが変わっているのにテストが1つも変わっていない場合に、挙動が変わる変更かを問う
#   3. コミットの種類: メッセージ先頭のプレフィックス（feat 等）が変更内容と合っているかを問う
#   4. README の同期漏れ: 監視対象（コマンド・エージェント・スキル・スタック、追加/削除/リネーム）の変更があり
#      README.md がステージされていない場合に、README への反映が必要な変更かを問う
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
$DefaultReadmeSyncThreshold = 0.7
# README 同期漏れの監視パターン（-like）の保険の既定値。config.json の features.readmeSync.watchPatterns が優先。
# スタック定義の置き場は README.md の「stacks/ 配下のプロファイル」と /setup の実装（stacks/<名前>/）から特定した
$DefaultReadmeWatchPatterns = @('.claude/commands/*', '.claude/agents/*', '.claude/skills/*', 'stacks/*')
# 差分の行数・state の文字数・README の文字数の上限は出典なし（暫定値）
$DiffMaxLines = 200
$StateMaxChars = 20000
$ReadmeMaxChars = 20000

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

# --- 4. README の同期漏れの対象判定（コードの条件） ---
# 条件: (1) ステージ済みに監視対象の変更がある AND (2) README.md がステージされていない
$readmeMode = Get-JevMode -Feature 'readmeSync'
$readmeActive = $false
$readmeThreshold = [double](Get-JevFeatureSetting -Feature 'readmeSync' -Name 'threshold' -Default $DefaultReadmeSyncThreshold)

if ($readmeMode -ne 'off') {
    $watchPatterns = @(Get-JevFeatureSetting -Feature 'readmeSync' -Name 'watchPatterns' -Default $null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($watchPatterns.Count -eq 0) {
        $watchPatterns = $DefaultReadmeWatchPatterns
    }

    $global:LASTEXITCODE = 0
    $nameStatus = @(git -C $RepoRoot -c core.quotepath=false diff --cached --name-status)
    if ($LASTEXITCODE -eq 0) {
        $watched = New-Object System.Collections.Generic.List[string]
        $watchedPaths = New-Object System.Collections.Generic.List[string]
        $readmeStaged = $false
        foreach ($line in $nameStatus) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            # 形式: 状態<TAB>パス（リネームは 状態<TAB>旧パス<TAB>新パス）
            $fields = $line -split "`t"
            if ($fields.Count -lt 2) {
                continue
            }
            $status = $fields[0].Substring(0, 1)
            $paths = @($fields[1..($fields.Count - 1)])
            if ($paths -contains 'README.md') {
                $readmeStaged = $true
            }
            $inWatch = $false
            foreach ($p in $paths) {
                if (Test-AnyLike -Path $p -Patterns $watchPatterns) {
                    $inWatch = $true
                }
            }
            # 追加・削除・リネームはディレクトリ構成の変更の候補として、パスを問わず対象にする
            if ($inWatch -or $status -in @('A', 'D', 'R')) {
                $watched.Add("$status`t$($paths -join ' -> ')")
                foreach ($p in $paths) {
                    $watchedPaths.Add($p)
                }
            }
        }
        if ($watched.Count -gt 0 -and -not $readmeStaged) {
            $readmeActive = $true
        }
    }
}

if ($readmeActive) {
    # 質問定義・README・差分のどれかが読めない場合は、この機能だけ静かにスキップする
    $readmeQuestions = Get-JevQuestionDefinition -Name 'readme-sync'
    $readmeQuestion = Get-ConfigProperty -Object $readmeQuestions -Name 'needsReadmeUpdate'
    $readmeText = $null
    try {
        $readmeText = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $readmeText = $null
    }
    $global:LASTEXITCODE = 0
    $readmeDiffLines = @(git -C $RepoRoot -c core.quotepath=false diff --cached -- @($watchedPaths | Select-Object -Unique))
    if ($null -eq $readmeQuestion -or [string]::IsNullOrWhiteSpace($readmeText) -or $LASTEXITCODE -ne 0) {
        $readmeActive = $false
    }
    else {
        $readmeDiff = (@($readmeDiffLines | Select-Object -First $DiffMaxLines) -join "`n")
        if ($readmeDiff.Length -gt $StateMaxChars) {
            $readmeDiff = $readmeDiff.Substring(0, $StateMaxChars)
        }
        if ($readmeText.Length -gt $ReadmeMaxChars) {
            $readmeText = $readmeText.Substring(0, $ReadmeMaxChars)
        }
        $stateParts.Add("## 変更ファイル（状態 A=追加 M=変更 D=削除 R=リネーム）`n$($watched -join "`n")`n`n## 差分（先頭 $DiffMaxLines 行）`n$readmeDiff`n`n## README.md の本文（先頭 $ReadmeMaxChars 文字）`n$readmeText")
        $questions['needsReadmeUpdate'] = $readmeQuestion
    }
}

if ($questions.Count -eq 0) {
    exit 0
}

# --- jev への問い合わせ（②③④が複数該当するときは1リクエスト） ---
# off の機能はその質問を含めていない。残った機能の mode は off ではないので shadow を渡して呼ぶ。
$featureLabel = (@(
        if ($testsActive) { 'tests' }
        if ($typeActive) { 'commitType' }
        if ($readmeActive) { 'readmeSync' }
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
    if ($readmeActive) {
        Write-JevLog -Feature 'readmeSync' -Mode $readmeMode -Result $result -Decision 'skipped' -AnswerIds @('needsReadmeUpdate')
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

# --- 4. README の同期漏れの判定 ---
if ($readmeActive) {
    $readmeProbability = Get-JevNoulValue -Answers $result.Answers -Id 'needsReadmeUpdate'
    $decision = 'pass'
    if ($null -eq $readmeProbability) {
        $decision = 'no-answer'
    }
    elseif ([double]$readmeProbability -ge $readmeThreshold) {
        $percent = ([double]$readmeProbability).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($readmeMode -eq 'enforce') {
            $decision = 'flagged-stop'
            $stopMessages.Add("README.md に反映が必要な変更の可能性が高いですが、README.md がステージされていません（確率 $percent、しきい値 $readmeThreshold）。`n  対応方法: readme-syncer エージェントで README.md を同期してください。同期が不要と判断する場合は -SkipJev を付けて続行できます。")
        }
        else {
            $decision = 'flagged-shadow'
            Write-Host "WARNING: jev(shadow): README.md の同期漏れの疑いがあります（反映が必要な確率 $percent）。readme-syncer エージェントで README.md を同期してください。記録のみ（shadow）でコミットは止めません。止めたい場合は環境変数 JEV_MODE_READMESYNC=enforce（または .claude/jev/config.json の features.readmeSync.mode）を設定してください。" -ForegroundColor Yellow
        }
    }
    Write-JevLog -Feature 'readmeSync' -Mode $readmeMode -Result $result -Decision $decision -AnswerIds @('needsReadmeUpdate')
}

if ($stopMessages.Count -gt 0) {
    Write-Host "ERROR: jev の判定によりコミットを止めました（ステージはそのまま残してあります）。" -ForegroundColor Red
    foreach ($text in $stopMessages) {
        Write-Host "  - $text" -ForegroundColor Red
    }
    exit 2
}

exit 0
