# テストエラー分析ドキュメント

作成日: 2025-07-27
最終更新: 2025-07-27

## 概要

このドキュメントは、`make test-all`実行時に発生するテストエラーの詳細な分析と対応策を記録します。

## テスト環境

- Docker環境でPostgreSQL、MySQL、MSSQL、SQLiteを実行
- Elixir 1.18.1
- Erlang/OTP 26

## エラー分析

### 1. PostgreSQL関連エラー

#### エラーカテゴリ
- [x] ストリーミングテスト関連
- [x] バッチテスト関連
- [ ] キャスト構文テスト関連
- [x] 接続プール関連

#### 詳細なエラー記録

1. **DBConnection.EncodeError** (BatchTest)
   - エラー: `Postgrex expected an integer in -2147483648..2147483647, got "not_a_number"`
   - ファイル: test/batch_test.exs:217
   - 原因: 整数型パラメータに文字列を渡している

2. **active_sql_transaction** (BatchTest)
   - エラー: `code: :active_sql_transaction`
   - ファイル: test/batch_test.exs:240
   - 原因: トランザクション分離レベルの設定で既存トランザクションとの競合

3. **RuntimeError: outdated connection** (StreamTest, PostgreSQLStreamingTest)
   - エラー: `an outdated connection has been given to DBConnection on handle_prepare/3`
   - 複数箇所で発生
   - 原因: 接続プールから古い接続を使用している

#### 対応策
1. BatchTestのパラメータ型チェックを修正
2. トランザクション管理のロジックを見直し
3. ストリーミングテストでの接続管理を改善

### 2. MySQL関連エラー

#### エラーカテゴリ
- [x] キャスト構文テスト関連
- [x] 複数SQL文の処理関連
- [x] セットアップエラー

#### 詳細なエラー記録

1. **KeyError** (YesqlMySQLTest)
   - エラー: `key :mysql not found in: [mysql: #PID<0.438.0>]`
   - ファイル: test/mysql_test.exs:21
   - 原因: コンテキストのキー名の不一致

2. **MySQL構文エラー** (DriverCastSyntaxTest)
   - エラー: `You have an error in your SQL syntax...near 'SELECT'`
   - ファイル: test/driver_cast_syntax_test.exs:143
   - 原因: MySQLは複数のSELECT文を1つのクエリで実行できない

#### 対応策
1. mysql_test.exsのコンテキストキー名を修正
2. MySQLのSQLファイルを1つのSELECT文に修正

### 3. MSSQL関連エラー

#### エラーカテゴリ
- [x] スカラー変数エラー
- [x] キャスト構文テスト関連
- [x] セットアップエラー

#### 詳細なエラー記録

1. **KeyError** (YesqlMSSQLTest)
   - エラー: `key :mssql not found in: [mssql: #PID<0.431.0>]`
   - ファイル: test/mssql_test.exs:21
   - 原因: コンテキストのキー名の不一致

2. **スカラー変数エラー** (DriverCastSyntaxTest)
   - エラー: `Must declare the scalar variable "@p1"`
   - ファイル: test/driver_cast_syntax_test.exs:197
   - 原因: MSSQLも複数のSELECT文を1つのクエリで実行できない

#### 対応策
1. mssql_test.exsのコンテキストキー名を修正
2. MSSQLのSQLファイルを1つのSELECT文に修正

### 4. SQLite関連エラー

#### エラーカテゴリ
- [ ] ストリーミングテスト関連
- [ ] reset関数の引数エラー

#### 詳細なエラー記録
```
（ここに実際のエラーメッセージを記録）
```

#### 対応策
```
（ここに対応策を記録）
```

### 5. DuckDB関連エラー

#### エラーカテゴリ
- [ ] ストリーミングテスト関連
- [ ] 環境変数設定関連

#### 詳細なエラー記録
```
（ここに実際のエラーメッセージを記録）
```

#### 対応策
```
（ここに対応策を記録）
```

## 共通パターン

### 環境変数関連
- [ ] FULL_TEST
- [ ] 各ドライバー固有の_TEST環境変数
- [ ] 各ドライバー固有の_STREAM_TEST環境変数

### 接続設定関連
- [ ] ホスト名の設定
- [ ] ポート番号の設定
- [ ] 認証情報の設定

## 対応履歴

| 日付 | 対応内容 | 結果 |
|------|----------|------|
| 2025-07-27 | MySQL/MSSQLのSQLファイルにセミコロン追加 | エラー：複数SELECT文は非対応 |
| 2025-07-27 | PostgreSQLストリーミングテストのセットアップ修正 | 部分的改善 |
| 2025-07-27 | run-tests.shに環境変数追加 | 完了 |

## 根本原因分析

### 1. 複数SQL文の扱い
- YesQLは`;`で区切られた複数のSQL文を扱えるが、**ドライバーが対応していない場合がある**
- MySQL、MSSQLでは1つのクエリで複数のSELECT文を実行できない
- 解決策: 各SQL文を個別に実行するか、SQLファイルを分割する

### 2. コンテキストキー名の不一致
- テストセットアップで返すキー名と、テスト内で参照するキー名が異なる
- 例: `[mysql: conn]` vs `%{mysql: conn}`

### 3. 接続プール管理
- ストリーミングテストで長時間の処理中に接続がタイムアウト
- 並行処理で同じ接続を使用しようとしている

## 次のステップ

1. 各ドライバーごとにテストを実行し、詳細なエラーログを収集
2. エラーパターンを分析し、共通の原因を特定
3. 優先順位を付けて修正を実施
4. 修正後の再テストと結果の記録