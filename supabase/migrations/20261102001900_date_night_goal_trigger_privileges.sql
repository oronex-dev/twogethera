-- CP-012 hardening: trigger guards need the membership-owner context to read
-- verified JWT identity; all client supplied ownership values remain ignored.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.can_read_shared_records(uuid) TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE OR REPLACE FUNCTION app_private.guard_cp012_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(NEW.couple_id) THEN
    RAISE EXCEPTION 'active couple membership required' USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := v_actor;
    NEW.updated_by := v_actor;
    NEW.created_at := statement_timestamp();
    NEW.updated_at := NEW.created_at;
    NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'identity and revision are server controlled' USING ERRCODE = '42501';
    END IF;
    NEW.updated_by := v_actor;
    NEW.updated_at := statement_timestamp();
    NEW.revision := OLD.revision + 1;
  END IF;
  IF TG_TABLE_NAME = 'shared_goal_milestones' THEN
    IF TG_OP = 'INSERT' OR OLD.is_completed IS DISTINCT FROM NEW.is_completed THEN
      NEW.completed_at := CASE WHEN NEW.is_completed THEN statement_timestamp() ELSE NULL END;
    ELSE
      NEW.completed_at := OLD.completed_at;
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_cp012_row() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_cp012_row() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION app_private.guard_date_night_vote()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL OR NEW.user_id IS DISTINCT FROM v_actor
     OR NOT app_private.can_read_shared_records(NEW.couple_id) THEN
    RAISE EXCEPTION 'only a current couple member may record their own response' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.date_night_ideas i WHERE i.id = NEW.idea_id AND i.couple_id = NEW.couple_id AND i.status = 'proposed') THEN
    RAISE EXCEPTION 'responses are available only for proposed ideas' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := statement_timestamp();
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_date_night_vote() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_date_night_vote() FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY IF EXISTS date_night_vote_pair_access ON public.date_night_votes;
CREATE POLICY date_night_vote_pair_access ON public.date_night_votes FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id) AND user_id = (COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), ''), (NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid))
  WITH CHECK (app_private.can_read_shared_records(couple_id) AND user_id = (COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), ''), (NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid));

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
COMMIT;
