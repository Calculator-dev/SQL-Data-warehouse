/*
=============================================================
Hidron e-commerce database: full schema (PostgreSQL)
=============================================================
Script Purpose:
    Creates every table, constraint, index, function and trigger
    of the Hidron online shop database in the 'public' schema.

Source:
    Generated with pg_dump --schema-only after applying the
    application's Drizzle migrations 0000 to 0008. Diagram and
    table reference: see README.md in this folder.

How to run:
    Run on an empty database (PostgreSQL 13+). The pg_trgm and
    unaccent extensions must be available (standard contrib).
=============================================================
*/

--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';

--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;

--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';

--
-- Name: refresh_product_search(integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_product_search(product_ids integer[]) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'extensions'
    AS $$
  WITH doc AS (
    SELECT
      p.id,
      p.name,
      b.name AS brand_name,
      (SELECT string_agg(c.name, ' ')
         FROM product_categories pc JOIN categories c ON c.id = pc.category_id
        WHERE pc.product_id = p.id) AS category_names,
      (SELECT string_agg(t.name, ' ')
         FROM product_tags pt JOIN tags t ON t.id = pt.tag_id
        WHERE pt.product_id = p.id) AS tag_names,
      concat_ws(' ', p.sku,
        (SELECT string_agg(v.sku, ' ') FROM product_variants v WHERE v.product_id = p.id)
      ) AS skus,
      concat_ws(' ', p.short_description, p.description) AS descriptions
    FROM products p
    LEFT JOIN brands b ON b.id = p.brand_id
    WHERE p.id = ANY(product_ids)
  )
  UPDATE products p
     SET search_text = search_normalize(concat_ws(' ', d.name, d.brand_name, d.category_names, d.tag_names, d.skus)),
         search_vector =
              setweight(to_tsvector('simple', search_normalize(d.name)), 'A')
           || setweight(to_tsvector('simple', search_normalize(concat_ws(' ', d.brand_name, d.category_names))), 'B')
           || setweight(to_tsvector('simple', search_normalize(concat_ws(' ', d.tag_names, d.skus))), 'C')
           || setweight(to_tsvector('simple', search_normalize(search_strip_html(d.descriptions))), 'D')
    FROM doc d
   WHERE p.id = d.id
$$;

--
-- Name: search_normalize(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_normalize(input text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'public', 'extensions'
    AS $$
  SELECT lower(unaccent('unaccent'::regdictionary, coalesce(input, '')))
$$;

--
-- Name: search_strip_html(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_strip_html(input text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(input, ''), '<[^>]*>', ' ', 'g'),
           '&[a-zA-Z#0-9]+;', ' ', 'g'),
         '\\n', ' ', 'g')
$$;

--
-- Name: slugify(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.slugify(input text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'public', 'extensions'
    AS $$
  SELECT left(trim(both '-' from regexp_replace(search_normalize(input), '[^a-z0-9]+', '-', 'g')), 200)
$$;

--
-- Name: trg_brand_search(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_brand_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    PERFORM refresh_product_search(ARRAY(SELECT id FROM products WHERE brand_id = NEW.id));
  END IF;
  RETURN NULL;
END $$;

--
-- Name: trg_category_search(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_category_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    PERFORM refresh_product_search(ARRAY(SELECT product_id FROM product_categories WHERE category_id = NEW.id));
  END IF;
  RETURN NULL;
END $$;

--
-- Name: trg_product_children_search_new(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_product_children_search_new() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM refresh_product_search(ARRAY(SELECT DISTINCT product_id FROM new_rows));
  RETURN NULL;
END $$;

--
-- Name: trg_product_children_search_old(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_product_children_search_old() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM refresh_product_search(ARRAY(SELECT DISTINCT product_id FROM old_rows));
  RETURN NULL;
END $$;

--
-- Name: trg_products_search(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_products_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM refresh_product_search(ARRAY[NEW.id]);
  RETURN NULL;
END $$;

--
-- Name: trg_products_slug(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_products_slug() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE base text;
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    base := slugify(NEW.name);
    IF base = '' THEN base := 'proizvod'; END IF;
    IF EXISTS (SELECT 1 FROM products WHERE slug = base AND id <> NEW.id) THEN
      NEW.slug := base || '-' || NEW.id;
    ELSE
      NEW.slug := base;
    END IF;
  ELSE
    NEW.slug := slugify(NEW.slug);
  END IF;
  RETURN NEW;
END $$;

--
-- Name: trg_tag_search(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_tag_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    PERFORM refresh_product_search(ARRAY(SELECT product_id FROM product_tags WHERE tag_id = NEW.id));
  END IF;
  RETURN NULL;
END $$;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_users (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role character varying(50) DEFAULT 'admin'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: admin_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_users_id_seq OWNED BY public.admin_users.id;

--
-- Name: brands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brands (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(100) NOT NULL,
    logo_url character varying(500),
    description text,
    website_url character varying(255),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: brands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.brands_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: brands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.brands_id_seq OWNED BY public.brands.id;

--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(100) NOT NULL,
    description text,
    image_url character varying(500),
    parent_id integer,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;

--
-- Name: colors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colors (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hex character varying(7) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT colors_hex_valid CHECK (((hex)::text ~ '^#[0-9A-Fa-f]{6}$'::text))
);

--
-- Name: colors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.colors_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: colors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.colors_id_seq OWNED BY public.colors.id;

--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id integer NOT NULL,
    order_id integer NOT NULL,
    product_id integer,
    product_name character varying(255) NOT NULL,
    product_sku character varying(100) NOT NULL,
    selected_size character varying(50),
    selected_color character varying(50),
    price numeric(10,2) NOT NULL,
    quantity integer NOT NULL,
    total numeric(10,2) NOT NULL,
    variant_id integer,
    CONSTRAINT order_items_price_nonnegative CHECK ((price >= (0)::numeric)),
    CONSTRAINT order_items_quantity_positive CHECK ((quantity > 0)),
    CONSTRAINT order_items_total_valid CHECK ((total = (price * (quantity)::numeric)))
);

--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id integer NOT NULL,
    order_number character varying(50) NOT NULL,
    customer_first_name character varying(100) NOT NULL,
    customer_last_name character varying(100) NOT NULL,
    customer_email character varying(255) NOT NULL,
    customer_phone character varying(20) NOT NULL,
    shipping_address character varying(255) NOT NULL,
    shipping_city character varying(100) NOT NULL,
    shipping_postal_code character varying(20) NOT NULL,
    shipping_country character varying(100) DEFAULT 'Bosnia and Herzegovina'::character varying NOT NULL,
    payment_method character varying(50) DEFAULT 'cash_on_delivery'::character varying NOT NULL,
    payment_status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    subtotal numeric(10,2) NOT NULL,
    shipping_cost numeric(10,2) DEFAULT '0'::numeric NOT NULL,
    total numeric(10,2) NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    notes text,
    admin_notes text,
    newsletter boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tracking_token character varying(64) DEFAULT (md5(((random())::text || (clock_timestamp())::text)) || md5(((random())::text || (clock_timestamp())::text))) NOT NULL,
    CONSTRAINT orders_payment_method_valid CHECK (((payment_method)::text = 'cash_on_delivery'::text)),
    CONSTRAINT orders_payment_status_valid CHECK (((payment_status)::text = ANY ((ARRAY['pending'::character varying, 'paid'::character varying, 'failed'::character varying, 'refunded'::character varying])::text[]))),
    CONSTRAINT orders_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'cancelled'::character varying, 'refunded'::character varying])::text[]))),
    CONSTRAINT orders_totals_valid CHECK (((subtotal >= (0)::numeric) AND (shipping_cost >= (0)::numeric) AND (total = (subtotal + shipping_cost))))
);

--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;

--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_categories (
    product_id integer NOT NULL,
    category_id integer NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: product_colors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_colors (
    product_id integer NOT NULL,
    color_id integer NOT NULL,
    image_url character varying(500)
);

--
-- Name: product_sizes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_sizes (
    product_id integer NOT NULL,
    size_id integer NOT NULL
);

--
-- Name: product_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_tags (
    product_id integer NOT NULL,
    tag_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: product_variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_variants (
    id integer NOT NULL,
    product_id integer NOT NULL,
    sku character varying(100) NOT NULL,
    size character varying(50),
    color character varying(50),
    price numeric(12,2) NOT NULL,
    sale_price numeric(12,2),
    stock integer DEFAULT 0 NOT NULL,
    in_stock boolean DEFAULT true NOT NULL,
    image_url character varying(500),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT product_variants_price_positive CHECK ((price > (0)::numeric)),
    CONSTRAINT product_variants_sale_price_valid CHECK (((sale_price IS NULL) OR ((sale_price > (0)::numeric) AND (sale_price < price)))),
    CONSTRAINT product_variants_stock_nonnegative CHECK ((stock >= 0))
);

--
-- Name: product_variants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_variants_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: product_variants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_variants_id_seq OWNED BY public.product_variants.id;

--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id integer NOT NULL,
    sku character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    short_description text DEFAULT ''::text NOT NULL,
    brand_id integer,
    price numeric(12,2) NOT NULL,
    sale_price numeric(12,2),
    stock integer DEFAULT 0 NOT NULL,
    in_stock boolean DEFAULT true NOT NULL,
    colors json DEFAULT '[]'::json,
    sizes json DEFAULT '[]'::json,
    image_url character varying(500),
    images text[] DEFAULT '{}'::text[] NOT NULL,
    has_variants boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    search_text text DEFAULT ''::text NOT NULL,
    search_vector tsvector,
    slug character varying(255) DEFAULT ''::character varying NOT NULL,
    CONSTRAINT products_price_positive CHECK ((price > (0)::numeric)),
    CONSTRAINT products_sale_price_valid CHECK (((sale_price IS NULL) OR ((sale_price > (0)::numeric) AND (sale_price < price)))),
    CONSTRAINT products_stock_nonnegative CHECK ((stock >= 0))
);

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;

--
-- Name: search_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_logs (
    id integer NOT NULL,
    query character varying(200) NOT NULL,
    normalized_query character varying(200) NOT NULL,
    result_count integer NOT NULL,
    fuzzy boolean DEFAULT false NOT NULL,
    source character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: search_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.search_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: search_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.search_logs_id_seq OWNED BY public.search_logs.id;

--
-- Name: search_synonyms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_synonyms (
    id integer NOT NULL,
    words text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: search_synonyms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.search_synonyms_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: search_synonyms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.search_synonyms_id_seq OWNED BY public.search_synonyms.id;

--
-- Name: sizes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sizes (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    size_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: sizes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sizes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: sizes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sizes_id_seq OWNED BY public.sizes.id;

--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    slug character varying(50) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;

--
-- Name: admin_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users ALTER COLUMN id SET DEFAULT nextval('public.admin_users_id_seq'::regclass);

--
-- Name: brands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands ALTER COLUMN id SET DEFAULT nextval('public.brands_id_seq'::regclass);

--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);

--
-- Name: colors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colors ALTER COLUMN id SET DEFAULT nextval('public.colors_id_seq'::regclass);

--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);

--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);

--
-- Name: product_variants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants ALTER COLUMN id SET DEFAULT nextval('public.product_variants_id_seq'::regclass);

--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);

--
-- Name: search_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_logs ALTER COLUMN id SET DEFAULT nextval('public.search_logs_id_seq'::regclass);

--
-- Name: search_synonyms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_synonyms ALTER COLUMN id SET DEFAULT nextval('public.search_synonyms_id_seq'::regclass);

--
-- Name: sizes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sizes ALTER COLUMN id SET DEFAULT nextval('public.sizes_id_seq'::regclass);

--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);

--
-- Name: admin_users admin_users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_email_unique UNIQUE (email);

--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);

--
-- Name: admin_users admin_users_username_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_username_unique UNIQUE (username);

--
-- Name: brands brands_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_name_unique UNIQUE (name);

--
-- Name: brands brands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_pkey PRIMARY KEY (id);

--
-- Name: brands brands_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_slug_unique UNIQUE (slug);

--
-- Name: categories categories_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_unique UNIQUE (name);

--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);

--
-- Name: categories categories_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_unique UNIQUE (slug);

--
-- Name: colors colors_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colors
    ADD CONSTRAINT colors_name_unique UNIQUE (name);

--
-- Name: colors colors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colors
    ADD CONSTRAINT colors_pkey PRIMARY KEY (id);

--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);

--
-- Name: orders orders_order_number_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_unique UNIQUE (order_number);

--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);

--
-- Name: orders orders_tracking_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_tracking_token_unique UNIQUE (tracking_token);

--
-- Name: product_categories product_categories_product_id_category_id_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_product_id_category_id_pk PRIMARY KEY (product_id, category_id);

--
-- Name: product_colors product_colors_product_id_color_id_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_colors
    ADD CONSTRAINT product_colors_product_id_color_id_pk PRIMARY KEY (product_id, color_id);

--
-- Name: product_sizes product_sizes_product_id_size_id_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_sizes
    ADD CONSTRAINT product_sizes_product_id_size_id_pk PRIMARY KEY (product_id, size_id);

--
-- Name: product_tags product_tags_product_id_tag_id_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_tags
    ADD CONSTRAINT product_tags_product_id_tag_id_pk PRIMARY KEY (product_id, tag_id);

--
-- Name: product_variants product_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_pkey PRIMARY KEY (id);

--
-- Name: product_variants product_variants_sku_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_sku_unique UNIQUE (sku);

--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);

