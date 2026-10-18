# jev（TypeSafe AI の判断専用モデル）を呼ぶ共有ライブラリ。
# .claude/jev/ 配下の各スクリプトから dot-source して使う。単体実行しない。
# stdout の文字コード固定（[Console]::OutputEncoding）は呼び出し元が行う
# （docs/powershell-contributing.md の「標準出力の文字コード」参照）。
#
# 最重要の方針: jev を使わないプロジェクトの邪魔をしない。
#   - API キーが無ければ何も送らず、skipped を返すだけで正常に進む
#   - 通信の失敗でも例外を投げず、skipped（理由付き）を返す
#   - API キー・送信本文（state・質問文）はログにも出力にも残さない
#
# API 仕様の出典: https://docs.typesafe.ai/api 、https://docs.typesafe.ai/introduction/quickstart

. (Join-Path $PSScriptRoot '..\..\commands\lib\project-config.ps1')

# このファイルは .claude/jev/lib/ に置かれているため、1階層上が .claude/jev/ になる。
$script:JevDir = Split-Path -Parent $PSScriptRoot

# 接続先の切り替え（OpenRouter 経由）の出典:
#   https://openrouter.ai/docs/guides/community/typesafe-sdk.md
#   https://openrouter.ai/docs/guides/community/jev.md
# - base URL は環境変数 TYPESAFE_BASE_URL で切り替える。OpenRouter は https://openrouter.ai/api で、
#   後ろに /v1/systemone を付けた先へ送る。認証は同じ Authorization: Bearer <キー>（OpenRouter のキーでよい）
# - OpenRouter 向けのモデル ID は、jev-latest → ~typesafe/jev-latest、jev-1.13 → typesafe/jev-1.13 に変換し、
#   typesafe/... のように / を含む ID はそのまま使う（SDK と同じ）
$script:JevDefaultBaseUrl = 'https://api.typesafe.ai'
$script:JevDefaultModel = 'jev-latest'
$script:JevValidModes = @('shadow', 'enforce', 'off')

<#
.SYNOPSIS
    .env.local から指定名の行（NAME=値）の値を返す。無ければ $null。
.DESCRIPTION
    指定名の行だけを読む（他の行は読まない）。値の前後の空白と引用符は除く。空値は $null。
#>
function Get-JevEnvLocalValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $envPath = Join-Path (Get-RepoRoot) '.env.local'
    if (-not (Test-Path -LiteralPath $envPath)) {
        return $null
    }

    try {
        foreach ($line in (Get-Content -LiteralPath $envPath -Encoding UTF8)) {
            if ($line -notmatch ('^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*?)\s*$')) {
                continue
            }
            $value = $Matches[1]
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                $value = $Matches[1]
            }
            $value = $value.Trim()
            if ([string]::IsNullOrWhiteSpace($value)) {
                return $null
            }
            return $value
        }
    }
    catch {
        return $null
    }
    return $null
}

<#
.SYNOPSIS
    jev の API キーを返す。無ければ $null。
.DESCRIPTION
    環境変数 TYPESAFE_API_KEY を優先し、無ければ .env.local の TYPESAFE_API_KEY= の行を読む。
#>
function Get-JevApiKey {
    $fromEnv = $env:TYPESAFE_API_KEY
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        return $fromEnv.Trim()
    }
    return (Get-JevEnvLocalValue -Name 'TYPESAFE_API_KEY')
}

<#
.SYNOPSIS
    接続先の base URL（末尾の / を除いたもの）を返す。
.DESCRIPTION
    優先順位: 環境変数 TYPESAFE_BASE_URL > .env.local の TYPESAFE_BASE_URL= > config.json の baseUrl > 既定。
#>
function Get-JevBaseUrl {
    $candidates = @(
        $env:TYPESAFE_BASE_URL,
        (Get-JevEnvLocalValue -Name 'TYPESAFE_BASE_URL'),
        (Get-ConfigProperty -Object (Get-JevConfig) -Name 'baseUrl')
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return ([string]$candidate).Trim().TrimEnd('/')
        }
    }
    return $script:JevDefaultBaseUrl
}

<#
.SYNOPSIS
    接続先の種類（openrouter / typesafe）を base URL のホスト名から判定する。
#>
function Get-JevProvider {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseUrl
    )

    try {
        $hostName = ([System.Uri]$BaseUrl).Host
        if ($hostName -eq 'openrouter.ai' -or $hostName.EndsWith('.openrouter.ai')) {
            return 'openrouter'
        }
    }
    catch { }
    return 'typesafe'
}

<#
.SYNOPSIS
    送信するモデル ID を返す。config.json の model（既定 jev-latest）を、OpenRouter 向けなら SDK と同じ規則で変換する。
