main にマージ済みのローカルブランチを整理します。

まず、削除対象を一覧表示してください。この呼び出しでは何も削除されません。

```powershell
.\.claude\commands\git\cleanup.ps1
```

一覧をユーザーに提示し、削除してよいか確認してください。**確認が取れるまで削除を実行しないこと。**

確認が取れたら、ユーザーの選択に応じて以下のいずれかを実行してください。

ローカルブランチのみ削除する場合:

```powershell
.\.claude\commands\git\cleanup.ps1 -Delete Local
```

ローカルとリモート（origin）の両方を削除する場合:

```powershell
.\.claude\commands\git\cleanup.ps1 -Delete LocalAndRemote
```

削除後は結果を報告してください。

注意事項:

- `main` と現在のブランチは常に対象外
- 削除は `git branch -d` で行う。マージ済みブランチしか削除されない（`-D` による強制削除は行わない）
- リモートの削除は他の作業者にも影響するため、`LocalAndRemote` を選ぶ場合は必ずユーザーの明示的な同意を得ること。迷う場合は `Local` を選ぶ
- マージ済みの判定は `origin/main` を基準に行う。[merge.md](merge.md) の `/git:merge` は GitHub 上でマージするため、ローカルの `main` は明示的に pull しない限り古いままになり、基準にすると実際にはマージ済みのブランチが漏れる
- `origin/main` は最後に `git fetch` した時点の内容。一覧が実態より少ないと感じた場合は `git fetch origin` を実行してから再度一覧を取ること
- squash merge・rebase merge で取り込まれたブランチは「マージ済み」と判定されず一覧に出ない（`/git:merge` はマージコミット方式のため、通常この運用では問題にならない）
- 一覧に出ないブランチは未マージの可能性がある。`-D` での強制削除は提案せず、ユーザーに状況を報告すること
