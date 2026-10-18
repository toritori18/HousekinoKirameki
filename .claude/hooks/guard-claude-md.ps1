# PreToolUse フック(Edit|Write): CLAUDE.md への変更をユーザー確認制にする

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$j = $raw | ConvertFrom-Json
$f = $j.tool_input.file_path

if ($f -match 'CLAUDE\.md$') {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'ask'
            permissionDecisionReason = 'CLAUDE.md を変更しようとしています。ユーザーの明示的な指示がある場合のみ許可してください。'
        }
    } | ConvertTo-Json -Compress
}
