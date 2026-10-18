# 作業の引き継ぎメモ

作業を数日にまたいで続けるときのために、`/compact` の代わりに「作業ごとのメモをファイルへ書き出し → `/clear` → 次のセッションで読み込む」流れを用意している。`/compact` は要約後にファイルやスキルを読み込み直すため縮みにくい。メモは `.claude/handoff/` に置き、`.gitignore` 対象（git で管理しない）。

## 流れ

1. 作業を中断・終了するとき、`/wrap` と打つ。「今日はここまで」「続きは明日」などと言えば Claude が `wrap` スキルを自動で呼ぶこともある。メモが `.claude/handoff/<作業名>.md` に書かれる
2. Claude が「/clear で区切れます」と伝えたら、**ユーザーが手で `/clear` を打つ**（フックからは `/clear` を実行できない）
3. 新しいセッションの開始時（startup / clear / compact）に、`handoff-list.ps1`（SessionStart フック）がメモの一覧（作業名 / 次の一手 / 更新日 / パス）を Claude に渡す。依頼が一覧の作業の続きなら、Claude が該当メモを読んでから着手する
4. 作業が完了したら `/wrap done`。メモが `.claude/handoff/archive/` へ移り、一覧に出なくなる

## メモの書式

3項目だけを残す。一覧表示がこの書式の先頭3行を読むため、書式は変えない。

```
# <作業名>
次の一手: <1行>
更新: YYYY-MM-DD

## 目的
## 未完了と次の一手
## 決定事項と理由
```

## 話題の切り替え検知（jev を使う部分）

`handoff-prompt.ps1`（UserPromptSubmit フック）が、プロンプトの送信ごとに [jev](jev.md) へ次の2つを問う。注入するのは**提案だけ**で、プロンプトを止めることはない（`enforce` でも `shadow` と同じ扱い）。

| 機能 | 問い | 結果 |
|---|---|---|
| `handoffSelect` | 最初の依頼が、どのメモの続きか | 該当するメモの全文を Claude に渡す |
| `topicShift` | 新しい依頼が、基準の作業とは無関係な別の作業か（基準は読み込み中メモの「目的」、無ければ最初の依頼） | wrap でメモを書き出し、`/clear` で区切ることを Claude がユーザーに提案する。ユーザーが同じ作業の続きだと答えれば、そのまま続ける |

- しきい値・タイムアウトは `.claude/jev/config.json` の `features.handoffSelect` / `features.topicShift`。**値は出典の無い暫定値**（[jev.md](jev.md) の「設定」参照）
- セッションごとの状態（最初の依頼の抜粋・読み込み中のメモ）は `.claude/handoff/.state/<session_id>.json` に保存する。SessionStart で初期化される
- スラッシュコマンド（`/` で始まるプロンプト）では何もしない
- スケジュールタスクやバックグラウンドのサブエージェントの報告でも UserPromptSubmit は発火する。そこで誤検知しても、注入するのは提案だけなので害は小さい

## jev が無い場合

API キー（`TYPESAFE_API_KEY`）が無ければ、`handoff-prompt.ps1` は何も出さずに終了する。`/wrap`、`/wrap done`、SessionStart の一覧表示は jev に関係なく動く。つまり jev が無いと「最初の依頼の自動マッチ」と「話題の切り替え検知」だけが働かず、メモの読み込みは一覧を見た Claude とユーザーの判断になる。

## 関連ファイル

| パス | 役割 |
|---|---|
| `.claude/skills/wrap/SKILL.md` | メモの書き出し |
| `.claude/hooks/handoff-list.ps1` | SessionStart: 一覧の注入、状態の初期化 |
| `.claude/hooks/handoff-prompt.ps1` | UserPromptSubmit: 話題の切り替え検知 |
| `.claude/jev/lib/handoff.ps1` | メモの読み取りなど、2つのフックの共有部品 |
| `.claude/jev/questions/handoff.json` | jev への質問定義 |
