# .claude/project.json（プロジェクト固有のコマンド定義）を扱う共有ヘルパー。
# .claude/commands/ 配下の各スクリプトから dot-source して使う。
#
# このファイル自体は単体実行しない。stdout の文字コード固定（[Console]::OutputEncoding）は
# 呼び出し元が行う（docs/powershell-contributing.md の「標準出力の文字コード」参照）。

<#
.SYNOPSIS
    リポジトリのルートディレクトリの絶対パスを返す。
.DESCRIPTION
    このファイルは .claude/commands/lib/ に置かれているため、3階層上がリポジトリルートになる。
    呼び出し元のカレントディレクトリに依存させないため、$PSScriptRoot を基準に解決する。
#>
function Get-RepoRoot {
    return Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

<#
.SYNOPSIS
    オブジェクトから指定名のプロパティ値を取り出す。存在しなければ $null を返す。
.DESCRIPTION
    ConvertFrom-Json が返すのは PSCustomObject であり、存在しないプロパティへのアクセスは
    Strict Mode では例外になる。キーの有無で分岐する箇所が多いため、ここで吸収する。
    （Windows PowerShell 5.1 の ConvertFrom-Json には -AsHashtable が無い。
    docs/powershell-contributing.md の「5.1 で使えない構文」参照）
#>
function Get-ConfigProperty {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

<#
.SYNOPSIS
    .claude/project.json を読み込む。未作成の場合は $null を返す。
.DESCRIPTION
    BOM なしの UTF-8 を 5.1 が ANSI コードページとして誤読するのを避けるため
    -Encoding UTF8 を明示する（docs/powershell-contributing.md の「ファイル形式」参照）。

    JSON として壊れている場合はここで exit 1 する。dot-source されているため、
    呼び出し元のスクリプトごと終了する（壊れた設定のまま後続を動かさないための意図的な動作）。
#>
function Get-ProjectConfig {
    $path = Join-Path (Get-RepoRoot) '.claude\project.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Host "ERROR: .claude/project.json を JSON として解析できませんでした: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  対応方法: JSON の構文を修正するか、/setup を実行し直して再生成してください。" -ForegroundColor Red
        exit 1
    }
}

<#
.SYNOPSIS
    project.json の commands.<Name> を返す。未定義・null・空文字はすべて $null（未導入）として扱う。
#>
function Get-ProjectCommand {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Config,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $commands = Get-ConfigProperty -Object $Config -Name 'commands'
    $value = Get-ConfigProperty -Object $commands -Name $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    return $value
}

<#
.SYNOPSIS
    project.json に書かれた1行コマンドを実行する。成功したら $true、失敗したら $false を返す。
.DESCRIPTION
    project.json はリポジトリ内で版管理される信頼済みの設定ファイルであり、
    「npm run lint」「python -m pip install -e ".[dev]"」のように引数と引用符を含む
    1行コマンドをそのまま書ける形式にしている。実行可能ファイルと引数へ機械的に分割すると
    引用符を正しく扱えないため、Invoke-Expression で実行する。

    $LASTEXITCODE は直前の外部コマンドの値が残るため、実行前に 0 へ戻してから判定する。
#>
function Invoke-ProjectCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    $global:LASTEXITCODE = 0
    Push-Location -LiteralPath $WorkingDirectory
    try {
        Invoke-Expression $Command
        $succeeded = $?
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Host "ERROR: コマンドの実行に失敗しました: $Command" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  対応方法: 必要なツールがインストールされているか、.claude/project.json のコマンド定義が正しいかを確認してください。" -ForegroundColor Red
        return $false
    }
    finally {
        Pop-Location
    }

    if (-not $succeeded) {
        return $false
    }
    if ($exitCode -ne 0) {
        return $false
    }
    return $true
}

<#
.SYNOPSIS
    project.json が未作成のときに案内を表示する。
#>
function Write-ProjectConfigMissing {
    Write-Host "ERROR: .claude/project.json がありません。" -ForegroundColor Red
    Write-Host "  対応方法: /setup <スタック名> を実行してスタックを選択してください（例: /setup nextjs-ts）。" -ForegroundColor Red
    Write-Host "  利用できるスタックは stacks/ 配下のディレクトリ名です。" -ForegroundColor Red
}
