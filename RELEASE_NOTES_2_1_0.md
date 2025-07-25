# YesQL v2.1.0 リリースノート

リリース日: 2025-07-25

## 概要

YesQL v2.1.0では、全てのサポートされているデータベースドライバーに対して**ストリーミング結果セット**機能を追加しました。この機能により、大規模なデータセットをメモリ効率的に処理できるようになります。

## 主な新機能

### ストリーミング結果セットのサポート

大量のデータを扱う際のメモリ使用量を最小限に抑えながら、データを順次処理する機能です。

```elixir
# 100万件のデータをメモリ効率的に処理
{:ok, stream} = Yesql.Stream.query(conn,
  "SELECT * FROM large_table WHERE created_at > $1",
  [~D[2024-01-01]],
  driver: :postgrex,
  chunk_size: 1000
)

# ストリームを処理
stream
|> Stream.map(&process_row/1)
|> Stream.filter(&valid?/1)
|> Enum.count()
```

### ドライバー別の実装

各データベースの特性を活かした最適化されたストリーミング実装：

- **PostgreSQL**: カーソルベース（同期/非同期対応）
- **MySQL**: サーバーサイドカーソル
- **DuckDB**: Arrow形式、並列スキャン
- **SQLite**: ステップ実行、FTS5対応
- **MSSQL**: ページネーション、カーソルエミュレーション
- **Oracle**: REF CURSOR、BULK COLLECT

### 新しいAPI

- `Yesql.Stream.query/4` - ストリーミングクエリの実行
- `Yesql.Stream.process/5` - チャンクごとの処理
- `Yesql.Stream.reduce/6` - 集約処理
- `Yesql.Stream.batch_process/6` - バッチ処理

## 使用例

### ファイルへのエクスポート

```elixir
{:ok, count} = Yesql.Stream.process(conn,
  "SELECT * FROM users WHERE status = $1",
  ["active"],
  fn row ->
    IO.puts(file, "#{row.id},#{row.name},#{row.email}")
  end,
  driver: :postgrex,
  chunk_size: 5000
)
```

### 並列処理

```elixir
# DuckDBの並列スキャン
{:ok, stream} = DuckDBStream.create_parallel_scan(conn,
  "large_table",
  parallelism: 8,
  where: "date >= '2024-01-01'"
)
```

## パフォーマンス

- メモリ使用量: 大規模データセットでも一定（チャンクサイズに依存）
- 処理速度: 最初の結果をすぐに処理開始可能
- スケーラビリティ: データ量に関わらず安定した性能

## 移行ガイド

v2.0.0からv2.1.0への移行に破壊的変更はありません。ストリーミング機能は追加のAPIとして提供されます。

## ドキュメント

- [ストリーミングガイド](guides/streaming_guide.md) - 詳細な使用方法とベストプラクティス
- [README.md](README.md) - ストリーミング使用例を追加

## 今後の予定

- 非同期クエリ実行の最適化
- プリペアドステートメントのキャッシング
- 接続プール管理の統一化

## 謝辞

このリリースの実装は、Claude Code (Anthropic)を使用したAIペアプログラミングにより行われました。