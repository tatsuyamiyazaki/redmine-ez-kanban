# 0011 DBフェッチの有界化（counts → 予算付き列フェッチ）

Type: AFK

## What to build

ボード1リクエストが DB から取得・インスタンス化するチケットを `render_cap` 件以下に抑える（ADR-0006）。現状は `IssueQuery#issues` を LIMIT なしで全件ロードし、リーフ判定・Scope 判定・WIP カウントを Ruby 側で行っているため、巨大プロジェクト＋ポーリングでメモリ/CPU が無制限に膨らむ（セキュリティレビュー MEDIUM-1）。0003/0007 が本来規定していた「列ごと GROUP BY COUNT」へ実装を揃え直し、あわせてフェッチ自体を有界化する。

- **リーフ判定を SQL へ**: nested set の `rgt = lft + 1`（フルツリーで子ゼロ、ADR-0002 のセマンティクスそのまま）。毎リクエスト再計算しキャッシュしない（R1, R4）。
- **Scope を SQL へ**: `root_id = :root AND lft > :parent_lft AND rgt < :parent_rgt`（R3、深さ非依存の真子孫）。
- **counts フェーズ**: アクティブクエリのスコープ（可視性込み。`IssueQuery` の標準機構を流用、R7）∧ リーフ ∧ Scope ∧ 範囲条件に対し、ステータス別 `GROUP BY COUNT` を1本実行。Layout の配置 precedence（明示マッピング > Done 列 > 未分類列）でステータス→列に集約し、各列の**正確な WIP 件数**（R10-1）と総数（超過バナー判定、R-0007）を行を1件も生成せずに得る。
- **予算付きフェッチフェーズ**: 列を左から右へ、`render_cap` を共有予算として消費（R-0007 の現行セマンティクス維持）。カードがあり予算が残る列ごとに `status_id IN (その列の全ステータス) ... ORDER BY ... LIMIT 残予算` を発行。合計フェッチ行数 ≤ `render_cap`。
- **列内ソートも SQL へ**(R9): クエリ指定があればそのソート、無指定なら優先度 position 降順 → 期日昇順（期日なしは末尾。`NULLS LAST` は使わず移植可能な `CASE WHEN due_date IS NULL` 式で PG/MySQL/SQLite 互換）。
- パンくず（Ancestry）は描画カード（≤ `render_cap`）に対する既存処理のまま変更なし。
- `Board` の公開インターフェース（`columns` / `over_cap?` / `render_cap` / `highlight_wip?` / `query`）は不変。`cards`（フラット全件リスト）は内部化または廃止し、依存テストを `columns` 経由に書き換える。

### 実装ノート

- 可視性とフィルタの一貫性は `IssueQuery` の標準スコープ（Redmine 6 の `base_scope` 相当）に条件を AND する形で担保し、可視性チェックを自前実装しない（R7 の大原則）。
- 列→ステータスの対応は「全 `IssueStatus` を `Layout#column_key_for` で引いた逆引き」で具体化する（ステータスは少数・Redmine がキャッシュ済み）。
- クエリ指定時のソートは `IssueQuery#issues` が `sort_clause` を自前適用するため現行でも R9 どおり機能している。列ごとフェッチでも `issues()` を使う限り挙動は変わらない。
- `rgt = lft + 1` は Redmine コアが維持する nested set の整合性に依存する。これは現行 `Issue#leaf?` が読む同じデータであり、依存は増えていない。

## Acceptance criteria

- [ ] 1リクエストでインスタンス化される Issue が `render_cap` 件以下（counts は COUNT のみ）
- [ ] `render_cap` 超過時も各列の WIP 件数が正確な総数を示す（既存 0007 テスト維持）
- [ ] 超過バナーが counts の総数で判定される（既存テスト維持）
- [ ] リーフ判定・Scope・サブプロジェクト範囲の既存テストが全て通る（挙動不変）
- [ ] 予算が左の列から消費される（左列が満杯なら右列は描画されない）テストが通る
- [ ] 列内ソート: クエリ指定ソートに従う / 無指定時は優先度↓→期日↑（期日なしは末尾）のテストが通る
- [ ] PG 以外でも動く移植可能な ORDER BY 式（ベンダー固有構文なし）

## Blocked by

None - can start immediately
