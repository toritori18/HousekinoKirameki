param(
    # 展開するスタックのディレクトリ名（stacks/ 配下）。未指定なら一覧を表示するだけで何もしない。
    [string] $Stack,

    # 既存ファイルを上書きする。既定では上書きせずスキップする（破壊的な操作は明示指定のときだけ行う）。
    [switch] $Force
)

# 初回セットアップ。stacks/<スタック名>/ の内容をリポジトリルートへ展開し、
# .claude/project.json（各コマンドの実体を定義するファイル）を作る。
#
# git の初期化と hooks の登録はここでは行わない（/git:init が担当する）。

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'lib\project-config.ps1')

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$StacksRoot = Join-Path $RepoRoot 'stacks'

if (-not (Test-Path -LiteralPath $StacksRoot)) {
    Write-Host "ERROR: stacks ディレクトリが見つかりません（$StacksRoot）。" -ForegroundColor Red
    exit 1
}

$available = @(Get-ChildItem -LiteralPath $StacksRoot -Directory | Sort-Object Name)

<#
.SYNOPSIS
    利用できるスタックの一覧を、stack.json の description とともに表示する。
#>
function Show-AvailableStack {
    Write-Host "利用できるスタック:" -ForegroundColor Cyan
    foreach ($dir in $available) {
        $description = ''
        $stackJson = Join-Path $dir.FullName 'stack.json'
        if (Test-Path -LiteralPath $stackJson) {
            try {
                $parsed = (Get-Content -LiteralPath $stackJson -Raw -Encoding UTF8 | ConvertFrom-Json)
                $description = Get-ConfigProperty -Object $parsed -Name 'description'
            }
            catch {
                $description = '(stack.json を解析できません)'
            }
        }
        Write-Host ("  {0,-14} {1}" -f $dir.Name, $description)
    }
}

# --- スタック未指定: 一覧を出すだけで何もしない ---
if ([string]::IsNullOrWhiteSpace($Stack)) {
    Write-Host "=== セットアップ ===" -ForegroundColor Cyan
    Write-Host ""
    Show-AvailableStack
    Write-Host ""
    Write-Host "使うスタックを指定して実行してください（例: /setup nextjs-ts）。" -ForegroundColor Yellow
    Write-Host "どのスタックにも当てはまらない場合は、stacks/ に新しいプロファイルを作ってから実行してください。" -ForegroundColor Yellow
    exit 0
}

$StackRoot = Join-Path $StacksRoot $Stack
if (-not (Test-Path -LiteralPath $StackRoot)) {
    Write-Host "ERROR: スタック '$Stack' が見つかりません。" -ForegroundColor Red
    Write-Host ""
    Show-AvailableStack
    exit 1
}

Write-Host "=== セットアップ（$Stack） ===" -ForegroundColor Cyan

# --- [1/4] スタックのファイルをルートへ展開 ---
Write-Host ""
Write-Host "[1/4] スタックのファイルを展開しています..."

$FilesRoot = Join-Path $StackRoot 'files'
$copied = 0
$skippedFiles = New-Object System.Collections.Generic.List[string]

if (Test-Path -LiteralPath $FilesRoot) {
    foreach ($file in (Get-ChildItem -LiteralPath $FilesRoot -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($FilesRoot.Length + 1)
        $destination = Join-Path $RepoRoot $relative

        if ((Test-Path -LiteralPath $destination) -and (-not $Force)) {
            $skippedFiles.Add($relative)
            continue
        }

        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        if (-not $?) {
            Write-Host "ERROR: $relative のコピーに失敗しました。" -ForegroundColor Red
            exit 1
        }
        $copied++
    }
}

Write-Host "  $copied 件を展開しました。"
if ($skippedFiles.Count -gt 0) {
    Write-Host "  既に存在するため上書きしなかったファイル（$($skippedFiles.Count) 件）:" -ForegroundColor Yellow
    foreach ($name in $skippedFiles) {
        Write-Host "    - $name" -ForegroundColor Yellow
    }
    Write-Host "  上書きする場合は -Force を付けて再実行してください。" -ForegroundColor Yellow
}

# --- [2/4] project.json の作成 ---
Write-Host ""
Write-Host "[2/4] .claude/project.json を作成しています..."

$stackJsonPath = Join-Path $StackRoot 'stack.json'
if (-not (Test-Path -LiteralPath $stackJsonPath)) {
    Write-Host "ERROR: $Stack に stack.json がありません（$stackJsonPath）。" -ForegroundColor Red
    exit 1
}

$projectJsonPath = Join-Path $RepoRoot '.claude\project.json'
if ((Test-Path -LiteralPath $projectJsonPath) -and (-not $Force)) {
    Write-Host "  .claude/project.json は既に存在します。スキップしました（上書きするには -Force）。" -ForegroundColor Yellow
}
else {
    Copy-Item -LiteralPath $stackJsonPath -Destination $projectJsonPath -Force
    if (-not $?) {
        Write-Host "ERROR: .claude/project.json の作成に失敗しました。" -ForegroundColor Red
        exit 1
    }
    Write-Host "  .claude/project.json を作成しました。"
}

# --- [3/4] 環境変数ファイルの作成 ---
Write-Host ""
Write-Host "[3/4] 環境変数ファイルを作成しています..."

$envExample = Join-Path $RepoRoot '.env.example'
$envLocal = Join-Path $RepoRoot '.env.local'
if (-not (Test-Path -LiteralPath $envExample)) {
    Write-Host "  .env.example が無いためスキップしました。" -ForegroundColor Yellow
}
elseif (Test-Path -LiteralPath $envLocal) {
    Write-Host "  .env.local は既に存在します。スキップしました。" -ForegroundColor Yellow
}
else {
    Copy-Item -LiteralPath $envExample -Destination $envLocal
    if (-not $?) {
        Write-Host "ERROR: .env.local の作成に失敗しました。" -ForegroundColor Red
        exit 1
    }
    Write-Host "  .env.local を作成しました。必要な接続情報を設定してください。"
}

# --- [4/4] 依存パッケージのインストール ---
Write-Host ""
Write-Host "[4/4] 依存パッケージをインストールしています..."

$config = Get-ProjectConfig
$install = Get-ConfigProperty -Object $config -Name 'install'
if ([string]::IsNullOrWhiteSpace($install)) {
    Write-Host "  install コマンドが未設定のためスキップしました。" -ForegroundColor Yellow
}
else {
    Write-Host "  $install"
    if (-not (Invoke-ProjectCommand -Command $install -WorkingDirectory $RepoRoot)) {
        Write-Host "ERROR: 依存パッケージのインストール（$install）に失敗しました。" -ForegroundColor Red
        Write-Host "  対応方法: 必要なランタイム（Node.js・.NET SDK・Python 等）がインストールされているか確認してください。" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "=== セットアップ完了 ===" -ForegroundColor Cyan
Write-Host "次のステップ:"
Write-Host "  1. .env.local を編集して接続情報を設定する"
Write-Host "  2. /git:init で git リポジトリを初期化し、hooks（push 前の機密情報チェック）を登録する"
Write-Host "  3. README.md・docs/tech-stack.md のプレースホルダ（波かっこ2つで囲まれた箇所）を埋める"
Write-Host "  4. /server:start で開発サーバーを起動する（サーバーを使うスタックの場合）"
exit 0
