-- CP-006A application migration: account/couple membership boundary only.
-- No invitations, product records, archive content, Storage or Realtime policies.
BEGIN;

DO $$
DECLARE
  v_owner oid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'twogethera_membership_owner') THEN
    CREATE ROLE twogethera_membership_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION;
    COMMENT ON ROLE twogethera_membership_owner IS 'twogethera:cp006a:membership-owner:v1';
  END IF;
  SELECT oid INTO v_owner FROM pg_roles WHERE rolname = 'twogethera_membership_owner';
  IF NOT EXISTS (
       SELECT 1 FROM pg_roles
       WHERE oid = v_owner
         AND NOT rolcanlogin
         AND NOT rolsuper
         AND NOT rolcreatedb
         AND NOT rolcreaterole
         AND NOT rolreplication
         AND NOT rolbypassrls
         AND NOT rolinherit
         AND shobj_description(oid, 'pg_authid') = 'twogethera:cp006a:membership-owner:v1'
       ) OR EXISTS (
       SELECT 1 FROM pg_auth_members
       WHERE member = v_owner
          OR (roleid = v_owner AND member <> (SELECT oid FROM pg_roles WHERE rolname = 'postgres'))
     ) THEN
    RAISE EXCEPTION 'unsafe membership owner role' USING ERRCODE = '42501';
  END IF;
END $$;

-- Supabase's managed postgres role is not a superuser. Grant it the ability to
-- SET ROLE for migration-owned DDL, while keeping the application role isolated
-- from API roles and all other principals.
GRANT twogethera_membership_owner TO postgres;

CREATE SCHEMA IF NOT EXISTS app_private AUTHORIZATION twogethera_membership_owner;
REVOKE ALL ON SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA app_private TO authenticated;

