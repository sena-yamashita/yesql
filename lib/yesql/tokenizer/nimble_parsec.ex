defmodule Yesql.Tokenizer.NimbleParsec do
  @moduledoc """
  Nimble Parsec を使用した SQL トークナイザー実装。
  
  SQL コメント（--, /*, #）と文字列リテラルを正しく処理し、
  パラメータ（:name 形式）を認識します。
  """
  
  import NimbleParsec
  
  # コメントと文字列は結果に含めないので ignore でラップ
  
  # 単一行コメント: -- から行末まで
  single_line_comment =
    string("--")
    |> optional(utf8_string([not: ?\n], min: 0))
    |> optional(string("\n"))
    |> ignore()
  
  # 複数行コメント: /* から */ まで
  # 注意: ネストしたコメントはサポートしない
  multi_line_comment =
    string("/*")
    |> repeat(
      lookahead_not(string("*/"))
      |> utf8_char([])
    )
    |> string("*/")
    |> ignore()
  
  # MySQL スタイルコメント: # から行末まで
  mysql_comment =
    string("#")
    |> optional(utf8_string([not: ?\n], min: 0))
    |> optional(string("\n"))
    |> ignore()
  
  # エスケープシーケンス
  escape_sequence = 
    string("\\")
    |> utf8_char([])
  
  # 文字列リテラル（単一引用符）
  single_quoted_string =
    string("'")
    |> repeat(
      choice([
        escape_sequence,
        utf8_char(not: ?')
      ])
    )
    |> string("'")
    |> reduce({__MODULE__, :to_string_literal, []})
  
  # 文字列リテラル（二重引用符）- SQL 識別子
  double_quoted_string =
    string("\"")
    |> repeat(
      choice([
        escape_sequence,
        utf8_char(not: ?\")
      ])
    )
    |> string("\"")
    |> reduce({__MODULE__, :to_string_literal, []})
  
  # パラメータ名の文字
  param_start = ascii_char([?a..?z, ?A..?Z, ?_])
  param_continue = ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])
  
  # パラメータ: :name 形式
  parameter =
    ignore(string(":"))
    |> concat(param_start)
    |> repeat(param_continue)
    |> reduce({__MODULE__, :to_param, []})
    |> unwrap_and_tag(:named_param)
  
  # SQL フラグメント（特殊文字以外の連続）
  # より効率的に、特殊文字の開始を先読みして停止
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
    |> reduce({__MODULE__, :to_fragment, []})
    |> unwrap_and_tag(:fragment)
  
  # 連続するコロン（::）- PostgreSQLのキャスト演算子
  double_colon =
    string("::")
    |> reduce({__MODULE__, :to_fragment, []})
    |> unwrap_and_tag(:fragment)
    
  # コロンの後に識別子文字が続かない場合
  non_param_colon =
    string(":")
    |> lookahead_not(param_start)
    |> reduce({__MODULE__, :to_fragment, []})
    |> unwrap_and_tag(:fragment)
  
  # メインパーサー
  sql_element =
    choice([
      # コメント（結果に含まれない）
      single_line_comment,
      multi_line_comment,
      mysql_comment,
      # 文字列リテラル（フラグメントとして扱う）
      single_quoted_string |> unwrap_and_tag(:fragment),
      double_quoted_string |> unwrap_and_tag(:fragment),
      # 特殊なコロン（:: を先にチェック）
      double_colon,
      # パラメータ
      parameter,
      # その他のコロン
      non_param_colon,
      # 通常のフラグメント
      sql_fragment
    ])
  
  # 全体のパーサー
  defparsec :parse_sql, repeat(sql_element) |> eos()
  
  # ヘルパー関数
  @doc false
  def to_fragment(chars) when is_list(chars) do
    chars
    |> Enum.map(fn
      [?\\, char] -> <<char>>  # エスケープシーケンスの処理
      char when is_integer(char) -> <<char>>
      other -> to_string(other)
    end)
    |> Enum.join()
  end
  
  @doc false
  def to_param(chars) when is_list(chars) do
    chars
    |> Enum.map(&<<&1>>)
    |> Enum.join()
    |> String.to_atom()
  end
  
  @doc false
  def to_string_literal(parts) when is_list(parts) do
    parts
    |> Enum.map(fn
      "'" -> "'"
      "\"" -> "\""
      "\\" -> "\\"
      [?\\, char] -> <<char>>  # エスケープシーケンス
      char when is_integer(char) -> <<char>>
      str when is_binary(str) -> str
    end)
    |> Enum.join()
  end
end