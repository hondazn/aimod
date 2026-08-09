# README 例集

良い例と悪い例を比較して、効果的なREADMEの書き方を学ぶ。

---

## 良い例

### 例1: シンプルで明確（JavaScript ライブラリ）

```markdown
# fastjson

JSONを高速にパース・シリアライズする。標準ライブラリの3倍高速。

## インストール

\`\`\`bash
npm install fastjson
\`\`\`

## 使い方

\`\`\`javascript
import { parse, stringify } from 'fastjson';

const data = parse('{"name": "test"}');
console.log(data); // { name: 'test' }

const json = stringify({ name: 'test' });
console.log(json); // '{"name":"test"}'
\`\`\`

## ライセンス

MIT
```

**なぜ良いか:**
- 冒頭で「何をするか」「なぜ使うか（3倍高速）」が一目で分かる
- コード例がコピペで動き、入力と出力の両方が示されている
- 必要最小限の情報に絞っている

### 例2: 機能が豊富でも整理されている（TypeScript ライブラリ）

```markdown
# dataflow

データパイプラインを宣言的に構築する。

## 特徴

- **宣言的なAPI**: メソッドチェーンでパイプラインを記述
- **型安全**: TypeScriptで完全な型推論を提供
- **プラグインで拡張可能**: カスタム変換を追加可能

## クイックスタート

\`\`\`typescript
import { pipeline, transform, filter } from 'dataflow';

const result = pipeline([1, 2, 3, 4, 5])
  .pipe(filter(x => x > 2))
  .pipe(transform(x => x * 2))
  .collect();

console.log(result); // [6, 8, 10]
\`\`\`

## ドキュメント

- [API リファレンス](./docs/api.md)
- [プラグイン開発](./docs/plugins.md)
```

**なぜ良いか:**
- 特徴を3つに絞り、それぞれに具体的な説明がある
- コード例が実用的なシナリオを示し、期待される出力も含まれている
- 詳細は別ドキュメントにリンクし、READMEを軽量に保っている

### 例3: CLIツール

```markdown
# imgopt

画像を一括最適化する。

\`\`\`bash
imgopt ./images --quality 80 --format webp
\`\`\`

## インストール

\`\`\`bash
npm install -g imgopt
\`\`\`

## 使い方

\`\`\`bash
# 基本
imgopt ./images

# 品質指定
imgopt ./images --quality 80

# フォーマット変換
imgopt ./images --format webp
\`\`\`

## オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--quality, -q` | 圧縮品質 (1-100) | 85 |
| `--format, -f` | 出力形式 | 元のまま |
| `--output, -o` | 出力先 | 上書き |
```

**なぜ良いか:**
- 冒頭に実行例があり、何ができるか即座に分かる
- オプションが表形式で見やすく、デフォルト値も明記されている
- コマンド例が段階的に複雑になり、学習しやすい

### 例4: Python ライブラリ

```markdown
# tableforge

CSVとExcelファイルを相互変換・加工する。pandasの10分の1のメモリで動作。

## インストール

\`\`\`bash
pip install tableforge
\`\`\`

## 使い方

\`\`\`python
from tableforge import read_csv, to_excel

# CSVを読み込んでExcelに変換
data = read_csv("sales.csv")
data.filter(lambda row: row["amount"] > 1000)
data.to_excel("sales_filtered.xlsx")

print(f"処理件数: {len(data)}")  # 処理件数: 42
\`\`\`

## ライセンス

Apache-2.0
```

**なぜ良いか:**
- 「pandasの10分の1のメモリ」という具体的な差別化
- Python の慣習に沿った例（pip install、from ... import）
- 実用的なシナリオ（CSVの読み込み、フィルタ、Excel出力）

### 例5: Go CLIツール

```markdown
# dbmigrate

データベースマイグレーションを管理する。

\`\`\`bash
dbmigrate up --to latest
\`\`\`

## インストール

\`\`\`bash
go install github.com/example/dbmigrate@latest
\`\`\`

## 使い方

\`\`\`bash
# マイグレーションファイルを作成
dbmigrate new add_users_table

# マイグレーションを実行
dbmigrate up

# ロールバック
dbmigrate down --steps 1

# 状態を確認
dbmigrate status
\`\`\`

## 設定

`dbmigrate.yaml` をプロジェクトルートに配置:

\`\`\`yaml
database:
  driver: postgres
  url: ${DATABASE_URL}
migrations:
  dir: ./migrations
\`\`\`

## ライセンス

MIT
```

**なぜ良いか:**
- Go の慣習に沿ったインストール方法（go install）
- 典型的なワークフロー（作成→実行→ロールバック→確認）を順序立てて提示
- 設定ファイルの例が具体的で、環境変数の使い方も示されている

