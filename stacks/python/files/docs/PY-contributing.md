# コントリビュートガイド（Python）

対象は `.py`。`.claude/` 配下の `.ps1` は [powershell-contributing.md](powershell-contributing.md) を参照。

## 開発フロー

1. `main` ブランチから feature ブランチを作成する（/git:branch）
2. 変更を実装する
3. /check を通してからプルリクエストを作成する（/git:pr）

詳細は [git-rules.md](git-rules.md) を参照。

## 仮想環境

依存パッケージはプロジェクトごとの仮想環境に入れる。/setup を実行する前に作成・有効化しておくこと。

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

`.venv/` は `.gitignore` で除外されている。

## コーディング規約

命名・書式は PEP 8 に従う。書式は `ruff format`（/format）で整形し、違反は `ruff check`（/lint）で検出する。

### 命名

| 対象 | 形式 | 例 |
|---|---|---|
| モジュール・パッケージ | snake_case | `game_loader.py` |
| 関数・変数・引数 | snake_case | `load_game_list` |
| クラス | PascalCase | `GameLoader` |
| 定数 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| 非公開（モジュール内部） | 先頭にアンダースコア | `_parse_row` |

### 型ヒント

- 公開する関数・メソッドには**必ず型ヒントを付ける**（引数と戻り値の両方）
- 型検査は mypy の `strict` で行う（`pyproject.toml` の `[tool.mypy]`）
- `Any` は使用禁止。型が定まらない場合は `object` を使い、`isinstance` で絞り込む

### ディレクトリ

| パス | 役割 |
|---|---|
| `src/` | アプリケーションのコード |
| `tests/` | テストコード |
| `docs/sql/` | SQLファイル（マイグレーション・初期データ等） |

### コメント・docstring

- コメント・docstring は日本語で書く
- 自明な処理にコメントは書かない。「なぜそうしているか」が非自明な場合のみ書く
- 公開する関数・クラスには docstring を書く（引数・戻り値・送出する例外を含める）

例：
```python
def validate_token(token: str) -> bool:
    """ユーザーの認証トークンを検証する。

    Args:
        token: JWT トークン文字列

    Returns:
        トークンが有効な場合は True

    Raises:
        TokenExpiredError: トークンの有効期限が切れている場合
    """
    # 有効期限が切れていないかチェック
    if token.expires_at < now:
        raise TokenExpiredError
    return True
```

### 例外処理

- 例外を握りつぶさない。`except:` や `except Exception: pass` は書かない
- 捕捉する例外は具体的な型を指定する

### テスト

- テストフレームワークは pytest を使用する
- テストファイルは `tests/test_*.py` に置く（`pyproject.toml` の `testpaths` で `tests` を指定）
- テスト関数名は `test_` で始める

## 禁止事項

- 存在しないパッケージ・API・メソッドの使用（実装前に [.claude/factcheck.md](../.claude/factcheck.md) のチェックリストに従い、PyPI と公式ドキュメントで実在確認する）
- `Any` 型の使用
- デバッグ用の `print` を本番コードに残すこと（ログ出力が必要な場合は `logging` を使う）
- APIキー・シークレットのコードへの直書き（必ず `.env.local` 経由で参照する）
- `.env.local` の git へのコミット
- ミュータブルなデフォルト引数（`def f(items: list = [])` のような書き方）

## プルリクエストのルール

- タイトルはコミットメッセージ規約に従う（[git-rules.md](git-rules.md) 参照）
- CI がすべて通過していること
