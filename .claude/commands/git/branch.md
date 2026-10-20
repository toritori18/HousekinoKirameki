引数で指定したブランチ名で、最新の `origin/main` から新しいブランチを作成してチェックアウトしてください。

現在いるブランチではなく、`git fetch origin main` したうえで `origin/main` を起点にします（マージ済みブランチや古い main から分岐しないため）。upstream は設定されません。未コミットの変更はそのまま新しいブランチへ持っていかれます（`origin/main` との差分と衝突する場合はエラーで止まります）。fetch に失敗したときは手元の `origin/main` で、`origin/main` が無いときは現在の HEAD から作成し、どちらも WARNING を出します。

```powershell
.\.claude\commands\git\branch.ps1 -Name "$ARGUMENTS"
```

ブランチ名は docs/git-rules.md のルールに従ってください:
- 機能追加: `feature/<name>`
- バグ修正: `fix/<name>`
- ドキュメント: `docs/<name>`
