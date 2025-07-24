# YesQL システム構成仕様書 - 現在の実装状態

## 1. プロジェクト概要

### 1.1 基本情報
- **プロジェクト名**: YesQL
- **バージョン**: 2.0.0（マルチドライバー対応版）
- **言語**: Elixir (Erlang VM)
- **ビルドツール**: Mix
- **最小Elixirバージョン**: 1.5以上

### 1.2 目的
SQLファイルからElixir関数を自動生成し、型安全なデータベースアクセスを提供するライブラリ。プロトコルベースのドライバーシステムにより、複数のデータベースエンジンをサポート。

### 1.3 主な変更点（v1.0.1→v2.0.0）
- プロトコルベースのドライバーアーキテクチャを導入
- DuckDBサポートを追加
- ドライバー固有ロジックの分離とモジュール化
- 拡張可能な設計への移行

## 2. 現在のアーキテクチャ

### 2.1 ディレクトリ構造
```
yesql/
├── lib/
│   ├── yesql.ex                    # メインモジュール（defqueryマクロ）
│   └── yesql/
│       ├── driver.ex               # ドライバープロトコル定義
│       ├── driver_factory.ex       # ドライバーインスタンス生成
│       ├── exceptions.ex           # カスタム例外定義
│       ├── tokenizer.ex            # SQLトークナイザーインターフェース
│       └── driver/                 # ドライバー実装
│           ├── duckdb.ex          # DuckDBドライバー
│           ├── ecto.ex            # Ectoドライバー
│           └── postgrex.ex        # Postgrexドライバー
├── src/
│   └── sql_tokenizer.xrl          # Leexトークナイザー定義
├── test/
│   ├── yesql_test.exs            # 既存テストスイート
│   ├── duckdb_test.exs           # DuckDB専用テスト
│   └── sql/
│       └── duckdb/               # DuckDB用SQLファイル
└── mix.exs                        # プロジェクト設定（依存関係を含む）
```

### 2.2 コアコンポーネント

#### 2.2.1 YesQL モジュール (lib/yesql.ex)
**責務**:
- `defquery`マクロの提供
- ドライバーファクトリーとの連携
- SQLファイルの読み込みと関数生成
- ドライバー非依存の共通ロジック

**主要な変更**:
```elixir
defmacro defquery(file_path, opts \\ []) do
  # ドライバー名の正規化（モジュール名→アトム）
  driver_atom = case driver_name do
    Postgrex -> :postgrex
    Ecto -> :ecto
    atom when is_atom(atom) -> atom
    _ -> driver_name
  end
  
  # DriverFactoryを使用してドライバーインスタンスを作成
  case DriverFactory.create(driver_atom) do
    {:ok, driver_instance} ->
      # ドライバー固有のパラメータ変換を実行
      {sql, param_spec} = Driver.convert_params(driver_instance, raw_sql, [])
      # 関数定義を生成
  end
end
```

#### 2.2.2 ドライバープロトコル (lib/yesql/driver.ex)
**新規追加コンポーネント**

プロトコルとして定義され、各ドライバーが実装すべきインターフェースを提供：

```elixir
defprotocol Yesql.Driver do
  @spec execute(t, any, String.t, list) :: {:ok, any} | {:error, any}
  def execute(driver, conn, sql, params)

  @spec convert_params(t, String.t, list) :: {String.t, list}
  def convert_params(driver, sql, param_spec)

  @spec process_result(t, any) :: {:ok, list(map)} | {:error, any}
  def process_result(driver, raw_result)
end
```

#### 2.2.3 ドライバーファクトリー (lib/yesql/driver_factory.ex)
**新規追加コンポーネント**

動的なドライバーインスタンス生成を担当：

```elixir
def create(driver_name) do
  case driver_name do
    :postgrex ->
      if match?({:module, _}, Code.ensure_compiled(Postgrex)) do
        {:ok, %Yesql.Driver.Postgrex{}}
      else
        {:error, :driver_not_loaded}
      end
    :duckdb ->
      if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
        {:ok, %Yesql.Driver.DuckDB{}}
      else
        {:error, :driver_not_loaded}
      end
    # ... 他のドライバー
  end
end
```

## 3. ドライバー実装詳細

### 3.1 Postgrexドライバー (lib/yesql/driver/postgrex.ex)
**PostgreSQL用の実装**:
- パラメータ形式: `$1, $2, $3...`
- 結果形式: `%{columns: [...], rows: [...]}`
- 既存の実装をプロトコルベースに移行

### 3.2 Ectoドライバー (lib/yesql/driver/ecto.ex)
**Ecto経由のデータベースアクセス**:
- `Ecto.Adapters.SQL.query/3`を使用
- 複数のデータベースバックエンドをサポート
- Postgrexと同じパラメータ形式を使用

### 3.3 DuckDBドライバー (lib/yesql/driver/duckdb.ex)
**新規追加 - DuckDB分析エンジンサポート**:

```elixir
defmodule Yesql.Driver.DuckDB do
  defstruct []
  
  if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, conn, sql, params) do
        case Duckdbex.query(conn, sql, params) do
          {:ok, result_ref} ->
            case Duckdbex.fetch_all(result_ref) do
              {:ok, rows} ->
                {:ok, %{rows: rows, columns: extract_columns(rows)}}
              error -> error
            end
          error -> error
        end
      end
    end
  end
end
```

**特徴**:
- パラメータ形式: PostgreSQLと同じ `$1, $2...`
- 結果セットの自動変換
- Duckdbexライブラリとの統合

## 4. データフロー（更新版）

