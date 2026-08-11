# クエリアンチパターン詳細

各節の構成: 症状（アンチパターンの形）／見つけ方（会話・SQL上の兆候）／例外（用いてもよい場合）／解決策。

## 14. フィア・オブ・ジ・アンノウン（恐怖のunknown） / Fear of the Unknown

**症状**: NULLを一般値のように扱う、または一般値（-1等）でNULLを代用する。

- `hours + 10` や `first_name || middle_initial` は片方がNULLなら全体がNULL（フルネームが消える）
- `WHERE assigned_to = 123` も `NOT (assigned_to = 123)` もNULL行を返さない（比較結果が unknown）
- `WHERE col = NULL` は常に0行
- NULL回避の特殊値 `-1` は SUM/AVG を汚染し、列ごとの特殊値の文書化負担を生む

**見つけ方**: 「値が未設定の行はどう見つける？」「DBにデータはあるのにアプリでフルネームが空になる」「`priority <> 1` のレポートから未設定行が漏れる」

**例外**: 外部入出力（CSV等）ではNULLを直接表現できず `\N` 等のマッピングが要る。「複数種類の欠損状態」を区別したい場合はNULL単独では不足。

**解決策**: NULLは「不明」を表す一意な値として扱う。3値論理（TRUE/FALSE/unknown）の要点: `NULL = NULL` → NULL、`NULL AND FALSE` → FALSE、`NULL OR TRUE` → TRUE、`NOT (NULL)` → NULL。

```sql
SELECT * FROM Bugs WHERE assigned_to IS NULL;
-- NULLも含め常にTRUE/FALSEになる非等価比較（SQL-99。Oracleは未対応、MySQLは <=> ）
SELECT * FROM Bugs WHERE assigned_to IS DISTINCT FROM 1;
-- 式中のNULLは COALESCE で代替値に
SELECT first_name || COALESCE(' ' || middle_initial || ' ', ' ') || last_name FROM Accounts;
```

値が欠けることが意味をなさない列には NOT NULL 制約（アプリでなくDBで強制）。

ミニAP: `NOT IN (NULL, 'NEW')` はどの行にもマッチしない（`NOT (col = NULL)` が unknown のまま AND されるため）。IN/NOT IN リストにNULLを含めない。

## 15. アンビギュアスグループ（曖昧なグループ） / Ambiguous Groups

**症状**: 単一値の原則違反 — SELECT列に「GROUP BY指定列でも集約関数でもない列」を書く。「MAXを取った行の他の列も返るはず」という期待は成り立たない（最大値の行が複数ある/MAXとMINで別の行になる/SUMは元のどの行とも一致しない）。多くのDBはエラーにするが、SQLite と `ONLY_FULL_GROUP_BY` 無効のMySQLは**不定値を黙って返す**。

**見つけ方**: `must appear in the GROUP BY clause`（PostgreSQL）、`incompatible with sql_mode=only_full_group_by`（MySQL）等のエラー。MySQL/SQLiteで「たまに違う行が返る」報告。

**例外**: 関数従属性が成立する場合（GROUP BYした列が主キーで、他列が一意に決まる）は論理的に曖昧でない。PostgreSQL 9.1+は主キーGROUP BY時に同一テーブルの他列を許容。

**解決策**: 要件とデータ量で選ぶ。

| 解法 | 使い分けの目安 |
|---|---|
| 集約結果のみ返す（他列を諦める) | 行の詳細が不要ならこれが最単純 |
| ウィンドウ関数 `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` → rownum=1 | 標準的で読みやすい第一候補（MySQL 8.0+） |
| 相関サブクエリ（`NOT EXISTS` でより新しい行がない） | 読みやすいが行ごと実行で遅め |
| 導出テーブル（集約をサブクエリ化してJOIN） | 相関サブクエリより速い傾向。同値重複に注意 |
| OUTER JOIN 自己結合 | 大量データで性能最優先。保守コスト高 |
| `GROUP_CONCAT` / `LISTAGG` | 全値を連結して見せたい場合（製品依存） |
| `ANY_VALUE`（MySQL） | どの値でも構わない/従属性を自分が保証できる場合 |

性能は実測で比較する（一方が常に優れているとは仮定しない）。

ミニAP: 「ポータブルSQL」— 全製品共通で動くSQLへの固執自体がアンチパターン。ベンダー拡張の利益を捨てても完全な移植性は得られない。差異はAdapter層で吸収する。

## 16. ランダムセレクション / Random Selection

**症状**: `SELECT * FROM Bugs ORDER BY RAND() LIMIT 1`。RAND() は行ごとの非決定値でインデックス化不可能なため、全行の手作業ソートになる。開発環境では気づかず、データ増加とともに確実に遅くなる。

**見つけ方**: 「ランダムに返すクエリが本当に遅い」「全行フェッチしないと選べないのでメモリを増やしたい」「一部のエントリが他より高頻度で表示される」（欠番の偏り）

**例外**: データ量が小さく増えない見込みの場合（50州からの選択等）は実害なし。

**解決策**: テーブル全体をソートしない手法をデータ特性で選ぶ。

