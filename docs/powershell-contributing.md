# コントリビュートガイド（PowerShell）

対象は `.claude/` 配下の `.ps1`。用途は3種類ある。

| 場所 | 用途 |
|---|---|
| `.claude/commands/` | スラッシュコマンドから呼ばれる実行スクリプト |
| `.claude/commands/lib/` | 複数のスクリプトから dot-source される共有ヘルパー。単体実行しない |
| `.claude/hooks/` | Claude Code のフックスクリプト |
| `.claude/session-check.ps1` | SessionStart フック。**フックだが `hooks/` の外にある**ため、`settings.json` の `deny`（`Edit(./.claude/hooks/**)`）の対象外で編集できてしまう。書き方は下記「フックスクリプト（`hooks/`）」に従うこと |

アプリケーション本体のコードは、拡張子に対応する規約ドキュメントを参照する。対応表は `.claude/project.json` の `contributing` にある。

## 実行環境

- Windows PowerShell **5.1**（Desktop エディション）。PowerShell 7 系ではない
- スクリプトは Claude Code から非対話で実行される（標準入力からの応答は返らない）

出典: 本環境での実測（`$PSVersionTable.PSVersion` = `5.1.26100.9549`、2026-09-23 時点）

### 5.1 で使えない構文

PowerShell 7 で追加された以下は **5.1 のパーサーが受け付けない**。使用しないこと。

| 使えないもの | 代替 |
|---|---|
| `&&` / `\|\|`（パイプラインチェーン演算子） | `if (-not $?) { ... }` で分岐する |
| `? :`（三項演算子） | `if` / `else` |
| `??` / `??=`（null 合体演算子） | `if ($null -eq $x) { ... }` |
| `ConvertFrom-Json -AsHashtable` | 既定の戻り値（`PSCustomObject`）のまま扱う |

出典: 本環境の PowerShell 5.1 での実測（`[System.Management.Automation.Language.Parser]::ParseInput` が `&&` を "The token '&&' is not a valid statement separator in this version."、`? :` を "Unexpected token '?' in expression or statement."、`??` を "Unexpected token '??' in expression or statement." で拒否した。`ConvertFrom-Json` のパラメータ一覧に `AsHashtable` は存在しなかった）

## ファイル形式

文字コード・改行・インデントは [.editorconfig](../.editorconfig) を正とする（`[*.ps1]` セクションで定義しているのは `charset` と `indent_size` のみ。改行は `[*]` の `end_of_line = lf` を継承する）。特に以下は必須。

- **文字コードは UTF-8（BOM あり）**
- インデントはスペース4（`[*]` の2とは異なる）
- 改行は LF（`.ps1` だけ CRLF にしない）

BOM を付け忘れると、5.1 はファイルを ANSI コードページ（日本語環境では CP932）として読む。UTF-8 の日本語コメントが Shift-JIS として区切られてずれ、**コメント行が直後の改行を飲み込んで次の1行が消える**。

- 消えた行が独立した文だった場合 → **エラーも出ず、終了コード 0 のまま挙動だけ壊れる**
- 消えた行がブロックの開始（`if (...) {` 等）だった場合 → パースエラーで停止する

どちらになるかは日本語文字列のバイト数次第で選べない。前者はビルドやコマンドの成功を素通りするため、実行して確認しても検出できない。

日本語を含む `.ps1` を読む処理を書く場合も同様で、`Get-Content` には必ず `-Encoding UTF8` を明示する（省略すると 5.1 は既定の ANSI コードページとして読む）。

## 出力

### 標準出力の文字コード

スクリプトの先頭（`param()` があればその直後）で stdout を UTF-8 に固定する。

