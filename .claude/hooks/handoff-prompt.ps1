# UserPromptSubmit フック: プロンプトの送信ごとに jev へ次の2つを問い、提案を additionalContext として注入する。
#   handoffSelect: セッション最初の依頼が、どの引き継ぎメモの続きか（該当メモの全文を注入）
#   topicShift   : 2回目以降の依頼が、基準の作業とは無関係な別の作業か（wrap と /clear の提案を注入）
# 全体の流れは docs/handoff.md、モード・しきい値は docs/jev.md を参照。
#
# 方針: 注入するのは提案だけで、プロンプトを決してブロックしない（enforce でも shadow と同じ扱い）。
#   decision: block も exit 2 も使わない。どんな失敗（API キー無し・通信失敗・タイムアウト・例外）でも
#   静かに exit 0 で終わる。stdout に出すのは JSON 1つだけ（注入が無いときは何も出さない）。
# UserPromptSubmit の入出力（stdin の session_id / prompt、hookSpecificOutput.additionalContext）:
#   https://code.claude.com/docs/en/hooks#userpromptsubmit

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 出典なし（暫定値）: 状態に残す最初の依頼の抜粋 400 文字、jev に送る新しい依頼の上限 2000 文字、
# 候補にするメモの最大件数 20、注入するメモ全文の上限 8000 文字、
# config.json が読めないときの既定しきい値（handoffSelect 0.6 / topicShift 0.7）と既定タイムアウト 5 秒。
# additionalContext の上限（10,000 文字）は https://code.claude.com/docs/en/hooks の出力上限の節で確認済み。
$MaxFirstPromptChars = 400
$MaxPromptChars = 2000
$MaxCandidates = 20
$MaxNoteChars = 8000
$DefaultSelectThreshold = 0.6
$DefaultShiftThreshold = 0.7
$DefaultTimeoutSec = 5

<#
.SYNOPSIS
    UserPromptSubmit の additionalContext を JSON 1つとして標準出力に書く（ブロックはしない）。
#>
function Write-PromptContext {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    @{
        hookSpecificOutput = @{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $Text
        }
    } | ConvertTo-Json -Compress
}

<#
.SYNOPSIS
    状態ファイルを現在の値で書き直す（3項目を毎回すべて書く）。
#>
function Save-PromptState {
    param(
        [string] $SessionId,
        [string] $FirstPrompt,
        [string] $LoadedNote,
        [bool] $ShiftSuggested
    )

    Write-HandoffState -SessionId $SessionId -State ([ordered]@{
            firstPrompt    = $FirstPrompt
            loadedNote     = $LoadedNote
            shiftSuggested = $ShiftSuggested
        })
}