### 4.1 コンパイル時フロー
```
1. defquery マクロ呼び出し
   ↓
2. ドライバー名の正規化（Postgrex → :postgrex）
   ↓
3. DriverFactory.create でドライバーインスタンス生成
   ↓
4. SQLファイル読み込み
   ↓
5. Driver.convert_params でドライバー固有のSQL変換
   ↓
6. 名前付きパラメータ抽出とマッピング生成
   ↓
7. Elixir関数定義生成（ドライバーインスタンスを含む）
```

### 4.2 実行時フロー
```
1. 生成された関数呼び出し
   ↓
2. 名前付きパラメータから実パラメータへのマッピング
   ↓
3. Driver.execute でSQL実行（ドライバー固有の実装）
   ↓
4. Driver.process_result で結果変換
   ↓
5. 統一形式のマップリストを返却
```

## 5. 使用例

### 5.1 基本的な使用方法
```elixir
# Postgrexドライバーの使用
defmodule MyApp.Query do
  use Yesql, driver: :postgrex, conn: MyApp.Repo
  
  Yesql.defquery("queries/get_user.sql")
end

# DuckDBドライバーの使用
defmodule MyApp.Analytics do
  use Yesql, driver: :duckdb
  
  Yesql.defquery("queries/sales_report.sql")
end

# 実行時のドライバー指定
Yesql.defquery("queries/dynamic.sql", driver: :ecto, conn: MyApp.Repo)
```

### 5.2 DuckDB固有の使用例
```elixir
# セットアップ
{:ok, db} = Duckdbex.open("analytics.db")
{:ok, conn} = Duckdbex.connection(db)

# クエリ実行
MyApp.Analytics.sales_report(conn, 
  start_date: ~D[2024-01-01], 
  end_date: ~D[2024-12-31]
)
# => {:ok, [%{product: "A", total: 1000.0}, ...]}
```

## 6. 拡張ポイント

### 6.1 新しいドライバーの追加方法

1. **ドライバーモジュールの作成**:
```elixir
defmodule Yesql.Driver.MySQL do
  defstruct []
  
  if match?({:module, _}, Code.ensure_compiled(MyXQL)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, conn, sql, params) do
        # MySQL固有の実行ロジック
      end
      
      def convert_params(_driver, sql, _param_spec) do
        # :name → ? への変換
      end
      
      def process_result(_driver, raw_result) do
        # 結果の統一形式への変換
      end
    end
  end
end
```

2. **DriverFactoryへの追加**:
```elixir
# driver_factory.ex に追加
:mysql ->
  if match?({:module, _}, Code.ensure_compiled(MyXQL)) do
    {:ok, %Yesql.Driver.MySQL{}}
  else
    {:error, :driver_not_loaded}
  end
```

3. **依存関係の追加** (mix.exs):
```elixir
{:myxql, "~> 0.6", optional: true}
```

### 6.2 パラメータ形式のカスタマイズ
各ドライバーの`convert_params/3`実装で、データベース固有のパラメータ形式に対応：

- PostgreSQL/DuckDB: `$1, $2, $3...`
- MySQL/SQLite: `?, ?, ?...`
- Oracle: `:1, :2, :3...`
- MSSQL: `@p1, @p2, @p3...`

## 7. テスト戦略

### 7.1 ドライバー別テスト
各ドライバーは独立したテストファイルを持つ：
- `test/yesql_test.exs` - Postgrex/Ecto
- `test/duckdb_test.exs` - DuckDB

### 7.2 条件付きテスト実行
```elixir
# 環境変数によるテスト制御
@moduletag :duckdb
@moduletag :skip_on_ci

setup_all do
  case System.get_env("DUCKDB_TEST") do
    "true" -> # DuckDBテストを実行
    _ -> :skip
  end
end
```

## 8. パフォーマンスと最適化

### 8.1 コンパイル時最適化
- SQLはコンパイル時に一度だけ解析
- パラメータマッピングは事前計算
- ドライバーインスタンスはマクロ展開時に決定

### 8.2 実行時最適化
- 最小限のパラメータ変換処理
- ドライバー固有の最適化を活用
- 結果変換の遅延評価

## 9. 今後の拡張計画

### 9.1 短期計画
- [ ] MySQL/MariaDBドライバーの実装
- [ ] SQLiteドライバーの実装
- [ ] バッチクエリのサポート
- [ ] トランザクション管理の改善

### 9.2 長期計画
- [ ] MSSQL/Oracleドライバー（優先度：低）
- [ ] プリペアドステートメントのキャッシング
- [ ] 非同期クエリ実行のサポート
- [ ] ストリーミング結果セットの処理

## 10. 移行ガイド

### 10.1 v1.xからv2.0への移行
既存のコードは後方互換性が保たれているため、変更は不要：

```elixir
# 従来の使用方法（引き続き動作）
use Yesql, driver: Postgrex, conn: MyApp.Repo

# 新しい推奨方法（アトムを使用）
use Yesql, driver: :postgrex, conn: MyApp.Repo
```

### 10.2 新機能の活用
DuckDBサポートを利用する場合：
1. 依存関係に`duckdbex`を追加
2. ドライバーとして`:duckdb`を指定
3. DuckDB接続を渡してクエリを実行

## 11. まとめ

YesQL v2.0.0は、プロトコルベースのドライバーアーキテクチャにより、以下を実現：

1. **拡張性**: 新しいデータベースドライバーを簡単に追加可能
2. **保守性**: ドライバー固有ロジックの明確な分離
3. **柔軟性**: 実行時のドライバー選択が可能
4. **互換性**: 既存コードとの完全な後方互換性

この設計により、YesQLは単一データベース向けのツールから、マルチデータベース対応の汎用SQLライブラリへと進化しました。