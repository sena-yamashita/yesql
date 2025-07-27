# pretty_print_formatter SQL Lexer 分析

## 概要

[pretty_print_formatter](https://github.com/san650/pretty_print_formatter)のSQL lexerを調査し、YesQLのトークナイザーとして採用可能かを評価しました。

## 比較表

| 機能 | YesQL現在の実装 | pretty_print_formatter | Nimble Parsec実装 |
|-----|----------------|----------------------|------------------|
| パラメータ形式 | `:name` | `$1`, `?1` | `:name` |
| 文字列リテラル | ✅ サポート | ❌ コメントアウト | ✅ サポート |
| SQLコメント | ❌ 非対応 | ✅ `--`のみ | ✅ 全形式対応 |
| 複数行コメント | ❌ 非対応 | ❌ 非対応 | ✅ `/* */` |
| MySQLコメント | ❌ 非対応 | ❌ 非対応 | ✅ `#` |
| キャスト演算子 | ✅ `::` | ❌ 非対応 | ✅ `::` |
| 実装の複雑さ | シンプル | シンプル | 中程度 |
| エラーハンドリング | 基本的 | 最小限 | 詳細 |

## pretty_print_formatter lexerの特徴

### 長所
- シンプルで理解しやすい実装
- 標準的なLeex形式
- 行番号の追跡

### 短所
- **`:name`形式のパラメータをサポートしていない**（致命的）
- 文字列リテラルがコメントアウトされている
- SQLコメントは`--`形式のみ
- エラーハンドリングが最小限
- YesQLの要件を満たさない

## 実装詳細

### Definitions
```erlang
KEYWORDS    = [A-Z]+
INT         = [0-9]+
NAME        = [a-zA-Z0-9"_.]+
WHITESPACE  = [\s\t\n\r]
SEPARATOR   = [,;]
OPERATORS   = [*+=<>!']+
VARIABLE    = [$?][0-9]+  // $1, ?1形式のみ
PAREN_OPEN  = [([]
PAREN_CLOSE = [)\]]
COMMENT     = (-)(-)[\s].*
```

### 主な問題点

1. **パラメータ形式の非互換性**
   - YesQLは`:name`形式を使用
   - pretty_print_formatterは`$1`, `?1`形式のみ

2. **文字列リテラルの未実装**
   - 文字列内の`:`が誤認識される可能性

3. **限定的なコメントサポート**
   - `--`形式のみ対応
   - `/* */`や`#`形式は未対応

## 結論

**pretty_print_formatterのSQL lexerは、YesQLのトークナイザーとして採用するには適していません。**

理由：
1. `:name`形式のパラメータをサポートしていない（最も重要）
2. 文字列リテラルの処理が未実装
3. SQLコメントのサポートが限定的
4. YesQLの既存APIとの互換性がない

## 推奨事項

現在の選択肢の中では、以下の順序で推奨します：

1. **Nimble Parsec実装**（既に実装済み）
   - 全ての要件を満たす
   - SQLコメントと文字列リテラルを正しく処理
   - パフォーマンスも許容範囲内

2. **現在のLeex実装**（デフォルト）
   - シンプルで高速
   - コメント内のパラメータ問題はあるが、多くの場合で動作

3. **将来的な検討**
   - [elixir-dbvisor/sql](https://github.com/elixir-dbvisor/sql) - より高度なSQL解析が必要な場合

pretty_print_formatterのlexerは、別のパラメータ形式（`$1`形式）を使用するシステム向けに設計されており、YesQLには不適切です。