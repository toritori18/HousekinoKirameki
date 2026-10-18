# jev による開発支援

jev は TypeSafe AI の判断専用モデルで、文章を生成せず、型付きの判断（noul = はい/いいえの確率、choice = 選択肢、score = 段階評価）を確率付きで返す API である。開発中の「意味の判断」を、コードの外で安く速く行わせるために使う。

API 仕様の出典: <https://docs.typesafe.ai/api> 、<https://docs.typesafe.ai/introduction/quickstart>

## 方針

- **jev を使わないプロジェクトの邪魔をしない。** API キーが無ければ何も送らず、正常終了する。表示は機能によって異なる
  - コミット時の判定: 何も表示しない
  - 資料選び: 「jev をスキップしました。資料は自分で選んでください」を1行表示する（結果が空では、使えないのか該当なしなのか区別できないため）
- **コードの条件 AND jev の判定がそろったときだけ指摘する。** jev 単独では止めない
- **最初は記録だけ（shadow）。** 精度をログで確認してから enforce に切り替える
- API キーと送信本文（資料の抜粋・差分・コミットメッセージ・応答本文（末尾 8000 文字））は、ログにも画面にも残さない

## 有効化

`.env.local` に次の行を追記する（`.env.example` にも同じ行がコメントで載っている）。環境変数 `TYPESAFE_API_KEY` が設定されていればそちらを優先する。

```
TYPESAFE_API_KEY=（取得したキー）
```

キーが無い間、以下の機能はすべて無効（スキップ）になる。

## 機能

| 機能 | 実体 | 内容 |
|---|---|---|
| テスト追加漏れ（tests） | `.claude/jev/check-commit.ps1`（/git:push から呼ばれる） | ソースが変わりテストが変わっていないコミットで、「この変更はプログラムの挙動を変えるか」を問う |
| コミットの種類（commitType） | 同上 | メッセージ先頭の `feat:` 等が、変更内容と合っているかを問う |
| 資料選び（selectDocs） | `.claude/jev/select-docs.ps1`、スキル `jev-select-docs` | 作業内容に関係する資料を `docs/` と README.md から選ぶ |
| 出典の有無（sources） | Stop フック（`.claude/hooks/stop-check-sources.ps1`）、質問定義 `questions/sources.json` | ソースの未コミット変更があるとき、応答が実装報告であり（`isImplementation`）かつ出典または「出典なし」が含まれていない（`hasSources`）場合だけ指摘する。ソースの判定は project.json の `testing.sourcePatterns`、無ければ `contributing` の拡張子（`.md` / `.ps1` の変更は対象外）で行い、どちらも無ければ判定しない。`stop_hook_active` が true のとき・変更集合が前回判定時と同じとき・判定に失敗したときは何もしない。enforce は `decision: block`、shadow はログに記録するだけで何も返さない。フックの登録は `.claude/settings.json` |

### テスト追加漏れ

次の両方がそろったときだけ jev に問う。

1. ステージ済みファイルのうち `testing.sourcePatterns` に一致するものがあり、`testing.testPatterns` に一致するものが1つも無い（[project-config.md](project-config.md) 参照。project.json か `testing` キーが無ければこの判定は行わない）
2. jev が「挙動を変える」と答えた確率がしきい値以上

### コミットの種類

メッセージ先頭が `feat|fix|refactor|docs|chore:` のときだけ問う（それ以外はスキップ）。jev の選んだ種類がメッセージと違い、かつ confidence がしきい値以上のときに指摘する。種類の定義は [git-rules.md](git-rules.md) の「コミットメッセージ規約」の表と同じ。

### 2つが同時に該当するとき

テスト追加漏れとコミットの種類は1リクエストにまとめて問う。それぞれのモードは個別に解決する。

## モード

コミット時（tests / commitType）:

| モード | 動作 |
|---|---|
| `shadow` | 判定を記録し、指摘に該当するときだけ `WARNING:` で1行通知する。コミットは止めない（既定） |
| `enforce` | 指摘に該当するとコミットせずに終了する（終了コード 2。ステージはそのまま残る） |
| `off` | jev を呼ばない |

Stop フック（sources）:

| モード | 動作 |
|---|---|
| `shadow` | ログに記録するだけ（画面にも Claude にも何も返さない）。結果は `.claude/jev/logs/` で確認する（既定） |
| `enforce` | 指摘に該当すると `decision: block` で応答を差し戻す |
| `off` | jev を呼ばない |

shadow で `additionalContext` を返さないのは、Stop フックがそれを返すと会話が継続し、Claude がもう1ターン動いて利用料がかかるため。

