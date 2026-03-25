# チュートリアル 例集

良い例と悪い例の比較から、効果的なチュートリアルの書き方を学ぶ。

---

## 良い例: 明確なステップと確認方法

```markdown
# チュートリアル: Node.jsでREST APIを作成する

このチュートリアルでは、Express.jsを使って簡単なREST APIを作成します。
最終的に、JSON形式でデータを返すAPIエンドポイントが動作する状態になります。

## 前提条件

- Node.js 18以上（`node --version` で確認）
- 基本的なJavaScriptの知識
- ターミナル操作の基本

## 所要時間

約15分

---

## ステップ

### 1. プロジェクトを作成する

新しいディレクトリを作成し、npm initを実行する。

\`\`\`bash
mkdir my-api
cd my-api
npm init -y
\`\`\`

**確認**: `package.json` が作成されていればOK

### 2. Expressをインストールする

\`\`\`bash
npm install express
\`\`\`

**確認**: `node_modules` ディレクトリが作成される

### 3. サーバーファイルを作成する

`index.js` を作成し、以下のコードを記述する。

\`\`\`javascript
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.json({ message: 'Hello, World!' });
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
\`\`\`

### 4. サーバーを起動する

\`\`\`bash
node index.js
\`\`\`

**期待される出力**:
\`\`\`
Server running at http://localhost:3000
\`\`\`

### 5. 動作を確認する

別のターミナルで以下を実行:

\`\`\`bash
curl http://localhost:3000
\`\`\`

**期待される出力**:
\`\`\`json
{"message":"Hello, World!"}
\`\`\`

---

## トラブルシューティング

### エラー: "Cannot find module 'express'"

**原因**: npm installが完了していない、または別ディレクトリで実行した

**解決方法**:
1. `node_modules` ディレクトリが存在するか確認
2. 存在しなければ `npm install` を再実行
3. `package.json` がある同じディレクトリにいることを確認

### エラー: "EADDRINUSE: address already in use :::3000"

**原因**: ポート3000が別のプロセスで使用中

**解決方法**:
1. 他のプロセスを終了する: `lsof -i :3000` で確認し `kill <PID>` で停止
2. または `const port = 3001;` に変更して別ポートを使用
```

**なぜこれが良いか:**
- 冒頭で「何ができるか」が一文で分かる
- 各ステップに確認方法がある（読者が迷わない）
- コードがコピペで動く（省略なし）
- トラブルシューティングに原因と解決方法の両方がある
- 前提条件にバージョンと確認方法が示されている

---

## 悪い例とその改善

### パターン1: 手順の飛び・コード省略

```markdown
## REST APIを作成する

まず、package.jsonを作成します。

次に、以下のコードを書きます:

\`\`\`javascript
const express = require('express');
// ...
app.listen(3000);
\`\`\`

これでAPIが動きます。
```

**問題点:**
- `npm init` と `npm install express` の手順がない（読者が「express が見つからない」エラーに遭遇する）
- コードが `...` で省略されている（コピペで動かない）
- 確認方法がない（「動きます」だけでは読者は本当に動いたか分からない）

---

### パターン2: 1ステップに複数アクション

```markdown
### ステップ1: セットアップ

ディレクトリを作成し、npmを初期化し、必要なパッケージをインストールして、
package.jsonのscriptsを編集し、.envファイルを作成し、.gitignoreも追加します。

\`\`\`bash
mkdir project && cd project && npm init -y && npm install express dotenv && echo "PORT=3000" > .env
\`\`\`
```

**問題点:**
- 1ステップに6つ以上のアクション（どこで失敗したか分からない）
- `&&` チェーンが途中で失敗すると原因特定が困難
- 初心者は「何が起きているか」を追えない

**改善版:**
```markdown
### 1. ディレクトリを作成する

\`\`\`bash
mkdir project
cd project
\`\`\`

**確認**: `pwd` で `project` ディレクトリにいることを確認

### 2. npmを初期化する

\`\`\`bash
npm init -y
\`\`\`

**確認**: `package.json` が作成される

### 3. パッケージをインストールする

\`\`\`bash
npm install express dotenv
\`\`\`

**確認**: `node_modules` ディレクトリが作成される
```

---

### パターン3: 抽象的な説明のみ

