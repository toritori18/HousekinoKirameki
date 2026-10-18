# コントリビュートガイド（C# / .NET）

対象は `.cs` / `.csproj`。`.claude/` 配下の `.ps1` は [powershell-contributing.md](powershell-contributing.md) を参照。

## 開発フロー

1. `main` ブランチから feature ブランチを作成する（/git:branch）
2. 変更を実装する
3. /check を通してからプルリクエストを作成する（/git:pr）

詳細は [git-rules.md](git-rules.md) を参照。

## プロジェクトの作成

このひな形にはソリューション・プロジェクトファイルを含めていない（構成がアプリの種類によって変わるため）。/setup の後に `dotnet new` で作成すること。

```powershell
dotnet new sln -n <ソリューション名>
dotnet new console -o src/<プロジェクト名>
dotnet new xunit -o tests/<プロジェクト名>.Tests
dotnet sln add src/<プロジェクト名> tests/<プロジェクト名>.Tests
dotnet restore
```

作成したプロジェクトの種類（コンソール / Web API / クラスライブラリ等）と対象フレームワークは [tech-stack.md](tech-stack.md) に記載すること。

Web アプリケーションの場合は、`.claude/project.json` の `devServer` に起動コマンド（`dotnet watch run --project src/<プロジェクト名>` 等）と待ち受けポートを設定すると /server:start が使えるようになる。

## コーディング規約

書式は `dotnet format`（/format）で整形し、違反は `dotnet format --verify-no-changes`（/lint）で検出する。書式のルールは `.editorconfig` を正とする。

### 命名

| 対象 | 形式 | 例 |
|---|---|---|
| クラス・構造体・列挙型・メソッド・プロパティ | PascalCase | `GameLoader`、`LoadAsync` |
| インターフェイス | `I` + PascalCase | `IGameRepository` |
| ローカル変数・引数 | camelCase | `gameId` |
| private フィールド | `_` + camelCase | `_repository` |
| 定数 | PascalCase | `MaxRetryCount` |
| 非同期メソッド | 末尾に `Async` | `LoadGamesAsync` |

### 型・null

- **null 許容参照型を有効にする**（`.csproj` の `<Nullable>enable</Nullable>`）。null を許容する箇所は `?` で明示する
- 型が明らかな場合は `var` を使ってよい。右辺から型が読み取れない場合は型名を書く
- `dynamic` は使用禁止

### 非同期

- I/O を伴う処理は `async` / `await` で書く。`.Result` や `.Wait()` による同期待ちは行わない（デッドロックの原因になる）
- キャンセル可能な処理には `CancellationToken` を引数で受け取る

### ディレクトリ

| パス | 役割 |
|---|---|
| `src/` | アプリケーションのプロジェクト |
| `tests/` | テストプロジェクト |
| `docs/sql/` | SQLファイル（マイグレーション・初期データ等） |

### コメント

- コメントは日本語で書く
- 自明な処理にコメントは書かない。「なぜそうしているか」が非自明な場合のみ書く
- public なクラス・メソッドには XML ドキュメントコメントを書く（`<summary>`・`<param>`・`<returns>`・`<exception>`）

例：
```csharp
/// <summary>
/// ユーザーの認証トークンを検証する。
/// </summary>
/// <param name="token">JWT トークン文字列</param>
/// <returns>トークンが有効な場合は true</returns>
/// <exception cref="TokenExpiredException">トークンの有効期限が切れている場合</exception>
public bool ValidateToken(string token)
{
    // 有効期限が切れていないかチェック
    if (token.ExpiresAt < DateTimeOffset.UtcNow)
    {
        throw new TokenExpiredException();
    }
    return true;
}
```

### ブロック

- `if` / `for` などのブロックは、1行であっても必ず `{}` で囲む（省略しない）

### テスト

- テストフレームワークは xUnit を使用する
- テストプロジェクトは `tests/<対象プロジェクト名>.Tests` に置く
- テストメソッド名は「対象_条件_期待結果」の形式で書く（例: `ValidateToken_期限切れ_例外を送出する`）

## 禁止事項

- 存在しない NuGet パッケージ・API・メソッドの使用（実装前に [.claude/factcheck.md](../.claude/factcheck.md) のチェックリストに従い、NuGet と公式ドキュメントで実在確認する）
- `dynamic` の使用
- ビルド警告の放置（警告が出た状態でコミットしない）
- 例外の握りつぶし（`catch { }` のように何もしない catch を書かない）
- APIキー・接続文字列のコードへの直書き（必ず `.env.local` または構成プロバイダ経由で参照する）
- `.env.local` の git へのコミット

## プルリクエストのルール

- タイトルはコミットメッセージ規約に従う（[git-rules.md](git-rules.md) 参照）
- CI がすべて通過していること
