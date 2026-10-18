# コントリビュートガイド（TypeScript）

対象は `.ts` / `.tsx` / `.mjs` / `.css`。`.claude/` 配下の `.ps1` は [powershell-contributing.md](powershell-contributing.md) を参照。

## 開発フロー

1. `main` ブランチから feature ブランチを作成する（/git:branch）
2. 変更を実装する
3. /check を通してからプルリクエストを作成する（/git:pr）

詳細は [git-rules.md](git-rules.md) を参照。

## コーディング規約

### 言語・型

- アプリケーションのロジックは TypeScript（`.ts` / `.tsx`）で書く。`.mjs` はビルドツールの設定ファイルに限る
- `any` 型は使用禁止。不明な型は `unknown` を使い、型ガードで絞り込む
- `tsconfig.json` の `strict: true` と、ESLint の `@typescript-eslint/no-explicit-any` により自動チェックされる

### ファイル・命名

- コンポーネントファイル・クラスは PascalCase（例: `GameCard.tsx`）
- 関数・変数・型フィールドは camelCase（例: `shortDescription`）
- インポートパスは `@/` エイリアスを使用し、相対パス（`../../`）は使わない（`tsconfig.json` の `paths` で定義）

### ディレクトリ

| パス | 役割 |
|---|---|
| `src/pages/` | ページコンポーネント |
| `src/components/` | 再利用可能なUIコンポーネント |
| `src/types/` | 型定義（`named export` で公開） |
| `src/utils/` | ユーティリティ関数 |
| `src/data/` | 静的データ（JSON等） |
| `src/styles/` | スタイルシート |
| `docs/sql/` | SQLファイル（マイグレーション・初期データ等） |

### コンポーネント

- ページ・コンポーネントは `default export`
- 型・定数は `named export`

### スタイル

スタイリングの方針（CSS フレームワークを使うか、CSS Modules を使うか等）はプロジェクトごとに決め、**決めた内容をこの節に追記すること**。方針が書かれていない状態で新しいスタイルの書き方を持ち込まない。

### コメント

- コメントは日本語で書く
- 自明な処理にコメントは書かない。「なぜそうしているか」が非自明な場合のみ書く
- 関数・クラス・型には JSDoc コメントを記載する（`@param`、`@returns`、`@throws` を含む）
- `if` / `for` などの分岐・ループには `//` でその意図を説明するコメントを記載する

例：
```ts
/**
 * ユーザーの認証トークンを検証する
 * @param token - JWT トークン文字列
 * @returns トークンが有効な場合は true
 * @throws TokenExpiredError - トークンの有効期限切れ
 */
function validateToken(token: string): boolean {
  // 有効期限が切れていないかチェック
  if (token.expiresAt < now) {
    throw new TokenExpiredError();
  }
  return true;
}
```

### ブロック

- `if` / `for` などのブロックは、1行であっても必ず `{}` で囲む（省略しない）。ESLint の `curly` ルールで強制される

例：
```ts
// ✅ 良い
if (isValid) {
  return true;
}

// ❌ 悪い
if (isValid) return true;
```

### 設定ファイル（`.mjs`）

- ES Modules（`export default`）で書く
- 型補完のため、JSDoc の型注釈を付ける（例: `/** @type {import('next').NextConfig} */`）
- アプリケーションのロジックを設定ファイルに書かない

### テスト

- テストフレームワークは Vitest を使用する
- テストファイルは `*.test.ts(x)` / `*.spec.ts(x)` 形式で配置する
- テストファイルが1つもない場合も /test は正常終了する（`--passWithNoTests`）

## 禁止事項

- 存在しない npm パッケージ・API・メソッドの使用（実装前に [.claude/factcheck.md](../.claude/factcheck.md) のチェックリストに従い実在確認する）
- `any` 型の使用（ESLint により `error` として検出される）
- `console.log` を本番コードに残すこと（ESLint により `error` として検出される）
  - `console.warn` / `console.error` は許可する。意図して残す障害ログは対象外であり、デバッグ目的の出力を消し忘れないことが `no-console` の狙いであるため
- APIキー・シークレットのコードへの直書き（必ず `.env.local` 経由で参照する）
- `.env.local` の git へのコミット

## プルリクエストのルール

- タイトルはコミットメッセージ規約に従う（[git-rules.md](git-rules.md) 参照）
- CI がすべて通過していること
