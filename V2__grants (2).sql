/*
  File        : V2__grants.sql
  Project     : Energy Pulse 2.0 (EP2.0)
  Database    : epulse2  (Lakebase project lbase-app-epulse2-<env>, branch production)
  Purpose     : Grants the Databricks App's service principal access to the app schema.
  Run as      : Database owner role
  Author      : Yedukondalu Kamma
  Created     : 2026-11-02

  When to run
  After V1__schema.sql, and after the Databricks App has been bound to the database.
  Binding the app is what creates the service principal's Postgres role.

  Role name
  ${app_sp_role} is replaced at run time with the app's role:
    Flyway : -placeholders.app_sp_role=<role>
    psql   : sed "s/\${app_sp_role}/<role>/g" V2__grants.sql | psql ...
  To find it: SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%';

  Safe to re-run.

  Change log
  2026-11-02  yk  Initial version
*/

GRANT USAGE ON SCHEMA app TO "${app_sp_role}";

-- Read access to all app tables
GRANT SELECT ON ALL TABLES IN SCHEMA app TO "${app_sp_role}";

-- Insert / update on the tables the app writes to
GRANT INSERT, UPDATE ON
  app.users, app.leadership_message, app.settings, app.learning_resources,
  app.notifications, app.notification_reads,
  app.catalog_items, app.catalog_item_categories, app.catalog_item_colors,
  app.catalog_item_icons, app.catalog_item_opcos, app.catalog_item_statuses,
  app.admin_pinned_catalog_items, app.user_pinned_catalog_items,
  app.custom_dashboards, app.custom_dashboard_widgets
TO "${app_sp_role}";

-- Delete only where users can remove things in the UI
GRANT DELETE ON
  app.admin_pinned_catalog_items, app.user_pinned_catalog_items,
  app.custom_dashboards, app.custom_dashboard_widgets, app.notification_reads
TO "${app_sp_role}";

-- Identity columns
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO "${app_sp_role}";

-- Audit log is append-only for the app
GRANT INSERT ON app.audit_log TO "${app_sp_role}";
REVOKE UPDATE, DELETE, TRUNCATE ON app.audit_log FROM "${app_sp_role}";
