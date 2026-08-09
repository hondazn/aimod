# API ドキュメント スタイルガイド

APIリファレンスを書く際の一貫したスタイルを定義する。迷ったときはこのガイドに従う。

---

## 目次

- [説明の書き方](#説明の書き方)
- [命名規則](#命名規則)
- [型の表記](#型の表記)
- [表の形式](#表の形式)
- [コード例の形式](#コード例の形式)
- [エラーの記載](#エラーの記載)
- [REST API固有のルール](#rest-api固有のルール)
- [一貫性チェックリスト](#一貫性チェックリスト)

---

## 説明の書き方

### 一文目のルール

動詞で始め、「する」で終わる。主語（「この関数は」等）を省略して簡潔にする。これにより、多くのAPIを一覧で読む際のスキャン速度が上がる。

```
良い例:
  ユーザーを取得する。
  新しい注文を作成する。
  指定されたIDのアイテムを削除する。

避ける:
  ユーザーを取得します。          → 「〜する」に統一
  この関数はユーザーを取得する。  → 主語は不要
  ユーザーの取得                  → 体言止めは避ける
```

### 詳細説明

一文目だけでは伝わらない振る舞いがある場合、空行の後に補足を追加する。内部実装ではなく、利用者が知るべき振る舞い（副作用、エッジケース、前提条件）を記述する。

```markdown
## getUser

ユーザーを取得する。

指定されたIDに対応するユーザー情報を返す。
ユーザーが存在しない場合は `UserNotFoundError` をスローする。
削除済みユーザーは取得できない。
```

### 用語の一貫性

同じ概念には同じ用語を使う。1つのドキュメント内で表記が揺れると読者が混乱する。

```
統一する:
  「パラメータ」と「引数」 → どちらかに統一（推奨: パラメータ）
  「返す」と「戻す」 → どちらかに統一（推奨: 返す）
  「スローする」と「投げる」 → どちらかに統一（推奨: スローする）
```

---

## 命名規則

### パラメータ名

```
推奨: camelCase

良い例: userId, createdAt, maxRetries
避ける: user_id, CreatedAt, MAXRETRIES
```

ただし、Pythonドキュメントでは snake_case を使う。言語の慣例に合わせる。

### エンドポイント

```
推奨: kebab-case + 複数形

良い例:
  GET /api/users
  GET /api/user-profiles
  POST /api/order-items

避ける:
  GET /api/User
  GET /api/userProfiles
  POST /api/OrderItem
```

### 型名

```
推奨: PascalCase

良い例: User, OrderItem, CreateUserParams
避ける: user, order_item, createUserParams
```

---

## 型の表記

### プリミティブ型

```
string    - 文字列
number    - 数値（整数・浮動小数点）
boolean   - 真偽値
null      - null
undefined - undefined（TypeScript）
```

### 配列

```
推奨: T[] 形式（シンプルな型の場合）
  string[]
  User[]

複合型の場合: Array<T> 形式
  Array<string | number>
  Array<{ id: string; name: string }>
```

### オプショナル

```
TypeScript: string | undefined, User?
Python:     Optional[str], str | None (3.10+)
Go:         *string (ポインタ)
Rust:       Option<String>
```

### オブジェクト / 構造体

複雑な型はインターフェース定義を示す。フィールドごとにコメントで説明を付けると、表と照らし合わせなくても理解できる。

```typescript
interface User {
  id: string;           // ユーザーの一意識別子
  name: string;         // 表示名
  email?: string;       // メールアドレス（オプショナル）
  role: 'admin' | 'member' | 'guest';  // ユーザーロール
}
```

---

## 表の形式

### パラメータ表

```markdown
| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| id | string | Yes | ユーザーID |
| name | string | No | 表示名（デフォルト: ''） |
| options.limit | number | No | 取得件数（デフォルト: 20、最大: 100） |
```

ルール:
- 型は常に記載する（型がないパラメータ表は不完全）
- 必須は `Yes` / `No` で統一する（`Required` / `Optional` や記号は使わない）
- デフォルト値は説明欄に `（デフォルト: 値）` の形式で記載する
- 制約条件（最大値、文字数、パターン等）も説明欄に記載する
- ネストされたオプションは `options.limit` のようにドット記法で表す

### レスポンスフィールド表

```markdown
| フィールド | 型 | 説明 |
|-----------|----|----|
| id | string | 一意の識別子 |
| createdAt | string (ISO 8601) | 作成日時 |
| items | OrderItem[] | 注文アイテムの配列 |
```

---

## コード例の形式

### 基本構造

使用例は「コピペしてそのまま動く」ことが最も重要。未定義の変数を使わず、必要なインポートも含める。

```typescript
import { getUser } from 'user-service';

// コメントで何をしているか説明
const user = await getUser('usr_abc123');
console.log(user);
// { id: 'usr_abc123', name: 'John', email: 'john@example.com' }
```

### 複数例の場合

ユースケースが異なる例を、基本 -> 応用 -> エラーハンドリングの順に記載する。

```typescript
import { getUser, getUsers } from 'user-service';

// 基本的な使用
const user = await getUser('usr_123');

// オプション付き
const users = await getUsers({ limit: 10, offset: 0 });

// エラーハンドリング
try {
  const user = await getUser('invalid');
} catch (error) {
  if (error instanceof UserNotFoundError) {
    console.log('User not found');
  }
}
```

### 出力の示し方

期待される出力は `//` コメントで示す。JSONオブジェクトの場合は整形して読みやすくする。

```typescript
console.log(result);
// {
//   id: 'usr_abc123',
//   name: 'John',
//   items: ['item_1', 'item_2']
// }
```

---

## エラーの記載

### エラー表（関数/メソッド用）

```markdown
| エラー | 条件 |
|--------|------|
| ValidationError | 入力が制約を満たさない場合 |
| NotFoundError | 指定されたリソースが存在しない場合 |
| AuthError | 認証が失敗した場合 |
```

### エラー表（REST API用）

HTTPステータスコードを含める。

```markdown
| ステータス | エラーコード | 説明 |
|-----------|------------|------|
| 400 | VALIDATION_ERROR | リクエストが不正 |
| 401 | UNAUTHORIZED | 認証が必要または無効 |
| 403 | FORBIDDEN | 権限が不足 |
| 404 | NOT_FOUND | リソースが存在しない |
| 409 | CONFLICT | 重複や競合 |
| 429 | RATE_LIMIT_EXCEEDED | レート制限超過 |
```

### エラーレスポンスの例

エラーレスポンスのJSON構造も示す。利用者はエラーハンドリングのコードを書くためにこの構造を知る必要がある。

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input",
    "details": [
      { "field": "email", "message": "Invalid format" }
    ]
  }
}
```

---

## REST API固有のルール

### HTTPメソッドの使い分け

| メソッド | 用途 | 冪等性 |
|---------|------|--------|
| GET | リソースの取得 | Yes |
| POST | リソースの作成 | No |
| PUT | リソースの完全置換 | Yes |
| PATCH | リソースの部分更新 | No |
| DELETE | リソースの削除 | Yes |

### ステータスコード

```
成功:
  200 OK           - 取得/更新成功
  201 Created      - 作成成功（LocationヘッダーにリソースのURLを含める）
  204 No Content   - 削除成功（レスポンスボディなし）

クライアントエラー:
  400 Bad Request   - リクエストが不正
  401 Unauthorized  - 認証が必要
  403 Forbidden     - 権限がない
  404 Not Found     - リソースが存在しない
  409 Conflict      - 競合（例: 重複）
  422 Unprocessable Entity - バリデーションエラー（400と使い分ける場合）
  429 Too Many Requests    - レート制限超過

サーバーエラー:
  500 Internal Server Error - サーバー内部エラー
  503 Service Unavailable   - サービス一時停止
```

### パスパラメータ vs クエリパラメータ

```
パスパラメータ: リソースの識別に使用
  GET /users/{id}
  GET /orders/{orderId}/items/{itemId}

クエリパラメータ: フィルタ、ページネーション、ソート、オプションに使用
  GET /users?limit=10&offset=0
  GET /products?category=electronics&sort=price&order=desc
```

### 認証方式の記載

ドキュメントの冒頭または各エンドポイントに認証方式を明記する。

```markdown
### 認証

Bearer Tokenが必要。`Authorization: Bearer {token}` ヘッダーで送信する。
トークンの取得は [認証ガイド](#認証ガイド) を参照。
```

### ページネーション

ページネーションがあるエンドポイントでは、パラメータとレスポンスの両方にページネーション情報を記載する。

```markdown
#### クエリパラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| limit | number | No | 取得件数（デフォルト: 20、最大: 100） |
| cursor | string | No | 次ページのカーソル（前回レスポンスの `nextCursor`） |

#### レスポンス

| フィールド | 型 | 説明 |
|-----------|----|----|
| data | User[] | ユーザーの配列 |
| nextCursor | string \| null | 次ページのカーソル。最終ページの場合は `null` |
| hasMore | boolean | 次のページがあるか |
```

---

## 一貫性チェックリスト

ドキュメント全体の一貫性を確認する際に使用する。

```
命名:
  - [ ] パラメータ名がcamelCaseか（Python以外）
  - [ ] 型名がPascalCaseか
  - [ ] エンドポイントがkebab-caseで複数形か

説明:
  - [ ] 説明が動詞で始まっているか（「〜する」で終わる）
  - [ ] 同じ概念に同じ用語を使っているか
  - [ ] 冗長な主語（「この関数は」等）がないか

表:
  - [ ] すべてのパラメータに型があるか
  - [ ] 必須/任意がYes/Noで統一されているか
  - [ ] デフォルト値が説明欄に記載されているか

例:
  - [ ] コード例に未定義変数がないか
  - [ ] コード例に期待される出力があるか
  - [ ] import文が含まれているか
```