```markdown
## 認証を実装する

認証機能を追加するには、まずユーザーモデルを作成します。
次に、パスワードをハッシュ化する処理を追加します。
その後、JWTトークンを生成するロジックを実装します。
最後に、ミドルウェアで認証チェックを行います。
```

**問題点:**
- コードが一切ない（「何をすればいいか」が分からない）
- 各ステップの具体的な手順がない
- 読者は「分かった気になる」だけで手が動かない

**改善版:**
```markdown
### 1. bcryptとjsonwebtokenをインストールする

\`\`\`bash
npm install bcrypt jsonwebtoken
\`\`\`

### 2. パスワードをハッシュ化する関数を作成する

`auth.js` を作成:

\`\`\`javascript
const bcrypt = require('bcrypt');

async function hashPassword(password) {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(password, salt);
}

module.exports = { hashPassword };
\`\`\`

**確認**: 以下のコードで動作をテスト:
\`\`\`javascript
const { hashPassword } = require('./auth');
hashPassword('mypassword').then(hash => console.log(hash));
// 出力例: $2b$10$xK8f...（60文字のハッシュ値）
\`\`\`

### 3. JWTトークンを生成する関数を追加する

`auth.js` に以下を追加:

\`\`\`javascript
const jwt = require('jsonwebtoken');

const SECRET_KEY = 'your-secret-key-change-in-production';

function generateToken(userId) {
  return jwt.sign({ id: userId }, SECRET_KEY, { expiresIn: '1h' });
}

module.exports = { hashPassword, generateToken };
\`\`\`

**確認**:
\`\`\`javascript
const { generateToken } = require('./auth');
const token = generateToken(123);
console.log(token);
// 出力例: eyJhbGciOiJIUzI1NiIs...（3つのドット区切り文字列）
\`\`\`
```

---

## ビフォー・アフター: 全体像

### Before

```markdown
# Reactアプリを作る

Create React Appを使います。

\`\`\`
npx create-react-app my-app
cd my-app
npm start
\`\`\`

これでReactアプリが動きます。次にコンポーネントを作成していきましょう。
コンポーネントはsrc/componentsフォルダに作成するのが一般的です。
```

**問題:** 前提条件なし、確認方法なし、コンポーネント作成は「説明」だけで終わっている

### After

```markdown
# チュートリアル: Reactアプリを作成する

Create React Appでプロジェクトを作成し、カスタムコンポーネントを追加して表示する。

## 前提条件

- Node.js 18以上（`node --version` で確認）
- npm 9以上（`npm --version` で確認）

## 所要時間

約10分

---

## ステップ

### 1. プロジェクトを作成する

\`\`\`bash
npx create-react-app my-app
\`\`\`

**確認**: 「Happy hacking!」と表示されれば成功（2-3分かかる場合がある）

### 2. プロジェクトディレクトリに移動する

\`\`\`bash
cd my-app
\`\`\`

### 3. 開発サーバーを起動する

\`\`\`bash
npm start
\`\`\`

**期待される結果**: ブラウザが自動で開き、http://localhost:3000 にReactのロゴが表示される

### 4. コンポーネント用ディレクトリを作成する

\`\`\`bash
mkdir src/components
\`\`\`

### 5. Helloコンポーネントを作成する

`src/components/Hello.js` を作成:

\`\`\`javascript
function Hello({ name }) {
  return <h1>Hello, {name}!</h1>;
}

export default Hello;
\`\`\`

### 6. App.jsでコンポーネントを使用する

`src/App.js` を以下の内容に置き換える:

\`\`\`javascript
import Hello from './components/Hello';

function App() {
  return (
    <div>
      <Hello name="World" />
    </div>
  );
}

export default App;
\`\`\`

**確認**: ブラウザに「Hello, World!」と表示される（ホットリロードで自動反映）

---

## トラブルシューティング

### npm startでエラーが出る

**原因**: `my-app` ディレクトリ内で実行していない可能性

**解決方法**: `cd my-app` を実行してからやり直す

### ブラウザが自動で開かない

**原因**: ブラウザの設定やWSL環境での制限

**解決方法**: 手動で http://localhost:3000 にアクセスする

---

## まとめ

このチュートリアルで学んだこと:
- Create React Appでプロジェクトを作成する方法
- カスタムコンポーネントの作成方法
- propsの渡し方と表示

## 次のステップ

- [React公式チュートリアル](https://react.dev/learn) で状態管理を学ぶ
- 複数のコンポーネントを組み合わせてページを構成する
```
