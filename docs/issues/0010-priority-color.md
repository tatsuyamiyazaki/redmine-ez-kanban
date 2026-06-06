# 0010 優先度色（カード左縁のカラーストライプ）

Type: AFK

## What to build

各カードの左縁に優先度を示すカラーストライプを表示し、一目で優先度がわかるようにする。色の意味づけは Redmine 標準の相対優先度位置（`IssuePriority#position_name`: lowest / low / default / high / highest）を再利用し、チケット一覧の優先度強調と一貫させる。再実装はしない。

- カード root 要素に `priority-<position_name>` クラスを付与する。
- `default` 以外の4段階（lowest / low / high / highest）に Redmine パレットを複製した色の左帯を当て、`default` は帯なし。
- 常時オン（追加設定なし）。WIP 強調と同じく純粋に情報提供のみで、カードの配置・列内ソート・可視性には一切影響しない（R5/R10 不変）。
- 既存の優先度名テキスト（`.ez-kanban-card__priority`）は維持する（正確な名称表示＋色覚多様性への冗長キュー）。
- `position_name` が `nil`（無効化された優先度を参照する古いチケット等）の場合は帯なしにフェイルセーフ。
- 色値はプラグイン CSS に定義（Redmine の優先度色は表セル向け CSS のため左帯には直接流用できない）。意味づけのみ Redmine を再利用する。

## Acceptance criteria

- [ ] highest/high/low/lowest のカードに `priority-<position_name>` クラスが付く
- [ ] default 優先度のカードには優先度由来のストライプクラスが付かない（帯なし）
- [ ] 優先度名テキストは従来どおり表示される
- [ ] 追加設定なしで常時表示される（オプトイン設定を持たない）
- [ ] ストライプはカードの配置・列内ソート・可視性を変えない（R5/R10 不変）
- [ ] クラス付与ロジックのテストが通る

## Blocked by

- 0002 リーフカード（フラット表示）
