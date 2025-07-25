# YesQL パフォーマンスベンチマーク

このディレクトリには、YesQLの各ドライバーのパフォーマンスを測定するベンチマークスクリプトが含まれています。

## ベンチマークの目的

1. **ドライバー間のパフォーマンス比較**: 各データベースドライバーの実行速度を比較
2. **抽象化レイヤーのオーバーヘッド測定**: YesQLの抽象化レイヤーが追加するオーバーヘッドを測定
3. **最適化ポイントの特定**: パフォーマンスボトルネックを特定し、最適化の機会を見つける

## ベンチマークの実行方法

### 必要な環境

- Elixir 1.14以上
- 測定対象のデータベース（PostgreSQL、MySQL等）が実行中であること

### PostgreSQLベンチマーク

```bash
# PostgreSQLベンチマークのみ実行
POSTGRESQL_BENCH=true \
PGHOST=localhost \
PGUSER=postgres \
PGPASSWORD=postgres \
PGDATABASE=yesql_bench \
mix run bench/driver_benchmark.exs
```

### MySQLベンチマーク

```bash
# MySQLベンチマークのみ実行
MYSQL_BENCH=true \
MYSQL_HOST=localhost \
MYSQL_USER=root \
MYSQL_PASSWORD=password \
MYSQL_DATABASE=yesql_bench \
mix run bench/driver_benchmark.exs
```

### 抽象化レイヤーのオーバーヘッド測定

```bash
# オーバーヘッド測定のみ実行
OVERHEAD_BENCH=true mix run bench/driver_benchmark.exs
```

### 全てのベンチマークを実行

```bash
# 全てのベンチマークを実行
POSTGRESQL_BENCH=true \
MYSQL_BENCH=true \
OVERHEAD_BENCH=true \
PGHOST=localhost \
PGUSER=postgres \
PGPASSWORD=postgres \
PGDATABASE=yesql_bench \
MYSQL_HOST=localhost \
MYSQL_USER=root \
MYSQL_PASSWORD=password \
MYSQL_DATABASE=yesql_bench \
mix run bench/driver_benchmark.exs
```

## ベンチマーク項目

### 1. クエリ実行パフォーマンス

- **シンプルSELECT**: 単一パラメータでの基本的なSELECTクエリ
- **複数パラメータSELECT**: 複数のパラメータを使用したより複雑なクエリ
- **JOIN付きクエリ**: テーブル結合を含む複雑なクエリ

各項目について、以下を比較：
- ネイティブドライバー直接実行
- YesQL経由での実行

### 2. 抽象化レイヤーのオーバーヘッド

- **パラメータ変換**: 名前付きパラメータから各DBの形式への変換時間
- **結果処理**: クエリ結果を統一形式に変換する時間

## ベンチマーク結果の読み方

結果は以下の形式で表示されます：

```
Name                              ips        average  deviation         median         99th %
Postgrex直接 - シンプルSELECT    5.23 K      191.21 μs    ±21.45%      180.00 μs      300.00 μs
YesQL経由 - シンプルSELECT       5.01 K      199.60 μs    ±22.13%      188.00 μs      310.00 μs

Comparison: 
Postgrex直接 - シンプルSELECT    5.23 K
YesQL経由 - シンプルSELECT       5.01 K - 1.04x slower +8.39 μs
```

- **ips**: 1秒あたりの実行回数（高いほど良い）
- **average**: 平均実行時間
- **deviation**: 標準偏差（低いほど安定している）
- **median**: 中央値
- **99th %**: 99パーセンタイル値

## 期待されるオーバーヘッド

YesQLの抽象化レイヤーは以下のオーバーヘッドを追加します：

1. **パラメータ変換**: 約5-10μs（クエリの複雑さによる）
2. **結果処理**: 約2-5μs（結果セットのサイズによる）

これらのオーバーヘッドは、ほとんどのアプリケーションにおいて無視できるレベルです。

## カスタムベンチマークの作成

独自のベンチマークを作成する場合は、`bench_helper.exs`の関数を使用できます：

```elixir
# カスタムベンチマークの例
defmodule MyBenchmark do
  def run do
    results = %{
      "My Query 1" => BenchHelper.measure(fn ->
        # クエリ実行
      end),
      "My Query 2" => BenchHelper.measure(fn ->
        # 別のクエリ実行
      end)
    }
    
    BenchHelper.format_results(results)
  end
end
```

## トラブルシューティング

### データベース接続エラー

データベースが起動していることと、接続情報が正しいことを確認してください。

### 依存関係エラー

```bash
mix deps.get
```

を実行して、必要な依存関係をインストールしてください。

## 今後の拡張

- DuckDB、MSSQL、Oracleドライバーのベンチマーク追加
- より複雑なクエリパターンのテスト
- 並行実行性能の測定
- メモリ使用量の詳細分析