--
-- Name: products products_sku_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_unique UNIQUE (sku);

--
-- Name: products products_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_slug_unique UNIQUE (slug);

--
-- Name: search_logs search_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_logs
    ADD CONSTRAINT search_logs_pkey PRIMARY KEY (id);

--
-- Name: search_synonyms search_synonyms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_synonyms
    ADD CONSTRAINT search_synonyms_pkey PRIMARY KEY (id);

--
-- Name: sizes sizes_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sizes
    ADD CONSTRAINT sizes_name_unique UNIQUE (name);

--
-- Name: sizes sizes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sizes
    ADD CONSTRAINT sizes_pkey PRIMARY KEY (id);

--
-- Name: tags tags_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_name_unique UNIQUE (name);

--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);

--
-- Name: tags tags_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_slug_unique UNIQUE (slug);

--
-- Name: admin_users_email_lower_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX admin_users_email_lower_unique ON public.admin_users USING btree (lower((email)::text));

--
-- Name: brands_active_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX brands_active_name_idx ON public.brands USING btree (is_active, name);

--
-- Name: categories_active_display_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX categories_active_display_idx ON public.categories USING btree (is_active, display_order);

--
-- Name: categories_parent_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX categories_parent_id_idx ON public.categories USING btree (parent_id);

--
-- Name: order_items_order_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_items_order_id_idx ON public.order_items USING btree (order_id);

