# 技術スタック

バージョンを書くときは、依存定義ファイル（`package.json` / `.csproj` / `pyproject.toml` 等）の実際の値を確認してから書くこと（[.claude/factcheck.md](../.claude/factcheck.md)）。

## 必要環境

| 項目 | バージョン |
|---|---|
| Node.js | 20.9 以上（Next.js 16 の要件） |
| Windows PowerShell | 5.1（同梱スクリプトの実行に必要） |

## フロントエンド

| 技術 | 用途 |
|---|---|
| Next.js 16（Pages Router）+ React 19 | UIフレームワーク・ページルーティング |
| TypeScript 5.9 | 言語（ゲームエンジンは UI から切り離した純粋な TypeScript で書く） |
| 未定 | スタイリング |

## バックエンド

| 技術 | 用途 |
|---|---|
| Next.js API Routes | jev API の中継（API キーはサーバー側の環境変数にだけ置く） |

## データベース・認証

| 技術 | 用途 |
|---|---|
| 未定 | データベース・認証・ストレージ |

マイグレーションの方式（SQL ファイルを手動適用するのか、マイグレーションツールを使うのか）もここに書いてください。/db:migrate はこの記述を参照します。

## インフラ / ホスティング

| 技術 | 用途 |
|---|---|
| 未定 | アプリのホスティング・デプロイ |

手動デプロイの手順もここに書いてください。/deploy はこの記述を参照します。

## 開発ツール

| 技術 | 用途 |
|---|---|
| ESLint 9 | 静的解析（/lint） |
| Prettier 3 | コード整形（/format） |
| Vitest 4 | テスト（/test） |

各コマンドの実体は `.claude/project.json` に定義されています（[project-config.md](project-config.md) 参照）。
