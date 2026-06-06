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
test グループの gem を入れてからテストする。`bin/test.sh` がこれを一括で行う
（native 拡張を持つ gem＝`debug` 等のビルドに `build-essential` が要るため、
slim イメージでは未導入だと `bundle install` が失敗する。`bin/test.sh` が
不足時に自動導入する）:

```bash
docker compose exec redmine bash /usr/src/redmine/plugins/redmine_ez_kanban/bin/test.sh
```

単一テストファイルのみ:

```bash
docker compose exec redmine bash -lc \
  "cd /usr/src/redmine && RAILS_ENV=test bundle exec ruby -Itest \
   plugins/redmine_ez_kanban/test/functional/kanban_controller_test.rb"
```

## CSS / JS を変更したとき（本番アセットの再コンパイル）

本番（production）では Propshaft が **precompile 済みのフィンガープリント資産**
（例 `public/assets/plugin_assets/redmine_ez_kanban/ez_kanban-<hash>.css`）を配信する。
`assets/stylesheets/*.css` や `assets/javascripts/*.js` を編集しても、**ソース変更＋
コンテナ再起動だけでは新しいフィンガープリントが生成されず、古い資産が配信され続ける**。
ブラウザをハードリロードしても直らない（リンク先の hash が変わらないため）。

変更を反映するには強制再生成が必要:

```bash
docker compose exec -u root redmine bash -lc \
  "cd /usr/src/redmine && RAILS_ENV=production SECRET_KEY_BASE=dummy \
   bundle exec rails assets:clobber && \
   RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rails assets:precompile"
docker compose restart redmine
```

再生成後は hash が変わる（例 `ez_kanban-82e5b4a5.css` → `ez_kanban-12bcbf90.css`）ので、
HTML の `<link>` も新 URL を指し、ブラウザは通常リロードで新規取得する。
配信中の中身は次で確認できる:

```bash
docker compose exec redmine bash -lc \
  "grep -n priority public/assets/plugin_assets/redmine_ez_kanban/ez_kanban-*.css"
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