--
-- Name: order_items_product_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_items_product_id_idx ON public.order_items USING btree (product_id);

--
-- Name: order_items_variant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_items_variant_id_idx ON public.order_items USING btree (variant_id);

--
-- Name: orders_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_created_at_idx ON public.orders USING btree (created_at);

--
-- Name: orders_customer_email_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_customer_email_trgm_idx ON public.orders USING gin (customer_email public.gin_trgm_ops);

--
-- Name: orders_number_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_number_trgm_idx ON public.orders USING gin (order_number public.gin_trgm_ops);

--
-- Name: orders_payment_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_payment_status_created_at_idx ON public.orders USING btree (payment_status, created_at);

--
-- Name: orders_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_status_created_at_idx ON public.orders USING btree (status, created_at);

--
-- Name: product_categories_category_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_categories_category_id_idx ON public.product_categories USING btree (category_id);

--
-- Name: product_categories_one_primary_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX product_categories_one_primary_idx ON public.product_categories USING btree (product_id) WHERE is_primary;

--
-- Name: product_colors_color_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_colors_color_id_idx ON public.product_colors USING btree (color_id);

--
-- Name: product_sizes_size_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_sizes_size_id_idx ON public.product_sizes USING btree (size_id);

--
-- Name: product_tags_tag_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_tags_tag_id_idx ON public.product_tags USING btree (tag_id);

