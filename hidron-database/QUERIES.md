# How the complex queries work

The most involved queries in the Hidron backend, and why each one is written the way it is. File paths refer to the Hidron repository (`backend/`).

## 1. Checkout: lock the stock, then subtract

`src/controllers/orderController.ts`

```ts
db.transaction(async (trx) => {
  SELECT ... FROM product_variants JOIN products ... WHERE id = ? FOR UPDATE
  if (row.stock < quantity) throw 409
  UPDATE product_variants SET stock = stock - ?, in_stock = stock - ? > 0
  ...
  INSERT INTO orders ...; INSERT INTO order_items ...
})
```

- **`FOR UPDATE` prevents overselling.** If two customers buy the last swimsuit at the same moment, both could read `stock = 1` and both succeed. `FOR UPDATE` locks the row, so the second checkout waits until the first commits, then sees `stock = 0` and gets a 409 "Only 0 units available".
- **`stock = stock - n` instead of a number computed in the app.** The database does the arithmetic on the current value. The `CHECK (stock >= 0)` constraint is a second safety net.
- **Prices come from the database.** The client sends only product IDs and quantities, and the server uses `sale_price ?? price` from the locked row. A customer can't change the price in the browser.
- **One transaction.** The order, its lines and the stock changes all commit together or not at all. The cart is merged first (the same product added twice becomes one line), so each row is locked only once.

## 2. Cancelling an order puts stock back

`src/controllers/adminController.ts`

The order row is locked with `FOR UPDATE`. Each line's quantity is then added back to its variant or product in the same transaction. This is why `order_items` keeps both `variant_id` and `product_id`: the stock goes back to the right row. The lock and the "a cancelled order stays cancelled" check stop two admins clicking Cancel at once from restocking twice.

## 3. Filtering by category with `EXISTS`

`src/controllers/productController.ts`

```sql
EXISTS (SELECT 1 FROM product_categories pc
        WHERE pc.product_id = products.id AND pc.category_id = ANY($1::int[]))
```

A product can be in several categories. With a `JOIN`, a product in two of the selected categories would appear twice, so you'd need `DISTINCT`, and pagination and counts would break. `EXISTS` only asks "is it in any of these?", so each product appears at most once. `ANY(array)` handles any number of selected categories with a single parameter.

## 4. Filter counts that leave out their own filter

`src/controllers/productController.ts`

```ts
const where = (skip: Group) => { /* every filter except `skip` */ }
categories: ... WHERE where("category") GROUP BY pc.category_id
brands:     ... WHERE where("brand")    GROUP BY brand_id
prices:     count(*) FILTER (WHERE price <= 30), ...
```

This is how a shop's sidebar normally works. If you tick "Arena", the brand list should still show how many products the other brands have, or you could never switch brands. So each group of counts uses every active filter except its own. The four queries run in parallel with `Promise.all`. `count(*) FILTER (WHERE ...)` calculates all the price ranges in one pass over the table instead of one query per range.

## 5. Ranked, typo-tolerant search

`src/services/search/searchService.ts`, `src/services/search/normalize.ts`

This is the most complex part of the system. It's built entirely in Postgres, with no Elasticsearch or Algolia to run or pay for.

- **Normalizing.** The same rules run in TypeScript (`normalizeText`) and in SQL (`search_normalize`): lowercase, remove accents, `đ → d`. So `naočale` and `naocale` match each other. The two must stay in sync, which is why the comment in `normalize.ts` says so.
- **The query** (`buildTsQuery`). Each word turns into `gog:*ABC | gog:D`.
  - `:*ABC` matches word prefixes in the name, brand, categories, tags and SKU, so results appear while the customer is typing.
  - `:D` matches only whole words in descriptions, so `cap` doesn't match "capacity" deep in a description.
  - Words are combined with AND, so every word must match. Synonyms are added as alternatives: `naocale` also matches `goggles`.
- **Ranking.** `ts_rank_cd('{0.1, 0.2, 0.4, 1.0}', ...)` makes a match in the name count 10 times as much as a match in the description. Extra points are added for:
  - how similar the name is to the query (`word_similarity`),
  - the name starting with the query (+0.5),
  - an exact SKU match (+5, so pasting a SKU always puts that product first),
  - the product being in stock (+0.1).
- **Typo fallback.** If the strict search finds nothing, it runs again with trigram similarity `strict_word_similarity >= 0.45`, but only for words of 4 or more characters. That's how `gogles` finds goggles and `funkta` finds Funkita. The 0.45 threshold was chosen so `funkta` matches "funkita" (0.50) but not "funky" (0.44). Fuzzy search only runs after an empty result because it's slower and less precise.
- **Fallback before migration.** If the search migrations haven't been applied, it uses plain `ILIKE` matching instead of returning errors.

## 6. Keeping the search index current with triggers

`drizzle/0007_search_functions.sql`

`refresh_product_search(ids)` rebuilds the search columns for a list of products in one `UPDATE ... FROM (WITH doc AS ...)`. It's called by:

- **A row-level trigger on `products`**, limited to `UPDATE OF name, sku, description, ...`. The `search_*` columns aren't in that list on purpose. The function itself updates `search_*`, and if those columns were listed the trigger would fire again forever.
- **Statement-level triggers with transition tables** (`REFERENCING NEW TABLE AS new_rows`) on the link tables. Saving a product with 20 variants inserts 20 rows. A row-level trigger would rebuild the index 20 times. This version rebuilds once per statement for `SELECT DISTINCT product_id FROM new_rows`.
- **Rename triggers** on brands, categories and tags, so renaming "Arena" re-indexes every Arena product.

The search data lives in the database rather than the app so it can't drift. Admin edits, seed scripts and manual SQL fixes all keep the index correct.

## 7. The "searches with no results" report

`src/controllers/searchController.ts`

```sql
GROUP BY l.normalized_query
HAVING max(l.result_count) = 0
   AND NOT EXISTS (SELECT 1 FROM search_logs s
                   WHERE s.result_count > 0
                     AND s.normalized_query LIKE l.normalized_query || '%'
                     AND length(s.normalized_query) > length(l.normalized_query))
```

The goal is to show real failed searches, not partial typing. Someone typing "gog" on the way to "goggles" logs "gog". If "gog" returned nothing but a longer search starting with "gog" later found results, it was just an unfinished word, so the `NOT EXISTS` hides it. `HAVING max(result_count) = 0` keeps only queries that never found anything. `(array_agg(query ORDER BY created_at DESC))[1]` shows the most recent way the query was actually typed, with its original capitals and accents.

## 8. Automatic URL slugs

`drizzle/0008_product_slugs.sql`

A `BEFORE INSERT` trigger turns the name into `arena-cobra-ultra-swipe-naocale`. If that slug is already taken it adds `-<id>` at the end. It runs only when `slug` is empty or is changed directly, never on a rename, so existing links and Google results keep working. The backfill used `row_number() OVER (PARTITION BY slugify(name))`: the first product with a given name kept the plain slug and later duplicates got the id added.

## Known limitation

Checkout locks rows in the order the cart lists them. If two customers check out at the same time with the same two items in opposite order (A then B, and B then A), Postgres detects a deadlock and cancels one of the checkouts, which shows that customer an error. The fix is to sort the merged cart by variant and product ID before locking, so every checkout locks rows in the same order.
