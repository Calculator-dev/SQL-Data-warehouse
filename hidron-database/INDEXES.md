# Indexes

Every index in the Hidron database: what it's for and which query uses it. The definitions are in [`schema.sql`](schema.sql).

The database has **60 indexes**:

| Kind | Count | Created by |
|---|---|---|
| Primary keys | 16 | One per table |
| Unique constraints | 15 | SKUs, slugs, names, order numbers, tracking tokens, admin login |
| Other indexes | 29 | Below |

## Index types used

| Type | Used for | Example |
|---|---|---|
| **B-tree** (the default) | Equality, ranges, sorting | `price BETWEEN 30 AND 60`, `ORDER BY created_at DESC` |
| **B-tree, multi-column** | Filtering by one column and sorting by another | `WHERE status = 'pending' ORDER BY created_at` |
| **GIN on `tsvector`** | Full-text search | `search_vector @@ to_tsquery('gog:*')` |
| **GIN trigram** (`gin_trgm_ops`) | `ILIKE '%text%'` and typo-tolerant matching | `customer_email ILIKE '%kupac%'` |
| **Partial unique** | A rule that applies only to some rows | At most one primary category per product |
| **Expression unique** | Uniqueness after a transformation | Admin emails unique regardless of case |

## Catalog

| Index | Columns | Why |
|---|---|---|
| `products_price_idx` | `price` | Sorting by price and the price filter. Confirmed with `EXPLAIN`: "cheapest first" reads the index instead of sorting the table. |
| `products_created_at_idx` | `created_at` | The "newest" sort. Postgres reads the index backwards for `DESC`. |
| `products_brand_id_idx` | `brand_id` | The brand filter, and clearing `brand_id` when a brand is deleted (`ON DELETE SET NULL`). |
| `products_search_vector_idx` | GIN `search_vector` | Full-text product search. See the findings below. |
| `products_search_text_trgm_idx` | GIN trigram `search_text` | Typo-tolerant search fallback. See the findings below. |
| `products_name_trgm_idx`, `products_description_trgm_idx`, `products_short_description_trgm_idx` | GIN trigram | Added for `ILIKE` search before full-text search existed. See the findings below. |
| `product_variants_product_id_idx` | `product_id` | Loading a product's variants on the product page, and deleting them with the product. |
| `categories_parent_id_idx` | `parent_id` | Loading subcategories, and the check that blocks deleting a category that still has children. |
| `categories_active_display_idx` | `(is_active, display_order)` | The category menu: active categories in display order. |
| `brands_active_name_idx` | `(is_active, name)` | The brand list: active brands by name. |

## Link tables

Each link table has a two-column primary key, for example `(product_id, category_id)`. A multi-column B-tree index can only be searched by its first column, so the primary key covers "categories of this product" but not "products in this category". Each table therefore has a second index on the other column:

| Index | Serves |
|---|---|
| `product_categories_category_id_idx` | The category filter (`EXISTS ... category_id = ANY(...)`), category counts in the sidebar, and cascade deletes when a category is removed |
| `product_tags_tag_id_idx` | The tag filter and cascade deletes |
| `product_colors_color_id_idx` | Colour lookups and cascade deletes |
| `product_sizes_size_id_idx` | Size lookups and cascade deletes |
| `product_categories_one_primary_idx` | Partial unique index on `product_id WHERE is_primary`. It doesn't speed anything up: it makes the database reject a second primary category for the same product. |

## Orders

| Index | Columns | Why |
|---|---|---|
| `orders_status_created_at_idx` | `(status, created_at)` | Admin order list filtered by status, newest first |
| `orders_payment_status_created_at_idx` | `(payment_status, created_at)` | The same, filtered by payment status |
| `orders_created_at_idx` | `created_at` | Unfiltered order list, dashboard "recent orders", date ranges |
| `orders_number_trgm_idx`, `orders_customer_email_trgm_idx` | GIN trigram | Admin order search by part of an order number or email. See the findings below. |
| `order_items_order_id_idx` | `order_id` | Loading an order's lines, and deleting them with the order |
| `order_items_product_id_idx` | `product_id` | Deleting a product must check that no order uses it. Without this index every product delete would scan all order lines. |
| `order_items_variant_id_idx` | `variant_id` | Clearing `variant_id` when a variant is deleted (`ON DELETE SET NULL`) |

## Admin and search

| Index | Columns | Why |
|---|---|---|
| `admin_users_email_lower_unique` | unique `lower(email)` | Stops `Admin@hidron.ba` and `admin@hidron.ba` from becoming two accounts |
| `search_logs_created_at_idx` | `created_at` | The search report's date range, and deleting logs older than 180 days |
| `search_logs_normalized_query_idx` | `(normalized_query, created_at)` | Grouping searches by query for "top searches" and "searches with no results" |
| `search_synonyms_words_idx` | GIN `words` | Finding synonym groups that contain a word. The app currently loads all groups into memory, so it's rarely used. |

## Findings: indexes the current queries don't use

I loaded 50,000 test products and 50,000 test orders into a copy of the schema and checked each query with `EXPLAIN ANALYZE`. Three queries read the whole table even though an index exists, and three indexes are probably never used:

| Query | Time at 50k rows | Why the index isn't used | Fix |
|---|---|---|---|
| **Product search** (`searchService.ts`, strict mode) | 39 ms (0.2 ms with the index) | The search condition is `search_vector @@ ... OR lower(sku) = ... OR EXISTS (variant SKU)`. There's no index on `lower(sku)`, and Postgres can't use an index for one side of an `OR` and scan for the other. | Add indexes on `lower(sku)` for `products` and `product_variants`, or look up the exact SKU as a separate query |
| **Typo fallback** (`strict_word_similarity(...) >= 0.45`) | 300 ms | The function form can't use an index. Only the operator form can. | Use `token <<% search_text` with `SET pg_trgm.strict_word_similarity_threshold = 0.45` |
| **Admin order search** (`orderController.ts`) | 109 ms | Searches 4 columns with `OR`. First and last name have no index, so the two that do aren't used either. | Add trigram indexes on the name columns, or one combined search column |
| **Product `name` / `description` / `short_description` trigram indexes** | n/a | Only the pre-migration fallback search uses `ILIKE` on these, and it also searches `sku`, which has no trigram index. | Check `idx_scan` in `pg_stat_user_indexes` in production. If it's 0, drop them: they slow down every product save and the description index is large. |

With Hidron's current catalog (a few hundred products) each of these takes a few milliseconds, so none is urgent. They start to matter at a few thousand products or orders.
