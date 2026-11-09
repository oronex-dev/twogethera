-- Serialize milestone completion against goal completion and votes against
-- date-night selection so concurrent requests cannot cross lifecycle checks.
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
  IF TG_TABLE_NAME = 'shared_goal_milestones' THEN
    PERFORM 1 FROM public.shared_goals g WHERE g.id = NEW.goal_id AND g.couple_id = NEW.couple_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'goal unavailable' USING ERRCODE = '42501'; END IF;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := v_actor; NEW.updated_by := v_actor;
    NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.revision := 1;
    IF TG_TABLE_NAME = 'date_night_ideas' THEN NEW.status := 'proposed'; END IF;
    IF TG_TABLE_NAME = 'shared_goals' THEN NEW.status := 'active'; END IF;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'identity and revision are server controlled' USING ERRCODE = '42501';
    END IF;
    IF TG_TABLE_NAME = 'date_night_ideas' AND NOT (
      (OLD.status = 'proposed' AND NEW.status IN ('proposed','selected','cancelled')) OR
      (OLD.status = 'selected' AND NEW.status IN ('proposed','selected','scheduled','cancelled')) OR
      (OLD.status = 'scheduled' AND NEW.status IN ('selected','scheduled','completed','cancelled')) OR
      (OLD.status IN ('completed','cancelled') AND NEW.status = OLD.status)
    ) THEN RAISE EXCEPTION 'invalid date-night lifecycle transition' USING ERRCODE = '23514'; END IF;
    IF TG_TABLE_NAME = 'shared_goals' AND NOT (
      (OLD.status = 'active' AND NEW.status IN ('active','paused','completed')) OR
      (OLD.status = 'paused' AND NEW.status IN ('active','paused','completed')) OR
      (OLD.status = 'completed' AND NEW.status = 'completed')
    ) THEN RAISE EXCEPTION 'invalid shared-goal lifecycle transition' USING ERRCODE = '23514'; END IF;
    IF TG_TABLE_NAME = 'shared_goals' AND NEW.status = 'completed'
       AND EXISTS (SELECT 1 FROM public.shared_goal_milestones m WHERE m.couple_id = NEW.couple_id AND m.goal_id = NEW.id AND NOT m.is_completed) THEN
      RAISE EXCEPTION 'complete all milestones before completing this goal' USING ERRCODE = '23514';
    END IF;
    NEW.updated_by := v_actor; NEW.updated_at := statement_timestamp(); NEW.revision := OLD.revision + 1;
  END IF;
  IF TG_TABLE_NAME = 'shared_goal_milestones' THEN
    IF TG_OP = 'INSERT' OR OLD.is_completed IS DISTINCT FROM NEW.is_completed THEN
      NEW.completed_at := CASE WHEN NEW.is_completed THEN statement_timestamp() ELSE NULL END;
    ELSE NEW.completed_at := OLD.completed_at;
    END IF;
    IF NOT NEW.is_completed AND EXISTS (SELECT 1 FROM public.shared_goals g WHERE g.couple_id = NEW.couple_id AND g.id = NEW.goal_id AND g.status = 'completed') THEN
      RAISE EXCEPTION 'completed goal milestones cannot be reopened' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_cp012_row() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_cp012_row() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION app_private.guard_date_night_vote()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_status text;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL OR NEW.user_id IS DISTINCT FROM v_actor
     OR NOT app_private.can_read_shared_records(NEW.couple_id) THEN
    RAISE EXCEPTION 'only a current couple member may record their own response' USING ERRCODE = '42501';
  END IF;
  SELECT i.status INTO v_status FROM public.date_night_ideas i
   WHERE i.id = NEW.idea_id AND i.couple_id = NEW.couple_id FOR UPDATE;
  IF NOT FOUND OR v_status <> 'proposed' THEN
    RAISE EXCEPTION 'responses are available only for proposed ideas' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := statement_timestamp();
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_date_night_vote() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_date_night_vote() FROM PUBLIC, anon, authenticated, service_role;

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
COMMIT;