--
-- Name: product_variants_product_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_variants_product_id_idx ON public.product_variants USING btree (product_id);

--
-- Name: products_brand_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_brand_id_idx ON public.products USING btree (brand_id);

--
-- Name: products_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_created_at_idx ON public.products USING btree (created_at);

--
-- Name: products_description_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_description_trgm_idx ON public.products USING gin (description public.gin_trgm_ops);

--
-- Name: products_name_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_name_trgm_idx ON public.products USING gin (name public.gin_trgm_ops);

--
-- Name: products_price_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_price_idx ON public.products USING btree (price);

--
-- Name: products_search_text_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_search_text_trgm_idx ON public.products USING gin (search_text public.gin_trgm_ops);

--
-- Name: products_search_vector_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_search_vector_idx ON public.products USING gin (search_vector);

--
-- Name: products_short_description_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_short_description_trgm_idx ON public.products USING gin (short_description public.gin_trgm_ops);

--
-- Name: search_logs_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX search_logs_created_at_idx ON public.search_logs USING btree (created_at);

--
-- Name: search_logs_normalized_query_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX search_logs_normalized_query_idx ON public.search_logs USING btree (normalized_query, created_at);

--
-- Name: search_synonyms_words_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX search_synonyms_words_idx ON public.search_synonyms USING gin (words);