| 手法 | 前提・特徴 |
|---|---|
| `WHERE key = ROUND(RAND()*(max-min))+min` | 主キーが連続していること。欠番でゼロ行になりうる |
| `WHERE key >= 乱数 ORDER BY key LIMIT 1` | ゼロ行は解消するが欠番直後のキーに偏る |
| 全キー値をアプリで取得して1つ選ぶ | 均等だがキー一覧のメモリとクエリ2回 |
| `COUNT(*)` → 乱数オフセットで `LIMIT 1 OFFSET n` | 連続性を前提にできず均等に選びたい場合 |
| `TABLESAMPLE`（SQL Server）/ `SAMPLE`（Oracle） | 製品固有の最適化。制限事項をドキュメントで確認 |
| 選択結果を一定時間キャッシュして使い回す | クエリ自体を最適化できない場合の回避策 |

ミニAP: 複数行のランダム取得 — 単一行手法の繰り返しは重複と無限リトライ（行数不足時）のリスクがある。性能とコードの単純さのトレードオフとして `ORDER BY RAND() LIMIT n` を選ぶ余地もある。

## 17. プアマンズ・サーチエンジン（貧者のサーチエンジン） / Poor Man's Search Engine

**症状**: キーワード検索を `LIKE '%crash%'` や REGEXP で実装。通常のインデックスが効かず全行スキャン、`%one%` が money/prone/lonely にもマッチ、データ増加でスケールしない。

**見つけ方**: 「LIKEのワイルドカードの間に変数を挿入するには？」「語形違いにマッチする正規表現は？」「ドキュメントが増えると検索が耐えられないほど遅い」

**例外**: 使用頻度が極めて低くインデックス維持コストの方が高いクエリ。アドホックな調査クエリ。

**解決策**: 専用の全文検索機構を使う。

| 選択肢 | 使い分けの目安 |
|---|---|
| ベンダー拡張（MySQL `FULLTEXT` + `MATCH...AGAINST`、PostgreSQL `TSVECTOR` + GIN + `@@`、SQL Server `CONTAINS`、Oracle CONTEXT、SQLite FTS） | 使用中のDBに統合済み。単一製品依存でよいなら第一候補 |
| 独立検索エンジン（Elasticsearch/OpenSearch、Solr、Sphinx） | ベンダー中立・大規模・高度な検索要件 |
| 転置インデックス自作（Keywords + 交差テーブル + 同期トリガー） | 外部製品を入れられず軽量に済ませたい場合 |

```sql
-- MySQL
ALTER TABLE Bugs ADD FULLTEXT INDEX bugfts (summary, description);
SELECT * FROM Bugs WHERE MATCH(summary, description) AGAINST ('+crash -save' IN BOOLEAN MODE);
```

## 18. スパゲッティクエリ / Spaghetti Query

**症状**: 複雑な仕事を1つの「エレガントな」クエリで解こうとする。典型は複数の独立した集計の同時実行 — 無関係なテーブルを結合条件なしでJOINして**意図しないデカルト積**が発生し、COUNT/SUMが水増しされる。保守不能・最適化困難。

**見つけ方**: 「SUMやCOUNTがありえないほど大きい」「このクエリを書くのに丸1日かかった」「もう1つDISTINCTを追加してみよう」（水増しの誤魔化し）

**例外**: 単一クエリしか受け付けないBIツール・レポートコンポーネント。複数結果を1つのソート順で扱いたい場合。連番生成等の**意図的な** CROSS JOIN は正当。

**解決策**: 分割統治。無関係な集計は別々の単純なクエリに分ける（正確性の検証・要件追加・SQLエンジンの最適化すべてが楽になる）。行ごとに違う値の大量UPDATEは、巨大CASEでなく SELECT で UPDATE 文を生成して実行する手もある。UNIONは同じ列構造を縦に積む場合、CASEは行内の条件分岐に使い、「無関係な集計を1クエリに統合しない」が核心。

## 19. インプリシットカラム（暗黙の列） / Implicit Columns

**症状**: `SELECT *` と INSERT の列リスト省略。JOINで同名列（`b.title` と `a.title`）が衝突し連想配列受け取りで片方が消える。列の追加・削除・順序変更で `INSERT ... VALUES` が個数不一致エラーか**サイレントに誤った列へ格納**。序数アクセスのコードもずれる。不要列の転送で帯域も浪費。

**見つけ方**: 「古い列名で参照していて障害が起きた。漏れがあるかもしれない」「クエリが2MBフェッチしているが表示は1/10以下」

**例外**: 使い捨てのアドホッククエリ。`SELECT b.*, a.first_name` のような片側のみの限定使用。開発効率を実行時効率より優先すると明示的に判断した場合。

**解決策**: SELECT も INSERT も列名を明示する（ポカヨケ）。列順変更に影響されず、列追加に影響されず、列削除は**即座にエラーになって原因箇所が特定できる**（fail early）。関数・エイリアスが必要になった時点でどのみちワイルドカードは使えなくなるため、最初から明示する方が変更が楽。
