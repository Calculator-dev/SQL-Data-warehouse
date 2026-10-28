# Caching

How Hidron avoids hitting the database on every request, and why it's built this way. File paths refer to the Hidron repository.

## Why

The shop is read-heavy. Hundreds of visitors browse the same catalog pages, while an admin changes products a few times a day. There's one backend server and a hosted Postgres database, so caching is built from simple layers that need no extra infrastructure: no Redis, no CDN configuration beyond HTTP headers.

The one rule that never relies on a cache is **money and stock at checkout**. Checkout reads price and stock from the database with a row lock (see [`QUERIES.md`](QUERIES.md)), so a stale page can show an old price or "in stock" but can never sell at a wrong price or oversell.

## The layers, from the database outwards

| # | Layer | What it holds | How long | Cleared when |
|---|---|---|---|---|
| 1 | Precomputed columns in Postgres | Search text, search vector, `in_stock` | Always current | Triggers and the same `UPDATE` keep them in sync |
| 2 | Connection pool | Open database connections | 30 s idle | Recycled after 7,500 queries |
| 3 | Server memory: API responses | Public product API responses | 60 s, max 200 | Synonym change, search reindex |
| 4 | Server memory: search synonyms | Synonym lookup table | 5 min | Any synonym edit |
| 5 | Server memory: feed images | JPEG conversions for Google/Facebook feeds | Up to 100 images | Least recently used is dropped |
| 6 | HTTP headers (browser) | API responses, images | 1 min to 1 year | Expiry |
| 7 | Prerendered HTML | Product and category pages, sitemap | Until next build | 10 min after an admin catalog change |
| 8 | Frontend memory (React Query) | Data already loaded in this browser tab | 1 min to forever | Expiry, or after placing or updating an order |

### 1. Precomputed columns in the database

The closest thing to a cache inside Postgres is columns that store a computed result:

- `products.search_vector` and `products.search_text` hold the product's name, brand, categories, tags, SKUs and descriptions, already lowercased and accent-free. Computing them per search would mean joining 5 tables for every product. Triggers rebuild them whenever any of that data changes (see `drizzle/0007_search_functions.sql`), so unlike a normal cache they can't go stale.
- `products.in_stock` and `product_variants.in_stock` are set in the same `UPDATE` that changes `stock` (`in_stock = stock - n > 0`), so "in stock only" is a simple boolean filter.

`order_items` also copies product name, SKU and price. That isn't a cache: it's the historical record of what was bought and at what price, and it's meant to differ from the product later.

Postgres's own memory cache (`shared_buffers`) is managed by the database host and isn't configured by the app.

### 2. Connection pool

`backend/src/db/index.ts`

```ts
new Pool({ max: 10, idleTimeoutMillis: 30_000, maxUses: 7_500, ... })
// on connect: SET search_path TO public, extensions; SET statement_timeout TO '15s'
```

Opening a Postgres connection (TLS and authentication) takes longer than most of the queries, so up to 10 connections are kept open and reused. `maxUses` replaces each connection after 7,500 queries so a long-running server doesn't build up per-connection memory. `statement_timeout` stops one slow query from holding a connection forever.

### 3. API response cache

`backend/src/routes/productRoutes.ts`

```ts
const key = req.originalUrl;            // e.g. /api/products?category=3&sortBy=price&page=2
if (cached && cached.expiresAt > Date.now()) return cached response
...
responseCache.set(key, { expiresAt: Date.now() + 60_000, body })
if (responseCache.size >= 200) delete the oldest entry
```

Every public product endpoint (listing, product page, filters, search suggestions, categories, brands) is cached for 60 seconds, keyed by the full URL including query parameters. During busy periods the same few pages are requested over and over, so this removes most catalog queries. Only successful responses are cached. The size limit of 200 keeps memory bounded.

The search logging middleware is registered before the cache, so searches served from the cache are still counted in the search report.

### 4. Synonym cache

`backend/src/services/search/searchService.ts`

Every search needs the synonym list (`naocale` → `goggles`). It's loaded into memory and kept for 5 minutes. Editing synonyms in the admin clears it immediately. If the database fails while reloading, the last good copy is used, so search keeps working. A similar check, "are the search migrations installed?", is stored permanently once it succeeds.

### 5. Feed image cache

`backend/src/routes/feedRoutes.ts`

Google Merchant needs JPEG images, but products are stored as WebP/PNG/AVIF. The server converts on request and keeps the last 100 results in memory, dropping the least recently used. Converting an image takes far longer than a database query, and feed crawlers request the same images repeatedly.

### 6. HTTP caching headers

| Resource | `Cache-Control` | Why |
|---|---|---|
| Public product API | `public, max-age=60, stale-while-revalidate=300` | The browser reuses a response for 1 minute. For 5 minutes after that it shows the saved copy instantly and fetches a fresh one in the background. |
| Product images (`/uploads`, Backblaze B2) | `public, max-age=31536000, immutable` | Each upload gets a new random file name, so a file never changes and can be cached for a year. `etag` is off because there's nothing to revalidate. |
| Converted feed images | `public, max-age=2592000, immutable` | 30 days, for the same reason |

### 7. Prerendered pages

`frontend/scripts/prerender.mjs`, `backend/src/services/deployHook.ts`

At build time the frontend fetches the whole catalog once and writes static HTML for every product and category page, plus `sitemap.xml` and the product feeds. Search engines, link previews and first page loads get finished HTML without touching the API.

When an admin creates, edits or deletes a product, category or brand, the backend schedules a frontend rebuild. Changes are batched: the rebuild starts 10 minutes after the last change, so editing 30 products triggers one build, not 30.

### 8. Frontend data cache (React Query)

`frontend/src/providers/query/query-client.tsx`, `frontend/src/services/*/queries.ts`

Data a visitor has already loaded is reused when they move between pages:

| Data | Reused for |
|---|---|
| Default | 5 minutes, kept in memory 30 minutes |
| Brands, categories | The whole visit (they rarely change) |
| Filter counts, search suggestions | 1 minute |
| Product lists, product page, a single order | 5 minutes |
| Order lists, colours, sizes, tags | 10 minutes |

Placing an order clears the cached products and orders in that browser, so the shopper sees the new stock straight away.

## Known gaps

- **Admin product edits don't clear the API response cache (layer 3).** Only synonym edits and a search reindex do. After a price or stock change, the server can keep serving the old data for up to 60 seconds, and a returning visitor's browser can add a few more minutes through layers 6 and 8. Checkout always uses the current price and stock, so the shopper is never charged the old price, but they may see it before confirming. Fix: call `clearProductResponseCache()` from the admin product, category and brand routes, next to the existing `scheduleFrontendRebuild` hook in `adminRoutes.ts`.
- **The response cache lives in one server process.** That's fine with one backend instance. With two or more, each has its own copy and clearing one doesn't clear the others. That would be the point to move it to Redis or a CDN.
- **The response cache drops the oldest entry when full, not the least recently used.** With 200 slots and a 60-second lifetime this makes little difference.
