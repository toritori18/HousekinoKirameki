現在のブランチから main への Pull Request を作成してください。

手順:

1. 現在のブランチを確認する。`main` の場合は中止し、`/git:branch` で作業ブランチを作成するよう案内する
2. 未コミット・未プッシュの変更がある場合は、先に `/git:push` を実行するよう案内する
3. コミット履歴からタイトルと本文を組み立てる:

```powershell
git log main..HEAD --oneline
```

4. PR を作成する:

```powershell
gh pr create --base main --title "<タイトル>" --body "<本文>"
```

注意事項:

- タイトルはブランチの主目的を1行で要約する（コミットメッセージ規約のプレフィックスを付ける）
- 本文には変更内容の箇条書きと動作確認方法を含める
- `gh` CLI が未インストールの場合は https://cli.github.com/ からのインストールを案内する
