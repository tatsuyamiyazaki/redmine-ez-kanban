# 開発環境（Docker）

このプラグインは単体では動作せず、ホスト Redmine が必要です。`docker-compose.yml` で
Redmine 6.0（ADR-0001）+ PostgreSQL を立ち上げ、このリポジトリを
`plugins/redmine_ez_kanban` としてマウントして開発・テストします。

## 前提

- Docker Desktop が起動していること（`docker ps` が通る状態）。

## 起動

```bash
docker compose up -d
# 初回はイメージ取得 + DB 初期化に数分かかる
```

プラグインのマイグレーション（マイグレーションが追加されたら）:

```bash
docker compose exec redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
docker compose restart redmine
```

ブラウザで http://localhost:3000 （初期管理者 admin / admin）。
Administration → Plugins に `Redmine EZ Kanban` が出れば認識成功。

## テスト実行

公式イメージは本番用で development/test の gem を除外しているため、初回のみ
test グループの gem を入れてからテストする。`bin/test.sh` がこれを一括で行う:

```bash
docker compose exec redmine bash /usr/src/redmine/plugins/redmine_ez_kanban/bin/test.sh
```

単一テストファイルのみ:

```bash
docker compose exec redmine bash -lc \
  "cd /usr/src/redmine && RAILS_ENV=test bundle exec ruby -Itest \
   plugins/redmine_ez_kanban/test/functional/kanban_controller_test.rb"
```

## 停止 / クリーンアップ

```bash
docker compose down          # コンテナ停止（データは残る）
docker compose down -v       # DB・filesボリュームごと破棄（完全初期化）
```

## 補足

- リポジトリ全体をプラグインとしてマウントするため、`docs/` や `.claude/` も
  コンテナ内のプラグインディレクトリに見えるが、Redmine のプラグインローダは
  `init.rb` を基準に読み込むため無害。
- プラグインID（`init.rb` の `Redmine::Plugin.register :redmine_ez_kanban`）と
  マウント先ディレクトリ名 `redmine_ez_kanban` は一致させること。
