-- CP-013 follow-up: expose only metadata needed by the paired recovery flow,
-- cancel parent-child purge jobs on goal restore, serialize privacy requests
-- against concurrent deletes, and keep audit deltas in a stable currency.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION public.list_my_recoverable_shared_records()
RETURNS TABLE(
  target_table text,
  target_id uuid,
  deleted_at timestamptz,
  restore_until timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'active paired couple required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
    SELECT d.target_table,d.target_id,d.deleted_at,d.restore_until
      FROM app_private.ordinary_deleted_records d
     WHERE d.restore_until>statement_timestamp()
       AND d.parent_table IS NULL
       AND app_private.can_read_shared_records(d.couple_id)
       AND NOT EXISTS (
         SELECT 1 FROM app_private.privacy_content_blocks b
          WHERE b.target_table=d.target_table AND b.target_id=d.target_id
       )
     ORDER BY d.deleted_at DESC;
END
$function$;
ALTER FUNCTION public.list_my_recoverable_shared_records() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.list_my_recoverable_shared_records() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.list_my_recoverable_shared_records() TO authenticated;

CREATE OR REPLACE FUNCTION public.restore_my_shared_record(p_table text,p_record_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_couple uuid; v_until timestamptz;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR p_record_id IS NULL OR p_table NOT IN (
    'bucket_list_items','important_dates','plans','plan_tasks','couple_memories',
    'date_night_ideas','shared_goals','shared_goal_milestones'
  ) THEN RETURN false; END IF;
  SELECT couple_id,restore_until INTO v_couple,v_until
    FROM app_private.ordinary_deleted_records
   WHERE target_table=p_table AND target_id=p_record_id FOR UPDATE;
  IF NOT FOUND THEN
    EXECUTE format('SELECT couple_id FROM public.%I WHERE id=$1',p_table)
      INTO v_couple USING p_record_id;
    RETURN v_couple IS NOT NULL AND app_private.can_read_shared_records(v_couple)
      AND app_private.content_is_unblocked(p_table,p_record_id);
  END IF;
  IF v_until<=statement_timestamp() OR NOT app_private.can_read_shared_records(v_couple)
     OR EXISTS(SELECT 1 FROM app_private.privacy_content_blocks
        WHERE target_table=p_table AND target_id=p_record_id) THEN
    RETURN false;
  END IF;
  PERFORM 1 FROM public.couple_spaces WHERE id=v_couple AND state='paired' FOR SHARE;
  IF NOT FOUND THEN RETURN false; END IF;

  IF EXISTS(
    SELECT 1 FROM app_private.lifecycle_purge_jobs j
     WHERE j.job_kind='ordinary_record' AND j.state='processing'
       AND ((j.target_table=p_table AND j.target_id=p_record_id)
         OR (p_table='plans' AND j.target_table='plan_tasks' AND EXISTS(
           SELECT 1 FROM app_private.ordinary_deleted_records d
            WHERE d.target_table='plan_tasks' AND d.target_id=j.target_id
              AND d.parent_table='plans' AND d.parent_id=p_record_id))
         OR (p_table='shared_goals' AND j.target_table='shared_goal_milestones' AND EXISTS(
           SELECT 1 FROM app_private.ordinary_deleted_records d
            WHERE d.target_table='shared_goal_milestones' AND d.target_id=j.target_id
              AND d.parent_table='shared_goals' AND d.parent_id=p_record_id)))
  ) THEN RETURN false; END IF;

  UPDATE app_private.lifecycle_purge_jobs j SET state='cancelled',lease_until=NULL
   WHERE j.job_kind='ordinary_record' AND j.state IN ('pending','retry')
     AND ((j.target_table=p_table AND j.target_id=p_record_id)
       OR (p_table='plans' AND j.target_table='plan_tasks' AND EXISTS(
         SELECT 1 FROM app_private.ordinary_deleted_records d
          WHERE d.target_table='plan_tasks' AND d.target_id=j.target_id
            AND d.parent_table='plans' AND d.parent_id=p_record_id))
       OR (p_table='shared_goals' AND j.target_table='shared_goal_milestones' AND EXISTS(
         SELECT 1 FROM app_private.ordinary_deleted_records d
          WHERE d.target_table='shared_goal_milestones' AND d.target_id=j.target_id
            AND d.parent_table='shared_goals' AND d.parent_id=p_record_id)));
  IF p_table IN ('plans','shared_goals') THEN
    DELETE FROM app_private.ordinary_deleted_records
     WHERE parent_table=p_table AND parent_id=p_record_id;
  END IF;
  DELETE FROM app_private.ordinary_deleted_records
   WHERE target_table=p_table AND target_id=p_record_id;
  RETURN true;
END
$function$;
ALTER FUNCTION public.restore_my_shared_record(text,uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.restore_my_shared_record(text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.restore_my_shared_record(text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION app_private.guard_financial_audit_currency()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF (NEW.currency_code,NEW.currency_exponent)
       IS DISTINCT FROM (OLD.currency_code,OLD.currency_exponent) THEN
    RAISE EXCEPTION 'expense currency cannot be changed after recording'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_financial_audit_currency() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_financial_audit_currency() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS a_financial_audit_currency_guard ON public.couple_expenses;
CREATE TRIGGER a_financial_audit_currency_guard
  BEFORE UPDATE ON public.couple_expenses
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_financial_audit_currency();

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
COMMIT;
