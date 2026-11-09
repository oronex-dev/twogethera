-- CP-024: use Supabase Auth's signed AMR password timestamp for recent
-- reauthentication. Routine refresh preserves this timestamp; a new password
-- sign-in creates a new Auth session and timestamp. Never trust user metadata.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- The role's DDL privileges were revoked after prior migrations. Temporarily
-- grant only the schemas needed to create/replace its owned functions; these
-- grants are revoked before this transaction commits.
GRANT CREATE ON SCHEMA app_private, public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION app_private.current_request_password_auth_time()
RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = '' AS $function$
DECLARE
  v_claims jsonb;
  v_amr jsonb;
  v_entry jsonb;
  v_method text;
  v_timestamp jsonb;
  v_timestamp_text text;
  v_entry_timestamp bigint;
  v_password_auth_time bigint;
  v_now bigint := floor(extract(epoch FROM statement_timestamp()))::bigint;
BEGIN
  IF NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '') IS NULL THEN
    RETURN NULL;
  END IF;
  BEGIN
    v_claims := pg_catalog.current_setting('request.jwt.claims', true)::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF pg_catalog.jsonb_typeof(v_claims) IS DISTINCT FROM 'object' THEN RETURN NULL; END IF;
  v_amr := v_claims -> 'amr';
  IF pg_catalog.jsonb_typeof(v_amr) IS DISTINCT FROM 'array' THEN RETURN NULL; END IF;
  IF pg_catalog.jsonb_array_length(v_amr) = 0 THEN RETURN NULL; END IF;

  FOR v_entry IN SELECT value FROM pg_catalog.jsonb_array_elements(v_amr)
  LOOP
    IF pg_catalog.jsonb_typeof(v_entry) IS DISTINCT FROM 'object' THEN RETURN NULL; END IF;
    IF pg_catalog.jsonb_typeof(v_entry -> 'method') IS DISTINCT FROM 'string'
       OR pg_catalog.jsonb_typeof(v_entry -> 'timestamp') IS DISTINCT FROM 'number' THEN
      RETURN NULL;
    END IF;
    v_method := v_entry ->> 'method';
    -- Only the supported password method can satisfy this gate. Reject
    -- unexpected methods rather than silently treating unknown claims as proof.
    IF v_method IS DISTINCT FROM 'password' THEN RETURN NULL; END IF;
    v_timestamp := v_entry -> 'timestamp';
    v_timestamp_text := v_timestamp::text;
    IF v_timestamp_text !~ '^[0-9]{1,12}$' THEN RETURN NULL; END IF;
    v_entry_timestamp := v_timestamp_text::bigint;
    IF v_entry_timestamp > v_now THEN RETURN NULL; END IF;
    v_password_auth_time := greatest(v_password_auth_time, v_entry_timestamp);
  END LOOP;

  RETURN v_password_auth_time;
