-- =====================================================================
-- V1__schema.sql - Energy Pulse 2.0 (epulse2) Lakebase schema
-- Run first. Creates schema app, 17 tables, indexes, triggers, seed.
-- Grants are in V2__grants.sql (run after the app is bound to the database).
-- Project : lbase-app-epulse2-<env>   Database : epulse2   Schema : app
-- Source  : "Lakebase Architecture and Key Relationships Diagram" (Confluence)
--   -- FIX: review fix to a diagram column or a missing key/constraint
--   -- ADD: recommended new column
--
-- Tables: 17 (16 from the diagram + notification_reads)
--
-- Assumptions to confirm with the team:
--   A1. Users are identified by SSO email (Databricks Apps request header).
--   A2. Notifications can be per user (user_id set) or broadcast (user_id NULL);
--       read status is tracked per user in notification_reads.
--   A3. Images (wallpaper, avatar, poster, media) are stored in a UC volume;
--       tables hold paths/URLs only.
--   A4. Admins are flagged with users.is_admin (alternative: workspace group).
--   A5. Rows are physically deleted only for pins, dashboards, widgets and
--       notification reads; content is retired with is_active / is_published.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app;

-- ---------------------------------------------------------------------
-- Shared: keep updated_at current on every UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- =====================================================================
-- 1. USERS
-- =====================================================================
CREATE TABLE app.users (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email          TEXT        NOT NULL UNIQUE,            -- FIX: SSO identity (A1)
  first_name     TEXT,
  last_name      TEXT,
  avatar_path    TEXT,                                   -- FIX: UC volume path (A3)
  is_admin       BOOLEAN     NOT NULL DEFAULT false,     -- FIX: admin flag (A4)
  is_active      BOOLEAN     NOT NULL DEFAULT true,
  preferences    JSONB       NOT NULL DEFAULT '{}',      -- ADD: theme, default dashboard, etc.
  last_login_at  TIMESTAMPTZ,                            -- ADD: usage / inactive-user cleanup
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- 2. HOME PAGE CONTENT
-- =====================================================================
CREATE TABLE app.leadership_message (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  author_name   TEXT        NOT NULL,
  author_title  TEXT,
  message       TEXT        NOT NULL,
  url           TEXT,
  published_at  TIMESTAMPTZ NOT NULL DEFAULT now(),      -- ADD: schedule / show date
  is_active     BOOLEAN     NOT NULL DEFAULT true,       -- ADD: retire without deleting
  created_by    TEXT        NOT NULL,                    -- FIX: audit
  updated_by    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.settings (                              -- FIX: single-row table with PK
  id                     SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  leadership_message_id  BIGINT REFERENCES app.leadership_message(id) ON DELETE SET NULL,
  system_alert_message   TEXT,
  alert_level            TEXT NOT NULL DEFAULT 'info'    -- ADD: alert severity
                         CHECK (alert_level IN ('info', 'warning', 'critical')),
  alert_starts_at        TIMESTAMPTZ,                    -- ADD: show alert from
  alert_ends_at          TIMESTAMPTZ,                    -- ADD: auto-hide alert after
  wallpaper_path         TEXT,                           -- FIX: UC volume path (A3)
  updated_by             TEXT        NOT NULL,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (alert_ends_at IS NULL OR alert_starts_at IS NULL OR alert_ends_at > alert_starts_at)
);

CREATE TABLE app.learning_resources (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title              TEXT        NOT NULL,
  subtitle           TEXT,
  url                TEXT,
  media_url          TEXT,                               -- video/media link or volume path
  poster_image_path  TEXT,                               -- FIX: UC volume path (A3)
  resource_type      TEXT NOT NULL DEFAULT 'link'        -- ADD: label / filter in the UI
                     CHECK (resource_type IN ('video', 'document', 'link')),
  sort_order         INT         NOT NULL DEFAULT 0,     -- FIX: display order
  is_published       BOOLEAN     NOT NULL DEFAULT true,  -- FIX: hide without deleting
  created_by         TEXT        NOT NULL,
  updated_by         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- 3. NOTIFICATIONS
-- =====================================================================
CREATE TABLE app.notifications (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES app.users(id) ON DELETE CASCADE,  -- FIX: NULL = broadcast (A2)
  type        TEXT NOT NULL DEFAULT 'info'               -- ADD: icon / colour in the UI
              CHECK (type IN ('info', 'alert', 'action')),
  title       TEXT        NOT NULL,
  url         TEXT,
  created_by  TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ                                -- ADD: clean up old notifications
);

CREATE TABLE app.notification_reads (                    -- FIX: replaces notifications.read (A2)
  notification_id  BIGINT      NOT NULL REFERENCES app.notifications(id) ON DELETE CASCADE,
  user_id          BIGINT      NOT NULL REFERENCES app.users(id)         ON DELETE CASCADE,
  read_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (notification_id, user_id)
);

-- =====================================================================
-- 4. CATALOG - lookup tables
-- =====================================================================
CREATE TABLE app.catalog_item_categories (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  sort_order  INT     NOT NULL DEFAULT 0,                -- ADD: dropdown order
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE app.catalog_item_colors (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  hex_code    TEXT    NOT NULL CHECK (hex_code ~ '^#[0-9A-Fa-f]{6}$'),  -- FIX: actual value
  sort_order  INT     NOT NULL DEFAULT 0,                -- ADD: dropdown order
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE app.catalog_item_icons (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  icon_key    TEXT    NOT NULL UNIQUE,                   -- FIX: key the React UI renders
  sort_order  INT     NOT NULL DEFAULT 0,                -- ADD: dropdown order
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE app.catalog_item_opcos (                    -- check: does opco master exist in Delta?
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  code        TEXT    UNIQUE,
  sort_order  INT     NOT NULL DEFAULT 0,                -- ADD: dropdown order
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE app.catalog_item_statuses (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  sort_order  INT     NOT NULL DEFAULT 0
);

-- =====================================================================
-- 5. CATALOG - items and pins
-- =====================================================================
CREATE TABLE app.catalog_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  short_code       TEXT    NOT NULL UNIQUE,              -- FIX: unique
  title            TEXT    NOT NULL,
  subtitle         TEXT,
  description      TEXT,                                 -- ADD: tooltip / detail text
  url              TEXT,                                 -- FIX: what the tile opens (confirm)
  open_in_new_tab  BOOLEAN NOT NULL DEFAULT true,        -- ADD: link behaviour
  sort_order       INT     NOT NULL DEFAULT 0,           -- ADD: default catalog order
  category_id      BIGINT REFERENCES app.catalog_item_categories(id),  -- FIX: *_id naming
  color_id         BIGINT REFERENCES app.catalog_item_colors(id),
  icon_id          BIGINT REFERENCES app.catalog_item_icons(id),
  opco_id          BIGINT REFERENCES app.catalog_item_opcos(id),
  status_id        BIGINT REFERENCES app.catalog_item_statuses(id),
  created_by       TEXT        NOT NULL,
  updated_by       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.admin_pinned_catalog_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  catalog_item_id  BIGINT NOT NULL UNIQUE
                   REFERENCES app.catalog_items(id) ON DELETE CASCADE,
  sort_order       INT         NOT NULL DEFAULT 0,       -- FIX: ordering
  created_by       TEXT        NOT NULL,                 -- FIX: which admin pinned it
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.user_pinned_catalog_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT NOT NULL REFERENCES app.users(id)         ON DELETE CASCADE,
  catalog_item_id  BIGINT NOT NULL REFERENCES app.catalog_items(id) ON DELETE CASCADE,
  sort_order       INT         NOT NULL DEFAULT 0,       -- FIX: ordering
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, catalog_item_id)                      -- FIX: no duplicate pins
);

-- =====================================================================
-- 6. DASHBOARDS
-- =====================================================================
CREATE TABLE app.dashboard_widgets (                     -- widget catalog
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  short_code  TEXT    NOT NULL UNIQUE,                   -- FIX: unique
  title       TEXT    NOT NULL,
  kpi_id      TEXT,                                      -- FIX: link to kpi_registry in Delta (confirm)
  is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE app.custom_dashboards (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, title)
);

CREATE TABLE app.custom_dashboard_widgets (
  id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  custom_dashboard_id  BIGINT NOT NULL REFERENCES app.custom_dashboards(id) ON DELETE CASCADE,
  dashboard_widget_id  BIGINT NOT NULL REFERENCES app.dashboard_widgets(id),
  sort_order           INT   NOT NULL DEFAULT 0,         -- FIX: layout order
  config               JSONB NOT NULL DEFAULT '{}',      -- FIX: size, position, filters
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- 7. INDEXES (foreign keys and common lookups)
-- =====================================================================
CREATE INDEX ix_notifications_user          ON app.notifications (user_id, created_at DESC);
CREATE INDEX ix_notification_reads_user     ON app.notification_reads (user_id);
CREATE INDEX ix_leadership_message_active   ON app.leadership_message (is_active, published_at DESC);
CREATE INDEX ix_learning_resources_pub      ON app.learning_resources (is_published, sort_order);
CREATE INDEX ix_catalog_items_category      ON app.catalog_items (category_id);
CREATE INDEX ix_catalog_items_opco          ON app.catalog_items (opco_id);
CREATE INDEX ix_catalog_items_status        ON app.catalog_items (status_id);
CREATE INDEX ix_user_pins_user              ON app.user_pinned_catalog_items (user_id, sort_order);
CREATE INDEX ix_custom_dashboards_user      ON app.custom_dashboards (user_id);
CREATE INDEX ix_cdw_dashboard               ON app.custom_dashboard_widgets (custom_dashboard_id, sort_order);

-- =====================================================================
-- 8. updated_at TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_users_updated              BEFORE UPDATE ON app.users                    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_leadership_message_updated BEFORE UPDATE ON app.leadership_message       FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_settings_updated           BEFORE UPDATE ON app.settings                 FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_learning_resources_updated BEFORE UPDATE ON app.learning_resources       FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_catalog_items_updated      BEFORE UPDATE ON app.catalog_items            FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_custom_dashboards_updated  BEFORE UPDATE ON app.custom_dashboards        FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER trg_cdw_updated                BEFORE UPDATE ON app.custom_dashboard_widgets FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- =====================================================================
-- 9. SEED (single settings row)
-- =====================================================================
INSERT INTO app.settings (id, updated_by) VALUES (1, 'system')
ON CONFLICT (id) DO NOTHING;
