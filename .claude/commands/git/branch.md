引数で指定したブランチ名で新しいブランチを作成してチェックアウトしてください。

```powershell
.\.claude\commands\git\branch.ps1 -name "$ARGUMENTS"
```

ブランチ名は docs/git-rules.md のルールに従ってください:
- 機能追加: `feature/<name>`
- バグ修正: `fix/<name>`
- ドキュメント: `docs/<name>`