END
$function$;
REVOKE ALL ON FUNCTION app_private.current_request_password_auth_time()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.request_my_account_deletion(p_operation_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_password_auth_time bigint := app_private.current_request_password_auth_time();
  v_request_id uuid;
BEGIN
  v_actor := app_private.current_identity_for_deletion(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE = '42501'; END IF;
  IF p_operation_id IS NULL OR v_password_auth_time IS NULL
     OR v_password_auth_time < floor(extract(epoch FROM statement_timestamp()))::bigint - 600 THEN
    RAISE EXCEPTION 'recent reauthentication required' USING ERRCODE = '42501';
  END IF;
  SELECT request_id INTO v_request_id FROM app_private.account_deletion_requests
    WHERE user_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN RETURN v_request_id; END IF;
  IF EXISTS (SELECT 1 FROM app_private.account_deletion_requests WHERE user_id=v_actor) THEN
    RAISE EXCEPTION 'account deletion already pending' USING ERRCODE='42501';
  END IF;
  PERFORM public.close_my_couple_space(p_operation_id);
  UPDATE public.user_profiles SET avatar_path=NULL WHERE user_id=v_actor;
  v_request_id := gen_random_uuid();
  INSERT INTO app_private.account_deletion_requests(request_id,user_id,operation_id,state)
    VALUES(v_request_id,v_actor,p_operation_id,'pending');
  RETURN v_request_id;
END
$function$;
ALTER FUNCTION public.request_my_account_deletion(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.request_my_account_deletion(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_my_account_deletion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_my_privacy_removal(
  p_operation_id uuid,p_table text,p_record_id uuid,p_field text DEFAULT NULL,p_remove_record boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_couple uuid;
  v_request uuid;
  v_allowed boolean := false;
  v_password_auth_time bigint := app_private.current_request_password_auth_time();
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_record_id IS NULL OR v_password_auth_time IS NULL
     OR v_password_auth_time < floor(extract(epoch FROM statement_timestamp()))::bigint - 600 THEN
    RAISE EXCEPTION 'recent reauthentication required' USING ERRCODE='42501';
  END IF;
  SELECT request_id INTO v_request FROM app_private.privacy_removal_requests
    WHERE requester_user_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN RETURN v_request; END IF;
  IF p_table NOT IN ('bucket_list_items','important_dates','plans','plan_tasks','couple_memories',
       'date_night_ideas','shared_goals','shared_goal_milestones',
       'couple_expenses','recurring_expense_rules','memory_attachments','expense_receipts') THEN
    RAISE EXCEPTION 'unsupported privacy target' USING ERRCODE='22023';
  END IF;
  IF p_remove_record THEN
    v_allowed := p_field IS NULL;
  ELSE
    v_allowed := (p_table,p_field) IN (
      ('bucket_list_items','description'),('important_dates','notes'),
      ('plans','description'),('plans','location'),('couple_memories','caption'),
      ('couple_memories','personal_notes'),('date_night_ideas','description'),
      ('date_night_ideas','location'),('date_night_ideas','shared_notes'),
      ('shared_goals','description'),('shared_goal_milestones','description'),
      ('couple_expenses','description'),('recurring_expense_rules','description')
    );
  END IF;
  IF NOT v_allowed THEN RAISE EXCEPTION 'unsupported privacy field' USING ERRCODE='22023'; END IF;
  EXECUTE format('SELECT couple_id FROM public.%I WHERE id=$1',p_table) INTO v_couple USING p_record_id;
  IF v_couple IS NULL OR NOT app_private.can_read_shared_records(v_couple) THEN
    RAISE EXCEPTION 'record unavailable' USING ERRCODE='42501';
  END IF;
  v_request := gen_random_uuid();
  IF p_table IN ('plans','shared_goals') THEN
    UPDATE app_private.lifecycle_purge_jobs SET state='cancelled',lease_until=NULL
     WHERE job_kind='ordinary_record' AND state IN ('pending','retry') AND target_table IN ('plan_tasks','shared_goal_milestones')
       AND target_id IN (SELECT d.target_id FROM app_private.ordinary_deleted_records d
         WHERE d.parent_table=p_table AND d.parent_id=p_record_id);
    DELETE FROM app_private.ordinary_deleted_records WHERE parent_table=p_table AND parent_id=p_record_id;
  END IF;
  UPDATE app_private.lifecycle_purge_jobs SET state='cancelled',lease_until=NULL
    WHERE job_kind='ordinary_record' AND state IN ('pending','retry') AND target_table=p_table AND target_id=p_record_id;
  DELETE FROM app_private.ordinary_deleted_records WHERE target_table=p_table AND target_id=p_record_id;
  IF p_remove_record THEN
    INSERT INTO app_private.privacy_content_blocks(couple_id,target_table,target_id,retain_until)
      VALUES(v_couple,p_table,p_record_id,statement_timestamp()+interval '31 days')
      ON CONFLICT(target_table,target_id) DO NOTHING;
    INSERT INTO app_private.lifecycle_purge_jobs(job_kind,couple_id,target_table,target_id,due_at)
      VALUES('privacy_record',v_couple,p_table,p_record_id,statement_timestamp())
      ON CONFLICT DO NOTHING;
    INSERT INTO app_private.privacy_removal_requests(request_id,operation_id,requester_user_id,couple_id,target_table,target_id,target_field,removes_record,state)
      VALUES(v_request,p_operation_id,v_actor,v_couple,p_table,p_record_id,NULL,true,'blocked');
  ELSE
    EXECUTE format('UPDATE public.%I SET %I = '''' WHERE id=$1 AND couple_id=$2',p_table,p_field)
      USING p_record_id,v_couple;
    INSERT INTO app_private.privacy_removal_requests(request_id,operation_id,requester_user_id,couple_id,target_table,target_id,target_field,removes_record,state,completed_at)
      VALUES(v_request,p_operation_id,v_actor,v_couple,p_table,p_record_id,p_field,false,'redacted',statement_timestamp());
  END IF;
  RETURN v_request;
END
$function$;
ALTER FUNCTION public.record_my_privacy_removal(uuid,text,uuid,text,boolean) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.record_my_privacy_removal(uuid,text,uuid,text,boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_my_privacy_removal(uuid,text,uuid,text,boolean) TO authenticated;

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private, public FROM twogethera_membership_owner;

DO $preflight$
DECLARE
  v_oid oid := 'app_private.current_request_password_auth_time()'::regprocedure;
BEGIN
  IF pg_catalog.pg_get_userbyid((SELECT proowner FROM pg_catalog.pg_proc WHERE oid=v_oid))
       <> 'twogethera_membership_owner'
     OR (SELECT prosecdef FROM pg_catalog.pg_proc WHERE oid=v_oid)
     OR NOT ((SELECT proconfig FROM pg_catalog.pg_proc WHERE oid=v_oid) @> ARRAY['search_path=""'])
     OR NOT pg_catalog.has_function_privilege('twogethera_membership_owner',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'signed password claim helper has unsafe ownership or execution settings';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) AS api_role(name)
    WHERE pg_catalog.has_function_privilege(api_role.name,v_oid,'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'signed password claim helper is executable by an API role';
  END IF;
END
$preflight$;

COMMIT;
