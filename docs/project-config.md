# プロジェクト設定（.claude/project.json）

このひな形は言語・フレームワークに依存しない作りになっている。
「このプロジェクトでは lint が何を指すのか」「規約ドキュメントはどれか」といった**言語ごとに変わる情報を1か所に集めたのが `.claude/project.json`** である。

`.claude/project.json` は /setup が `stacks/<スタック名>/stack.json` をコピーして作る。後から手で編集してもよい。

## 誰がこのファイルを読むか

| 読む側 | 何に使うか |
|---|---|
| `.claude/commands/run.ps1`（/lint /format /test /typecheck /build の実体） | `commands.<ステップ名>` のコマンドを実行する |
| `.claude/commands/check.ps1`（/check の実体） | `check` に並ぶステップを順に実行する |
| `.claude/commands/server/start.ps1` / `stop.ps1` | `devServer` の起動コマンドと待ち受けポート |
| `.claude/commands/setup.ps1` | `install` の依存パッケージ導入コマンド |
| `.claude/commands/verify-docs.ps1` | `docsExclude` の検査除外パターン |
| `coder` / `code-reviewer` エージェント | `contributing` から、対象ファイルの拡張子に対応する規約ドキュメントを引く |

## キー一覧

| キー | 型 | 説明 |
|---|---|---|
| `stack` | 文字列 | 元にしたスタックのディレクトリ名（`stacks/` 配下） |
| `description` | 文字列 | スタックの説明。/setup の一覧表示に使う |
| `install` | 文字列 / null | 依存パッケージの導入コマンド。/setup が実行する |
| `devServer.command` | 文字列 / null | 開発サーバーの起動コマンド。null なら /server:start は何もしない |
| `devServer.port` | 数値 / null | 開発サーバーの待ち受けポート。null なら起動確認と /server:stop ができない |
| `commands.lint` | 文字列 / null | 静的解析のコマンド（/lint） |
| `commands.format` | 文字列 / null | コード整形のコマンド（/format） |
| `commands.typecheck` | 文字列 / null | 型検査のコマンド（/typecheck） |
| `commands.test` | 文字列 / null | テスト実行のコマンド（/test） |
| `commands.build` | 文字列 / null | 本番ビルドのコマンド（/build） |
| `check` | 文字列の配列 | /check で実行するステップを実行順に並べたもの |
| `contributing` | オブジェクト | 拡張子（`.ts` 等）→ 規約ドキュメントのパスの対応表 |
| `docsExclude` | 文字列の配列（省略可） | ドキュメント検査から外すパスのパターン（ワイルドカード可） |

### コマンドの書き方

コマンドは**引数も含めた1行の文字列**で書く。`npm run lint`・`dotnet format --verify-no-changes`・`python -m pytest` のように、シェルに打つそのままの形でよい。

実行時のカレントディレクトリは常にリポジトリのルートになる。

### null（未設定）の意味

`null` は「このプロジェクトにそのツールを導入していない」という意味である。エラーではない。

- /lint などのコマンドは「設定されていません」と表示して正常終了する
- /check は、未設定のステップをスキップし、最後にスキップした項目をまとめて表示する

導入していないツールのコマンド名を推測で書かないこと。導入するときは、ツールの候補をユーザーに確認してから追加する。

### check の特別なステップ

`check` に書く `verify-docs` だけは `commands` を参照せず、同梱の `.claude/commands/verify-docs.ps1` を実行する（言語に依存しないため）。
それ以外の名前は `commands.<その名前>` を実行する。独自のステップ名を足すこともできる。

### contributing の対応表

`coder` エージェントと `code-reviewer` エージェントは、変更するファイルの拡張子からこの表を引いて規約ドキュメントを読む。
表に無い拡張子のファイルを実装・レビューする場合、エージェントは自己判断で規約を作らず、ユーザーに規約ドキュメントの作成を確認する。

`.ps1` の規約（[powershell-contributing.md](powershell-contributing.md)）は言語非依存のコアに含まれるため、どのスタックでも対応表に入れておくこと。

## 設定例

```json
{
  "stack": "nextjs-ts",
  "description": "Next.js (Pages Router) + TypeScript + Vitest + Prettier",
  "install": "npm install",
  "devServer": {
    "command": "npm run dev",
    "port": 3000
  },
  "commands": {
    "lint": "npm run lint",
    "format": "npm run format",
    "typecheck": "npx tsc --noEmit",
    "test": "npm run test",
    "build": "npm run build"
  },
  "check": ["verify-docs", "lint", "typecheck", "test", "build"],
  "contributing": {
    ".ts": "docs/TS-contributing.md",
    ".ps1": "docs/powershell-contributing.md"
  }
}
```

## スタックを追加するには

1. `stacks/<新しいスタック名>/stack.json` を作る（上記のキーを埋める）
2. そのスタックでしか使わないファイル（依存定義・ビルド設定・言語別の規約ドキュメント等）を `stacks/<新しいスタック名>/files/` に置く。ここに置いたファイルは、/setup が**そのままの相対パスで**リポジトリのルートへ展開する
   - 例: `stacks/<名前>/files/docs/XX-contributing.md` → `docs/XX-contributing.md`
3. 規約ドキュメントのファイル名は言語ごとに別名にする（展開後のパスがスタック間で衝突しないようにするため）
4. `files/` 配下の `.md` に書く相対リンクは、**展開後の位置**を基準にする。同じスタックに同梱されるだけのファイル（依存定義ファイル等）へはリンクを張らず、コード体裁で名前を書く
5. README.md の「スタック」の表に行を追加する

/setup は既存ファイルを上書きしない。上書きが必要な場合のみ `-Force` を使う。
