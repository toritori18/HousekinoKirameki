# セットアップガイド

## 必要環境

使用するスタックによって異なります。このプロジェクトの必要環境は [tech-stack.md](tech-stack.md) に記載してください。

- Node.js 系のスタック: Node.js と npm
- .NET 系のスタック: .NET SDK
- Python 系のスタック: Python と pip

いずれの場合も、同梱のスクリプトを実行するために **Windows PowerShell 5.1** と **git** が必要です。

## 初回セットアップ

```powershell
git clone <リポジトリURL>
cd <プロジェクト名>
```

クローン後、Claude Code で以下を順に実行します。

### 1. スタックの展開

```
/setup
```

引数なしで実行すると、利用できるスタックの一覧が表示されます（何も変更されません）。
使うスタックを決めたら、名前を指定して実行します。

```
/setup nextjs-ts
```

これにより以下が行われます。

1. `stacks/<スタック名>/files/` の内容がリポジトリのルートへ展開される
2. `.claude/project.json` が作られる（各コマンドの実体を定義するファイル。[project-config.md](project-config.md) 参照）
3. `.env.example` から `.env.local` が作られる
4. 依存パッケージがインストールされる

### 2. git の初期化と hooks の登録

```
/git:init
```

push 前の機密情報チェックと `/check`（`.claude/hooks/pre-push`）を有効にするため、クローン後に必ず実行してください。
既に `.git` がある場合は初期化をスキップし、hooks の登録のみ行います。

手動で行う場合は次のコマンドと同じです。

```powershell
git init -b main
git config core.hooksPath .claude/hooks
```

### 3. 環境変数の設定

`.env.local` を編集して必要な値を設定してください。`.env.local` は `.gitignore` で除外されており、コミットしてはいけません。

### 4. プレースホルダを埋める

`README.md` と [tech-stack.md](tech-stack.md) には波かっこ2つで囲まれたプレースホルダが残っています。プロジェクトの内容に書き換えてください。
セッション開始時のチェック（`.claude/session-check.ps1`）が、残っている場合に知らせます。

## 日常の操作

| やりたいこと | コマンド |
|---|---|
| 開発サーバーを起動する | /server:start |
| 開発サーバーを停止する | /server:stop |
| 静的解析 | /lint |
| コード整形 | /format |
| 型検査 | /typecheck |
| テスト | /test |
| 本番ビルド | /build |
| プッシュ前の総点検 | /check |

実行されるコマンドの実体は `.claude/project.json` にあります。スタックによって中身が変わります。
ツールを導入していない項目は「設定されていません」と表示されます（エラーではありません）。
