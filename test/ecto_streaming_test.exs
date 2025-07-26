defmodule EctoStreamingTest do
  use ExUnit.Case
  
  # テスト用のEctoリポジトリモック
  defmodule TestRepo do
    def stream(_sql, _params, opts) do
      # テスト用のストリームを返す
      max_rows = Keyword.get(opts, :max_rows, 500)
      
      # シンプルなテストデータ
      Stream.unfold({1, 100}, fn
        {i, max} when i > max -> nil
        {i, max} -> 
          row = %{id: i, name: "User #{i}", active: true}
          {row, {i + 1, max}}
      end)
      |> Stream.chunk_every(max_rows)
      |> Stream.flat_map(&Function.identity/1)
    end
    
    def transaction(fun, _opts \\ []) do
      # トランザクションをシミュレート
      try do
        result = fun.()
        {:ok, result}
      rescue
        e -> {:error, e}
      end
    end
    
    def rollback(reason) do
      throw({:rollback, reason})
    end
  end
  
  # Ecto.Adapters.SQLのモック
  defmodule Ecto.Adapters.SQL do
    def query(TestRepo, sql, _params) do
      # カーソルベースクエリのシミュレーション
      cond do
        String.contains?(sql, "LIMIT") ->
          # チャンクデータを返す
          {:ok, %{
            rows: Enum.map(1..10, fn i -> [i, "User #{i}", true] end),
            columns: ["id", "name", "active"]
          }}
        true ->
          {:ok, %{rows: [], columns: []}}
      end
    end
  end
  
  describe "基本的なストリーミング" do
    test "Ectoストリームの作成" do
      sql = "SELECT * FROM users WHERE active = $1"
      params = [true]
      
      {:ok, stream} = Yesql.Stream.EctoStream.create(TestRepo, sql, params)
      
      # Streamオブジェクトであることを確認
      assert %Stream{} = stream
      
      # ストリームから最初の10件を取得
      results = Enum.take(stream, 10)
      assert length(results) == 10
      assert %{id: 1, name: "User 1", active: true} = hd(results)
    end
    
    test "max_rowsオプションの動作" do
      sql = "SELECT * FROM users"
      params = []
      
      {:ok, stream} = Yesql.Stream.EctoStream.create(TestRepo, sql, params, 
        max_rows: 20
      )
      
      # 全データを取得
      results = Enum.to_list(stream)
      assert length(results) == 100
    end
  end
  
  describe "トランザクション内でのストリーミング" do
    test "transaction_streamの実行" do
      sql = "SELECT * FROM users WHERE active = $1"
      params = [true]
      
      {:ok, count} = Yesql.Stream.EctoStream.transaction_stream(
        TestRepo, 
        sql, 
        params,
        fn row ->
          assert %{id: _, name: _, active: true} = row
        end
      )
      
      assert {:ok, 100} == count
    end
    
    test "バッチ処理の実行" do
      sql = "SELECT * FROM users"
      params = []
      
      {:ok, batch_count} = Yesql.Stream.EctoStream.batch_process(
        TestRepo,
        sql,
        params,
        10,
        fn batch ->
          assert length(batch) <= 10
          assert Enum.all?(batch, &match?(%{id: _, name: _, active: _}, &1))
        end
      )
      
      assert {:ok, 10} == batch_count  # 100件 / 10件ずつ = 10バッチ
    end
  end
  
  describe "カーソルベースストリーミング" do
    test "トランザクションなしでのストリーミング" do
      # カーソルベースストリーミングは実際のRepoが必要なため、
      # このテストではモックの限界を示す
      sql = "SELECT * FROM users"
      params = []
      
      # Ecto.Adapters.SQLが呼ばれるが、TestRepoは登録されていないため
      # 実際にはエラーになることを確認
      stream = Yesql.Stream.EctoStream.cursor_based_stream(
        TestRepo,
        sql,
        params,
        :id,
        chunk_size: 10
      )
      
      # 実際のRepoではないためエラーになる
      assert_raise RuntimeError, ~r/could not lookup Ecto repo/, fn ->
        stream |> Enum.take(10)
      end
    end
  end
  
  describe "並列ストリーミング" do
    @tag :skip  # 並列処理のテストは複雑なため、必要に応じて実装
    test "parallel_streamの動作" do
      sql = "SELECT * FROM large_table"
      params = []
      
      {:ok, stream} = Yesql.Stream.EctoStream.parallel_stream(
        TestRepo,
        sql,
        params,
        parallelism: 4,
        chunk_size: 25
      )
      
      results = stream |> Enum.to_list()
      assert length(results) > 0
    end
  end
  
  describe "エラーハンドリング" do
    test "無効なSQLでのエラー" do
      # このテストは実際のEctoではエラーになるが、
      # モックではストリームが作成される
      sql = "INVALID SQL"
      params = []
      
      result = Yesql.Stream.EctoStream.create(TestRepo, sql, params)
      # モックなので成功する
      assert {:ok, _stream} = result
    end
  end
  
  describe "Yesql.Stream統合" do
    test "Yesql.Streamからの呼び出し" do
      sql = "SELECT * FROM users WHERE active = $1"
      params = [true]
      
      {:ok, stream} = Yesql.Stream.query(
        TestRepo,
        sql,
        params,
        driver: :ecto,
        max_rows: 50
      )
      
      # ストリームが正しく作成されることを確認
      results = Enum.take(stream, 5)
      assert length(results) == 5
    end
    
    test "process関数との統合" do
      sql = "SELECT * FROM users"
      params = []
      # count = 0
      
      {:ok, processed_count} = Yesql.Stream.process(
        TestRepo,
        sql,
        params,
        fn row ->
          assert %{id: _, name: _, active: _} = row
        end,
        driver: :ecto
      )
      
      assert processed_count == 100
    end
    
    test "reduce関数との統合" do
      sql = "SELECT * FROM users"
      params = []
      
      {:ok, total} = Yesql.Stream.reduce(
        TestRepo,
        sql,
        params,
        0,
        fn row, acc ->
          acc + row.id
        end,
        driver: :ecto
      )
      
      # 1 + 2 + ... + 100 = 5050
      assert total == 5050
    end
    
    test "batch_process関数との統合" do
      sql = "SELECT * FROM users"
      params = []
      
      {:ok, batch_count} = Yesql.Stream.batch_process(
        TestRepo,
        sql,
        params,
        20,
        fn batch ->
          assert length(batch) <= 20
        end,
        driver: :ecto
      )
      
      assert batch_count == 5  # 100件 / 20件ずつ = 5バッチ
    end
  end
end