---

## 悪い例

### 例1: 冗長な説明

```markdown
# MyProject

## はじめに

このプロジェクトは、現代のウェブ開発において非常に重要な課題である
データ処理の効率化を目指して開発されました。近年、データ量の増大に
伴い、従来の手法では対応が困難になってきています。そこで本プロジェクト
では、最新のアルゴリズムを採用し、高速かつ効率的なデータ処理を実現
しています。

## 背景

従来のデータ処理手法には以下のような問題がありました...
（長い説明が続く）
```

**何が問題か:**
- 5行読んでも何をするプロジェクトか分からない（読者はここで離脱する）
- 背景説明が長すぎて、使い方にたどり着けない
- 「はじめに」「背景」は README に不要なセクション

**改善版:**
```markdown
# MyProject

データを高速に変換・集計する。従来手法の5倍高速。

## インストール
...
```

### 例2: 動かないコード例

```markdown
## 使い方

\`\`\`javascript
import { process } from 'mylib';

// データを処理
const result = process(data);
// ...その他の処理
\`\`\`
```

**何が問題か:**
- `data` が未定義で、何を渡せばいいか分からない
- `...その他の処理` で省略されていて、全体像が見えない
- コピペしても動かないので、読者は自力で補完する必要がある

**改善版:**
```markdown
\`\`\`javascript
import { process } from 'mylib';

const data = { name: 'test', value: 123 };
const result = process(data);
console.log(result); // { name: 'TEST', value: 246 }
\`\`\`
```

### 例3: 具体性のない機能の羅列

```markdown
## 特徴

- 高速
- 軽量
- 使いやすい
- モダン
- 拡張可能
- 型安全
- テスト済み
- ドキュメント完備
- コミュニティサポート
- クロスプラットフォーム
- プラグインシステム
- カスタマイズ可能
```

**何が問題か:**
- 12個もあるが、どれも「どのくらい？」が分からない
- 他のどのプロジェクトにも当てはまる汎用的な言葉ばかり
- 読者は「で、具体的に何が良いの？」と思う

**改善版:**
```markdown
## 特徴

- **10倍高速**: 独自のストリーミングパーサーで従来手法を大幅に上回る
- **型安全**: TypeScriptで完全な型推論を提供、エディタ補完が効く
- **プラグイン対応**: 20行で独自の変換処理を追加できる
```

---

## 改善ビフォー・アフター

### Before

```markdown
# DataProcessor

## About

DataProcessorは、様々なデータ処理タスクを実行するための
汎用的なライブラリです。JSONやCSVなど、多くのフォーマットに
対応しており、柔軟な設定が可能です。

## Installation

npmを使用してインストールできます:

\`\`\`
npm install dataprocessor
\`\`\`

## Usage

基本的な使い方:

\`\`\`javascript
const dp = require('dataprocessor');
dp.process(data, options);
\`\`\`

詳しくはドキュメントを参照してください。
```

### After

```markdown
# DataProcessor

JSON・CSVを変換・フィルタリング・集計する。

## インストール

\`\`\`bash
npm install dataprocessor
\`\`\`

## 使い方

\`\`\`javascript
import { transform } from 'dataprocessor';

// JSONをCSVに変換
const csv = transform([
  { name: 'Alice', age: 30 },
  { name: 'Bob', age: 25 }
], { format: 'csv' });

console.log(csv);
// name,age
// Alice,30
// Bob,25
\`\`\`

## API

- `transform(data, options)` - フォーマット変換
- `filter(data, predicate)` - 条件でフィルタ
- `aggregate(data, key)` - キーで集計

詳細: [API リファレンス](./docs/api.md)

## ライセンス

MIT
```

**何が改善されたか:**
- 冒頭を動詞で始めて、何をするライブラリか一目で分かるようにした
- `About` セクションを削除し、冗長な説明を排除した
- コード例に具体的な入力データと出力を追加した
- `require` を `import` に更新した（モダンなスタイルに）
- APIの概要を追加し、ライブラリの全体像を示した

---

## チェックリスト

README作成後、以下を確認:

- [ ] 冒頭で「何をするか」が一文で分かるか
- [ ] インストールコマンドがプロジェクトの実際のパッケージマネージャーに合っているか
- [ ] コード例がコピペで動くか（変数定義、import文、期待される出力が全て含まれているか）
- [ ] 特徴は3〜5個に絞られ、それぞれに具体的な数値や比較が含まれているか
- [ ] 冗長な説明がないか（「はじめに」「背景」「このプロジェクトは〜」がないか）
- [ ] 見出しレベルは適切か（H1はプロジェクト名のみ、H2で主要セクション）
- [ ] 言語が統一されているか（日本語なら全て日本語、英語なら全て英語）
