# CLAUDE.md

## 基本ルール

- 応答・コミットメッセージ・PR の説明は日本語で書く
- コーディング（新規実装・修正）は `coder` エージェントに委任する
- コマンド・サブエージェント・スキル・スタック・ディレクトリ構成を変更したら、`readme-syncer` エージェントで [README.md](README.md) を同期する
- 実装時は、使用した出典（公式ドキュメント等）を画面・機能ごとにレスポンス末尾へ示す。無い場合は「出典なし」と明記する

## Git

- `main` への直接コミット・プッシュは禁止。`feature/<機能名>` / `fix/<バグ名>` ブランチで作業し、PR 経由でマージする
- プッシュは生の `git push` ではなく `/git:push` を使う
- コミットメッセージには `feat:` / `fix:` / `refactor:` / `docs:` / `chore:` を付ける

## 参照先

- プロジェクト概要・ディレクトリ構成・コマンド一覧: [README.md](README.md)
- Git 運用の詳細: [docs/git-rules.md](docs/git-rules.md)
- 技術スタック: [docs/tech-stack.md](docs/tech-stack.md)
- コーディング規約: `.claude/project.json` の `contributing` に拡張子ごとの規約ドキュメントが定義されている
- ハルシネーション防止: [.claude/factcheck.md](.claude/factcheck.md)（セッション開始時にフックで自動注入される）
