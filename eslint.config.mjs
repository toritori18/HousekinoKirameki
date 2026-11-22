// ESLint 設定（flat config）
// Next.js 16 では `next lint` が削除されたため、ESLint CLI（npm run lint）で実行する
// 参考: https://nextjs.org/docs/app/api-reference/config/eslint
//
// ESLint は 9 系に固定している。10 系は eslint-config-next 16.3.6 が内包する
// eslint-plugin-react と非互換で、lint 実行時に
// 「TypeError: Error while loading rule 'react/display-name':
//   contextOrFilename.getFilename is not a function」で停止する（本環境で実測）。
// eslint 9 系のインストール時に出る非推奨の警告は、この互換性の問題が解消されるまで許容する。
import { defineConfig, globalIgnores } from 'eslint/config'
import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTypeScript from 'eslint-config-next/typescript'
import prettier from 'eslint-config-prettier/flat'

const eslintConfig = defineConfig([
  ...nextVitals,
  // typescript-eslint の recommended を取り込む。@typescript-eslint/no-explicit-any（any 禁止）は
  // ここに含まれる（eslint-config-next 16.3.6 の dist/typescript.js を確認）
  ...nextTypeScript,
  // 整形に関するルールは Prettier に任せる。競合するルールを無効化するため最後に置く
  prettier,
  {
    // docs/TS-contributing.md の規約を機械的に強制する
    rules: {
      // console.log を本番コードに残すことの禁止（warn/error は許可）
      'no-console': ['error', { allow: ['warn', 'error'] }],
      // if/for などのブロックは 1 行でも {} 必須
      curly: ['error', 'all'],
    },
  },
  globalIgnores([
    // eslint-config-next のデフォルト除外
    '.next/**',
    'out/**',
    'build/**',
  ]),
])

export default eslintConfig
