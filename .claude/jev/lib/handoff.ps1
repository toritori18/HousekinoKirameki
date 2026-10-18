# 引き継ぎメモ（.claude/handoff/*.md）を読む共有ライブラリ。
# .claude/hooks/handoff-list.ps1 と handoff-prompt.ps1 から dot-source して使う。単体実行しない。
# stdout の文字コード固定は呼び出し元が行う（docs/powershell-contributing.md の「標準出力の文字コード」参照）。
# 使い方は docs/handoff.md を参照。
#
# メモの書式（wrap スキルが書く。ここの読み取りと一致させること）:
#   # <作業名>
#   次の一手: <1行>
#   更新: YYYY-MM-DD
#
#   ## 目的 / ## 未完了と次の一手 / ## 決定事項と理由

. (Join-Path $PSScriptRoot '..\..\commands\lib\project-config.ps1')

<#
.SYNOPSIS
    引き継ぎメモのディレクトリ（.claude/handoff）の絶対パスを返す。
#>
function Get-HandoffDir {
    return (Join-Path (Get-RepoRoot) '.claude\handoff')
}

<#
.SYNOPSIS
    セッションごとの状態ファイルのパスを返す。session_id に使えない文字があれば $null。
.DESCRIPTION
    session_id はファイル名に使うため、英数字・_・- 以外を含む場合はパス組み立てに使わず $null を返す
    （パスを抜けるような値を受け付けないため）。
#>
function Get-HandoffStatePath {
    param(
        [AllowNull()]
        [string] $SessionId
    )

    if ([string]::IsNullOrWhiteSpace($SessionId) -or $SessionId -notmatch '^[A-Za-z0-9_-]+$') {
        return $null
    }
    return (Join-Path (Get-HandoffDir) ".state\$SessionId.json")
}

<#
.SYNOPSIS
    引き継ぎメモを1ファイル読み、作業名・次の一手・更新日・目的の抜粋・全文を持つオブジェクトで返す。読めなければ $null。
#>
function Read-HandoffNote {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        # 「目的」節の抜粋の最大文字数
        [int] $PurposeMaxChars = 300
    )

    try {
        $text = [string](Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8)
    }
    catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $title = ''
    $next = ''
    $updated = ''
    $purposeLines = New-Object System.Collections.Generic.List[string]
    $inPurpose = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^##\s*(.+?)\s*$') {
            $inPurpose = ($Matches[1] -eq '目的')
            continue
        }
        if ($inPurpose) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $purposeLines.Add($line.Trim())
            }
            continue
        }
        if ($title -eq '' -and $line -match '^#\s+(.+?)\s*$') {
            $title = $Matches[1]
        }
        elseif ($next -eq '' -and $line -match '^次の一手\s*[:：]\s*(.*?)\s*$') {
            $next = $Matches[1]
        }
        elseif ($updated -eq '' -and $line -match '^更新\s*[:：]\s*(.*?)\s*$') {
            $updated = $Matches[1]
        }
    }
    if ($title -eq '') {
        $title = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    }
    $purpose = ($purposeLines -join ' ')
    if ($purpose.Length -gt $PurposeMaxChars) {
        $purpose = $purpose.Substring(0, $PurposeMaxChars)
    }

    return [pscustomobject]@{
        Title   = $title
        Next    = $next
        Updated = $updated
        Purpose = $purpose
        Name    = $File.Name
        Path    = '.claude/handoff/' + $File.Name
        Text    = $text
    }
}

<#
.SYNOPSIS
    引き継ぎメモの一覧を更新日時の新しい順で返す（archive 配下と隠しディレクトリは含めない）。
.DESCRIPTION
    ディレクトリ直下の *.md だけを対象にする（再帰しない）ため、archive/ は含まれない。
    メモが無い・ディレクトリが無い場合は空配列。
#>
function Get-HandoffNotes {
    $dir = Get-HandoffDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }
    $notes = New-Object System.Collections.Generic.List[object]
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.md' -File | Sort-Object LastWriteTime -Descending)) {
        $note = Read-HandoffNote -File $file
        if ($null -ne $note) {
            $notes.Add($note)
        }
    }
    return $notes.ToArray()
}

<#
.SYNOPSIS
    セッションの状態ファイルを読む。無い・壊れている場合は $null。
#>
function Read-HandoffState {
    param(
        [AllowNull()]
        [string] $SessionId
    )

    $path = Get-HandoffStatePath -SessionId $SessionId
    if ($null -eq $path -or -not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    セッションの状態ファイルを BOM なし UTF-8 で書く。失敗しても例外は投げない。
#>
function Write-HandoffState {
    param(
        [AllowNull()]
        [string] $SessionId,

        [Parameter(Mandatory = $true)]
        $State
    )

    try {
        $path = Get-HandoffStatePath -SessionId $SessionId
        if ($null -eq $path) {
            return
        }
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $json = $State | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        # 状態の保存失敗で本処理を止めない
    }
}