```powershell
# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

省略すると 5.1 は ANSI コードページ（CP932）で出力するため、Claude Code 側で日本語が文字化けして読めなくなる。エラーメッセージも読めなくなるため、失敗時に原因が分からなくなる。

他のファイルから dot-source されるだけで単体実行しないファイルは、呼び出し元が設定するため不要。

### メッセージ

- 本文は日本語で書く（同梱のスクリプトはすべて日本語に統一している）
- 異常系は `ERROR:` / `WARNING:` を先頭に付け、`-ForegroundColor Red` / `Yellow` を指定する
- エラーは「何が起きたか」だけで終わらせず、**復旧手順**まで出す

例：
```powershell
Write-Host "ERROR: ポート $port が10秒以内に解放されませんでした。ポートを使用しているプロセスを手動で停止してから再実行してください。" -ForegroundColor Red
```

## エラー処理

### 実行スクリプト（`commands/`）

- 外部コマンド（`git` / `npm` 等）を呼んだ直後は `if (-not $?) { ... }` で成否を確認する
- 失敗したら原因を出力して `exit 1` で終了する。握りつぶして続行しない
- 別の `.ps1` を `&` で呼んだ場合は、`$?` と `$LASTEXITCODE` の両方を見るのが確実（`if (-not $? -or $LASTEXITCODE -ne 0) { ... }`）。実例: [check.ps1](../.claude/commands/check.ps1)

```powershell
git commit -m $Message
if (-not $?) {
    Write-Host "ERROR: git commit に失敗しました。" -ForegroundColor Red
    exit 1
}
```

```powershell
& (Join-Path $PSScriptRoot 'verify-docs.ps1')
if (-not $? -or $LASTEXITCODE -ne 0) {
    Write-Host "ERROR: ドキュメントの参照先検査に失敗しました。" -ForegroundColor Red
    exit 1
}
```

### フックスクリプト（`hooks/`）

フックは終了コードではなく、**stdout に出力する JSON** で Claude Code に結果を伝える。`exit 1` は使わない。

```powershell
@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'ask'
        permissionDecisionReason = '（理由）'
    }
} | ConvertTo-Json -Compress
```

条件に該当しないときは何も出力しない。

なお `.claude/hooks/**` は [.claude/settings.json](../.claude/settings.json) の `deny` により Edit / Write が禁止されている。フックスクリプトの変更が必要な場合は、自分で編集せずユーザーに依頼すること。

## パス解決

呼び出し元のカレントディレクトリに依存させない。基準は `$PSScriptRoot` から解決する。

```powershell
# このファイルは .claude/commands/server/ に置かれているため、3階層上がリポジトリルートになる
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
```

dot-source のパス、ログの出力先、`Start-Process` のリダイレクト先も同様に絶対パスで指定する（`Start-Process` のリダイレクト先は呼び出し元のカレントディレクトリを基準に解決されるため）。実例: [server/start.ps1](../.claude/commands/server/start.ps1)

## パラメータ

- `param()` ブロックで宣言し、型を明示する（`[string]` / `[int]` 等）
- パラメータ名は PascalCase
- 必須は `[Parameter(Mandatory = $true)]`、取りうる値が決まっているものは `[ValidateSet(...)]` で縛る
- **破壊的な操作は既定で実行しない。** 明示的に指定された場合のみ行う

```powershell
param(
    # 既定は一覧表示のみ。削除は明示的に指定された場合しか行わない
    [ValidateSet("None", "Local", "LocalAndRemote")]
    [string]$Delete = "None"
)
```

実例: [git/cleanup.ps1](../.claude/commands/git/cleanup.ps1)

## コメント

- コメントは日本語で書く
- 自明な処理にコメントは書かない。「なぜそうしているか」が非自明な場合のみ書く
- 関数には `<# .SYNOPSIS #>` 形式のコメントベースヘルプを書く
- **実測を根拠に実装を決めた場合は、その実測内容と根拠をコメントに残す**（[.claude/factcheck.md](../.claude/factcheck.md) の方針。一次資料で裏が取れない場合は「出典なし」と明記する）

例：
```powershell
<#
.SYNOPSIS
    見出し文字列を GitHub のアンカー（#リンク）形式のスラッグに変換する。
#>
function ConvertTo-HeadingSlug {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Heading
    )
    ...
}
```

## 禁止事項

- BOM なしでの `.ps1` の作成（上記「ファイル形式」参照）
- `[Console]::OutputEncoding` を設定せずに日本語を出力すること（上記「標準出力の文字コード」参照）
- 日本語を含むファイルを `Get-Content` で読む際に `-Encoding UTF8` を省略すること（上記「ファイル形式」参照）
- 対話を要求するコマンドの使用（`Read-Host` / `Get-Credential` / `pause` / `Out-GridView`）— 非対話で実行されるため応答が返らず、処理が止まる
- 確認プロンプトが出る破壊的コマンドを、意図を明示せずに使うこと（`Remove-Item` 等は `-Force` / `-ErrorAction SilentlyContinue` などを明示する）
- `main` への直接プッシュを行う処理の追加（[git-rules.md](git-rules.md) 参照。[git/push.ps1](../.claude/commands/git/push.ps1) はブランチ名を検査して拒否している）
- APIキー・シークレットのコードへの直書き（必ず `.env.local` 経由で参照する。[development-setup.md](development-setup.md) 参照）