Stop フックには `-SkipJev` が無い。回避するには `JEV_MODE_SOURCES=off` を設定する。

優先順位（上が優先）:

1. 環境変数 `JEV_MODE_<機能名の大文字>`（例: `JEV_MODE_TESTS`、`JEV_MODE_COMMITTYPE`、`JEV_MODE_SELECTDOCS`、`JEV_MODE_SOURCES`）
2. 環境変数 `JEV_MODE`
3. `.claude/jev/config.json` の `features.<機能名>.mode`
4. `shadow`

enforce で止まったときは、指摘に沿って直して再実行するか、`.claude/commands/git/push.ps1` に `-SkipJev` を付けて判定なしで続行する。

## 設定（.claude/jev/config.json）

| キー | 意味 | 初期値 |
|---|---|---|
| `timeoutSec` | 通信のタイムアウト（秒） | 10 |
| `features.tests.threshold` | 「挙動を変える」確率がこの値以上で指摘 | 0.7 |
| `features.commitType.threshold` | 種類が違う判定の confidence がこの値以上で指摘 | 0.8 |
| `features.sources.threshold` | 「出典が含まれる」確率がこの値未満で指摘（Stop フック）。応答は末尾 8000 文字だけを送る（出典なしの暫定値） | 0.2 |
| `features.sources.implementationThreshold` | 「応答が実装報告である」確率がこの値以上のときだけ sources を指摘する（出典なしの暫定値） | 0.5 |
| `features.selectDocs.top` | 出力する資料の最大件数 | 3 |
| `features.selectDocs.minScore` | 出力する資料の最低スコア | 1 |
| `features.selectDocs.maxCandidates`（省略可） | 一度に採点する候補資料の上限（0 以下は既定値に戻す） | 40 |

**しきい値（0.7 / 0.8 / 0.2）と候補数の上限（40）、抜粋の長さ（400 文字）、差分の行数（200 行）は出典の無い暫定値である。** JSON にはコメントを書けないため、ここに明記する。shadow のログ（下記）で実際の確率の分布を見て調整すること。

質問文は `.claude/jev/questions/*.json` にコードと分けて置いてある。質問 ID はモデルに送られないため、質問の意味は instructions に完全に書く必要がある。質問文も暫定であり、ログを見て改善する前提である。

## 記録（ログ）

呼び出しごとに `.claude/jev/logs/YYYY-MM-DD.jsonl` へ1行の JSON を追記する（`.gitignore` 対象）。日時・機能・モード・skipped と理由・モデル・usage・各回答の値と確率・所要ミリ秒・最終判定を記録し、state と質問本文は記録しない。キー無し・off によるスキップは記録しない。書き込みに失敗しても本処理は止まらない。

最終判定の値: `pass`（指摘なし）、`flagged-shadow`（shadow で通知）、`flagged-stop`（enforce で停止）、`skipped`（通信失敗など）、`no-answer`（回答が想定の形でなかった）、`listed:N`（資料選びで N 件を出力）。

## 共通部品

`.claude/jev/lib/jev-client.ps1`（dot-source 用。単体実行しない）が次の関数を提供する。別の用途（Stop フック等）から使うときもこの部品を経由する。

| 関数 | 役割 |
|---|---|
| `Get-JevApiKey` | API キーの取得（環境変数、無ければ `.env.local`） |
| `Get-JevConfig` / `Get-JevFeatureSetting` | `config.json` の読み込み / 機能ごとの設定値の取得 |
| `Get-JevMode` | 機能ごとのモード解決 |
| `Invoke-Jev` | jev への問い合わせ。例外を投げず、失敗時は `Skipped = $true` と理由を返す。`-Feature` はモード解決とログ用のラベルで API には送られない |
| `New-JevResult` | `Invoke-Jev` の戻り値の生成 |
| `Get-JevFailureReason` | 通信失敗を `timeout` / `http-<コード>` / `network-error` / `other` に正規化する（生の例外メッセージは出さない） |
| `Get-JevAnswerKind` | 回答の種類を `noul` / `choice` / `score` のプロパティの有無で判定する |
| `ConvertTo-JevNumber` | 数値かつ範囲内の値だけを数値として返す |
| `Get-JevNoulValue` / `Get-JevChoiceValue` / `Get-JevScoreValue` | 回答の値を検証して取り出す。不正なら `$null`（呼び出し側は no-answer 扱い） |
| `Write-JevLog` | 呼び出しログの追記 |
| `Get-JevQuestionDefinition` | `questions/*.json` の読み込み。読めなければ `$null`（その機能だけ静かにスキップ） |
