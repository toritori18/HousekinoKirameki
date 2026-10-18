# セッション開始時チェック：必須項目が未設定の場合に Claude へ通知する

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$missing = @()

# スタックの選択チェック（.claude/project.json が各コマンドの実体を定義する）
if (-not (Test-Path ".claude/project.json")) {
    $missing += "・スタックが未選択です。/setup を実行してください（利用できるスタックの一覧が表示されます）。"
}

# README.md チェック
if (-not (Test-Path "README.md")) {
    $missing += "・README.md が存在しません。プロジェクト概要を記載してください。"
} elseif (Select-String -Path "README.md" -Pattern "\{\{" -Quiet) {
    $missing += "・README.md にプレースホルダーが残っています。プロジェクト情報を入力してください。"
}

# 技術スタック チェック
if (-not (Test-Path "docs/tech-stack.md")) {
    $missing += "・docs/tech-stack.md が存在しません。技術スタックを記載してください。"
} elseif (Select-String -Path "docs/tech-stack.md" -Pattern "\{\{例:" -Quiet) {
    $missing += "・docs/tech-stack.md の技術スタックが未入力です。プレースホルダーを実際の技術に書き換えてください。"
}

# コントリビュートガイド チェック。
# 対象は .claude/project.json の contributing に挙がっている規約ドキュメント（言語ごとに変わる）。
# ここでファイルを読むのは通知のためだけなので、解析できない場合は黙って飛ばす。
if (Test-Path ".claude/project.json") {
    try {
        $config = Get-Content -LiteralPath ".claude/project.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $contributing = $config.PSObject.Properties["contributing"]
        if ($null -ne $contributing) {
            $checked = @{}
            foreach ($property in $contributing.Value.PSObject.Properties) {
                $path = $property.Value
                # 同じドキュメントが複数の拡張子に紐づくため、重複して通知しない
                if ([string]::IsNullOrWhiteSpace($path) -or $checked.ContainsKey($path)) {
                    continue
                }
                $checked[$path] = $true

                if (-not (Test-Path $path)) {
                    $missing += "・$path が存在しません（.claude/project.json の contributing が参照しています）。"
                } elseif (Select-String -Path $path -Pattern "\{\{" -Quiet) {
                    $missing += "・$path にプレースホルダーが残っています。プロジェクトの規約に合わせて書き換えてください。"
                }
            }
        }
    }
    catch {
        $missing += "・.claude/project.json を JSON として解析できません。構文を確認してください。"
    }
}

# git リポジトリ チェック（未初期化だと Git 系コマンド・フックが動作しない）
if (-not (Test-Path ".git")) {
    $missing += "・git リポジトリが未初期化です。/git:init を実行してください（git init と git hooks の登録が行われます）。"
}

if ($missing.Count -gt 0) {
    $list = $missing -join "`n"
    $message = "作業を始める前に以下を設定してください:`n$list"
    $json = [PSCustomObject]@{
        hookSpecificOutput = [PSCustomObject]@{
            hookEventName     = "SessionStart"
            additionalContext = $message
        }
    } | ConvertTo-Json -Compress
    Write-Output $json
}
