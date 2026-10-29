-- Local-only prerequisite slice. Caller must use the guarded rehearsal runner.
DO $$ BEGIN
 IF current_database()<>'postgres' OR current_setting('server_version_num')::int/10000<>17 OR
 shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database')
 IS DISTINCT FROM 'twogethera:cp004b3:disposable:v1' THEN RAISE EXCEPTION 'wrong_rehearsal_target'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='cp004b2_owner') THEN
  CREATE ROLE cp004b2_owner NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
  COMMENT ON ROLE cp004b2_owner IS 'twogethera:cp004b3:disposable:v1';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='cp004b2_owner' AND NOT rolcanlogin
 AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
 AND shobj_description(oid,'pg_authid')='twogethera:cp004b3:disposable:v1') OR
 EXISTS(SELECT 1 FROM pg_auth_members WHERE roleid=(SELECT oid FROM pg_roles WHERE rolname='cp004b2_owner')
 OR member=(SELECT oid FROM pg_roles WHERE rolname='cp004b2_owner')) THEN
  RAISE EXCEPTION 'unsafe_owner_role' USING ERRCODE='42501';
 END IF;
END $$;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
 WHERE e.extname='pgcrypto' AND n.nspname='extensions' AND e.extversion='1.3') THEN
 RAISE EXCEPTION 'unreviewed_crypto_version'; END IF;
END $$;
GRANT USAGE ON SCHEMA auth,extensions TO cp004b2_owner;
REVOKE ALL ON auth.users FROM cp004b2_owner;
GRANT REFERENCES(id) ON auth.users TO cp004b2_owner;
