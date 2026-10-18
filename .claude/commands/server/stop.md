以下のコマンドを実行して開発サーバーを停止してください。

```powershell
.\.claude\commands\server\stop.ps1
```

停止対象は `.claude/project.json` の `devServer.port` で待ち受けているプロセスです。
`devServer.port` が未設定の構成では、停止するプロセスを特定できないため何もせずその旨を表示します。
