# ローカルCI環境セットアップガイド

## 概要
GitHub Actionsの実行をローカルで再現することで、CI環境でのデバッグを効率化します。

## actツールのインストール

### macOS
```bash
brew install act
```

### Linux
```bash
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Docker Desktop必須
actはDockerを使用するため、Docker Desktopがインストールされている必要があります。

## 基本的な使用方法

### 1. 全ワークフローの一覧表示
```bash
act -l
```

### 2. 特定のワークフローを実行
```bash
# Elixir CIワークフローを実行
act -W .github/workflows/elixir.yml

# Database Testsワークフローを実行
act -W .github/workflows/ci.yml
```

### 3. 特定のジョブを実行
```bash
# testジョブのみ実行
act -W .github/workflows/elixir.yml -j test
```

### 4. 環境変数を設定して実行
```bash
# CI環境変数を設定
act -W .github/workflows/elixir.yml --env CI=true
```

## YesQL専用設定

### 1. act設定ファイルの作成
`.act/secrets`ファイルを作成（.gitignoreに追加済み）：
```bash
mkdir -p .act
cat > .act/secrets << EOF
GITHUB_TOKEN=your-github-token-here
EOF
```

### 2. BatchTest問題のデバッグ用設定
`.act/env`ファイルを作成：
```bash
cat > .act/env << EOF
CI=true
MIX_ENV=test
POSTGRES_HOST=localhost
POSTGRES_USER=postgres  
POSTGRES_PASSWORD=postgres
POSTGRES_DATABASE=yesql_test
POSTGRES_PORT=5432
EOF
```

### 3. カスタムワークフローでBatchTestをデバッグ
`.github/workflows/batch-test-debug.yml`を作成：
```yaml
name: BatchTest Debug
on: [workflow_dispatch]

jobs:
  debug:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: yesql_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18.4'
          otp-version: '27.2.1'

      - name: Install dependencies
        run: |
          mix deps.get
          mix compile

      - name: Run migrations
        run: mix ecto.migrate

      - name: Run BatchTest with debug output
        run: |
          export CI=true
          export DEBUG_BATCH_TEST=true
          mix test test/batch_test.exs --trace
```

### 4. ローカルでの実行
```bash
# BatchTestデバッグワークフローを実行
act -W .github/workflows/batch-test-debug.yml
```

## BatchTest調査用のデバッグコード追加

`test/batch_test.exs`に追加するデバッグコード：
```elixir
if System.get_env("DEBUG_BATCH_TEST") do
  IO.puts("\n=== BatchTest Debug Info ===")
  IO.puts("CI: #{System.get_env("CI")}")
  IO.puts("Transaction opt: #{transaction_opt}")
  
  # バッチ実行前のテーブル状態
  {:ok, before_count} = Postgrex.query(conn, "SELECT COUNT(*) FROM batch_test", [])
  IO.puts("Records before batch: #{inspect(before_count.rows)}")
  
  # 各クエリを個別に実行してデバッグ
  Enum.each(Map.to_list(named_queries), fn {name, {query, params}} ->
    IO.puts("\nExecuting #{name}: #{query}")
    IO.puts("Params: #{inspect(params)}")
    
    case Postgrex.query(conn, query, params) do
      {:ok, result} ->
        IO.puts("Success: #{inspect(result)}")
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end)
  
  # バッチ実行後のテーブル状態
  {:ok, after_count} = Postgrex.query(conn, "SELECT COUNT(*) FROM batch_test", [])
  IO.puts("\nRecords after individual queries: #{inspect(after_count.rows)}")
end
```

## トラブルシューティング

### 1. Dockerイメージサイズの問題
デフォルトのUbuntuイメージは大きいため、軽量版を使用：
```bash
act -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

### 2. メモリ不足エラー
Dockerのメモリ制限を増やす：
- Docker Desktop → Settings → Resources → Memory: 8GB以上

### 3. ネットワークエラー
サービスコンテナへの接続は`localhost`ではなくサービス名を使用：
```bash
# .act/envで設定
POSTGRES_HOST=postgres  # localhostではなくサービス名
```

## 推奨されるデバッグフロー

1. **問題の特定**
   ```bash
   # CIログを確認
   gh run view <run-id> --log-failed | grep -A 10 -B 10 "BatchTest"
   ```

2. **ローカルで再現**
   ```bash
   # 同じ環境変数でテスト実行
   CI=true mix test test/batch_test.exs --trace
   ```

3. **actで完全再現**
   ```bash
   act -W .github/workflows/batch-test-debug.yml
   ```

4. **修正とテスト**
   - デバッグ出力を追加
   - 問題を特定
   - 修正を実装
   - actで確認

5. **本番CIで確認**
   ```bash
   git push origin fix-batch-test
   gh run watch
   ```

## 参考リンク
- [act公式ドキュメント](https://github.com/nektos/act)
- [GitHub Actions ローカル実行ガイド](https://openstandia.jp/tech/column/ac20221209/)
- [act実践ガイド](https://zenn.dev/skanehira/articles/2021-03-16-act)