# elixir-dbvisor/sql ライブラリ分析レポート

## 概要

`elixir-dbvisor/sql` は Elixir 用の SQL パーサーライブラリで、柔軟な SQL クエリ構築と自動パラメータ化を提供します。

## YesQL での利用可能性評価

### 利点

1. **パラメータ化クエリのサポート**
   - `{{変数名}}` 形式でパラメータを指定
   - 自動的に `?` プレースホルダーに変換
   - パラメータ値を別配列で管理

2. **柔軟な SQL 構築**
   - SQL の順序に依存しない構文
   - 複雑な CTE やサブクエリをサポート

3. **Elixir ネイティブ**
   - Hex パッケージとして利用可能
   - Apache-2.0 ライセンス

### 課題と制限

1. **パラメータ形式の違い**
   - YesQL: `:param` 形式
   - sql ライブラリ: `{{param}}` 形式
   - 変換が必要

2. **コメント処理の不明確さ**
   - テストコードからコメント処理の詳細が確認できない
   - SQL コメント内のパラメータ処理が不明

3. **文字列リテラル処理**
   - 基本的なクォート処理は確認
   - 詳細な仕様は不明

## 統合アプローチの提案

### 1. アダプターパターン実装

```elixir
defmodule Yesql.Tokenizer.SqlParser do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    # Step 1: :param → {{param}} に変換
    converted_sql = convert_yesql_to_sql_format(sql)
    
    # Step 2: SQL ライブラリでパース
    case parse_with_sql_library(converted_sql) do
      {:ok, parsed} -> convert_to_yesql_tokens(parsed)
      {:error, reason} -> {:error, reason, 1}
    end
  end
  
  defp convert_yesql_to_sql_format(sql) do
    # :param 形式を {{param}} 形式に変換
    # ただし、コメントと文字列リテラル内は除外
    Regex.replace(~r/:([a-zA-Z_]\w*)/, sql, "{{\\1}}")
  end
end
```

### 2. ハイブリッドアプローチ

```elixir
defmodule Yesql.Tokenizer.Hybrid do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    # コメントと文字列リテラルを事前処理
    {clean_sql, preserved} = extract_comments_and_strings(sql)
    
    # クリーンな SQL をトークナイズ
    tokens = tokenize_clean_sql(clean_sql)
    
    # 保存した要素を復元
    restore_preserved_elements(tokens, preserved)
  end
end
```

### 3. 段階的移行戦略

1. **Phase 1**: 現行のトークナイザーを維持
2. **Phase 2**: sql ライブラリを実験的に導入
3. **Phase 3**: パフォーマンスと機能性を評価
4. **Phase 4**: 必要に応じて完全移行

## 推奨事項

### 短期的推奨

1. **現行トークナイザーの改善**
   - コメント処理を追加
   - 文字列リテラル認識を改善
   - シンプルで確実な実装

2. **sql ライブラリの評価継続**
   - プロトタイプ実装
   - ベンチマーク測定
   - エッジケースの検証

### 長期的推奨

1. **プラガブルアーキテクチャの維持**
   - 複数のトークナイザー実装をサポート
   - ユーザーが選択可能

2. **コミュニティとの協調**
   - sql ライブラリへの貢献
   - YesQL 形式のサポート提案

## 結論

`elixir-dbvisor/sql` は興味深いライブラリですが、YesQL との統合には以下の作業が必要です：

1. パラメータ形式の変換層
2. コメント処理の検証と実装
3. パフォーマンステスト

現時点では、**既存のトークナイザーを改善する方が実用的**と考えられます。ただし、将来的なオプションとして sql ライブラリの統合も検討価値があります。

## 次のステップ

1. 簡単なコメント認識トークナイザーの実装
2. sql ライブラリのプロトタイプ統合
3. 両アプローチのベンチマーク比較
4. ユーザーフィードバックの収集