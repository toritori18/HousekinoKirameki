以下のコマンドを実行して開発サーバーを起動してください。

```powershell
.\.claude\commands\server\start.ps1
```

起動コマンドと待ち受けポートは `.claude/project.json` の `devServer` に定義されています。
スクリプトは、同じポートで動いている既存プロセスを停止し、ポートの解放を待ってからバックグラウンドで起動します（ログ: `logs/dev-server.log`、標準エラー出力: `logs/dev-server.err.log`）。

`devServer.command` が未設定の構成（開発サーバーを持たないスタック）では、何もせずその旨を表示します。
