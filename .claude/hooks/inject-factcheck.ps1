# SessionStart フック: factcheck.md をセッション開始時に一度だけコンテキストへ注入する
# (以前は Edit/Write のたびに注入していたが、コンテキスト消費が大きいため変更)

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$f = '.claude/factcheck.md'

if (Test-Path $f) {
    $c = [string](Get-Content $f -Raw -Encoding UTF8)
    @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $c
        }
    } | ConvertTo-Json -Compress
}
