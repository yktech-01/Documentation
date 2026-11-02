-- =====================================================================
-- V2__grants.sql - Energy Pulse 2.0 (epulse2) Lakebase grants
-- Run AFTER V1__schema.sql and AFTER the Databricks App is bound to the
-- database (binding creates the app service principal's Postgres role).
--
-- ${app_sp_role} is a placeholder:
--   Flyway : -placeholders.app_sp_role=<role name>
--   psql   : replace it, or use sed in the pipeline:
--            sed "s/\${app_sp_role}/<role name>/g" V2__grants.sql | psql ...
-- Find the role:  SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%';
-- Grants are idempotent; re-running is safe.
-- =====================================================================

GRANT USAGE ON SCHEMA app TO "${app_sp_role}";

-- read everything
GRANT SELECT ON ALL TABLES IN SCHEMA app TO "${app_sp_role}";

-- insert / update where the app writes
GRANT INSERT, UPDATE ON
  app.users, app.leadership_message, app.settings, app.learning_resources,
  app.notifications, app.notification_reads,
  app.catalog_items, app.catalog_item_categories, app.catalog_item_colors,
  app.catalog_item_icons, app.catalog_item_opcos, app.catalog_item_statuses,
  app.admin_pinned_catalog_items, app.user_pinned_catalog_items,
  app.custom_dashboards, app.custom_dashboard_widgets
TO "${app_sp_role}";

-- delete only where the UI removes rows (A5)
GRANT DELETE ON
  app.admin_pinned_catalog_items, app.user_pinned_catalog_items,
  app.custom_dashboards, app.custom_dashboard_widgets, app.notification_reads
TO "${app_sp_role}";

-- identity sequences used by INSERTs
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO "${app_sp_role}";
