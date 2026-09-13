-- =============================================================================
-- 02-schema.sql
--
-- Creates every table each of the 7 services needs, before any service gets
-- a chance to connect. Every service also runs its own idempotent
-- `CREATE TABLE IF NOT EXISTS` on startup (that's how this project was
-- written), so this file exists to make table creation explicit and
-- deterministic up front — and since it matches each service's own
-- migration exactly, the service's own migration is a no-op afterwards.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- auth_db — auth-service (Java/Spring Boot)
-- -----------------------------------------------------------------------------
\c auth_db

CREATE TABLE IF NOT EXISTS app_users (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(200) UNIQUE NOT NULL,
  password_hash VARCHAR(200) NOT NULL,
  role VARCHAR(40) NOT NULL DEFAULT 'USER',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_sessions (
  token VARCHAR(100) PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- catalog_db — catalog-service (Go)
-- -----------------------------------------------------------------------------
\c catalog_db

CREATE TABLE IF NOT EXISTS products (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(160) NOT NULL,
  category VARCHAR(100) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  price NUMERIC(12,2) NOT NULL CHECK(price>=0),
  image TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- inventory_db — inventory-service (Node.js/Express)
-- -----------------------------------------------------------------------------
\c inventory_db

CREATE TABLE IF NOT EXISTS inventory (
  product_id BIGINT PRIMARY KEY,
  quantity INTEGER NOT NULL DEFAULT 0 CHECK(quantity>=0),
  reserved INTEGER NOT NULL DEFAULT 0 CHECK(reserved>=0),
  reorder_level INTEGER NOT NULL DEFAULT 10 CHECK(reorder_level>=0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK(reserved<=quantity)
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- order_db — order-service (Python/FastAPI)
-- -----------------------------------------------------------------------------
\c order_db

CREATE TABLE IF NOT EXISTS orders (
  id BIGSERIAL PRIMARY KEY,
  user_email VARCHAR(200) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'CREATED',
  total NUMERIC(12,2) NOT NULL CHECK(total>=0),
  items JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- payment_db — payment-service (C#/ASP.NET Core)
-- -----------------------------------------------------------------------------
\c payment_db

CREATE TABLE IF NOT EXISTS payments (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
  method VARCHAR(40) NOT NULL,
  status VARCHAR(40) NOT NULL,
  transaction_ref VARCHAR(100) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  refunded_at TIMESTAMPTZ NULL
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- notification_db — notification-service (Ruby/Sinatra)
-- -----------------------------------------------------------------------------
\c notification_db

CREATE TABLE IF NOT EXISTS notifications (
  id BIGSERIAL PRIMARY KEY,
  recipient VARCHAR(200) NOT NULL,
  type VARCHAR(50) NOT NULL,
  subject VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;

-- -----------------------------------------------------------------------------
-- analytics_db — analytics-service (PHP)
-- -----------------------------------------------------------------------------
\c analytics_db

CREATE TABLE IF NOT EXISTS analytics_snapshots (
  id BIGSERIAL PRIMARY KEY,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO microapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO microapp;
