# 方向性の提案（宝石のきらめき CPU対戦ゲーム）

企画段階で整理した、ゲーム本体の方向性の保存版。
開発支援（どのプロジェクトでも使える jev の部品）は [jev.md](jev.md) を参照する。

## 決まっていること

- 題材: ボードゲーム「宝石のきらめき（Splendor）」を、コンピュータと対戦する形式で作る
- 実行形態: ブラウザで遊ぶ（Next.js + TypeScript。スタックは `nextjs-ts`）
- 対戦人数: 2〜4人（人間1人 + CPU 1〜3体）
- CPU の強さ: 段階的に強くする（Random → Heuristic → Jev →（任意で）MCTS）
- jev はコードを書かない。ゲームでは **CPU の判断の中身**を担当する

## jev について（確認できた範囲）

- 出典: <https://docs.typesafe.ai/api> / <https://docs.typesafe.ai/introduction/quickstart> / <https://docs.typesafe.ai/agent-skill>
- TypeSafe AI 社の、文章を生成しない判断専用のモデル。`noul`（はいの確率）・`choice`（選択肢から選ぶ）・`score`（段階評価）を確率付きで返す
- `POST https://api.typesafe.ai/v1/systemone`、認証は `Authorization: Bearer <API_KEY>`、model は `jev-latest`
- 公式 SDK は Python 版と JavaScript/TypeScript 版がある（GitHub の typesafe-ai 組織）。パッケージ名とバージョンは、導入時に npm レジストリで確認する
- 公式の Agent Skill（`typesafe-ai`）がある。jev を使うコードの設計方法を AI に教える手順書で、CPU を実装するときに coder に使わせる。導入は `claude plugin marketplace add typesafe-ai/skills` → `claude plugin install typesafe@typesafe-ai`

## アーキテクチャ

```
[ブラウザ UI (React)] ──▶ [ゲームエンジン (純TS)] ◀── [CPUプレイヤー interface]
                                                     ├ RandomBot
                                                     ├ HeuristicBot（ルールベース）
                                                     ├ JevBot ──▶ Next.js API Route ──▶ jev API
                                                     └ (将来) MCTSBot
```

- ゲームエンジンは UI から切り離した純粋な TypeScript で書く（`legalActions` / `applyAction`）
- API キーはサーバー側（API Route と環境変数）にだけ置く

## JevBot の設計方針（状況・評価・行動の3段階）

参考: kecy 氏「Jev でポーカーの遊び相手になってくれる AI」（Findy「Jev 使ってみてどうだった？」2026-10-05 の登壇資料）。
合法手を `choice` で直接選ばせる方式は、受け身の手に偏って失敗した。問いを狭く分け、計算と行動の確定はコードが担う方式でルールベース AI と互角になった。

| 段階 | 担当 | 内容の例 |
|---|---|---|
| 計算 | コード | 合法手、各カードを買うまでに足りないトークン数、貴族までの距離、相手が次の手番で買えるカード、点数差 |
| 状況（Situation） | jev `noul` | 「相手 X は特定の色のエンジンを組んでいるか」「相手は次の手番で15点に届きうるか」 |
| 評価（Evaluation） | jev `score` | 候補カードごとに「今の戦略に合うか」（0〜3）、予約する価値（0〜3） |
| 行動（Decision） | jev `noul` → コード | 「今は点数を取りに行くべき局面か」。確率をしきい値と優先順位で行動に変えるのはコード |

- エラーやタイムアウトのときは HeuristicBot の手を使う
- しきい値はコード側の定数として1か所にまとめ、難易度（性格）ごとに変える
- 強さの評価は、Heuristic との総当たり対戦で行う。短い比較だけで優劣を断定しない

## jev の活用先

| 用途 | 内容 | 価値 |
|---|---|---|
| CPU の判断 | 上記の3段階 | 高 |
| 対戦ログの分析 | ボット同士の大量の対局を、悪手かどうか・負けた原因などで分類する | 高 |
| バランス調整 | 難易度ごとの対局を評価する | 中 |
| ヒント・振り返り | 人間におすすめの手を見せる。対局後に疑問手を示す | 中 |

## 開発工程

| 工程 | 内容 | 成果物 |
|---|---|---|
| 0 | 環境準備（`nextjs-ts` スタックの展開、README と技術スタックの記入） | `/check` が成功する状態 |
| 1 | 要件定義（ルールの確定、カードデータを実物と照合、画面・難易度の要件） | `docs/requirements.md` |
| 2 | jev の技術検証（質問の数とレスポンス時間、盤面のテキスト表現） | `docs/jev-spike.md` |
| 3 | 設計（型、エンジンの API、CPU の interface、jev 連携、画面） | `docs/design.md` |
| 4 | 実装（エンジン → 画面 → Heuristic → JevBot → ヒント等） | コードとテスト |
| 5 | テスト・評価（ユニットテスト、ボット総当たりの勝率表、人間による手動プレイ） | 評価レポート |
| 6 | 仕上げ・振り返り（公開範囲の判断、retrospective スキルで振り返り） | 振り返り文書 |

## 注意点

- ゲームの名称とアートは権利物なので、個人利用・学習目的にとどめる。宝石は図形と色で表現する
- カードと貴族のデータは AI の記憶で作らず、実物と照合する
- jev は課金 API（利用回数の上限は設けない方針。利用量はログに記録する）
