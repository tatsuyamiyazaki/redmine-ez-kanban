#!/usr/bin/env bash
# Redmine コンテナ内で実行するプラグインテストランナー。
# 初回は test グループの gem を導入し、テストDBを用意してからテストを走らせる。
#
# 使い方（ホスト側）:
#   docker compose exec -u root -T redmine bash /usr/src/redmine/plugins/redmine_ez_kanban/bin/test.sh
#   # 単一ファイル: ... bin/test.sh test/functional/kanban_controller_test.rb
set -euo pipefail

REDMINE_ROOT=/usr/src/redmine
PLUGIN=redmine_ez_kanban
PLUGIN_ROOT="$REDMINE_ROOT/plugins/$PLUGIN"

cd "$REDMINE_ROOT"

# slim イメージは native 拡張のビルドツール未導入。debug 等の test gem が
# native ビルドを要するため、make/gcc が無ければ build-essential を導入する。
if ! command -v make >/dev/null 2>&1 || ! command -v gcc >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq build-essential
fi

# 公式 slim イメージは development/test グループ未導入。
# development(rubocop 等) はネイティブ拡張のビルドツールを要するため除外し、
# test グループのみ導入する。
bundle config unset without >/dev/null 2>&1 || true
bundle config set --local without "development" >/dev/null 2>&1 || true
bundle install

# 公式イメージの database.yml は production のみ。test 環境を冪等に追記する。
if ! grep -q "^test:" config/database.yml; then
  cat >> config/database.yml <<'YAML'
test:
  adapter: postgresql
  host: "db"
  port: "5432"
  username: "redmine"
  password: "redmine"
  database: "redmine_test"
  encoding: "utf8"
YAML
fi

# テストDBの作成・マイグレーション（存在すれば no-op）
RAILS_ENV=test bundle exec rake db:create
RAILS_ENV=test bundle exec rake db:migrate
RAILS_ENV=test bundle exec rake redmine:plugins:migrate NAME="$PLUGIN"

# 引数があれば単一テストファイル、無ければプラグインのテスト一式。
if [ "$#" -gt 0 ]; then
  RAILS_ENV=test bundle exec ruby -Itest "$@"
else
  RAILS_ENV=test bundle exec rake redmine:plugins:test NAME="$PLUGIN"
fi
