# Nimble Parsec を使った SQL トークナイザー実装の検討

## Nimble Parsec の利点

1. **宣言的な文法定義**
   - PEG（Parser Expression Grammar）ベース
   - 読みやすく保守しやすい文法定義
   - コンパイル時に効率的なパーサーを生成

2. **強力な組み合わせ子**
   - `ignore`, `unwrap_and_tag`, `lookahead` など
   - 複雑な文法も簡潔に表現可能

3. **パフォーマンス**
   - コンパイル時にパーサーを生成
   - 実行時のオーバーヘッドが少ない

4. **Elixir エコシステム統合**
   - Hex パッケージとして利用可能
   - 多くのプロジェクトで採用実績

## SQL トークナイザーの実装設計

### 基本的な文法定義

```elixir
defmodule Yesql.Tokenizer.NimbleParsec do
  import NimbleParsec
  
  # 空白文字
  whitespace = 
    ascii_string([?\s, ?\t, ?\n, ?\r], min: 1)
    |> ignore()
  
  # 単一行コメント
  single_line_comment =
    string("--")
    |> optional(utf8_string([not: ?\n], min: 0))
    |> optional(string("\n"))
    |> tag(:comment)
  
  # 複数行コメント
  multi_line_comment =
    string("/*")
    |> repeat_until(utf8_char([]), [string("*/")])
    |> string("*/")
    |> tag(:comment)
  
  # MySQL スタイルコメント
  mysql_comment =
    string("#")
    |> optional(utf8_string([not: ?\n], min: 0))
    |> optional(string("\n"))
    |> tag(:comment)
  
  # 文字列リテラル（単一引用符）
  single_quoted_string =
    ignore(string("'"))
    |> repeat(
      choice([
        string("\\'") |> replace("'"),
        utf8_char([not: ?'])
      ])
    )
    |> ignore(string("'"))
    |> reduce(:to_string)
    |> tag(:string_literal)
  
  # 文字列リテラル（二重引用符）
  double_quoted_string =
    ignore(string("\""))
    |> repeat(
      choice([
        string("\\\"") |> replace("\""),
        utf8_char([not: ?\"])
      ])
    )
    |> ignore(string("\""))
    |> reduce(:to_string)
    |> tag(:string_literal)
  
  # パラメータ
  parameter =
    ignore(string(":"))
    |> ascii_string([?a..?z, ?A..?Z, ?_], 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> reduce(:to_string)
    |> map(:String.to_atom)
    |> unwrap_and_tag(:named_param)
  
  # SQL フラグメント
  sql_fragment =
    times(
      lookahead_not(
        choice([
          string(":"),
          string("--"),
          string("/*"),
          string("#"),
          string("'"),
          string("\"")
        ])
      )
      |> utf8_char([]),
      min: 1
    )
    |> reduce(:to_string)
    |> unwrap_and_tag(:fragment)
  
  # メインパーサー
  sql_parser =
    repeat(
      choice([
        whitespace,
        single_line_comment,
        multi_line_comment,
        mysql_comment,
        single_quoted_string,
        double_quoted_string,
        parameter,
        sql_fragment
      ])
    )
    |> eos()
  
  defparsec :parse_sql, sql_parser
end
```

### 使用例

```elixir
defmodule Yesql.Tokenizer.NimbleParsecImpl do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    case Yesql.Tokenizer.NimbleParsec.parse_sql(sql) do
      {:ok, tokens, "", _, _, _} ->
        # コメントとstring_literalを除外し、
        # fragmentとnamed_paramのみを返す
        filtered_tokens = filter_tokens(tokens)
        {:ok, filtered_tokens, 1}
        
      {:error, reason, _, _, _, _} ->
        {:error, format_error(reason), 1}
    end
  end
  
  defp filter_tokens(tokens) do
    tokens
    |> Enum.filter(fn
      {:comment, _} -> false
      {:string_literal, _} -> false
      _ -> true
    end)
    |> Enum.map(fn
      {:fragment, text} -> {:fragment, text}
      {:named_param, param} -> {:named_param, param}
    end)
  end
end
```

## 実装の利点

1. **明確な文法定義**
   - コメントの種類を明確に定義
   - 文字列リテラルのエスケープ処理
   - パラメータの正確な認識

2. **拡張性**
   - 新しい構文要素の追加が容易
   - データベース固有の構文対応

3. **エラーハンドリング**
   - パース位置の情報
   - 詳細なエラーメッセージ

4. **テスタビリティ**
   - 各構成要素を個別にテスト可能
   - 文法の正確性を保証

## 実装手順

1. **依存関係の追加**
   ```elixir
   {:nimble_parsec, "~> 1.4"}
   ```

2. **基本パーサーの実装**
   - コメント処理
   - 文字列リテラル処理
   - パラメータ認識

3. **テストスイートの作成**
   - 各種コメントパターン
   - エッジケース
   - パフォーマンステスト

4. **既存トークナイザーとの互換性確保**
   - 同じトークン形式を出力
   - スムーズな移行

## 結論

Nimble Parsec を使用することで：

- **保守性の高い**実装が可能
- **バグの少ない**パーサーを構築
- **拡張可能な**アーキテクチャ

これは YesQL のトークナイザーとして理想的な選択肢です。