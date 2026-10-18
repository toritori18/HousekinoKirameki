# Stop フック: ソースコードの未コミット変更が一定数を超えたら CLAUDE.md の最新化を促す
# ノイズ防止のため、(1) 変更が5ファイル未満なら通知しない (2) 前回通知時と同じ変更セットなら再通知しない

# Claude Code は出力を UTF-8 として読むため、stdout を UTF-8 に固定する（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# git リポジトリでなければ何もしない（/setup 前の状態）
if (-not (Test-Path ".git")) {
    exit 0
}

$lines = git status --porcelain 2>$null
$codeFiles = @($lines | Where-Object { $_ -match '\.(ts|tsx|js|jsx)$' })

# 変更が少ないうちは通知しない（作業中は常に未コミット変更があるため）
if ($codeFiles.Count -lt 5) {
    exit 0
}

# 前回通知時と変更セットが同じなら再通知しない
$cacheFile = ".claude/.stop-check-cache"
$current = ($codeFiles | Sort-Object) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($current)))
if ((Test-Path $cacheFile) -and ((Get-Content $cacheFile -Raw).Trim() -eq $hash)) {
    exit 0
}
Set-Content -Path $cacheFile -Value $hash -Encoding Ascii

@{
    systemMessage = "ソースコードに多数の未コミット変更があります（$($codeFiles.Count) ファイル）。区切りの良いタイミングで /init を実行して CLAUDE.md を最新化してください。"
} | ConvertTo-Json -Compress
