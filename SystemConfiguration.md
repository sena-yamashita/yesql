# システム構成仕様書

## 1. プロジェクト概要

### 1.1 基本情報
- **プロジェクト名**: YesQL
- **バージョン**: 1.0.1
- **言語**: Elixir (Erlang VM)
- **ビルドツール**: Mix
- **最小Elixirバージョン**: 1.5以上

### 1.2 目的
SQLファイルからElixir関数を自動生成し、型安全なデータベースアクセスを提供するライブラリ。名前付きパラメータをサポートし、コンパイル時にSQLを検証する。

## 2. 現在のアーキテクチャ

### 2.1 ディレクトリ構造
```
yesql/
├── lib/
│   ├── yesql.ex           # メインモジュール（defqueryマクロ）
│   └── yesql/
│       └── tokenizer.ex    # SQLトークナイザーのインターフェース
├── src/
│   └── sql_tokenizer.xrl   # Leexトークナイザー定義
├── test/
│   └── yesql_test.exs     # テストスイート
└── mix.exs                 # プロジェクト設定
```

### 2.2 コアコンポーネント

#### 2.2.1 YesQL モジュール (lib/yesql.ex)
**責務**:
- `defquery`マクロの提供
- SQLファイルの読み込みと解析
- Elixir関数の動的生成
- パラメータ変換とSQL実行

**主要な機能**:
```elixir
@supported_drivers [:postgrex, :ecto]  # ハードコードされたドライバーサポート

defmacro defquery(name, file, opts \\ [])
# SQLファイルから関数を生成するマクロ
```

#### 2.2.2 Tokenizer モジュール (lib/yesql/tokenizer.ex)
**責務**:
- Leexトークナイザーへのインターフェース
- SQLファイルの字句解析
- 名前付きパラメータの抽出

**主要な機能**:
```elixir
def tokenize(str)
# SQL文字列をトークンリストに変換
```

#### 2.2.3 SQLトークナイザー定義 (src/sql_tokenizer.xrl)
**責務**:
- SQL構文の字句解析ルール定義
- 名前付きパラメータ（`:param`）の識別
- 通常のSQL文との区別

## 3. データフロー

### 3.1 コンパイル時フロー
```
1. defquery マクロ呼び出し
   ↓
2. SQLファイル読み込み
   ↓
3. Tokenizer.tokenize でSQL解析
   ↓
4. 名前付きパラメータ抽出
   ↓
5. Elixir関数定義生成
   ↓
6. ドライバー固有の実行コード生成
```

### 3.2 実行時フロー
```
1. 生成された関数呼び出し
   ↓
2. 名前付きパラメータを位置パラメータに変換
   - :name → $1, $2... (PostgreSQL)
   ↓
3. ドライバー経由でSQL実行
   - Postgrex.query!
   - Ecto.Adapters.SQL.query!
   ↓
4. 結果の変換と返却
```

## 4. 現在の実装詳細

### 4.1 パラメータ変換ロジック
```elixir
# 名前付きパラメータから位置パラメータへの変換
# 例: SELECT * FROM users WHERE id = :id AND name = :name
# → SELECT * FROM users WHERE id = $1 AND name = $2
```

### 4.2 ドライバー固有の実装
現在、ドライバー固有のロジックがyesql.ex内にハードコードされている：

```elixir
case driver do
  :postgrex ->
    # Postgrex固有の実装
  :ecto ->
    # Ecto固有の実装
end
```

## 5. 制限事項と課題

### 5.1 アーキテクチャ上の制限
1. **ドライバーサポートのハードコード**
   - 新しいドライバー追加にはソースコード修正が必要
   - @supported_drivers の静的定義

2. **ドライバー固有ロジックの密結合**
   - yesql.ex内に全てのドライバー実装が混在
   - 拡張性の欠如

3. **パラメータ変換の固定実装**
   - PostgreSQL形式（$1, $2）のみサポート
   - 他のDB形式（?, :1など）への対応困難

### 5.2 技術的債務
1. **抽象化の不足**
   - ドライバーインターフェースが未定義
   - 結果変換ロジックの重複

2. **テストの依存性**
   - PostgreSQLデータベースが必須
   - 他のDBでのテストが困難

## 6. DuckDB対応への要件

### 6.1 必要な変更点
1. **ドライバーインターフェースの抽象化**
   ```elixir
   defprotocol YesQL.Driver do
     def execute(driver, sql, params, opts)
     def convert_params(driver, sql, params)
   end
   ```

2. **パラメータ変換の拡張**
   - DuckDB形式のパラメータ対応
   - ドライバー毎の変換ロジック分離

3. **DuckDBexの統合**
   - 依存関係への追加
   - ドライバー実装の作成

### 6.2 リファクタリング計画
1. **Phase 1: ドライバー抽象化**
   - ドライバープロトコル定義
   - 既存実装の移行

2. **Phase 2: DuckDB実装**
   - DuckDBexドライバー作成
   - パラメータ変換実装

3. **Phase 3: テスト拡張**
   - DuckDB用テスト追加
   - CI/CD対応

## 7. 今後の拡張性

### 7.1 将来的なドライバー対応
- MySQL（優先度：低）
- MSSQL（優先度：低）
- Oracle（優先度：低）

### 7.2 アーキテクチャ改善案
1. **プラグインシステム**
   - 動的なドライバー登録
   - 外部パッケージとしてのドライバー提供

2. **設定の外部化**
   - ドライバー設定のconfigファイル化
   - 実行時の動的切り替え

## 8. DuckDBドライバーの現状と制限事項

### 8.1 実装状況
- **基本的なクエリ実行**: 動作可能
- **パラメータなしのクエリ**: 正常に動作
- **パラメータ付きクエリ**: 現在未サポート

### 8.2 技術的課題

#### 8.2.1 DuckDBexのパラメータ処理
- DuckDBexの`query/3`関数および`prepare_statement`/`execute_statement`の両方でパラメータが正しくバインドされない
- エラー: "Invalid Input Error: Values were not provided for the following prepared statement parameters"
- $1形式、?形式の両方で同じエラーが発生

#### 8.2.2 調査結果
- DuckDB自体は$1形式と?形式のパラメータをサポート
- DuckDBexのNIF実装におけるパラメータバインディングに問題がある可能性
- 他のDuckDBバインディング（Node.js、.NET等）でも類似の問題が報告されている

### 8.3 今後の対応方針
1. **短期的対応**
   - パラメータクエリのサポートを保留
   - ドキュメントに制限事項を明記
   - パラメータなしクエリのみの使用を推奨

2. **中長期的対応**
   - DuckDBexのアップデートを監視
   - 代替のDuckDBバインディングの評価
   - パラメータ変換方式の再設計

## 9. 参考情報

### 9.1 関連プロジェクト
- https://github.com/tschnibo/yesql/tree/dev（開発ブランチ）
- https://github.com/AlexR2D2/duckdbex（DuckDBドライバー）

### 9.2 技術スタック
- Erlang/OTP
- Leex（Erlang Lexical Analyzer）
- Mix（ビルドツール）
- ExUnit（テストフレームワーク）

### 9.3 ドライバー依存関係
- Postgrex: PostgreSQLドライバー（動作確認済）
- Ecto: Elixir ORM（動作確認済）
- Duckdbex: DuckDBドライバー（パラメータクエリに制限あり）