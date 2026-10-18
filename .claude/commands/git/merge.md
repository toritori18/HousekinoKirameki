Pull Request を main にマージしてください。

手順:

1. 対象の PR 番号を確認する（引数で指定されていればそれを使う。未指定なら現在のブランチに対応する PR を検索する）:

```powershell
gh pr view "$ARGUMENTS" --json number,state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision
```

2. 以下をすべて満たすことを確認する。満たさない場合はマージを中止し、状況をユーザーに報告する:
   - `state` が `OPEN` であること
   - `mergeable` が `MERGEABLE` であること
   - `statusCheckRollup` の CI が全て成功していること（`IN_PROGRESS` の場合は完了を待つ。`FAILURE` があれば中止。CI が未設定の場合は空になるため、その場合はこの条件をスキップする）
   - `mergeStateStatus` が `CLEAN` であること

3. 条件を満たしたらマージを実行する（マージコミット方式。ブランチは削除しない）:

```powershell
gh pr merge "$ARGUMENTS" --merge --delete-branch=false
```

4. マージ結果を確認し、ユーザーに報告する:

```powershell
gh pr view "$ARGUMENTS" --json state,mergedAt,mergeCommit
```

注意事項:

- CI が失敗している場合は絶対にマージしない
- レビュー必須設定がある場合（`reviewDecision` が `REVIEW_REQUIRED` 等）は承認状況も確認する
- ブランチ削除は行わない（`--delete-branch=false`）。削除が必要な場合はユーザーに確認してから別途行う
- `gh` CLI が未インストールの場合は https://cli.github.com/ からのインストールを案内する
