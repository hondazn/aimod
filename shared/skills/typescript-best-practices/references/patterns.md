# TypeScript 型パターン — コード例

`SKILL.md` のパターン一覧に対応する最小例。同型の例を書き直したもので、原典の写しではない。共有の原則（Parse don't validate・ポカヨケ）は `coding-standards` を土台にする。

## 1. ブランド型

プリミティブが複数の意味で使われ、取り違えが現実に起こり得るときだけ導入する。作成時に一度検証し、以降は型を信頼する。

```ts
type UserId = string & { readonly __brand: "UserId" };
type OrderId = string & { readonly __brand: "OrderId" };

function parseUserId(input: string): UserId {
  if (!/^u_[0-9a-f]{12}$/.test(input)) throw new Error(`不正な UserId: ${input}`);
  return input as UserId;
}

function loadOrders(user: UserId): Promise<Order[]> { /* 検証済み */ }
```

`as` は境界のパース関数の中だけで使う。ブランドは素の型の上に載せるので、`string` の演算はそのまま使える。

## 2. 判別可能ユニオン

フラグと省略可能フィールドの組は、有効な状態を型で列挙できない。状態ごとに変種を分ける。

```ts
// やってはいけない: 読み込み中かつエラー、が表現できてしまう
type ViewState = { loading: boolean; data?: Report; error?: string };

// 状態ごとの変種だけが存在できる
type ViewState =
  | { kind: "idle" }
  | { kind: "loading" }
  | { kind: "ready"; data: Report }
  | { kind: "failed"; error: string };
```

判別子の名前は `kind` / `type` / `tag` から1つ選び、リポジトリ内で統一する。変種ごとに値が一意なので、`switch (s.kind)` で自動的に絞り込まれる。

## 3. NonEmpty

空を排除できるなら、呼び出し側へ空の判断を漏らさない。

```ts
type NonEmpty<T> = [T, ...T[]];

const isNonEmpty = <T>(xs: T[]): xs is NonEmpty<T> => xs.length > 0;

// 空が来ない型なので添字アクセスが正当化される
function pickWinner(entries: NonEmpty<Entry>): Entry {
  return entries[Math.floor(Math.random() * entries.length)];
}

// 素の配列は境界で一度だけ絞る
function pickFrom(raw: Entry[]): Entry | undefined {
  return isNonEmpty(raw) ? pickWinner(raw) : undefined;
}
```

`T[]` を受け取る箇所で毎回 `length === 0` を検査するより、境界の1箇所に寄せる。

## 4. Pairs

偶数の長さを型で表す。TypeScript に「長さが偶数」という絞り込みは無いが、要素の型で表現できる。

```ts
type Pairs<T> = [T, T][];

// 読み出しは用途に合わせて用意する
const flatten = <T>(pairs: Pairs<T>): T[] => pairs.flat();

const sumPairs = (pairs: Pairs<number>): number =>
  pairs.reduce((acc, [a, b]) => acc + a + b, 0);
```

奇数長のリストが要るなら、その用途では `Pairs<T>` にしない。表現を用途に合わせて選ぶ。

## 5. 時間範囲

`{ start, end }` は `start > end` を書けてしまう。開始と長さに分ける。

```ts
// やってはいけない: 不変条件がコメントにしかない
type Range = { start: Date; end: Date }; // start <= end の約束

// 負の長さを書けない
type Span = { start: Date; durationMs: number };

const endOf = (s: Span): Date => new Date(s.start.getTime() + s.durationMs);
```

`durationMs` に素の `number` を渡す取り違えが現実に起きるなら、そのときだけブランド型にする（→ [1]）。反射的にブランド化しない。

## 6. 総関数

まず、その型の全入力で値が返るかを見る。空配列が自然な単位（合計が 0）なら `T[]` のままでよい。

```ts
// 空は 0。総関数なので強化は不要
const sum = (xs: number[]): number => xs.reduce((a, b) => a + b, 0);

// 部分関数: 空のとき返す値が無い。`!` で型を黙らせている
function newest(sessions: Session[]): Session {
  return sessions.at(0)!;
}

// 入力を強化すると `!` が消える
function newest(sessions: NonEmpty<Session>): Session {
  return sessions[0];
}
```

空を型で排除できないなら、もう一方の総関数の形がある。戻り値を `Session | undefined` にし、空の意味を知っている呼び出し側に判断を渡す。どちらでも、空の処理は境界の1回だけになる。

## 7. スキーマ・既存の型からの導出

形の真実の源を1つにする。生成型や既存の型があるなら、新しい `interface` を書かずに導出する。

```ts
import type { ChecksMessage } from "./generated/checks";

// 必要な部分だけ取り出す。スキーマが変わればコンパイルで気づく
function renderChecks(msg: Pick<ChecksMessage, "total" | "checks">): string { /* ... */ }

// 関数の境界は既存のシグネチャから取る
type SaveHandler = (input: Parameters<typeof save>[0]) => Awaited<ReturnType<typeof save>>;

// 定数からリテラル型を取り出す
const THEMES = { dark: "#111", light: "#eee" } as const;
type ThemeName = keyof typeof THEMES;
```

`Pick` / `Omit` / `Parameters` / `ReturnType` / `Awaited` / `typeof` を先に探し、それで足りないときだけ新しい型を書く。

## 8. オブジェクト引数

同型の位置引数は入れ替えてもコンパイルが通る。名前を付けて渡す。

```ts
// 順番を入れ替えても通る
openRange(10, 1, 40, 2);

// 取り違えが名前で防がれる
openRange({ start: { line: 10, col: 1 }, end: { line: 40, col: 2 } });
```

毎フレームの描画、字句解析、パーサなど、アロケーションが効くホットパスでは位置引数のままでよい。

## 9. 網羅性検査

変種を足したときにコンパイルエラーを出す。`default` で判別子を `never` に代入する。

```ts
function cost(node: Node): number {
  switch (node.kind) {
    case "leaf":
      return node.weight;
    case "branch":
      return node.children.reduce((a, c) => a + cost(c), 0);
    default: {
      const _exhaustive: never = node;
      return _exhaustive;
    }
  }
}
```

値を返す `switch` は `return` で、値を返さない `switch` は `void _exhaustive;` で終える。

## 10. `unknown` と絞り込み

`any` は触れた先の検査を止める。外部入力は `unknown` で受け、絞ってから使う。絞り込みは次の順で強いものから選ぶ。

1. 判別子による `switch` / `if`
2. `in` 演算子
3. `typeof` / `instanceof`
4. ユーザー定義型ガード（`x is T`）
5. `as`（境界で全フィールドを検証した後だけ）

```ts
function readName(input: unknown): string {
  if (typeof input !== "object" || input === null || !("name" in input)) {
    throw new Error("name が無い");
  }
  const { name } = input as { name: unknown };
  if (typeof name !== "string") throw new Error("name が文字列でない");
  return name;
}
```

型ガードは主張を実際に検証する。`return true` を書くガードは `as` より悪い。名前が安全だと主張する分、誤りが見つからなくなる。

外部入力の例: RPC のペイロード、`JSON.parse`、`postMessage`、IPC、ファイル、環境変数、DB の結果。
