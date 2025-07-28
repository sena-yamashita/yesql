# YesQL Makefile

.PHONY: help docker-up docker-down docker-test test-all test-postgres test-mysql test-mssql test-sqlite test-duckdb clean

help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Docker関連コマンド
docker-up: ## Dockerサービスを起動
	docker-compose -f docker/docker-compose.yml up -d

docker-down: ## Dockerサービスを停止
	docker-compose -f docker/docker-compose.yml down

docker-clean: ## Dockerサービスとボリュームを削除
	docker-compose -f docker/docker-compose.yml down -v

docker-logs: ## Dockerサービスのログを表示
	docker-compose -f docker/docker-compose.yml logs -f

docker-test: ## Docker環境ですべてのテストを実行
	./docker/run-tests.sh all

# データベース別テスト
test-all: ## すべてのテストを実行（Docker使用）
	CI=true ./docker/run-tests.sh all

test-postgres: ## PostgreSQLテストを実行
	./docker/run-tests.sh postgres

test-mysql: ## MySQLテストを実行
	./docker/run-tests.sh mysql

test-mssql: ## SQL Serverテストを実行
	./docker/run-tests.sh mssql

test-sqlite: ## SQLiteテストを実行
	./docker/run-tests.sh sqlite

test-duckdb: ## DuckDBテストを実行
	./docker/run-tests.sh duckdb

# ローカルテスト（Docker不使用）
test: ## ローカル環境でテストを実行
	mix test

test-unit: ## 単体テストのみ実行
	mix test --only unit

test-integration: ## 統合テストのみ実行
	mix test --only integration

# 開発ツール
format: ## コードフォーマット
	mix format

format-check: ## フォーマットチェック
	mix format --check-formatted

dialyzer: ## Dialyzer実行
	mix dialyzer

deps: ## 依存関係の取得
	mix deps.get

compile: ## コンパイル
	mix compile

clean: ## ビルド成果物をクリーン
	mix clean
	rm -rf _build deps

# YesQL専用コマンド
params-test: ## パラメータ変換テスト
	mix test.yesql.params

params-diff: ## トークナイザーの違いを表示
	mix test.yesql.params --show-diff

# CI関連
ci-local: ## ローカルでCI環境を再現
	@echo "Starting local CI environment..."
	@make docker-up
	@sleep 10
	@make test-all
	@make docker-down