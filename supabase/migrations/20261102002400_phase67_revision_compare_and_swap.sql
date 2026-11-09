-- Enforce optimistic concurrency in PostgreSQL, not only in Flutter filters.
-- Authenticated clients lose direct UPDATE access and must use these scoped,
-- revision-checked commands. The existing row triggers remain authoritative
-- for actor attribution, lifecycle validation, and revision increments.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.current_identity_is_verified(boolean) TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.can_read_shared_records(uuid) TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE FUNCTION public.update_date_night_idea(
  p_couple_id uuid, p_idea_id uuid, p_expected_revision bigint, p_changes jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint; v_rows integer;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_changes IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'object'
     OR p_changes = '{}'::jsonb THEN
    RETURN 'invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_changes) AS k(key)
       WHERE key <> ALL (ARRAY['title','description','status','scheduled_on',
         'estimated_amount_minor','estimated_currency_code','location','shared_notes','plan_id'])) THEN
    RETURN 'invalid';
  END IF;
  PERFORM 1 FROM public.couple_spaces WHERE id = p_couple_id FOR SHARE;
  IF NOT FOUND OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN 'unavailable'; END IF;
  SELECT revision INTO v_revision FROM public.date_night_ideas
   WHERE id = p_idea_id AND couple_id = p_couple_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'unavailable'; END IF;
  IF v_revision <> p_expected_revision THEN RETURN 'conflict'; END IF;
  UPDATE public.date_night_ideas SET
    title = CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE title END,
    description = CASE WHEN p_changes ? 'description' THEN p_changes->>'description' ELSE description END,
    status = CASE WHEN p_changes ? 'status' THEN p_changes->>'status' ELSE status END,
    scheduled_on = CASE WHEN p_changes ? 'scheduled_on' THEN (p_changes->>'scheduled_on')::date ELSE scheduled_on END,
    estimated_amount_minor = CASE WHEN p_changes ? 'estimated_amount_minor' THEN (p_changes->>'estimated_amount_minor')::bigint ELSE estimated_amount_minor END,
    estimated_currency_code = CASE WHEN p_changes ? 'estimated_currency_code' THEN p_changes->>'estimated_currency_code' ELSE estimated_currency_code END,
    location = CASE WHEN p_changes ? 'location' THEN p_changes->>'location' ELSE location END,
    shared_notes = CASE WHEN p_changes ? 'shared_notes' THEN p_changes->>'shared_notes' ELSE shared_notes END,
    plan_id = CASE WHEN p_changes ? 'plan_id' THEN (p_changes->>'plan_id')::uuid ELSE plan_id END
   WHERE id = p_idea_id AND couple_id = p_couple_id AND revision = p_expected_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RETURN 'conflict'; END IF;
  RETURN 'updated';
END
$function$;

CREATE FUNCTION public.update_shared_goal(
  p_couple_id uuid, p_goal_id uuid, p_expected_revision bigint, p_changes jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint; v_rows integer;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_changes IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'object'
     OR p_changes = '{}'::jsonb THEN
    RETURN 'invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_changes) AS k(key)
       WHERE key <> ALL (ARRAY['title','description','category','target_on','status'])) THEN
    RETURN 'invalid';
  END IF;
  PERFORM 1 FROM public.couple_spaces WHERE id = p_couple_id FOR SHARE;
  IF NOT FOUND OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN 'unavailable'; END IF;
  SELECT revision INTO v_revision FROM public.shared_goals
   WHERE id = p_goal_id AND couple_id = p_couple_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'unavailable'; END IF;
  IF v_revision <> p_expected_revision THEN RETURN 'conflict'; END IF;
  UPDATE public.shared_goals SET
    title = CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE title END,
    description = CASE WHEN p_changes ? 'description' THEN p_changes->>'description' ELSE description END,
    category = CASE WHEN p_changes ? 'category' THEN p_changes->>'category' ELSE category END,
    target_on = CASE WHEN p_changes ? 'target_on' THEN (p_changes->>'target_on')::date ELSE target_on END,
    status = CASE WHEN p_changes ? 'status' THEN p_changes->>'status' ELSE status END
   WHERE id = p_goal_id AND couple_id = p_couple_id AND revision = p_expected_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RETURN 'conflict'; END IF;
  RETURN 'updated';
END
$function$;

CREATE FUNCTION public.update_shared_goal_milestone(
  p_couple_id uuid, p_goal_id uuid, p_milestone_id uuid,
  p_expected_revision bigint, p_changes jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint; v_rows integer;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_changes IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'object'
     OR p_changes = '{}'::jsonb THEN
    RETURN 'invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_changes) AS k(key)
       WHERE key <> ALL (ARRAY['title','description','target_on','is_completed','sort_order'])) THEN
    RETURN 'invalid';
  END IF;
  PERFORM 1 FROM public.couple_spaces WHERE id = p_couple_id FOR SHARE;
  IF NOT FOUND OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN 'unavailable'; END IF;
  SELECT revision INTO v_revision FROM public.shared_goal_milestones
   WHERE id = p_milestone_id AND goal_id = p_goal_id AND couple_id = p_couple_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'unavailable'; END IF;
  IF v_revision <> p_expected_revision THEN RETURN 'conflict'; END IF;
  UPDATE public.shared_goal_milestones SET
    title = CASE WHEN p_changes ? 'title' THEN p_changes->>'title' ELSE title END,
    description = CASE WHEN p_changes ? 'description' THEN p_changes->>'description' ELSE description END,
    target_on = CASE WHEN p_changes ? 'target_on' THEN (p_changes->>'target_on')::date ELSE target_on END,
    is_completed = CASE WHEN p_changes ? 'is_completed' THEN (p_changes->>'is_completed')::boolean ELSE is_completed END,
    sort_order = CASE WHEN p_changes ? 'sort_order' THEN (p_changes->>'sort_order')::integer ELSE sort_order END
   WHERE id = p_milestone_id AND goal_id = p_goal_id AND couple_id = p_couple_id
     AND revision = p_expected_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RETURN 'conflict'; END IF;
  RETURN 'updated';
END
$function$;

ALTER FUNCTION public.update_date_night_idea(uuid,uuid,bigint,jsonb) OWNER TO twogethera_membership_owner;
ALTER FUNCTION public.update_shared_goal(uuid,uuid,bigint,jsonb) OWNER TO twogethera_membership_owner;
ALTER FUNCTION public.update_shared_goal_milestone(uuid,uuid,uuid,bigint,jsonb) OWNER TO twogethera_membership_owner;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE UPDATE ON public.date_night_ideas, public.shared_goals, public.shared_goal_milestones FROM PUBLIC, anon, authenticated, service_role;
REVOKE UPDATE (title,description,status,scheduled_on,estimated_amount_minor,estimated_currency_code,location,shared_notes,plan_id)
  ON public.date_night_ideas FROM PUBLIC, anon, authenticated, service_role;
REVOKE UPDATE (title,description,category,target_on,status)
  ON public.shared_goals FROM PUBLIC, anon, authenticated, service_role;
REVOKE UPDATE (title,description,target_on,is_completed,sort_order)
  ON public.shared_goal_milestones FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_date_night_idea(uuid,uuid,bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_shared_goal(uuid,uuid,bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_shared_goal_milestone(uuid,uuid,uuid,bigint,jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_date_night_idea(uuid,uuid,bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_shared_goal(uuid,uuid,bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_shared_goal_milestone(uuid,uuid,uuid,bigint,jsonb) TO authenticated;
COMMIT;
NOTIFY pgrst, 'reload schema';