#>
function Get-JevModelId {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseUrl
    )

    $model = Get-ConfigProperty -Object (Get-JevConfig) -Name 'model'
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = $script:JevDefaultModel
    }
    $model = ([string]$model).Trim()
    if ((Get-JevProvider -BaseUrl $BaseUrl) -eq 'openrouter' -and -not $model.Contains('/')) {
        if ($model -eq 'jev-latest') {
            return '~typesafe/jev-latest'
        }
        return "typesafe/$model"
    }
    return $model
}

<#
.SYNOPSIS
    .claude/jev/config.json を読む。無い・壊れている場合は $null。
#>
function Get-JevConfig {
    $path = Join-Path $script:JevDir 'config.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    config.json の features.<Feature>.<Name> を返す。無ければ Default。
#>
function Get-JevFeatureSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Feature,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        $Default = $null
    )

    $config = Get-JevConfig
    $features = Get-ConfigProperty -Object $config -Name 'features'
    $featureConfig = Get-ConfigProperty -Object $features -Name $Feature
    $value = Get-ConfigProperty -Object $featureConfig -Name $Name
    if ($null -eq $value) {
        return $Default
    }
    return $value
}

<#
.SYNOPSIS
    機能ごとの動作モード（shadow / enforce / off）を返す。
.DESCRIPTION
    優先順位: 環境変数 JEV_MODE_<FEATURE大文字> > 環境変数 JEV_MODE > config.json の features.<名前>.mode > shadow。
    不正な値はその段を無視して次の段へ進む。
    shadow = 判定を記録・通知するだけで止めない / enforce = 条件がそろったら止める / off = jev を呼ばない。
#>
function Get-JevMode {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Feature
    )

    $candidates = @(
        [Environment]::GetEnvironmentVariable('JEV_MODE_' + $Feature.ToUpperInvariant()),
        $env:JEV_MODE,
        (Get-JevFeatureSetting -Feature $Feature -Name 'mode')
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $normalized = ([string]$candidate).Trim().ToLowerInvariant()
        if ($script:JevValidModes -contains $normalized) {
            return $normalized
        }
    }
    return 'shadow'
}

<#
.SYNOPSIS
    Invoke-Jev の戻り値オブジェクトを作る。
#>
function New-JevResult {
    param(
        [bool] $Skipped,
        [string] $Reason,
        $Answers = $null,
        $Usage = $null,
        $Model = $null,
        [long] $ElapsedMs = 0
    )

    return [pscustomobject]@{
        Skipped   = $Skipped
        Reason    = $Reason
        Answers   = $Answers
        Usage     = $Usage
        Model     = $Model
        ElapsedMs = $ElapsedMs
    }
}

<#
.SYNOPSIS
    通信の失敗を種別（timeout / http-<コード> / network-error / other）に正規化する。
#>
function Get-JevFailureReason {
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    $status = 0
    try { $status = [int]$exception.Response.StatusCode } catch { $status = 0 }
    if ($status -gt 0) {
        return "http-$status"
    }
    if ($exception -is [System.Net.WebException]) {
        if ($exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
            return 'timeout'
        }
        return 'network-error'
    }
    return 'other'
}

<#
.SYNOPSIS
    値が数値で min〜max の範囲内なら [double] で返す。それ以外は $null（例外は投げない）。
#>
function ConvertTo-JevNumber {
    param(
        [AllowNull()]
        $Value,

        [double] $Min = 0,

        [double] $Max = 1
    )

    if ($Value -is [double] -or $Value -is [single] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or $number -lt $Min -or $number -gt $Max) {
            return $null
        }
        return $number
    }
    return $null
}

<#
.SYNOPSIS
    回答の種類を noul / choice / score のプロパティの有無で判定する。判定できなければ $null。
.DESCRIPTION
    公式例には type プロパティがあるが、type に頼らず頑丈にするためプロパティの有無で判定する。
#>
function Get-JevAnswerKind {
    param(
        [AllowNull()]
        $Answer
    )

    foreach ($kind in @('noul', 'choice', 'score')) {
        if ($null -ne $Answer -and $null -ne $Answer.PSObject.Properties[$kind]) {
            return $kind
        }
    }
    return $null
}

<#
.SYNOPSIS
    noul 回答の確率（0〜1）を返す。無い・数値でない・範囲外なら $null。
#>
function Get-JevNoulValue {
    param(
        [Parameter(Mandatory = $true)]
        $Answers,

        [Parameter(Mandatory = $true)]
        [string] $Id
    )

    $answer = Get-ConfigProperty -Object $Answers -Name $Id
    if ((Get-JevAnswerKind -Answer $answer) -ne 'noul') {
        return $null
    }
    return (ConvertTo-JevNumber -Value $answer.noul -Min 0 -Max 1)
}

