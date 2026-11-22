# SessionStart フック（startup / clear / compact）: 引き継ぎメモ（.claude/handoff/*.md）の一覧を Claude に渡し、
# そのセッションの状態ファイル（.claude/handoff/.state/<session_id>.json）を初期化する。
# jev には依存しない（API キーが無くても動く）。全体の流れは docs/handoff.md を参照。
#
# 安全側の設計: どんな失敗でも例外で落とさず、必ず exit 0 で終わる。
#   stdout に出すのは JSON 1つだけ（メモが無いときは何も出さない）。
# SessionStart の入出力（stdin の session_id / source、hookSpecificOutput.additionalContext）:
#   https://code.claude.com/docs/en/hooks#sessionstart

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 出典なし（暫定値）: 一覧に載せるメモの最大件数 30、1行の「次の一手」の最大文字数 200、
# 古い状態ファイルを消す日数 30。
# additionalContext の上限（10,000 文字）は https://code.claude.com/docs/en/hooks の出力上限の節で確認済み
# （上限に収めるため一覧は 9000 文字で切る）。
$MaxNotes = 30
$MaxNextChars = 200
$StateRetentionDays = 30
$MaxContextChars = 9000

try {
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $raw = [Console]::In.ReadToEnd()
    $inputData = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $inputData = $raw | ConvertFrom-Json
    }

    . (Join-Path $PSScriptRoot '..\jev\lib\handoff.ps1')

    $sessionId = ''
    if ($null -ne $inputData -and $inputData.PSObject.Properties['session_id']) {
        $sessionId = [string]$inputData.session_id
    }

    # --- 状態ファイルの初期化（最初の依頼・読み込み中メモ・提案済みフラグを空にする） ---
    Write-HandoffState -SessionId $sessionId -State ([ordered]@{
            firstPrompt    = ''
            loadedNote     = ''
            shiftSuggested = $false
        })

    # 古い状態ファイルを掃除する（セッションごとに増え続けるため）。失敗しても続行する
    try {
        $stateDir = Join-Path (Get-HandoffDir) '.state'
        if (Test-Path -LiteralPath $stateDir -PathType Container) {
            $limit = (Get-Date).AddDays(-$StateRetentionDays)
            Get-ChildItem -LiteralPath $stateDir -Filter '*.json' -File |
                Where-Object { $_.LastWriteTime -lt $limit } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }

    # --- メモの一覧 ---
    $notes = @(Get-HandoffNotes)
    if ($notes.Count -eq 0) {
        exit 0
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('引き継ぎメモの一覧（.claude/handoff/）。ユーザーの依頼が一覧の作業の続きなら、該当メモを Read で読んでから着手すること。続きでなければ読まなくてよい。')
    $count = 0
    foreach ($note in $notes) {
        if ($count -ge $MaxNotes) {
            break
        }
        $next = ([string]$note.Next) -replace '\s+', ' '
        if ($next.Length -gt $MaxNextChars) {
            $next = $next.Substring(0, $MaxNextChars)
        }
        $updated = [string]$note.Updated
        if ([string]::IsNullOrWhiteSpace($updated)) {
            $updated = '不明'
        }
        $lines.Add("- 作業名: $($note.Title) / 次の一手: $next / 更新: $updated / パス: $($note.Path)")
        $count++
    }
    $context = ($lines -join "`n")
    if ($context.Length -gt $MaxContextChars) {
        $context = $context.Substring(0, $MaxContextChars)
    }

    @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $context
        }
    } | ConvertTo-Json -Compress
}
catch {
    # 何が起きても Claude を止めない
}
exit 0
