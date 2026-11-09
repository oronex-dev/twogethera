-- CP-013 follow-up: allow the SECURITY DEFINER owner to resolve the Auth
-- claim helpers used by lifecycle triggers and RPCs. This grants schema
-- USAGE only; it does not grant access to Auth tables or sequences.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'twogethera_membership_owner'
      AND rolcanlogin = false
      AND rolbypassrls = false
  ) THEN
    RAISE EXCEPTION 'expected restricted membership owner role is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_namespace
    WHERE nspname = 'auth'
  ) THEN
    RAISE EXCEPTION 'Supabase Auth schema is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_proc AS auth_helper
    JOIN pg_catalog.pg_namespace AS ns
      ON ns.oid = auth_helper.pronamespace
    WHERE ns.nspname = 'auth'
      AND auth_helper.proname IN ('role', 'uid', 'jwt')
      AND auth_helper.pronargs = 0
  ) <> 3 THEN
    RAISE EXCEPTION 'expected Auth role, uid, and jwt helper functions are missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS auth_helper
    JOIN pg_catalog.pg_namespace AS ns
      ON ns.oid = auth_helper.pronamespace
    WHERE ns.nspname = 'auth'
      AND auth_helper.proname IN ('role', 'uid', 'jwt')
      AND auth_helper.pronargs = 0
      AND pg_catalog.pg_get_userbyid(auth_helper.proowner) <> 'supabase_auth_admin'
  ) THEN
    RAISE EXCEPTION 'Auth helper ownership differs from the expected Supabase owner';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS auth_helper
    JOIN pg_catalog.pg_namespace AS ns
      ON ns.oid = auth_helper.pronamespace
    WHERE ns.nspname = 'auth'
      AND auth_helper.proname IN ('role', 'uid', 'jwt')
      AND auth_helper.pronargs = 0
      AND NOT pg_catalog.has_function_privilege(
        'twogethera_membership_owner', auth_helper.oid, 'EXECUTE'
      )
  ) THEN
    RAISE EXCEPTION 'membership owner lacks EXECUTE on a required Auth helper';
  END IF;
END
$preflight$;

GRANT USAGE ON SCHEMA auth TO twogethera_membership_owner;

DO $privilege_check$
BEGIN
  IF NOT pg_catalog.has_schema_privilege(
    'twogethera_membership_owner', 'auth', 'USAGE'
  ) THEN
    RAISE EXCEPTION 'Auth schema USAGE grant did not take effect';
  END IF;

  IF pg_catalog.has_schema_privilege(
    'twogethera_membership_owner', 'auth', 'CREATE'
  ) THEN
    RAISE EXCEPTION
      'membership owner unexpectedly has CREATE privilege on Auth schema';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS auth_relation
    JOIN pg_catalog.pg_namespace AS ns
      ON ns.oid = auth_relation.relnamespace
    CROSS JOIN (
      VALUES
        ('SELECT'),
        ('INSERT'),
        ('UPDATE'),
        ('DELETE'),
        ('TRUNCATE'),
        ('REFERENCES'),
        ('TRIGGER')
    ) AS priv(name)
    WHERE ns.nspname = 'auth'
      AND auth_relation.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND pg_catalog.has_table_privilege(
        'twogethera_membership_owner', auth_relation.oid, priv.name
      )
  ) THEN
    RAISE EXCEPTION 'membership owner unexpectedly has privileges on Auth relations';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS auth_sequence
    JOIN pg_catalog.pg_namespace AS ns
      ON ns.oid = auth_sequence.relnamespace
    CROSS JOIN (VALUES ('USAGE'), ('SELECT'), ('UPDATE')) AS priv(name)
    WHERE ns.nspname = 'auth'
      AND auth_sequence.relkind = 'S'
      AND pg_catalog.has_sequence_privilege(
        'twogethera_membership_owner', auth_sequence.oid, priv.name
      )
  ) THEN
    RAISE EXCEPTION 'membership owner unexpectedly has privileges on Auth sequences';
  END IF;
END
$privilege_check$;

SET LOCAL ROLE twogethera_membership_owner;

DO $auth_helper_check$
BEGIN
  PERFORM auth.role();
  PERFORM auth.uid();
  PERFORM auth.jwt();
END
$auth_helper_check$;

RESET ROLE;
COMMIT;
