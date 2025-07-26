# Nimble Parsec トークナイザー

YesQL v2.0 から、SQL コメントと文字列リテラルを正しく処理する Nimble Parsec ベースのトークナイザーが利用可能になりました。

## 背景

デフォルトの Leex ベースのトークナイザーには以下の制限があります：

- SQL コメント（`--`, `/* */`, `#`）内の `:param` もパラメータとして認識してしまう
- 文字列リテラル内の `:param` もパラメータとして認識してしまう
- `-- name:` のようなメタデータ行でエラーになることがある

これらの問題を解決するため、Nimble Parsec を使用した新しいトークナイザーを実装しました。

## 使用方法

### アプリケーション設定

```elixir
# config/config.exs
config :yesql,
  tokenizer: Yesql.Tokenizer.NimbleParsecImpl
```

### 実行時設定

```elixir
# 全体的に設定
Yesql.Config.put_tokenizer(Yesql.Tokenizer.NimbleParsecImpl)

# 一時的に使用
Yesql.Config.with_tokenizer(Yesql.Tokenizer.NimbleParsecImpl, fn ->
  Yesql.parse(sql_with_comments)
end)
```

## 機能

### コメント処理

以下のコメント形式を正しく処理します：

```sql
-- 単一行コメント内の :param は無視されます
SELECT * FROM users WHERE id = :id

/* 
  複数行コメント内の :param も
  無視されます
*/
SELECT * FROM posts WHERE user_id = :user_id

# MySQL スタイルコメント内の :param も無視
SELECT * FROM logs WHERE level = :level
```

### 文字列リテラル処理

文字列リテラル内のパラメータ記号は無視されます：

```sql
-- 単一引用符内
SELECT * FROM users WHERE comment = ':not_a_param' AND id = :id

-- 二重引用符内（識別子）
SELECT * FROM "table:with:colons" WHERE id = :id

-- エスケープシーケンス
SELECT * FROM users WHERE name = 'O\'Brien' AND status = :status
```

### 特殊な SQL 構文

PostgreSQL のキャスト演算子なども正しく処理します：

```sql
-- :: はキャスト演算子として認識
SELECT id::text, created_at::date FROM users WHERE id = :id

-- URL などの文字列内のコロン
INSERT INTO logs (url) VALUES ('https://example.com/path')
```

## パフォーマンス

Nimble Parsec トークナイザーは、デフォルトの Leex トークナイザーと比較して約 2-3 倍遅くなりますが、絶対的な処理時間は十分高速です（通常のクエリで数十マイクロ秒）。

### ベンチマーク結果の例

```
Simple query (19 chars):
  Default: 22 μs
  Nimble:  61 μs (2.77x)

Complex query with comments (625 chars):
  Default: 50 μs
  Nimble: 134 μs (2.68x)
```

正確性とのトレードオフとして、このパフォーマンス差は許容範囲内です。

## 使用推奨

### Nimble Parsec トークナイザーを使用すべき場合

- SQL ファイルにコメントが含まれる
- SQL ファイルに `-- name:` のようなメタデータがある
- 文字列リテラル内に `:` を含む SQL を使用する
- より堅牢なパラメータ認識が必要

### デフォルトトークナイザーで十分な場合

- シンプルな SQL のみを使用
- コメントを含まない
- 最高のパフォーマンスが必要

## 実装の詳細

Nimble Parsec トークナイザーは、PEG（Parser Expression Grammar）ベースの実装で、以下の利点があります：

- 宣言的な文法定義
- 拡張が容易
- コンパイル時に最適化されたパーサーを生成

## 今後の検討事項

将来的に、以下のライブラリの利用も検討されています：

- [elixir-dbvisor/sql](https://github.com/elixir-dbvisor/sql) - より高度な SQL パース機能を提供するライブラリ

これらのライブラリは、より複雑な SQL 解析が必要になった場合のオプションとして検討される予定です。

## まとめ

Nimble Parsec トークナイザーは、SQL コメントと文字列リテラルを正しく処理し、より堅牢な SQL パラメータ認識を提供します。パフォーマンスのトレードオフはありますが、多くのユースケースで推奨される選択肢です。