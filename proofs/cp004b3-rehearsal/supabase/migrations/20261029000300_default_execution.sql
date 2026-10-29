-- Scoped to this application's owner in this disposable database.
-- Per-schema REVOKE cannot subtract the global PostgreSQL PUBLIC EXECUTE default.
SET LOCAL ROLE cp004b2_owner;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;
