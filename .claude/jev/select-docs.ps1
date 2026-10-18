param(
    # これから行う作業の内容（自然文）
    [Parameter(Mandatory = $true)]
    [string] $Task
)

# 作業に関係の深い資料を jev に選ばせる。候補は docs/ 配下の .md（再帰）と README.md。
# 各資料について score 質問（0〜3）を1リクエストにまとめて問い、上位の資料を「パス<TAB>スコア」で出力する。
#
# キーが無い・通信に失敗したときは、その旨を表示して終了コード 0 で終わる（資料は自分で選ぶ）。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'lib\jev-client.ps1')

# 候補数の上限と抜粋の長さ。出典の無い暫定値（1リクエストの大きさを抑えるための目安）。
$DefaultMaxCandidates = 40
$ExcerptMaxChars = 400

$SkipMessage = 'jev をスキップしました。資料は自分で選んでください'

<#
.SYNOPSIS
    .md の「最初の見出し」と「冒頭の本文」を連結し、指定文字数で切って返す。
.DESCRIPTION
    本文は見出し行・空行・コードフェンス行を除いた行を先頭から順に集める。
#>
function Get-DocExcerpt {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [int] $MaxChars
    )

    $heading = ''
    $bodyLines = New-Object System.Collections.Generic.List[string]
    $length = 0
    foreach ($line in (Get-Content -LiteralPath $FilePath -Encoding UTF8)) {
        if ($line -match '^\s*```') {
            continue
        }
        if ($line -match '^#{1,6}\s+(.+?)\s*$') {
            if ($heading -eq '') {
                $heading = $Matches[1]
            }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $bodyLines.Add($line.Trim())
        $length += $line.Trim().Length
        if ($length -ge $MaxChars) {
            break
        }
    }

    $text = "見出し: $heading`n" + ($bodyLines -join "`n")
    if ($text.Length -gt $MaxChars) {
        $text = $text.Substring(0, $MaxChars)
    }
    return $text
}

$mode = Get-JevMode -Feature 'selectDocs'
if ($mode -eq 'off' -or $null -eq (Get-JevApiKey)) {
    Write-Host $SkipMessage
    exit 0
}

$RepoRoot = Get-RepoRoot
$config = Get-ProjectConfig
$docsExclude = @(Get-ConfigProperty -Object $config -Name 'docsExclude' | Where-Object { $_ })

# --- 候補の収集 ---
$candidates = New-Object System.Collections.Generic.List[string]
$readme = Join-Path $RepoRoot 'README.md'
if (Test-Path -LiteralPath $readme) {
    $candidates.Add('README.md')
}
$docsRoot = Join-Path $RepoRoot 'docs'
if (Test-Path -LiteralPath $docsRoot) {
    $docFiles = Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter '*.md' | Sort-Object FullName
    foreach ($file in $docFiles) {
        $candidates.Add(($file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'))
    }
}

$candidates = @($candidates | Where-Object {
        $path = $_
        -not ($docsExclude | Where-Object { $path -like $_ })
    })

if ($candidates.Count -eq 0) {
    Write-Host '候補になる資料（docs/ 配下の .md と README.md）がありませんでした。'
    exit 0
}

$maxCandidates = [int](Get-JevFeatureSetting -Feature 'selectDocs' -Name 'maxCandidates' -Default $DefaultMaxCandidates)
if ($maxCandidates -le 0) {
    $maxCandidates = $DefaultMaxCandidates
}
if ($candidates.Count -gt $maxCandidates) {
    Write-Host "候補が $($candidates.Count) 件あるため、先頭の $maxCandidates 件だけを対象にします。" -ForegroundColor Yellow
    $candidates = @($candidates | Select-Object -First $maxCandidates)
}

# --- state と質問の組み立て ---
$template = Get-ConfigProperty -Object (Get-JevQuestionDefinition -Name 'select-docs') -Name 'docScore'
if ($null -eq $template) {
    # 質問定義が読めない場合は、この機能だけスキップする
    Write-Host $SkipMessage
    exit 0
}
$questions = [ordered]@{}
$idToPath = @{}
$stateBuilder = New-Object System.Text.StringBuilder
[void]$stateBuilder.Append("## 作業内容`n$Task`n`n## 資料候補`n")

for ($i = 0; $i -lt $candidates.Count; $i++) {
    $path = $candidates[$i]
    $id = "doc$i"
    $idToPath[$id] = $path
    $excerpt = Get-DocExcerpt -FilePath (Join-Path $RepoRoot ($path -replace '/', '\')) -MaxChars $ExcerptMaxChars
    [void]$stateBuilder.Append("`n### $path`n$excerpt`n")

    # 質問 ID はモデルに送られないため、対象の資料はパスを instructions に埋め込んで指す
    $questions[$id] = [ordered]@{
        type         = $template.type
        instructions = $template.instructions.Replace('{path}', $path)
        criteria     = @($template.criteria)
    }
}

$result = Invoke-Jev -Feature 'selectDocs' -State $stateBuilder.ToString() -Questions $questions -Mode $mode
if ($result.Skipped) {
    Write-Host $SkipMessage
    Write-JevLog -Feature 'selectDocs' -Mode $mode -Result $result -Decision 'skipped'
    exit 0
}

# --- 採点結果の集計 ---
$top = [int](Get-JevFeatureSetting -Feature 'selectDocs' -Name 'top' -Default 3)
$minScore = [double](Get-JevFeatureSetting -Feature 'selectDocs' -Name 'minScore' -Default 1)

$scored = New-Object System.Collections.Generic.List[object]
foreach ($id in $idToPath.Keys) {
    # 数値でない・範囲外（0〜criteria の最大インデックス）の値は無視する
    $score = Get-JevScoreValue -Answers $result.Answers -Id $id -Max (@($template.criteria).Count - 1)
    if ($null -eq $score) {
        continue
    }
    if ($score -ge $minScore) {
        $scored.Add([pscustomobject]@{ Path = $idToPath[$id]; Score = $score })
    }
}
$selected = @($scored | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, 'Path' | Select-Object -First $top)

Write-JevLog -Feature 'selectDocs' -Mode $mode -Result $result -Decision "listed:$($selected.Count)"

if ($selected.Count -eq 0) {
    Write-Host "スコアが $minScore 以上の資料はありませんでした。必要な資料は自分で選んでください。"
    exit 0
}

foreach ($item in $selected) {
    Write-Output ("{0}`t{1}" -f $item.Path, $item.Score.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture))
}
exit 0
