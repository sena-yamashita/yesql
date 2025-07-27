# ストリーミングテストエラーの修正計画

## 問題の分析

### エラーメッセージ
```
RuntimeError: an outdated connection has been given to DBConnection on handle_prepare/3
```

### 根本原因
1. **並行実行での接続共有**: 複数のタスクが同じ接続を使用しようとしている
2. **接続プールの枯渇**: async: falseでテストが実行されているため、接続が不足
3. **長時間実行**: ストリーミングクエリが長時間実行され、接続がタイムアウト

## 修正方針

### 1. 並行実行テストの修正
- 各タスクに個別の接続を割り当てる
- または、並行実行をやめて順次実行にする

### 2. 接続プール設定の見直し
- テスト用の接続プールサイズを増やす
- タイムアウト設定を調整

### 3. テストの構造改善
- setup_allで共通の接続を作成するのではなく、各テストで接続を作成
- 接続の有効性を確認してから使用

## 具体的な修正案

### Option 1: 並行実行を順次実行に変更
```elixir
test "複数のストリーミングクエリの実行", %{postgrex: conn} do
  # 順次実行
  {:ok, stream1} = Yesql.Stream.query(...)
  count1 = stream1 |> Enum.count()
  
  {:ok, stream2} = Yesql.Stream.query(...)
  count2 = stream2 |> Enum.count()
  
  assert count1 + count2 == 10000
end
```

### Option 2: 各タスクで新しい接続を作成
```elixir
test "複数のストリーミングクエリの並行実行", context do
  task1 = Task.async(fn ->
    {:ok, conn} = create_new_connection()
    {:ok, stream} = Yesql.Stream.query(conn, ...)
    result = stream |> Enum.count()
    close_connection(conn)
    result
  end)
  
  task2 = Task.async(fn ->
    {:ok, conn} = create_new_connection()
    {:ok, stream} = Yesql.Stream.query(conn, ...)
    result = stream |> Enum.count()
    close_connection(conn)
    result
  end)
end
```

### Option 3: トランザクション内でストリーミング実行
PostgreSQLのカーソルはトランザクション内でのみ有効なので、明示的にトランザクションで囲む

## 推奨する修正順序

1. まず、並行実行テストを無効化して他のテストが通るか確認
2. StreamTestとPostgreSQLStreamingTestの接続管理を改善
3. 並行実行が必要なテストは個別に対応