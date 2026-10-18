# {{プロジェクト名}}

{{プロジェクトの簡単な説明}}

## 機能

- {{機能1}}
- {{機能2}}

## このひな形について

言語・フレームワークに依存しない開発運用の仕組み（スラッシュコマンド・サブエージェント・フック・Git 運用ルール）を共通部分として持ち、**言語ごとに変わる設定はスタックとして差し替える**構成になっています。

- 共通部分 — `.claude/`（コマンド・エージェント・スキル・フック）と `docs/` の運用ルール
- 言語ごとの設定 — `stacks/` 配下のプロファイル。/setup で選んだものがリポジトリのルートへ展開される
- 展開結果の要 — `.claude/project.json`。「このプロジェクトで lint とは何を実行することか」を定義する（[docs/project-config.md](docs/project-config.md)）

## スタック

/setup で選べるスタックの一覧です。実体は `stacks/<スタック名>/` にあります。

| スタック | 内容 | 主なコマンド |
|---|---|---|
| `nextjs-ts` | Next.js (Pages Router) + TypeScript + Vitest + Prettier | `npm run lint` / `npm run typecheck` / `npm run test` / `npm run build` |
| `dotnet` | .NET (C#) + xUnit | `dotnet format` / `dotnet test` / `dotnet build` |
| `python` | Python + ruff + mypy + pytest | `ruff check` / `mypy` / `pytest` |

どれにも当てはまらない場合は、新しいプロファイルを作って追加できます（[docs/project-config.md](docs/project-config.md) の「スタックを追加するには」）。

## ディレクトリ構成

```
{{プロジェクト名}}/
├── CLAUDE.md               # Claude Code 向けガイド
├── README.md               # このファイル（プロジェクト説明）
├── .editorconfig           # 文字コード・改行・インデントの規約
├── .gitattributes          # 改行コードの正規化設定
├── .gitignore
├── .env.example            # 環境変数のサンプル
├── .github/
│   └── workflows/ci.yml    # CI（/check と同じ処理を実行）
├── .claude/
│   ├── settings.json       # 権限・フック設定
│   ├── project.json        # コマンド定義（/setup が生成する）
│   ├── factcheck.md        # ハルシネーション防止ルール
│   ├── session-check.ps1   # セッション開始時チェック（SessionStart フック）
│   ├── hooks/              # Git hooks・Claude Code フックスクリプト
│   ├── agents/             # サブエージェント定義
│   ├── skills/             # スキル定義
│   ├── jev/                # 開発支援（TypeSafe AI jev との連携。API キー無時は非動作）
│   │   ├── lib/            # 共有ライブラリ
│   │   ├── config.json     # 設定（動作モード等）
│   │   ├── select-docs.ps1 # 作業前の資料選び
│   │   ├── check-commit.ps1 # コミット判定（ /git:push 内で実行）
│   │   └── questions/      # jev の質問定義
│   └── commands/           # カスタムスラッシュコマンド
│       ├── check.ps1       # /check の実体
│       ├── run.ps1         # /lint・/format・/typecheck・/test・/build の実体
│       ├── setup.ps1       # /setup の実体
│       ├── verify-docs.ps1 # ドキュメントの参照先検査（/check から呼ばれる）
│       ├── lib/            # 共有ヘルパー（project-config.ps1）
│       ├── git/            # Git関連
│       ├── server/         # サーバー関連
│       └── db/             # DB関連
├── stacks/                 # 言語・フレームワークごとのプロファイル
│   ├── nextjs-ts/
│   │   ├── stack.json      # .claude/project.json の元になる定義
│   │   └── files/          # ルートへ展開するファイル（依存定義・規約ドキュメント・雛形ディレクトリ）
│   ├── dotnet/
│   └── python/
└── docs/                   # ドキュメント
    ├── git-rules.md        # Git運用ルール
    ├── tech-stack.md       # 技術スタック
    ├── development-setup.md # セットアップガイド
    ├── project-config.md   # .claude/project.json の仕様
    ├── powershell-contributing.md # PowerShell の規約
    ├── jev.md              # jev による開発支援（API キー・設定・使い方）
    ├── direction-proposal.md # ゲームの方向性（宝石のきらめき）
    └── sql/                # SQLファイル（マイグレーション・初期データ等）
```

`src/` と `tests/` は /setup でスタックの雛形が展開されます。言語ごとの規約ドキュメント（`docs/TS-contributing.md` 等）も同時に配置されます。

## 技術スタック

詳細は [docs/tech-stack.md](docs/tech-stack.md) を参照してください。

## セットアップ

詳細は [docs/development-setup.md](docs/development-setup.md) を参照してください。

```
/setup              # 利用できるスタックの一覧を表示する（何も変更しない）
/setup nextjs-ts    # スタックを展開し、.claude/project.json を作り、依存をインストールする
/git:init           # git の初期化と hooks（push 前の機密情報チェック）の登録
```

## カスタムコマンド

Claude Code で使えるカスタムスラッシュコマンドの一覧です。
各コマンドの実体は `.claude/commands/` 配下の `.md`（および `.ps1`）ファイルです。

### 開発

| コマンド | 内容 | 実体 | 使うタイミング |
|---|---|---|---|
| `/setup [スタック名]` | スタックの展開・`.claude/project.json` の作成・依存パッケージのインストール | `setup.ps1` | プロジェクト作成直後に1回 |
| `/server:start` | 開発サーバーを起動する | `server/start.ps1` | 作業開始時 |
| `/server:stop` | 開発サーバーを停止する | `server/stop.ps1` | 作業終了時 |
| `/lint` | 静的解析 | `run.ps1 lint` | コード変更後 |
| `/format` | コード整形 | `run.ps1 format` | コミット前 |
| `/typecheck` | 型検査 | `run.ps1 typecheck` | コード変更後 |
| `/test` | テスト実行 | `run.ps1 test` | コード変更後 |
| `/check` | ドキュメント検査 → lint → 型検査 → テスト → ビルドの一括総点検 | `check.ps1` | **プッシュ・デプロイ前** |
| `/build` | 本番用ビルド | `run.ps1 build` | デプロイ前の確認 |
| `/deploy` | デプロイ手順の案内（PR マージ → 自動デプロイ） | `deploy.md` 参照 | リリース時 |
| `/db:migrate` | DB のスキーマ変更（`docs/sql/` の SQL 適用等） | `db/migrate.md` 参照 | スキーマ変更時 |

`/lint`・`/format`・`/typecheck`・`/test`・`/build` と `/check` の各ステップは、`.claude/project.json` に定義されたコマンドを実行します。ツールを導入していない項目は「設定されていません」と表示されます（エラーではありません）。

### Git

| コマンド | 内容 | 実体 | 使うタイミング |
|---|---|---|---|
| `/git:init` | git リポジトリの初期化と hooks の登録 | `git/init.ps1` | クローン直後に1回 |
| `/git:branch <名前>` | ブランチを作成してチェックアウト（`feature/…` `fix/…` `docs/…`） | `git/branch.ps1` | 作業開始時 |
| `/git:status` | 変更ファイルの一覧を表示 | `git status` | 随時 |
| `/git:diff` | 変更内容の差分を表示 | `git diff` | コミット前の確認 |
| `/git:log` | コミット履歴を1行ずつ表示 | `git log --oneline` | 随時 |
| `/git:push "<メッセージ>"` | シークレット・main 直プッシュ・テスト追加漏れ・コミット種類をチェックした上でコミット＆プッシュ（jev による判定を含む） | `git/push.ps1` | 作業の区切り |
| `/git:pr` | 現在のブランチから main への PR を作成 | `gh pr create` | プッシュ後 |
| `/git:merge` | CI の成功を確認して PR を main へマージ | `gh pr merge` | PR 作成後 |
| `/git:cleanup` | マージ済みのローカルブランチを整理（既定は一覧表示のみ） | `git/cleanup.ps1` | ブランチが溜まったとき |

> **注意**: プッシュは生の `git push` ではなく必ず `/git:push` を使うこと（[docs/git-rules.md](docs/git-rules.md) 参照）。

### その他

| コマンド | 内容 | 実体 | 使うタイミング |
|---|---|---|---|
| `/plan` | 会話内容をもとに実装プランを Plan mode で整理 | `plan.md` 参照 | 実装に入る前 |

### 日常の基本フロー

```
セッション開始
  → /git:branch feature/<名前>   作業ブランチ作成
  → /server:start          開発サーバー起動
  → （実装・確認を繰り返す。随時 /git:status, /git:diff）
  → /check                 プッシュ前の総点検
  → /git:push "feat: …"    コミット＆プッシュ
  → /git:pr                PR 作成
  → /git:merge             CI 確認 → マージ → 自動デプロイ
```

### コマンドを追加するには

1. `.claude/commands/` に `<コマンド名>.md` を作成する（サブフォルダは `:` 区切りの名前空間になる。例: `git/pr.md` → `/git:pr`）
2. ファイル本文に Claude への指示を書く。`$ARGUMENTS` で引数を受け取れる
3. この一覧表にも行を追加する

## サブエージェント

Claude Code が特定のタスクを委譲するサブエージェントの一覧です。
各エージェントの実体は `.claude/agents/` 配下の `.md` ファイルです。

| エージェント | 役割 | ツール | 使うタイミング |
|---|---|---|---|
| `coder` | コンポーネント・関数・ロジックの実装と修正 | Read, Write, Edit, Glob, Grep, Bash, PowerShell | 実装するとき |
| `code-reviewer` | 規約ドキュメント・`factcheck.md` に基づくコードレビュー | Read, Grep, Glob | 実装完了後、コミット前 |
| `readme-syncer` | README.md の記述と実体の乖離を検出・修正 | Read, Edit, Glob, Grep, Bash | コマンド・エージェント・構成を変更した後 |
| `retrospective-writer` | 振り返り報告書の作成 | Read, Write, Glob, Grep, Bash, PowerShell | 開発の節目・振り返り依頼時 |

## スキル

| スキル | 内容 |
|---|---|
| `retrospective` | 振り返り報告書の書き方・テンプレート（`retrospective-writer` が使用） |
| `jev-select-docs` | 作業に着手する前に、読むべき資料を jev に選ばせて絞り込む（`coder` が実装前に実行） |

## ドキュメント

- [セットアップガイド](docs/development-setup.md)
- [Git運用ルール](docs/git-rules.md)
- [プロジェクト設定（.claude/project.json）](docs/project-config.md)
- [コントリビュートガイド（PowerShell）](docs/powershell-contributing.md)
- [jev による開発支援](docs/jev.md)
- [ゲームの方向性（宝石のきらめき）](docs/direction-proposal.md)

言語ごとのコントリビュートガイドは /setup で `docs/` に配置されます（`docs/TS-contributing.md`・`docs/CS-contributing.md`・`docs/PY-contributing.md`）。
