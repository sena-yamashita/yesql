# YesQL 依存関係トラブルシューティング

## 外部プロジェクトでコンパイルエラーが発生する場合

YesQLを外部プロジェクトのGit依存関係として使用する際に、以下のエラーが発生することがあります：

```
could not find an app file at "_build/dev/lib/yesql/ebin/yesql.app"
```

### 解決方法

1. **依存関係のクリーンアップ**
   ```bash
   # YesQLの依存関係をクリーン
   mix deps.clean yesql
   
   # すべての依存関係をクリーン（より確実）
   mix deps.clean --all
   
   # ビルドディレクトリを削除
   rm -rf _build
   ```

2. **依存関係の再取得とコンパイル**
   ```bash
   # 依存関係を再取得
   mix deps.get
   
   # コンパイル
   mix compile
   ```

3. **特定のブランチやタグを使用**
   ```elixir
   # mix.exs
   defp deps do
     [
       # masterブランチを使用
       {:yesql, git: "https://github.com/sena-yamashita/yesql.git", branch: "master", override: true},
       
       # または特定のタグを使用
       # {:yesql, git: "https://github.com/sena-yamashita/yesql.git", tag: "v2.1.0", override: true},
     ]
   end
   ```

4. **オプショナル依存関係の追加**
   
   YesQLはデータベースドライバーをオプショナル依存関係として定義しています。
   使用するドライバーを明示的に追加してください：

   ```elixir
   defp deps do
     [
       {:yesql, git: "https://github.com/sena-yamashita/yesql.git", branch: "master", override: true},
       
       # 使用するドライバーを追加
       {:postgrex, "~> 0.15"},    # PostgreSQL
       {:myxql, "~> 0.6"},        # MySQL
       {:duckdbex, "~> 0.3.9"},   # DuckDB
       {:exqlite, "~> 0.13"},     # SQLite
       {:tds, "~> 2.3"},          # MSSQL
       {:jamdb_oracle, "~> 0.5"}, # Oracle
     ]
   end
   ```

## それでも解決しない場合

1. **Elixirのバージョンを確認**
   ```bash
   elixir --version
   ```
   YesQLはElixir 1.14以上が必要です。

2. **詳細なログを確認**
   ```bash
   MIX_DEBUG=1 mix deps.compile yesql
   ```

3. **手動でコンパイル**
   ```bash
   cd deps/yesql
   mix compile
   cd ../..
   ```

## 既知の問題

- Elixir 1.18.4では、Ecto 3.5.xとの互換性問題が報告されています
- Windows環境では、LEEXトークナイザーのコンパイルに問題が発生する場合があります

## サポート

問題が解決しない場合は、以下の情報を含めてイシューを作成してください：

- Elixirのバージョン（`elixir --version`）
- Erlang/OTPのバージョン
- mix.exsの依存関係セクション
- `mix deps`の出力
- エラーメッセージの全文