--
-- Name: brands brands_search_refresh; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER brands_search_refresh AFTER UPDATE OF name ON public.brands FOR EACH ROW EXECUTE FUNCTION public.trg_brand_search();

--
-- Name: categories categories_search_refresh; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categories_search_refresh AFTER UPDATE OF name ON public.categories FOR EACH ROW EXECUTE FUNCTION public.trg_category_search();

--
-- Name: product_categories product_categories_search_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_categories_search_del AFTER DELETE ON public.product_categories REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_old();

--
-- Name: product_categories product_categories_search_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_categories_search_ins AFTER INSERT ON public.product_categories REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: product_categories product_categories_search_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_categories_search_upd AFTER UPDATE ON public.product_categories REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: product_tags product_tags_search_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_tags_search_del AFTER DELETE ON public.product_tags REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_old();

--
-- Name: product_tags product_tags_search_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_tags_search_ins AFTER INSERT ON public.product_tags REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: product_tags product_tags_search_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_tags_search_upd AFTER UPDATE ON public.product_tags REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: product_variants product_variants_search_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_variants_search_del AFTER DELETE ON public.product_variants REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_old();

--
-- Name: product_variants product_variants_search_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_variants_search_ins AFTER INSERT ON public.product_variants REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: product_variants product_variants_search_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_variants_search_upd AFTER UPDATE ON public.product_variants REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_product_children_search_new();

--
-- Name: products products_search_refresh; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_search_refresh AFTER INSERT OR UPDATE OF name, sku, description, short_description, brand_id ON public.products FOR EACH ROW EXECUTE FUNCTION public.trg_products_search();

--
-- Name: products products_slug_fill; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_slug_fill BEFORE INSERT OR UPDATE OF slug ON public.products FOR EACH ROW EXECUTE FUNCTION public.trg_products_slug();

--
-- Name: tags tags_search_refresh; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tags_search_refresh AFTER UPDATE OF name ON public.tags FOR EACH ROW EXECUTE FUNCTION public.trg_tag_search();

--
-- Name: categories categories_parent_id_categories_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_categories_id_fk FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE RESTRICT;

--
-- Name: order_items order_items_order_id_orders_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_orders_id_fk FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

--
-- Name: order_items order_items_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: order_items order_items_variant_id_product_variants_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_variant_id_product_variants_id_fk FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

--
-- Name: product_categories product_categories_category_id_categories_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_category_id_categories_id_fk FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;

--
-- Name: product_categories product_categories_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

--
-- Name: product_colors product_colors_color_id_colors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_colors
    ADD CONSTRAINT product_colors_color_id_colors_id_fk FOREIGN KEY (color_id) REFERENCES public.colors(id) ON DELETE CASCADE;

--
-- Name: product_colors product_colors_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_colors
    ADD CONSTRAINT product_colors_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

--
-- Name: product_sizes product_sizes_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_sizes
    ADD CONSTRAINT product_sizes_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

--
-- Name: product_sizes product_sizes_size_id_sizes_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_sizes
    ADD CONSTRAINT product_sizes_size_id_sizes_id_fk FOREIGN KEY (size_id) REFERENCES public.sizes(id) ON DELETE CASCADE;

--
-- Name: product_tags product_tags_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_tags
    ADD CONSTRAINT product_tags_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

--
-- Name: product_tags product_tags_tag_id_tags_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_tags
    ADD CONSTRAINT product_tags_tag_id_tags_id_fk FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;

--
-- Name: product_variants product_variants_product_id_products_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_product_id_products_id_fk FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

--
-- Name: products products_brand_id_brands_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_brand_id_brands_id_fk FOREIGN KEY (brand_id) REFERENCES public.brands(id) ON DELETE SET NULL;

--
-- PostgreSQL database dump complete
--

