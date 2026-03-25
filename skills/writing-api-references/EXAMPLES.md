# API リファレンス 例集

良い例と悪い例を比較して、効果的なAPIリファレンスの書き方を示す。

---

## 目次

- [関数リファレンスの例](#関数リファレンスの例)
- [REST APIリファレンスの例](#rest-apiリファレンスの例)
- [クラスリファレンスの例](#クラスリファレンスの例)
- [悪い例と改善版](#悪い例と改善版)
- [作成後チェックリスト](#作成後チェックリスト)

---

## 関数リファレンスの例

```markdown
## formatDate

日付を指定されたフォーマットで文字列に変換する。

### シグネチャ

\`\`\`typescript
function formatDate(date: Date, format?: string): string
\`\`\`

### パラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| date | Date | Yes | フォーマットする日付 |
| format | string | No | 出力フォーマット（デフォルト: 'YYYY-MM-DD'） |

#### サポートされるフォーマット

| トークン | 出力 | 例 |
|---------|------|-----|
| YYYY | 4桁の年 | 2024 |
| MM | 2桁の月 | 01-12 |
| DD | 2桁の日 | 01-31 |
| HH | 2桁の時（24時間） | 00-23 |
| mm | 2桁の分 | 00-59 |
| ss | 2桁の秒 | 00-59 |

### 戻り値

`string` - フォーマットされた日付文字列

### 例

\`\`\`typescript
import { formatDate } from 'date-utils';

// デフォルトフォーマット
const date = new Date('2024-01-15T10:30:00');
console.log(formatDate(date));
// '2024-01-15'

// カスタムフォーマット
console.log(formatDate(date, 'YYYY/MM/DD HH:mm'));
// '2024/01/15 10:30'

// 時刻のみ
console.log(formatDate(date, 'HH:mm:ss'));
// '10:30:00'
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| TypeError | dateがDateオブジェクトでない場合 |
| FormatError | サポートされていないフォーマットトークンの場合 |

### 関連

- [parseDate](#parsedate) - 文字列を日付に変換
- [addDays](#adddays) - 日付に日数を加算
```

**この例が良い理由:**
- シグネチャで型が一目でわかる
- パラメータの型・必須/任意が表形式で整理されている
- フォーマットトークンのような固有の仕様が一覧表で示されている
- 3つの使用例がそれぞれ異なるユースケースをカバーしている
- 各例に期待される出力がコメントで付記されている
- エラーケースが条件とともに明記されている
- 関連APIへのリンクで探索を助けている

---

## REST APIリファレンスの例

```markdown
## POST /api/users

新しいユーザーを作成する。

### 認証

Bearer Tokenが必要。スコープ: `users:write`

### リクエスト

#### ヘッダー

| 名前 | 値 | 必須 |
|------|----|----|
| Content-Type | application/json | Yes |
| Authorization | Bearer {token} | Yes |

#### ボディ

\`\`\`json
{
  "email": "user@example.com",
  "name": "John Doe",
  "role": "member"
}
\`\`\`

| フィールド | 型 | 必須 | 説明 | 制約 |
|-----------|----|----|------|------|
| email | string | Yes | メールアドレス | 有効なメール形式、最大254文字 |
| name | string | Yes | 表示名 | 1-100文字 |
| role | string | No | ユーザーロール | `"admin"`, `"member"`, `"guest"` のいずれか。デフォルト: `"member"` |

### レスポンス

#### 成功 (201 Created)

\`\`\`json
{
  "id": "usr_abc123",
  "email": "user@example.com",
  "name": "John Doe",
  "role": "member",
  "createdAt": "2024-01-15T10:30:00Z"
}
\`\`\`

| フィールド | 型 | 説明 |
|-----------|----|----|
| id | string | ユーザーの一意識別子（`usr_` プレフィックス） |
| email | string | メールアドレス |
| name | string | 表示名 |
| role | string | ユーザーロール |
| createdAt | string (ISO 8601) | 作成日時 |

#### エラー (400 Bad Request)

\`\`\`json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request body",
    "details": [
      { "field": "email", "message": "Invalid email format" }
    ]
  }
}
\`\`\`

#### エラー (409 Conflict)

\`\`\`json
{
  "error": {
    "code": "EMAIL_EXISTS",
    "message": "A user with this email already exists"
  }
}
\`\`\`

### レート制限

1分あたり60リクエスト。超過時は `429 Too Many Requests` を返す。

### 例

\`\`\`bash
curl -X POST https://api.example.com/api/users \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-token-here" \
  -d '{
    "email": "user@example.com",
    "name": "John Doe"
  }'
\`\`\`

**レスポンス:**

\`\`\`json
{
  "id": "usr_abc123",
  "email": "user@example.com",
  "name": "John Doe",
  "role": "member",
  "createdAt": "2024-01-15T10:30:00Z"
}
\`\`\`
```

**この例が良い理由:**
- 認証方式とスコープが明記されている
- ヘッダー、ボディが表形式で整理されている
- フィールドに制約条件が記載されている（文字数、列挙値）
- レスポンスフィールドにも型と説明がある
- 複数のエラーレスポンスがステータスコード別に示されている
- レート制限情報がある
- curlの完全な実行例がある

---

## クラスリファレンスの例

```markdown
## HttpClient

HTTP通信を行うクライアント。接続プール管理、リトライ、タイムアウトを内蔵する。

### コンストラクタ

\`\`\`typescript
new HttpClient(options?: HttpClientOptions)
\`\`\`

| パラメータ | 型 | 必須 | 説明 |
|-----------|----|----|------|
| options.baseUrl | string | No | リクエストのベースURL |
| options.timeout | number | No | タイムアウト（ミリ秒、デフォルト: 30000） |
| options.retries | number | No | リトライ回数（デフォルト: 3） |
| options.headers | Record<string, string> | No | 全リクエストに付与するヘッダー |

### プロパティ

| 名前 | 型 | 説明 |
|------|----|----|
| baseUrl | string \| undefined | 読み取り専用。設定されたベースURL |
| isConnected | boolean | 読み取り専用。接続状態 |

### メソッド

#### get\<T\>(path, options?)

指定パスにGETリクエストを送信する。

\`\`\`typescript
client.get<T>(path: string, options?: RequestOptions): Promise<Response<T>>
\`\`\`

**パラメータ:**
| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| path | string | Yes | リクエストパス |
| options.headers | Record<string, string> | No | 追加ヘッダー |
| options.params | Record<string, string> | No | クエリパラメータ |

**戻り値:** `Promise<Response<T>>` - レスポンスオブジェクト

#### post\<T\>(path, body, options?)

指定パスにPOSTリクエストを送信する。

\`\`\`typescript
client.post<T>(path: string, body: unknown, options?: RequestOptions): Promise<Response<T>>
\`\`\`

**パラメータ:**
| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| path | string | Yes | リクエストパス |
| body | unknown | Yes | リクエストボディ（JSON変換される） |
| options.headers | Record<string, string> | No | 追加ヘッダー |

**戻り値:** `Promise<Response<T>>` - レスポンスオブジェクト

#### close()

接続プールを解放し、クライアントを終了する。使用後に呼び出す。

\`\`\`typescript
client.close(): Promise<void>
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| TimeoutError | リクエストがタイムアウトした場合 |
| ConnectionError | サーバーに接続できない場合 |
| HttpError | サーバーが4xx/5xxを返した場合（statusCodeプロパティあり） |

### 例

\`\`\`typescript
import { HttpClient } from 'http-client';

// 基本的な使用
const client = new HttpClient({
  baseUrl: 'https://api.example.com',
  timeout: 5000,
});

// GETリクエスト
const users = await client.get<User[]>('/users', {
  params: { limit: '10' },
});
console.log(users.data);
// [{ id: 'usr_1', name: 'Alice' }, { id: 'usr_2', name: 'Bob' }]

// POSTリクエスト
const newUser = await client.post<User>('/users', {
  name: 'Charlie',
  email: 'charlie@example.com',
});
console.log(newUser.data);
// { id: 'usr_3', name: 'Charlie', email: 'charlie@example.com' }

// エラーハンドリング
try {
  await client.get('/users/nonexistent');
} catch (error) {
  if (error instanceof HttpError && error.statusCode === 404) {
    console.log('User not found');
  }
}

// 使用後にクリーンアップ
await client.close();
\`\`\`
```

**この例が良い理由:**
- クラスの役割を冒頭の一文で明確にしている
- コンストラクタオプションがネストされたプロパティまで記載されている
- 各メソッドにシグネチャ・パラメータ・戻り値がある
- ジェネリクス（`<T>`）の使い方が示されている
- エラー一覧が包括的
- 使用例がGET/POST/エラーハンドリング/クリーンアップまでカバーしている

---

## 悪い例と改善版

### パターン1: 型情報がない

**悪い例:**
```markdown
## formatDate

日付をフォーマットします。

### パラメータ

- date - 日付
- format - フォーマット

### 使用例

\`\`\`javascript
formatDate(date, format);
\`\`\`
```

**問題点:**
- 型情報がない（dateは何型？formatは何型？）
- 必須/任意が分からない
- 使用例が動かない（変数が未定義、具体的な値がない）
- 戻り値の説明がない
- 「〜します」で始まっている（スタイルガイド違反）

**改善版:** 本ファイル冒頭の[関数リファレンスの例](#関数リファレンスの例)を参照。

---

### パターン2: 省略されたコード例

**悪い例:**
```markdown
## getUserById

ユーザーを取得する。

### 使用例

\`\`\`typescript
const user = await getUserById(id);
// ユーザー情報を処理...
\`\`\`
```

**問題点:**
- `id` が未定義（何を渡せばいいかわからない）
- `...` で省略されている（実際に何が返るかわからない）
- 期待される戻り値が示されていない

**改善版:**
```markdown
## getUserById

指定されたIDのユーザー情報を取得する。ユーザーが存在しない場合は `UserNotFoundError` をスローする。

### シグネチャ

\`\`\`typescript
function getUserById(id: string): Promise<User>
\`\`\`

### パラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| id | string | Yes | ユーザーID（`usr_` プレフィックス） |

### 戻り値

`Promise<User>` - ユーザー情報

\`\`\`typescript
interface User {
  id: string;
  name: string;
  email: string;
  createdAt: Date;
}
\`\`\`

### 例

\`\`\`typescript
const user = await getUserById('usr_abc123');
console.log(user);
// {
//   id: 'usr_abc123',
//   name: 'John',
//   email: 'john@example.com',
//   createdAt: 2024-01-15T10:30:00.000Z
// }
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| UserNotFoundError | 指定されたIDのユーザーが存在しない場合 |
| ValidationError | IDの形式が不正な場合 |
```

---

### パターン3: 曖昧な説明

**悪い例:**
```markdown
## processData

データを処理する関数です。

### パラメータ

| 名前 | 説明 |
|------|------|
| data | 処理するデータ |
| options | オプション |

### 戻り値

処理結果
```

**問題点:**
- 「処理する」が曖昧（何を何にするのか不明）
- 「関数です」は冗長
- 型情報がない
- 「処理結果」では何が返るかわからない
- optionsの中身が不明

**改善版:**
```markdown
## processData

JSON配列をCSV形式に変換する。

### シグネチャ

\`\`\`typescript
function processData(data: object[], options?: ProcessOptions): string
\`\`\`

### パラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| data | object[] | Yes | 変換するJSONオブジェクトの配列 |
| options.delimiter | string | No | 区切り文字（デフォルト: `','`） |
| options.header | boolean | No | ヘッダー行を含めるか（デフォルト: `true`） |
| options.encoding | string | No | 出力エンコーディング（デフォルト: `'utf-8'`） |

### 戻り値

`string` - CSV形式の文字列。改行コードはLF。

### 例

\`\`\`typescript
const data = [
  { name: 'Alice', age: 30 },
  { name: 'Bob', age: 25 },
];

// デフォルト（カンマ区切り、ヘッダーあり）
console.log(processData(data));
// name,age
// Alice,30
// Bob,25

// TSV形式
console.log(processData(data, { delimiter: '\t', header: false }));
// Alice	30
// Bob	25
\`\`\`
```

---

### パターン4: ビフォー・アフター全体比較

**Before:**
```markdown
## createUser

ユーザーを作成します。

パラメータ: email, password, name

戻り値: ユーザーオブジェクト
```

**After:**
```markdown
## createUser

新しいユーザーアカウントを作成する。

### シグネチャ

\`\`\`typescript
function createUser(params: CreateUserParams): Promise<User>
\`\`\`

### パラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| email | string | Yes | メールアドレス（一意） |
| password | string | Yes | パスワード（8文字以上、英数字混在） |
| name | string | Yes | 表示名（1-50文字） |

### 戻り値

`Promise<User>` - 作成されたユーザー

\`\`\`typescript
interface User {
  id: string;
  email: string;
  name: string;
  createdAt: Date;
}
\`\`\`

### 例

\`\`\`typescript
const user = await createUser({
  email: 'user@example.com',
  password: 'securepass123',
  name: 'John Doe'
});

console.log(user);
// {
//   id: 'usr_abc123',
//   email: 'user@example.com',
//   name: 'John Doe',
//   createdAt: 2024-01-15T10:30:00.000Z
// }
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| ValidationError | パラメータが制約を満たさない場合 |
| EmailExistsError | メールアドレスが既に使用されている場合 |
```

---

## 作成後チェックリスト

APIリファレンスを作成・レビューした後、以下を確認する:

### 必須項目
- [ ] シグネチャ（型付き）が示されているか
- [ ] すべてのパラメータに型と説明があるか
- [ ] 必須/任意が明記されているか
- [ ] デフォルト値が示されているか（任意パラメータ）
- [ ] 戻り値に型と説明があるか
- [ ] 使用例がコピペで動くか（未定義変数がないか）
- [ ] 使用例に期待される出力がコメントで示されているか
- [ ] エラーケースが条件とともに列挙されているか

### 推奨項目
- [ ] 複数の使用例があるか（基本・オプション付き・エラーハンドリング）
- [ ] 複雑な戻り値の型がインターフェース定義で展開されているか
- [ ] 制約条件が記載されているか（文字数制限、範囲、パターン）
- [ ] 関連APIへのリンクがあるか
- [ ] REST APIの場合、認証方式が明記されているか
- [ ] REST APIの場合、レスポンスフィールドに型と説明があるか
