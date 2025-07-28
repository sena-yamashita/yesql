import Config

# テスト環境の設定はconfig/test.exsで管理
if Mix.env() == :test do
  import_config "test.exs"
end