-- This narrow postgres-owned bridge is required because managed Supabase does
-- not let postgres assume supabase_auth_admin, and app roles cannot access
-- Auth-managed rows. It answers only for the signed-in principal.
CREATE FUNCTION app_private.current_identity_is_verified(p_lock boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_confirmed timestamptz;
  v_banned_until timestamptz;
  v_anonymous boolean;
  v_token_exp text := auth.jwt() ->> 'exp';
BEGIN
  IF v_user_id IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RETURN NULL;
  END IF;
  IF v_token_exp IS NULL OR v_token_exp !~ '^[0-9]{1,12}$'
     OR v_token_exp::bigint <= floor(extract(epoch FROM statement_timestamp()))::bigint THEN
    RETURN NULL;
  END IF;
  IF p_lock THEN
    SELECT u.email_confirmed_at, u.banned_until, coalesce(u.is_anonymous, false)
      INTO v_confirmed, v_banned_until, v_anonymous
      FROM auth.users AS u WHERE u.id = v_user_id FOR SHARE;
  ELSE
    SELECT u.email_confirmed_at, u.banned_until, coalesce(u.is_anonymous, false)
      INTO v_confirmed, v_banned_until, v_anonymous
      FROM auth.users AS u WHERE u.id = v_user_id;
  END IF;
  IF v_confirmed IS NULL OR v_anonymous OR (v_banned_until IS NOT NULL AND v_banned_until > statement_timestamp()) THEN
    RETURN NULL;
  END IF;
  RETURN v_user_id;
END
$function$;
ALTER FUNCTION app_private.current_identity_is_verified(boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION app_private.current_identity_is_verified(boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE public.couple_spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','paired','archived','purging')),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  authorization_epoch bigint NOT NULL DEFAULT 1 CHECK (authorization_epoch > 0),
  privacy_epoch bigint NOT NULL DEFAULT 1 CHECK (privacy_epoch > 0),
  closed_at timestamptz,
  CHECK ((state IN ('archived','purging')) = (closed_at IS NOT NULL))
);

CREATE TABLE public.couple_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  -- Auth identity is revalidated by the private postgres-owned bridge. Avoid
  -- a cross-schema FK: managed Auth grants do not permit custom role owners to
  -- reference auth.users, and account deletion policy is not implemented yet.
  user_id uuid NOT NULL,
  seat smallint NOT NULL CHECK (seat IN (1,2)),
  -- CP-006A supports active/revoked only. Archive entitlements are a separate,
  -- policy-gated lifecycle and are deliberately not encoded as membership state.
  state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','revoked')),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  revoked_at timestamptz,
  UNIQUE (couple_id, id),
  UNIQUE (couple_id, user_id),
  UNIQUE (couple_id, seat),
  CHECK ((state = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE UNIQUE INDEX couple_memberships_one_active_space_per_user
  ON public.couple_memberships(user_id) WHERE state = 'active';
CREATE INDEX couple_memberships_scope_state
  ON public.couple_memberships(couple_id, state, seat);

CREATE TABLE app_private.couple_create_receipts (
  actor_user_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  committed_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY (actor_user_id, operation_id)
);

RESET ROLE;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.couple_spaces, public.couple_memberships TO authenticated;
REVOKE ALL ON public.couple_spaces, public.couple_memberships FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.couple_spaces, public.couple_memberships TO authenticated;
REVOKE ALL ON app_private.couple_create_receipts FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.couple_spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_memberships ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION app_private.can_read_couple(p_couple_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT app_private.current_identity_is_verified(false) IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.couple_memberships AS m
      JOIN public.couple_spaces AS s ON s.id = m.couple_id
      WHERE m.couple_id = p_couple_id
        AND m.user_id = app_private.current_identity_is_verified(false)
        AND m.state = 'active'
        AND s.state IN ('draft','paired')
    )
$function$;
ALTER FUNCTION app_private.can_read_couple(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.can_read_couple(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.can_read_couple(uuid) TO authenticated;

CREATE FUNCTION app_private.can_read_shared_records(p_couple_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT app_private.current_identity_is_verified(false) IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.couple_memberships AS actor
      JOIN public.couple_spaces AS s ON s.id = actor.couple_id
      WHERE actor.couple_id = p_couple_id
        AND actor.user_id = app_private.current_identity_is_verified(false)
        AND actor.state = 'active'
        AND s.state = 'paired'
        AND 2 = (SELECT count(*) FROM public.couple_memberships AS active_member
                  WHERE active_member.couple_id = s.id AND active_member.state = 'active')
    )
$function$;
ALTER FUNCTION app_private.can_read_shared_records(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.can_read_shared_records(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.can_read_shared_records(uuid) TO authenticated;

CREATE POLICY couple_spaces_read_current_member ON public.couple_spaces
  FOR SELECT TO authenticated USING (app_private.can_read_couple(id));
CREATE POLICY couple_memberships_read_current_space ON public.couple_memberships
  FOR SELECT TO authenticated USING (app_private.can_read_couple(couple_id));

CREATE FUNCTION app_private.enforce_space_transition()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.id <> NEW.id OR OLD.created_at <> NEW.created_at THEN
      RAISE EXCEPTION 'immutable space identity' USING ERRCODE = '42501';
    END IF;
    IF OLD.state = 'archived' AND NEW.state <> 'purging' THEN
      RAISE EXCEPTION 'archived space cannot be reopened' USING ERRCODE = '42501';
    END IF;
    IF OLD.state = 'paired' AND NEW.state = 'draft' THEN
      RAISE EXCEPTION 'paired space cannot return to draft' USING ERRCODE = '42501';
    END IF;
    IF OLD.state = 'draft' AND NEW.state NOT IN ('paired','archived','purging') THEN
      RAISE EXCEPTION 'invalid draft transition' USING ERRCODE = '42501';
    END IF;
    IF OLD.state = 'paired' AND NEW.state NOT IN ('archived','purging') THEN
      RAISE EXCEPTION 'invalid paired transition' USING ERRCODE = '42501';
    END IF;
    IF OLD.state = 'purging' THEN
      RAISE EXCEPTION 'purging space is terminal' USING ERRCODE = '42501';
    END IF;
    IF NEW.state = 'archived' AND OLD.closed_at IS NULL THEN NEW.closed_at := statement_timestamp(); END IF;
    IF OLD.closed_at IS NOT NULL AND NEW.closed_at IS DISTINCT FROM OLD.closed_at THEN
      RAISE EXCEPTION 'first closure is immutable' USING ERRCODE = '42501';
    END IF;
    NEW.updated_at := statement_timestamp();
    NEW.revision := OLD.revision + 1;
    IF NEW.state IS DISTINCT FROM OLD.state THEN NEW.authorization_epoch := OLD.authorization_epoch + 1; END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.enforce_space_transition() OWNER TO twogethera_membership_owner;
CREATE TRIGGER couple_spaces_guard BEFORE UPDATE ON public.couple_spaces
  FOR EACH ROW EXECUTE FUNCTION app_private.enforce_space_transition();

CREATE FUNCTION app_private.enforce_membership_transition()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_space_state text;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'membership history is immutable' USING ERRCODE = '42501'; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.id <> NEW.id OR OLD.couple_id <> NEW.couple_id OR OLD.user_id <> NEW.user_id OR OLD.seat <> NEW.seat
       OR OLD.created_at <> NEW.created_at THEN
      RAISE EXCEPTION 'immutable membership identity' USING ERRCODE = '42501';
    END IF;
    IF OLD.state <> 'active' OR NEW.state <> 'revoked' THEN
      RAISE EXCEPTION 'membership transition must be active to revoked' USING ERRCODE = '42501';
    END IF;
    SELECT state INTO v_space_state FROM public.couple_spaces WHERE id = OLD.couple_id FOR UPDATE;
    IF v_space_state IN ('archived','purging') THEN
      RAISE EXCEPTION 'closed space membership is immutable' USING ERRCODE = '42501';
    END IF;
    NEW.revoked_at := statement_timestamp();
    NEW.updated_at := statement_timestamp();
    NEW.revision := OLD.revision + 1;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'active' OR NEW.revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'new memberships must start active' USING ERRCODE = '42501';
    END IF;
    SELECT state INTO v_space_state FROM public.couple_spaces WHERE id = NEW.couple_id FOR UPDATE;
    IF v_space_state IN ('archived','purging') THEN
      RAISE EXCEPTION 'closed space cannot accept a member' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.enforce_membership_transition() OWNER TO twogethera_membership_owner;
CREATE TRIGGER couple_memberships_guard BEFORE INSERT OR UPDATE OR DELETE ON public.couple_memberships
  FOR EACH ROW EXECUTE FUNCTION app_private.enforce_membership_transition();

CREATE FUNCTION app_private.check_membership_cardinality()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_couple_id uuid; v_state text; v_active bigint; v_active_seat1 bigint;
BEGIN
  IF TG_TABLE_NAME = 'couple_spaces' THEN
    v_couple_id := coalesce(NEW.id, OLD.id);
  ELSE
    v_couple_id := coalesce(NEW.couple_id, OLD.couple_id);
  END IF;
  SELECT state INTO v_state FROM public.couple_spaces WHERE id = v_couple_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT count(*), count(*) FILTER (WHERE seat = 1) INTO v_active, v_active_seat1
    FROM public.couple_memberships
    WHERE couple_id = v_couple_id AND state = 'active';
  IF (v_state = 'draft' AND (v_active <> 1 OR v_active_seat1 <> 1))
     OR (v_state = 'paired' AND v_active <> 2)
     OR (v_state IN ('archived','purging') AND v_active <> 0) THEN
    RAISE EXCEPTION 'invalid couple membership cardinality' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END
$function$;
ALTER FUNCTION app_private.check_membership_cardinality() OWNER TO twogethera_membership_owner;
CREATE CONSTRAINT TRIGGER couple_spaces_cardinality AFTER INSERT OR UPDATE ON public.couple_spaces
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app_private.check_membership_cardinality();
CREATE CONSTRAINT TRIGGER couple_memberships_cardinality AFTER INSERT OR UPDATE OR DELETE ON public.couple_memberships
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app_private.check_membership_cardinality();

CREATE FUNCTION public.create_couple_space(p_operation_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_actor uuid; v_existing uuid; v_couple uuid;
BEGIN
  IF p_operation_id IS NULL THEN RAISE EXCEPTION 'invalid operation' USING ERRCODE = '22023'; END IF;
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 0));
  SELECT couple_id INTO v_existing FROM app_private.couple_create_receipts
    WHERE actor_user_id = v_actor AND operation_id = p_operation_id;
  IF FOUND THEN RETURN v_existing; END IF;
  IF EXISTS (SELECT 1 FROM public.couple_memberships WHERE user_id = v_actor AND state = 'active') THEN
    RAISE EXCEPTION 'active couple already exists' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.couple_spaces DEFAULT VALUES RETURNING id INTO v_couple;
  INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES(v_couple,v_actor,1);
  INSERT INTO app_private.couple_create_receipts(actor_user_id,operation_id,couple_id)
    VALUES(v_actor,p_operation_id,v_couple);
  RETURN v_couple;
END
$function$;
ALTER FUNCTION public.create_couple_space(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.create_couple_space(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_couple_space(uuid) TO authenticated;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.current_identity_is_verified(boolean) TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.enforce_space_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app_private.enforce_membership_transition() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app_private.check_membership_cardinality() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL TABLES IN SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
