# 外部ライブラリAPI確認チェックリスト

## 概要

外部ライブラリのAPIを使用する前に、必ず以下のチェックリストに従って確認を行ってください。
これは、誤ったAPI使用によるバグを防ぐための重要なプロセスです。

## チェックリスト

### 1. ドキュメントの確認

- [ ] 公式ドキュメントでAPIの仕様を確認
- [ ] 関数のシグネチャ（引数と戻り値の型）を確認
- [ ] 使用例を確認

### 2. ソースコードの確認

- [ ] GitHubなどでライブラリのソースコードを直接確認
- [ ] 関数の実装を確認
- [ ] テストコードで使用例を確認

### 3. 実際の動作確認

- [ ] iexで実際に関数を呼び出して動作を確認
- [ ] 戻り値の形式を確認
- [ ] エラーケースの挙動を確認

## 具体例：Duckdbex.fetch_chunk

### 誤った仮定
```elixir
# 誤：fetch_chunkが存在しないと仮定
# 正：実際にはv0.3.13で存在する
```

### 正しい確認方法

1. **GitHubでソースコードを確認**
   ```
   https://github.com/AlexR2D2/duckdbex/blob/v0.3.13/lib/duckdbex.ex#L269
   ```

2. **関数のspec確認**
   ```elixir
   @spec fetch_chunk(query_result()) :: list() | {:error, reason()}
   ```

3. **iexで動作確認**
   ```elixir
   iex> {:ok, db} = Duckdbex.open(":memory:")
   iex> {:ok, conn} = Duckdbex.connection(db)
   iex> {:ok, result} = Duckdbex.query(conn, "SELECT 1 as num")
   iex> Duckdbex.fetch_chunk(result)
   [[1]]
   iex> Duckdbex.fetch_chunk(result)
   []
   ```

## 確認ツール

### mix.exsに追加する依存関係
```elixir
{:ex_doc, "~> 0.31", only: :dev, runtime: false}
```

### ドキュメント生成
```bash
mix deps.get
mix docs
```

### hexdocsでの確認
```
https://hexdocs.pm/duckdbex/0.3.13/Duckdbex.html
```

## ベストプラクティス

1. **仮定をしない**
   - APIの存在や動作について推測で判断しない
   - 必ず実際の実装を確認する

2. **バージョンを確認**
   - 使用しているライブラリのバージョンを確認
   - バージョン間でAPIが変更されている可能性を考慮

3. **テストを書く**
   - 外部APIを使用する部分は必ずテストを書く
   - モックではなく実際のライブラリでテストする

4. **エラーハンドリング**
   - APIのエラーケースを理解する
   - 適切なエラーハンドリングを実装する

## 今回の教訓

DuckDBex.fetch_chunkの例から学んだこと：

1. **存在確認の重要性**
   - 関数が存在しないと仮定する前に、必ずソースコードを確認
   - GitHubやhexdocsで実際の実装を確認

2. **戻り値の形式**
   - fetch_chunkは行のリストを返す（各行もリスト）
   - 空の結果の場合は空リスト`[]`を返す

3. **Stream.resourceの正しい使い方**
   - 要素のリストではなく、要素そのものを返す場合がある
   - APIの仕様に合わせて適切に調整する必要がある

## 参考リンク

- [Duckdbex GitHub](https://github.com/AlexR2D2/duckdbex)
- [Duckdbex hexdocs](https://hexdocs.pm/duckdbex/)
- [Elixir Stream.resource](https://hexdocs.pm/elixir/Stream.html#resource/3)