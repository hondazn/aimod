# API リファレンス テンプレート集

用途に応じたテンプレートを選択する。プレースホルダー（`[説明]` 等）を実際の内容に置き換えて使用する。

---

## 目次

- [関数テンプレート](#関数テンプレート)
- [クラステンプレート](#クラステンプレート)
- [REST APIテンプレート](#rest-apiテンプレート)
- [GraphQL テンプレート](#graphql-テンプレート)
- [OpenAPI (Swagger) 形式テンプレート](#openapi-swagger-形式テンプレート)
- [選択ガイド](#選択ガイド)

---

## 関数テンプレート

単独の関数/メソッド用。

```markdown
## functionName

[関数の説明を一文で。動詞で始め「する」で終わる]

### シグネチャ

\`\`\`typescript
function functionName(param1: Type1, param2?: Type2): ReturnType
\`\`\`

### パラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| param1 | Type1 | Yes | [説明] |
| param2 | Type2 | No | [説明]（デフォルト: [値]） |

### 戻り値

`ReturnType` - [戻り値の説明]

### 例

\`\`\`typescript
import { functionName } from '[module]';

// 基本的な使用
const result = functionName('input');
console.log(result);
// [期待される出力]

// オプション付き
const result2 = functionName('input', { option: true });
console.log(result2);
// [期待される出力]
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| ErrorName | [発生条件] |

### 関連

- [relatedFunction](#relatedfunction) - [簡潔な説明]
```

---

## クラステンプレート

クラス全体用。メソッドが多い場合は、メソッド一覧表を冒頭に追加する。

```markdown
## ClassName

[クラスの説明を一文で]

### コンストラクタ

\`\`\`typescript
new ClassName(options?: Options)
\`\`\`

| パラメータ | 型 | 必須 | 説明 |
|-----------|----|----|------|
| options.key1 | Type | No | [説明]（デフォルト: [値]） |
| options.key2 | Type | No | [説明]（デフォルト: [値]） |

### プロパティ

| 名前 | 型 | 説明 |
|------|----|----|
| property1 | Type | [説明]。読み取り専用 |
| property2 | Type | [説明] |

### メソッド

#### methodName(param)

[メソッドの説明]

\`\`\`typescript
instance.methodName(param: Type): ReturnType
\`\`\`

**パラメータ:**

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| param | Type | Yes | [説明] |

**戻り値:** `ReturnType` - [説明]

#### anotherMethod()

[メソッドの説明]

\`\`\`typescript
instance.anotherMethod(): void
\`\`\`

### エラー

| エラー | 条件 |
|--------|------|
| ErrorName | [発生条件] |

### 例

\`\`\`typescript
import { ClassName } from '[module]';

// インスタンス化
const instance = new ClassName({ key1: 'value' });

// メソッドの使用
const result = instance.methodName('param');
console.log(result);
// [期待される出力]

// クリーンアップ（必要な場合）
instance.anotherMethod();
\`\`\`
```

---

## REST APIテンプレート

HTTPエンドポイント用。認証、レート制限、ページネーションのセクションは該当する場合のみ記載する。

```markdown
## POST /api/resource

[エンドポイントの説明]

### 認証

[認証方式]。スコープ: `[required:scope]`

### リクエスト

#### ヘッダー

| 名前 | 値 | 必須 |
|------|----|----|
| Authorization | Bearer {token} | Yes |
| Content-Type | application/json | Yes |

#### パスパラメータ

| 名前 | 型 | 説明 |
|------|----|----|
| id | string | リソースID |

#### クエリパラメータ

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| limit | number | No | 取得件数（デフォルト: 20、最大: 100） |
| offset | number | No | オフセット（デフォルト: 0） |

#### ボディ

\`\`\`json
{
  "field1": "string",
  "field2": 123
}
\`\`\`

| フィールド | 型 | 必須 | 説明 | 制約 |
|-----------|----|----|------|------|
| field1 | string | Yes | [説明] | [制約] |
| field2 | number | No | [説明] | [制約] |

### レスポンス

#### 成功 (201 Created)

\`\`\`json
{
  "id": "abc123",
  "field1": "string",
  "createdAt": "2024-01-01T00:00:00Z"
}
\`\`\`

| フィールド | 型 | 説明 |
|-----------|----|----|
| id | string | 作成されたリソースのID |
| field1 | string | [説明] |
| createdAt | string (ISO 8601) | 作成日時 |

#### エラー

| ステータス | エラーコード | 説明 |
|-----------|------------|------|
| 400 | VALIDATION_ERROR | リクエストが不正 |
| 401 | UNAUTHORIZED | 認証が無効 |
| 409 | CONFLICT | リソースが重複 |

エラーレスポンスの形式:

\`\`\`json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": [{ "field": "fieldName", "message": "Error detail" }]
  }
}
\`\`\`

### レート制限

[X]リクエスト/[期間]。超過時は `429 Too Many Requests` を返す。
`X-RateLimit-Remaining` ヘッダーで残りリクエスト数を確認可能。

### 例

\`\`\`bash
curl -X POST https://api.example.com/api/resource \
  -H "Authorization: Bearer token123" \
  -H "Content-Type: application/json" \
  -d '{"field1": "value", "field2": 123}'
\`\`\`

**レスポンス:**

\`\`\`json
{
  "id": "abc123",
  "field1": "value",
  "createdAt": "2024-01-15T10:30:00Z"
}
\`\`\`
```

---

## GraphQL テンプレート

GraphQL Query/Mutation用。

```markdown
## createUser (Mutation)

新しいユーザーを作成する。

### 定義

\`\`\`graphql
mutation CreateUser($input: CreateUserInput!) {
  createUser(input: $input) {
    id
    email
    name
    createdAt
  }
}
\`\`\`

### 引数

| 名前 | 型 | 必須 | 説明 |
|------|----|----|------|
| input | CreateUserInput! | Yes | ユーザー作成パラメータ |

#### CreateUserInput

| フィールド | 型 | 必須 | 説明 |
|-----------|----|----|------|
| email | String! | Yes | メールアドレス |
| name | String! | Yes | 表示名（1-50文字） |
| role | UserRole | No | ロール（デフォルト: MEMBER） |

#### UserRole (enum)

| 値 | 説明 |
|-----|------|
| ADMIN | 管理者 |
| MEMBER | 一般メンバー |
| GUEST | ゲスト |

### 戻り値の型

#### User

| フィールド | 型 | 説明 |
|-----------|----|----|
| id | ID! | ユーザーの一意識別子 |
| email | String! | メールアドレス |
| name | String! | 表示名 |
| createdAt | DateTime! | 作成日時（ISO 8601） |

### エラー

| エラーコード | 説明 |
|------------|------|
| VALIDATION_ERROR | 入力が不正 |
| EMAIL_EXISTS | メールアドレスが既に使用されている |

### 例

\`\`\`graphql
mutation {
  createUser(input: {
    email: "user@example.com"
    name: "John Doe"
  }) {
    id
    email
    name
    createdAt
  }
}
\`\`\`

**レスポンス:**

\`\`\`json
{
  "data": {
    "createUser": {
      "id": "usr_abc123",
      "email": "user@example.com",
      "name": "John Doe",
      "createdAt": "2024-01-15T10:30:00Z"
    }
  }
}
\`\`\`
```

---

## OpenAPI (Swagger) 形式テンプレート

OpenAPI 3.0仕様に準拠した形式。Swagger UIやコード自動生成ツールと連携する場合に使用する。

```yaml
openapi: '3.0.3'
info:
  title: [API名]
  version: '1.0.0'
  description: [API全体の説明]

paths:
  /api/resource:
    post:
      operationId: createResource
      summary: リソースを作成する
      description: 新しいリソースを作成して返す
      tags:
        - Resource
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - field1
              properties:
                field1:
                  type: string
                  description: [説明]
                  maxLength: 100
                field2:
                  type: number
                  description: [説明]
            example:
              field1: "value"
              field2: 123
      responses:
        '201':
          description: 作成成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Resource'
        '400':
          description: バリデーションエラー
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
        '401':
          description: 認証エラー

components:
  schemas:
    Resource:
      type: object
      properties:
        id:
          type: string
          description: リソースID
        field1:
          type: string
        createdAt:
          type: string
          format: date-time
          description: 作成日時
    Error:
      type: object
      properties:
        error:
          type: object
          properties:
            code:
              type: string
            message:
              type: string
            details:
              type: array
              items:
                type: object
                properties:
                  field:
                    type: string
                  message:
                    type: string

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

---

## 選択ガイド

| テンプレート | 用途 | 選択基準 |
|-------------|------|---------|
| 関数 | 単独の関数、ユーティリティ関数 | ライブラリやモジュールの個別関数を文書化する場合 |
| クラス | オブジェクト指向のクラス | 状態を持つオブジェクトや複数メソッドをまとめて文書化する場合 |
| REST API | HTTPエンドポイント | Web APIの仕様書を人間向けに書く場合 |
| GraphQL | GraphQL Query/Mutation | GraphQLスキーマのドキュメントを書く場合 |
| OpenAPI | 機械可読なAPI仕様 | Swagger UI連携、クライアントコード自動生成、CI/CD検証が必要な場合 |

複数の形式が必要な場合（例: 人間向けのREST APIドキュメント + 機械向けのOpenAPI仕様）は、両方を作成する。OpenAPIからMarkdownを自動生成するアプローチもある。

---

## 命名規則

### 関数/メソッド

```
動詞 + 名詞

例:
  getUser       - 取得
  createOrder   - 作成
  updateProfile - 更新
  deleteItem    - 削除
  validateInput - 検証
  parseConfig   - 解析
```

### REST APIエンドポイント

```
HTTP動詞 + リソース名（複数形）

例:
  GET    /users           - 一覧取得
  POST   /users           - 作成
  GET    /users/{id}      - 個別取得
  PUT    /users/{id}      - 完全更新
  PATCH  /users/{id}      - 部分更新
  DELETE /users/{id}      - 削除

ネスト:
  GET    /users/{userId}/orders          - ユーザーの注文一覧
  POST   /users/{userId}/orders          - ユーザーの注文作成
  GET    /users/{userId}/orders/{orderId} - 特定の注文取得
```