<#
.SYNOPSIS
    choice 回答の選択肢と confidence（0〜1）を [pscustomobject]@{ Choice; Confidence } で返す。不正なら $null。
#>
function Get-JevChoiceValue {
    param(
        [Parameter(Mandatory = $true)]
        $Answers,

        [Parameter(Mandatory = $true)]
        [string] $Id
    )

    $answer = Get-ConfigProperty -Object $Answers -Name $Id
    if ((Get-JevAnswerKind -Answer $answer) -ne 'choice') {
        return $null
    }
    $choice = $answer.choice
    $confidence = ConvertTo-JevNumber -Value (Get-ConfigProperty -Object $answer -Name 'confidence') -Min 0 -Max 1
    if (($choice -isnot [string]) -or [string]::IsNullOrWhiteSpace($choice) -or $null -eq $confidence) {
        return $null
    }
    return [pscustomobject]@{ Choice = $choice; Confidence = $confidence }
}

<#
.SYNOPSIS
    score 回答の値（0〜Max）を返す。無い・数値でない・範囲外なら $null。
#>
function Get-JevScoreValue {
    param(
        [Parameter(Mandatory = $true)]
        $Answers,

        [Parameter(Mandatory = $true)]
        [string] $Id,

        [double] $Max = 3
    )

    $answer = Get-ConfigProperty -Object $Answers -Name $Id
    if ((Get-JevAnswerKind -Answer $answer) -ne 'score') {
        return $null
    }
    return (ConvertTo-JevNumber -Value $answer.score -Min 0 -Max $Max)
}

<#
.SYNOPSIS
    jev に質問を送り、回答を返す。例外は投げない。
.DESCRIPTION
    キーが無い（Reason = 'no-key'）・モードが off（Reason = 'off'）のときは通信せず Skipped = $true を返す。
    通信やレスポンス解釈に失敗した場合も Skipped = $true と理由を返す。
    -Feature はモード解決とログ用のラベルで、API には送られない。複数機能を1リクエストにまとめる場合は
    'tests+commitType' のような連結ラベルでよい。
    -Mode は、呼び出し側でモードを解決済みの場合（複数機能を1リクエストにまとめるとき）に指定する。
    省略時は Get-JevMode -Feature で解決する。

    モデル名 jev-latest・Bearer 認証・エンドポイント・質問の形（choice の criteria はオブジェクト、
    score の criteria は配列、noul は criteria なし）の出典: https://docs.typesafe.ai/introduction/quickstart

    本文を UTF-8 のバイト配列にして ContentType に charset=utf-8 を付けるのは、5.1 では文字列のまま渡すと
    日本語が文字化けするという呼び出し元の指示に基づく（出典なし。この点の文字化けは当方では未実測）。
    なお、バイト配列で送った日本語がローカルの受信側で正しく復元されることは実測で確認している。
    TLS 1.2 を明示的に有効にするのは、5.1 の既定が古いプロトコルの場合に備えた予防措置（出典なし・未実測）。
