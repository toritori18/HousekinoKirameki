# Stop フック: 実装を伴う応答に「出典」または「出典なし」の明記があるかを jev で判定する
# （CLAUDE.md の「出典がない場合は『出典なし』と明記する」ルールの機械的な確認）。
#
# 方針: コードの条件（ソースの未コミット変更がある）AND jev の判定
# （応答が実装報告である AND 出典が含まれる確率が低い）がそろったときだけ指摘する。
# 安全側の設計: どんな失敗でも例外で落とさず、必ず exit 0 で終わる。
#   Stop フックで exit 2 を返すと Claude が止まれなくなるため、exit 2 は絶対に返さない。
#   stdout に出すのは JSON 1つだけ（指摘が無いときは何も出さない）。
# Stop フックの入出力: https://code.claude.com/docs/en/hooks#stop

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 出典なし（暫定値）: 応答を末尾から切り出す文字数 8000（出典は応答の末尾にあるため末尾を残す）、
# および config.json が読めないときの既定しきい値 0.2（hasSources）・0.5（isImplementation）。
$MaxStateChars = 8000
$DefaultThreshold = 0.2
$DefaultImplementationThreshold = 0.5

try {
    # --- stdin の JSON を読む ---
    # InputEncoding を UTF-8 にしてから読む。日本語を含む stdin（ファイルリダイレクト）が
    # 正しく復元されることを実測で確認済み（失敗しても ReadToEnd に進む）。
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $raw = [Console]::In.ReadToEnd()
    $inputData = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $inputData = $raw | ConvertFrom-Json
    }

    # 無限ループ防止（必須）。フックの指摘で続行した応答では判定しない
    if ($null -ne $inputData -and $inputData.PSObject.Properties['stop_hook_active'] -and $inputData.stop_hook_active -eq $true) {
        exit 0
    }

    $message = ''
    if ($null -ne $inputData -and $inputData.PSObject.Properties['last_assistant_message']) {
        $message = [string]$inputData.last_assistant_message
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        exit 0
    }

    . (Join-Path $PSScriptRoot '..\jev\lib\jev-client.ps1')

    # キー確認を最優先にする（キーが無ければ git も呼ばない）
    if ($null -eq (Get-JevApiKey)) {
        exit 0
    }
    $mode = Get-JevMode -Feature 'sources'
    if ($mode -eq 'off') {
        exit 0
    }

    $repoRoot = Get-RepoRoot
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
        exit 0
    }

    # --- ソースコードの未コミット変更を集める ---
    $config = $null
    $projectPath = Join-Path $repoRoot '.claude\project.json'
    if (Test-Path -LiteralPath $projectPath) {
        $config = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $sourcePatterns = @()
    $extensions = @()
    $testing = Get-ConfigProperty -Object $config -Name 'testing'
    $patternValue = Get-ConfigProperty -Object $testing -Name 'sourcePatterns'
    if ($null -ne $patternValue) {
        $sourcePatterns = @($patternValue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($sourcePatterns.Count -eq 0) {
        $contributing = Get-ConfigProperty -Object $config -Name 'contributing'
        if ($null -ne $contributing) {
            $extensions = @($contributing.PSObject.Properties.Name | Where-Object { $_ -ne '.md' -and $_ -ne '.ps1' })
        }
    }
    if ($sourcePatterns.Count -eq 0 -and $extensions.Count -eq 0) {
        exit 0
    }

    $global:LASTEXITCODE = 0
    $lines = @(git -C $repoRoot -c core.quotepath=false status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        exit 0
    }
    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line.Length -lt 4) {
            continue
        }
        $path = $line.Substring(3)
        if ($path -match ' -> (.+)$') {
            $path = $Matches[1]
        }
        # core.quotepath=false を指定しているため日本語パスはクォートされない。
        # 空白などを含むパスだけが "..." で囲まれるので両端の引用符を外す（パス内のエスケープ \" までは復元しない）
        $path = $path.Trim('"')
        $isSource = $false
        foreach ($pattern in $sourcePatterns) {
            if ($path -like $pattern) { $isSource = $true }
        }
        foreach ($extension in $extensions) {
            if ($path.EndsWith($extension, [System.StringComparison]::OrdinalIgnoreCase)) { $isSource = $true }
        }
        if ($isSource) {
            $changed.Add($path)
        }
    }
    if ($changed.Count -eq 0) {
        exit 0
    }

    # 前回判定時と同じ変更集合なら再判定しない（既存フックと同方式）
    $cacheFile = Join-Path $repoRoot '.claude\.stop-sources-cache'
    $current = (($changed | Sort-Object) -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($current)))
    }
    finally {
        $sha.Dispose()
    }
    $cached = ''
    if (Test-Path -LiteralPath $cacheFile) {
        $cached = ([string](Get-Content -LiteralPath $cacheFile -Raw)).Trim()
    }
    if ($cached -eq $hash) {
        exit 0
    }

    # --- jev に問う（実装報告か・出典があるか を1リクエストで） ---
    $definition = Get-JevQuestionDefinition -Name 'sources'
    $implQuestion = Get-ConfigProperty -Object $definition -Name 'isImplementation'
    $sourcesQuestion = Get-ConfigProperty -Object $definition -Name 'hasSources'
    if ($null -eq $implQuestion -or $null -eq $sourcesQuestion) {
        exit 0
    }
    $state = $message
    if ($state.Length -gt $MaxStateChars) {
        $state = $state.Substring($state.Length - $MaxStateChars)
    }
    $questions = [ordered]@{ isImplementation = $implQuestion; hasSources = $sourcesQuestion }
    $result = Invoke-Jev -Feature 'sources' -State "## 応答`n$state" -Questions $questions -Mode $mode
    if ($result.Skipped) {
        # 失敗時はキャッシュを更新しない（次回また判定する）
        Write-JevLog -Feature 'sources' -Mode $mode -Result $result -Decision 'skipped'
        exit 0
    }

    # ログには両方の回答（値）が残る
    $implementation = Get-JevNoulValue -Answers $result.Answers -Id 'isImplementation'
    $probability = Get-JevNoulValue -Answers $result.Answers -Id 'hasSources'
    if ($null -eq $implementation -or $null -eq $probability) {
        # 回答が使えなかった場合もキャッシュは更新しない（次回また判定する）
        Write-JevLog -Feature 'sources' -Mode $mode -Result $result -Decision 'no-answer'
        exit 0
    }

    # 判定が有効だったのでキャッシュを更新する。書き込み失敗でも判定・出力・ログは続ける
    try {
        Set-Content -LiteralPath $cacheFile -Value $hash -Encoding Ascii
    }
    catch { }

    $threshold = [double](Get-JevFeatureSetting -Feature 'sources' -Name 'threshold' -Default $DefaultThreshold)
    $implementationThreshold = [double](Get-JevFeatureSetting -Feature 'sources' -Name 'implementationThreshold' -Default $DefaultImplementationThreshold)
    if ($implementation -lt $implementationThreshold -or $probability -ge $threshold) {
        Write-JevLog -Feature 'sources' -Mode $mode -Result $result -Decision 'pass'
        exit 0
    }

    $reason = '実装を伴う応答の末尾に、使用した出典（公式ドキュメント等）を画面・機能ごとに整理して書くか、出典が無い場合は『出典なし』と明記してください（CLAUDE.md のルール）。'
    if ($mode -eq 'enforce') {
        Write-JevLog -Feature 'sources' -Mode $mode -Result $result -Decision 'flagged-stop'
        @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    }
    else {
        # shadow は記録のみ。stdout には何も出さない。
        # Stop フックが additionalContext を返すと会話が継続し、Claude がもう1ターン動いて利用料がかかるため
        # （https://code.claude.com/docs/en/hooks#stop の decision control）。結果は .claude/jev/logs/ で確認する。
        Write-JevLog -Feature 'sources' -Mode $mode -Result $result -Decision 'flagged-shadow'
    }
}
catch {
    # 何が起きても Claude を止めない
}
exit 0