try {
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        exit 0
    }
    $inputData = $raw | ConvertFrom-Json

    $prompt = ''
    if ($inputData.PSObject.Properties['prompt']) {
        $prompt = [string]$inputData.prompt
    }
    $sessionId = ''
    if ($inputData.PSObject.Properties['session_id']) {
        $sessionId = [string]$inputData.session_id
    }
    # 空のプロンプトとスラッシュコマンド（/ で始まるもの）では何もしない
    if ([string]::IsNullOrWhiteSpace($prompt) -or $prompt.TrimStart().StartsWith('/')) {
        exit 0
    }

    . (Join-Path $PSScriptRoot '..\jev\lib\jev-client.ps1')
    . (Join-Path $PSScriptRoot '..\jev\lib\handoff.ps1')

    # キー確認を最優先にする（キーが無ければ何も読み書きしない）
    if ($null -eq (Get-JevApiKey)) {
        exit 0
    }

    # SessionStart（handoff-list.ps1）が初期化していないセッション（resume など）では何もしない
    $state = Read-HandoffState -SessionId $sessionId
    if ($null -eq $state) {
        exit 0
    }
    $firstPrompt = [string](Get-ConfigProperty -Object $state -Name 'firstPrompt')
    $loadedNote = [string](Get-ConfigProperty -Object $state -Name 'loadedNote')
    $shiftSuggested = ((Get-ConfigProperty -Object $state -Name 'shiftSuggested') -eq $true)

    $newRequest = $prompt.Trim()
    if ($newRequest.Length -gt $MaxPromptChars) {
        $newRequest = $newRequest.Substring(0, $MaxPromptChars)
    }

    if ($firstPrompt -eq '') {
        # ---------- セッション最初の依頼: handoffSelect ----------
        # jev が失敗しても最初の依頼は一度きりなので、先に記録する
        $excerpt = $newRequest
        if ($excerpt.Length -gt $MaxFirstPromptChars) {
            $excerpt = $excerpt.Substring(0, $MaxFirstPromptChars)
        }
        Save-PromptState -SessionId $sessionId -FirstPrompt $excerpt -LoadedNote '' -ShiftSuggested $false

        $mode = Get-JevMode -Feature 'handoffSelect'
        if ($mode -eq 'off') {
            exit 0
        }
        $notes = @(Get-HandoffNotes | Select-Object -First $MaxCandidates)
        if ($notes.Count -eq 0) {
            exit 0
        }
        $definition = Get-JevQuestionDefinition -Name 'handoff'
        $template = Get-ConfigProperty -Object $definition -Name 'handoffSelect'
        if ($null -eq $template) {
            exit 0
        }

        # 質問定義の criteria（none）の前に、メモごとの選択肢（"1", "2", ...）を足す。
        # state の一覧と同じ番号で選ばせる。
        $criteria = [ordered]@{}
        $listLines = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $notes.Count; $i++) {
            $number = [string]($i + 1)
            $summary = "$($notes[$i].Title) / 次の一手: $($notes[$i].Next) / 目的: $($notes[$i].Purpose)"
            $summary = $summary -replace '\s+', ' '
            $criteria[$number] = $summary
            $listLines.Add("${number}. $summary")
        }
        $templateCriteria = Get-ConfigProperty -Object $template -Name 'criteria'
        if ($null -ne $templateCriteria) {
            foreach ($property in $templateCriteria.PSObject.Properties) {
                $criteria[$property.Name] = $property.Value
            }
        }
        $question = [ordered]@{
            type         = Get-ConfigProperty -Object $template -Name 'type'
            instructions = Get-ConfigProperty -Object $template -Name 'instructions'
            criteria     = $criteria
        }

        $stateText = "## 新しい依頼`n$newRequest`n`n## 引き継ぎメモ一覧`n$($listLines -join "`n")"
        $timeout = [int](Get-JevFeatureSetting -Feature 'handoffSelect' -Name 'timeoutSec' -Default $DefaultTimeoutSec)
        $result = Invoke-Jev -Feature 'handoffSelect' -State $stateText -Questions ([ordered]@{ handoffSelect = $question }) -Mode $mode -TimeoutSec $timeout
        if ($result.Skipped) {
            Write-JevLog -Feature 'handoffSelect' -Mode $mode -Result $result -Decision 'skipped'
            exit 0
        }
        $answer = Get-JevChoiceValue -Answers $result.Answers -Id 'handoffSelect'
        if ($null -eq $answer) {
            Write-JevLog -Feature 'handoffSelect' -Mode $mode -Result $result -Decision 'no-answer'
            exit 0
        }

        $threshold = [double](Get-JevFeatureSetting -Feature 'handoffSelect' -Name 'threshold' -Default $DefaultSelectThreshold)
        $index = 0
        $selected = ($answer.Choice -match '^\d+$') -and [int]::TryParse($answer.Choice, [ref]$index) -and $index -ge 1 -and $index -le $notes.Count
        if (-not $selected -or $answer.Confidence -lt $threshold) {
            Write-JevLog -Feature 'handoffSelect' -Mode $mode -Result $result -Decision 'pass'
            exit 0
        }

        # enforce でも shadow でも同じ: 該当メモの全文を注入するだけで、プロンプトは止めない
        $note = $notes[$index - 1]
        $text = [string]$note.Text
        if ($text.Length -gt $MaxNoteChars) {
            $text = $text.Substring(0, $MaxNoteChars)
        }
        Save-PromptState -SessionId $sessionId -FirstPrompt $excerpt -LoadedNote ([string]$note.Name) -ShiftSuggested $false
        Write-JevLog -Feature 'handoffSelect' -Mode $mode -Result $result -Decision 'injected'
        Write-PromptContext -Text ("このセッションの最初の依頼は、引き継ぎメモ $($note.Path) の作業の続きとみなされました。メモの内容を踏まえて着手してください（依頼がこの作業と無関係だと分かった場合は、メモを無視してよい）。`n`n" + $text)
        exit 0
    }

    # ---------- 2回目以降の依頼: topicShift ----------
    if ($shiftSuggested) {
        # 提案は1セッションに1回だけ（同じ提案を毎回出して邪魔をしないため。出典なしの設計判断）
        exit 0
    }
    $mode = Get-JevMode -Feature 'topicShift'
    if ($mode -eq 'off') {
        exit 0
    }

    # 基準の作業: 読み込み中メモの「目的」、無ければ最初の依頼
    $baseline = ''
    if ($loadedNote -ne '' -and $loadedNote -eq (Split-Path -Leaf $loadedNote)) {
        $notePath = Join-Path (Get-HandoffDir) $loadedNote
        if (Test-Path -LiteralPath $notePath -PathType Leaf) {
            $loaded = Read-HandoffNote -File (Get-Item -LiteralPath $notePath)
            if ($null -ne $loaded) {
                $baseline = [string]$loaded.Purpose
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($baseline)) {
        $baseline = $firstPrompt
    }

    $definition = Get-JevQuestionDefinition -Name 'handoff'
    $question = Get-ConfigProperty -Object $definition -Name 'topicShift'
    if ($null -eq $question) {
        exit 0
    }
    $stateText = "## 基準の作業`n$baseline`n`n## 新しい依頼`n$newRequest"
    $timeout = [int](Get-JevFeatureSetting -Feature 'topicShift' -Name 'timeoutSec' -Default $DefaultTimeoutSec)
    $result = Invoke-Jev -Feature 'topicShift' -State $stateText -Questions ([ordered]@{ topicShift = $question }) -Mode $mode -TimeoutSec $timeout
    if ($result.Skipped) {
        Write-JevLog -Feature 'topicShift' -Mode $mode -Result $result -Decision 'skipped'
        exit 0
    }
    $probability = Get-JevNoulValue -Answers $result.Answers -Id 'topicShift'
    if ($null -eq $probability) {
        Write-JevLog -Feature 'topicShift' -Mode $mode -Result $result -Decision 'no-answer'
        exit 0
    }
    $threshold = [double](Get-JevFeatureSetting -Feature 'topicShift' -Name 'threshold' -Default $DefaultShiftThreshold)
    if ($probability -lt $threshold) {
        Write-JevLog -Feature 'topicShift' -Mode $mode -Result $result -Decision 'pass'
        exit 0
    }

    Save-PromptState -SessionId $sessionId -FirstPrompt $firstPrompt -LoadedNote $loadedNote -ShiftSuggested $true
    Write-JevLog -Feature 'topicShift' -Mode $mode -Result $result -Decision 'injected'
    Write-PromptContext -Text '話題の切り替えの提案: 今回の依頼は、このセッションで進めてきた作業とは無関係な別の作業の可能性があります。着手する前に、ユーザーへ「別の作業に移るなら、今の作業を /wrap で引き継ぎメモに書き出してから /clear で区切ることをおすすめします。同じ作業の続きならそのまま進めます」と短く確認してください（/clear はユーザーが手で打つ。Claude からは実行できない）。ユーザーが同じ作業の続きだと答えたら、そのまま続けてください。'
}
catch {
    # 何が起きても Claude を止めない（プロンプトはブロックしない）
}
exit 0
