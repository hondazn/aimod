---
name: sql-query-antipatterns
description: |
  SQLのクエリ（SELECT/UPDATE/DELETE 等の DML）を書く・直す・レビューするときに適用する
  リファレンス。NULLの3値論理・GROUP BYの単一値原則・乱択・全文検索・クエリ肥大化・
  ワイルドカードのアンチパターンと解決策を収録する。テーブル設計・DDL は領分外（→ rdb-design）。
  トリガー: 「SQLを書いて」「このクエリを直して/速くして」「NULLの扱い」「GROUP BYでエラー」
  「ランダムに行を取得」「LIKE検索が遅い」「集計結果がおかしい」。
license: Proprietary
---

# SQLクエリ — アンチパターン回避リファレンス

## 使い方

- **クエリ作成時**: 下のレビュー観点で自分の書いたSQLを確認する
- **不具合調査・レビュー時**: アンチパターン一覧を症状から引く
- 該当が疑われた項目だけ、同ディレクトリの `ANTIPATTERNS.md` の該当節を読む

## クエリレビュー観点

1. **NULL**: 比較は `IS NULL` / `IS DISTINCT FROM`。`= NULL`・`NOT IN (NULL, ...)`・NULLを含む式の連結に注意 → [14]
2. **GROUP BY**: SELECT列は「グループ化列 or 集約関数」のみ（単一値の原則）。最大値の行の他列が欲しいならウィンドウ関数等 → [15]
3. **乱択**: `ORDER BY RAND()` はデータ増加で破綻。データ量に応じた手法を選ぶ → [16]
4. **文字列検索**: `LIKE '%word%'` はインデックス不使用。キーワード検索は全文検索機能へ → [17]
5. **複雑さ**: 無関係な集計を1クエリに詰めない。COUNT/SUMの水増しはデカルト積を疑う → [18]
6. **列指定**: `SELECT *`・INSERTの列リスト省略をプロダクションコードに残さない → [19]

## アンチパターン一覧

| # | 名前 | やりがちな書き方 | 何が壊れるか | 解決策 |
|---|---|---|---|---|
| 14 | Fear of the Unknown | `WHERE col = NULL`、NULL回避の特殊値(-1) | 3値論理で行が消える、集計汚染 | IS NULL / IS DISTINCT FROM / COALESCE |
| 15 | Ambiguous Groups | GROUP BYに無い列をSELECTに書く | エラー、またはMySQL/SQLiteで不定値 | ウィンドウ関数・導出テーブル等から選択 |
| 16 | Random Selection | `ORDER BY RAND() LIMIT 1` | インデックス不使用の全件ソート | 乱数キー参照・オフセット・TABLESAMPLE |
| 17 | Poor Man's Search Engine | `LIKE '%crash%'` / REGEXP | 全行スキャン、誤マッチ | 全文検索機能・転置インデックス |
| 18 | Spaghetti Query | 複雑な仕事を1クエリに詰め込む | 意図しないデカルト積で集計水増し、保守不能 | 分割統治（複数の単純なクエリ） |
| 19 | Implicit Columns | `SELECT *`、INSERT列リスト省略 | JOINの列名衝突、列変更でサイレント破壊 | 列名を明示（ポカヨケ） |

## 判定テスト

- 「NULL が入ったとき、この条件式は TRUE / FALSE / UNKNOWN のどれになるか言えるか」
- 「GROUP BY の選択列は、すべてグループごとに単一値に定まるか」
- 「このクエリが返す行数の上限を言えるか」— 言えないなら実データで壊れる
- 「`SELECT *` を使っていないか」— 列が増えたときにこのクエリの意味が変わらないか