#>
function Invoke-Jev {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Feature,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $State,

        [Parameter(Mandatory = $true)]
        $Questions,

        [string] $Mode,

        # 通信のタイムアウト（秒）。0 以下なら config.json の timeoutSec（無ければ 10）を使う。
        # プロンプト送信のたびに走るフックなど、短く待たせたい呼び出し元だけが指定する（既存の呼び出し元は影響を受けない）
        [int] $TimeoutSec = 0
    )

    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $Mode = Get-JevMode -Feature $Feature
    }
    if ($Mode -eq 'off') {
        return (New-JevResult -Skipped $true -Reason 'off')
    }

    $apiKey = Get-JevApiKey
    if ($null -eq $apiKey) {
        return (New-JevResult -Skipped $true -Reason 'no-key')
    }

    if ($TimeoutSec -gt 0) {
        $timeoutSec = $TimeoutSec
    }
    else {
        $timeoutSec = Get-ConfigProperty -Object (Get-JevConfig) -Name 'timeoutSec'
        if ($null -eq $timeoutSec -or [int]$timeoutSec -le 0) {
            $timeoutSec = 10
        }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $baseUrl = Get-JevBaseUrl
        $body = [ordered]@{
            model     = Get-JevModelId -BaseUrl $baseUrl
            state     = $State
            questions = $Questions
        }
        $json = $body | ConvertTo-Json -Depth 20 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $response = Invoke-RestMethod -Uri ($baseUrl + '/v1/systemone') -Method Post `
            -Headers @{ Authorization = "Bearer $apiKey" } `
            -ContentType 'application/json; charset=utf-8' `
            -Body $bytes -TimeoutSec ([int]$timeoutSec)
    }
    catch {
        $stopwatch.Stop()
        # 生の例外メッセージは画面にもログにも出さず、種別だけに正規化する
        $reason = Get-JevFailureReason -ErrorRecord $_
        return (New-JevResult -Skipped $true -Reason $reason -ElapsedMs $stopwatch.ElapsedMilliseconds)
    }
    $stopwatch.Stop()

    $answers = Get-ConfigProperty -Object $response -Name 'answers'
    if ($null -eq $answers) {
        return (New-JevResult -Skipped $true -Reason 'invalid-response' -ElapsedMs $stopwatch.ElapsedMilliseconds)
    }

    return (New-JevResult -Skipped $false -Reason '' `
            -Answers $answers `
            -Usage (Get-ConfigProperty -Object $response -Name 'usage') `
            -Model (Get-ConfigProperty -Object $response -Name 'model') `
            -ElapsedMs $stopwatch.ElapsedMilliseconds)
}

<#
.SYNOPSIS
    jev の呼び出し結果を .claude/jev/logs/YYYY-MM-DD.jsonl に1行追記する。
.DESCRIPTION
    記録するのは日時・機能・モード・skipped と理由・モデル・usage・各回答の値と確率・所要時間・最終判定のみ。
    state と質問本文は記録しない。キー無し・off による skipped は記録しない（使わないプロジェクトにログを残さない）。
    書き込みに失敗しても呼び出し元の処理を止めない。

    -AnswerIds で、このログ行に含める質問 ID を絞れる（複数機能を1リクエストにまとめた場合に使う）。
#>
function Write-JevLog {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Feature,

        [Parameter(Mandatory = $true)]
        [string] $Mode,

        [Parameter(Mandatory = $true)]
        $Result,

        # 最終判定（例: pass / flagged-shadow / flagged-stop / skipped）
        [Parameter(Mandatory = $true)]
        [string] $Decision,

        [string[]] $AnswerIds
    )

    try {
        if ($Result.Skipped -and ($Result.Reason -eq 'no-key' -or $Result.Reason -eq 'off')) {
            return
        }

        $answerLog = [ordered]@{}
        if (-not $Result.Skipped) {
            foreach ($property in $Result.Answers.PSObject.Properties) {
                if ($null -ne $AnswerIds -and $AnswerIds.Count -gt 0 -and $AnswerIds -notcontains $property.Name) {
                    continue
                }
                $answer = $property.Value
                # 種類は type ではなくプロパティの有無で判定する（Get-JevAnswerKind）
                $kind = Get-JevAnswerKind -Answer $answer
                $entry = [ordered]@{ type = $kind }
                if ($null -ne $kind) {
                    $entry['value'] = Get-ConfigProperty -Object $answer -Name $kind
                }
                # probabilities / confidence は存在するときだけ記録する
                if ($null -ne $answer -and $null -ne $answer.PSObject.Properties['probabilities']) {
                    $entry['probabilities'] = $answer.probabilities
                }
                if ($null -ne $answer -and $null -ne $answer.PSObject.Properties['confidence']) {
                    $entry['confidence'] = $answer.confidence
                }
                $answerLog[$property.Name] = $entry
            }
        }

        $record = [ordered]@{
            time      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
            feature   = $Feature
            mode      = $Mode
            skipped   = $Result.Skipped
            reason    = $Result.Reason
            provider  = Get-JevProvider -BaseUrl (Get-JevBaseUrl)
            model     = $Result.Model
            usage     = $Result.Usage
            cost      = Get-ConfigProperty -Object $Result.Usage -Name 'cost'
            answers   = $answerLog
            elapsedMs = $Result.ElapsedMs
            decision  = $Decision
        }
        $line = $record | ConvertTo-Json -Depth 10 -Compress

        $logDir = Join-Path $script:JevDir 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
        # 5.1 の Add-Content -Encoding UTF8 は新規ファイルの先頭に BOM を付けるとされるため、BOM なしで追記する
        # （出典なし・当方では未実測。BOM なしで書くこと自体は害がないので採用している）
        [System.IO.File]::AppendAllText($logPath, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        # ログの失敗で本処理を止めない
    }
}

<#
.SYNOPSIS
    .claude/jev/questions/<Name>.json を読み、PSCustomObject で返す。
.DESCRIPTION
    質問文はコードと分けて JSON に置く（人がレビューしやすくするため）。
    ファイルが無い・JSON として壊れている場合は $null を返す（呼び出し側はその機能だけ静かにスキップする）。
#>
function Get-JevQuestionDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $path = Join-Path $script:JevDir "questions\$Name.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}
