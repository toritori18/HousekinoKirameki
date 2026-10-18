# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

## 基本ルール

- 応答・コミットメッセージ・PR の説明は日本語で書く
- コーディング（コンポーネント・関数・ロジックの新規実装や修正）は `coder` エージェントに委任する
- カスタムコマンド・サブエージェント・スキル・スタック・ディレクトリ構成を追加/削除/リネーム、または役割を変更したときは、`readme-syncer` エージェントで [README.md](README.md) を同期する
- コードを生成・提案する前に [.claude/factcheck.md](.claude/factcheck.md) のチェックリストに従い、ハルシネーションを防ぐ
- この `CLAUDE.md` の変更は、ユーザーの明示的な指示がある場合のみ行う（フックにより確認が入る）

## プロジェクト概要・ディレクトリ構成

プロジェクト概要・ディレクトリ構成は [README.md](README.md) に記載する。変更を加えたときは該当箇所も更新すること。

## 技術スタック

[docs/tech-stack.md](docs/tech-stack.md) を参照してください。

## カスタムコマンド

各コマンドの意味・使うタイミングは **[README.md の「カスタムコマンド」セクション](README.md#カスタムコマンド)** を参照してください。
プッシュは生の `git push` ではなく必ず `/git:push` を使うこと。

## Git運用ルール（要約）

- `main` への直接コミット・プッシュは禁止（`/git:push` でもブロックされる）
- 機能追加は `feature/<機能名>`、バグ修正は `fix/<バグ名>` ブランチで作業し、PR 経由で main へマージする
- コミットメッセージは `feat:` / `fix:` / `refactor:` / `docs:` / `chore:` のプレフィックスを付ける

詳細は **[docs/git-rules.md](docs/git-rules.md)** を参照してください。

## コーディング規約・禁止事項

実装・レビューするファイルの拡張子に対応する規約ドキュメントを、`.claude/project.json` の `contributing` から引いて参照してください（例: `.ts` → `docs/TS-contributing.md`、`.ps1` → [docs/powershell-contributing.md](docs/powershell-contributing.md)）。

言語ごとの規約ドキュメントは /setup でスタックを展開したときに `docs/` へ配置されます。

Claude Code での実装時に特に注意すること：

- コードを実装した際は、使用した出典（公式ドキュメント・仕様書等）を画面・機能ごとに整理してレスポンスの末尾に表示する
- 出典がない場合は「出典なし」と明記すること。空欄にしない
