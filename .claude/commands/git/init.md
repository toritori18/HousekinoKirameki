git リポジトリを初期化し、git hooks（pre-push の機密情報チェック）を登録してください。

```powershell
.\.claude\commands\git\init.ps1
```

既に `.git` が存在する場合は初期化をスキップし、hooks の登録のみ行います。
