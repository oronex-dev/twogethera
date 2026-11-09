-- CP-013: Private Beta V1 allowlist, couple closure, privacy blocking, and
-- minimized financial event capture. This migration is additive. It does not
-- delete existing accounts or records and does not configure hosted Auth.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Read only the claims PostgREST installed after verifying the request JWT.
-- The restricted owner does not need access to the managed auth schema.
CREATE FUNCTION app_private.current_request_role()
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $function$
  SELECT NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
$function$;
REVOKE ALL ON FUNCTION app_private.current_request_role()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION app_private.current_request_auth_time()
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $function$
  SELECT NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'auth_time'
$function$;
REVOKE ALL ON FUNCTION app_private.current_request_auth_time()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE app_private.private_beta_allowlist (
  slot smallint PRIMARY KEY CHECK (slot IN (1,2)),
  user_id uuid NOT NULL UNIQUE,
  configured_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

CREATE TABLE app_private.account_deletion_requests (
  request_id uuid PRIMARY KEY,
  user_id uuid UNIQUE,
  operation_id uuid NOT NULL,
  state text NOT NULL CHECK (state IN ('pending','processing','failed','complete')),
  lease_until timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  failure_code text CHECK (failure_code IS NULL OR failure_code IN ('auth_admin_unavailable','auth_delete_rejected','unknown')),
  requested_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  completed_at timestamptz,
  UNIQUE (user_id, operation_id),
  CHECK ((state = 'complete') = (completed_at IS NOT NULL))
);

CREATE TABLE app_private.couple_closure_receipts (
  actor_user_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  couple_id uuid NOT NULL,
  closed_at timestamptz NOT NULL,
  PRIMARY KEY (actor_user_id, operation_id)
);

CREATE TABLE app_private.lifecycle_purge_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_kind text NOT NULL CHECK (job_kind IN ('privacy_record','ordinary_record','closed_couple')),
  couple_id uuid NOT NULL,
  target_table text,
  target_id uuid,
  due_at timestamptz NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','processing','retry','complete','cancelled')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  lease_until timestamptz,
  last_error_code text CHECK (last_error_code IS NULL OR last_error_code IN ('row_delete_restricted','temporary_unavailable','unknown')),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CHECK ((job_kind IN ('privacy_record','ordinary_record')) = (target_table IS NOT NULL AND target_id IS NOT NULL)),
  CHECK ((job_kind = 'closed_couple') = (target_table IS NULL AND target_id IS NULL))
);
CREATE UNIQUE INDEX lifecycle_purge_privacy_target_once
  ON app_private.lifecycle_purge_jobs(job_kind, couple_id, target_table, target_id)
  WHERE job_kind = 'privacy_record';
CREATE UNIQUE INDEX lifecycle_purge_ordinary_target_active_once
  ON app_private.lifecycle_purge_jobs(job_kind, couple_id, target_table, target_id)
  WHERE job_kind = 'ordinary_record' AND state IN ('pending','processing','retry');
CREATE UNIQUE INDEX lifecycle_purge_closed_couple_once
  ON app_private.lifecycle_purge_jobs(job_kind, couple_id)
  WHERE job_kind = 'closed_couple';
CREATE INDEX lifecycle_purge_jobs_due ON app_private.lifecycle_purge_jobs(available_at, due_at)
  WHERE state IN ('pending','retry');
CREATE TABLE app_private.ordinary_deleted_records (
  couple_id uuid NOT NULL,
  target_table text NOT NULL,
  target_id uuid NOT NULL,
  parent_table text,
  parent_id uuid,
  deleted_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  restore_until timestamptz NOT NULL,
  PRIMARY KEY (target_table,target_id),
  CHECK ((parent_table IS NULL) = (parent_id IS NULL)),
  CHECK (restore_until = deleted_at + interval '7 days')
);

CREATE TABLE app_private.privacy_removal_requests (
  request_id uuid PRIMARY KEY,
  operation_id uuid NOT NULL,
  requester_user_id uuid NOT NULL,
  couple_id uuid NOT NULL,
  target_table text NOT NULL,
  target_id uuid NOT NULL,
  target_field text,
  removes_record boolean NOT NULL,
  state text NOT NULL CHECK (state IN ('blocked','redacted','purged','retry')),
  requested_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  completed_at timestamptz,
  UNIQUE (requester_user_id, operation_id)
);

CREATE TABLE app_private.privacy_content_blocks (
  couple_id uuid NOT NULL,
  target_table text NOT NULL,
  target_id uuid NOT NULL,
  blocked_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  retain_until timestamptz NOT NULL,
  PRIMARY KEY (target_table, target_id)
);

CREATE TABLE app_private.financial_audit_scopes (
  couple_id uuid PRIMARY KEY,
  opaque_couple_ref uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  next_sequence bigint NOT NULL DEFAULT 1 CHECK (next_sequence > 0),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

CREATE TABLE app_private.financial_audit_actor_aliases (
  couple_id uuid NOT NULL REFERENCES app_private.financial_audit_scopes(couple_id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  actor_alias uuid NOT NULL DEFAULT gen_random_uuid(),
  PRIMARY KEY (couple_id, user_id),
  UNIQUE (couple_id, actor_alias)
);

CREATE TABLE app_private.financial_audit_heads (
  couple_id uuid NOT NULL REFERENCES app_private.financial_audit_scopes(couple_id) ON DELETE CASCADE,
  source_expense_id uuid NOT NULL,
  audit_event_id uuid NOT NULL,
  PRIMARY KEY (couple_id, source_expense_id)
);

CREATE TABLE app_private.financial_audit_retention (
  opaque_couple_ref uuid PRIMARY KEY,
  closed_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  CHECK (expires_at = closed_at + interval '90 days')
);

CREATE TABLE app_private.financial_audit_events (
  audit_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opaque_couple_ref uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('recorded','corrected','reversed')),
  actor_alias uuid NOT NULL,
  amount_minor bigint NOT NULL,
  currency_code text NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  currency_exponent smallint NOT NULL CHECK (currency_exponent BETWEEN 0 AND 3),
  effective_date date NOT NULL,
  event_sequence bigint NOT NULL CHECK (event_sequence > 0),
  schema_version smallint NOT NULL DEFAULT 1 CHECK (schema_version = 1),
  correction_reference uuid,
  UNIQUE (opaque_couple_ref, event_sequence),
  UNIQUE (opaque_couple_ref, audit_event_id),
  FOREIGN KEY (opaque_couple_ref, correction_reference)
    REFERENCES app_private.financial_audit_events(opaque_couple_ref, audit_event_id)
    DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX financial_audit_events_expiry_lookup
  ON app_private.financial_audit_events(opaque_couple_ref, event_sequence);

REVOKE ALL ON ALL TABLES IN SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;

RESET ROLE;
GRANT SELECT ON app_private.private_beta_allowlist,
  app_private.account_deletion_requests TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON app_private.private_beta_allowlist,
  app_private.account_deletion_requests, app_private.couple_closure_receipts,
  app_private.lifecycle_purge_jobs, app_private.ordinary_deleted_records, app_private.privacy_removal_requests,
  app_private.privacy_content_blocks, app_private.financial_audit_scopes,
  app_private.financial_audit_actor_aliases, app_private.financial_audit_heads,
  app_private.financial_audit_retention, app_private.financial_audit_events
  TO twogethera_membership_owner;

CREATE OR REPLACE FUNCTION app_private.current_identity_is_verified(p_lock boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_confirmed timestamptz;
  v_banned_until timestamptz;
  v_anonymous boolean;
  v_token_exp text := auth.jwt() ->> 'exp';
BEGIN
  IF v_user_id IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN RETURN NULL; END IF;
  IF v_token_exp IS NULL OR v_token_exp !~ '^[0-9]{1,12}$'
     OR v_token_exp::bigint <= floor(extract(epoch FROM statement_timestamp()))::bigint THEN RETURN NULL; END IF;
  IF (SELECT count(*) FROM app_private.private_beta_allowlist) <> 2
     OR NOT EXISTS (SELECT 1 FROM app_private.private_beta_allowlist WHERE user_id = v_user_id)
     OR EXISTS (SELECT 1 FROM app_private.account_deletion_requests
                WHERE user_id = v_user_id AND state IN ('pending','failed')) THEN
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

-- The deletion request entry point can retry its idempotency key after its own
-- request has fenced normal application access. This verifier still trusts
-- only Auth-managed identity and the fixed two-account allowlist.
CREATE FUNCTION app_private.current_identity_for_deletion(p_lock boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_confirmed timestamptz;
  v_banned_until timestamptz;
  v_anonymous boolean;
  v_token_exp text := auth.jwt() ->> 'exp';
BEGIN
  IF v_user_id IS NULL OR auth.role() IS DISTINCT FROM 'authenticated'
     OR v_token_exp IS NULL OR v_token_exp !~ '^[0-9]{1,12}$'
     OR v_token_exp::bigint <= floor(extract(epoch FROM statement_timestamp()))::bigint
     OR (SELECT count(*) FROM app_private.private_beta_allowlist) <> 2
     OR NOT EXISTS (SELECT 1 FROM app_private.private_beta_allowlist WHERE user_id=v_user_id) THEN
    RETURN NULL;
  END IF;
  IF p_lock THEN
    SELECT u.email_confirmed_at,u.banned_until,coalesce(u.is_anonymous,false)
      INTO v_confirmed,v_banned_until,v_anonymous FROM auth.users u WHERE u.id=v_user_id FOR SHARE;
  ELSE
    SELECT u.email_confirmed_at,u.banned_until,coalesce(u.is_anonymous,false)
      INTO v_confirmed,v_banned_until,v_anonymous FROM auth.users u WHERE u.id=v_user_id;
  END IF;
  IF v_confirmed IS NULL OR v_anonymous OR (v_banned_until IS NOT NULL AND v_banned_until>statement_timestamp()) THEN
    RETURN NULL;
  END IF;
  RETURN v_user_id;
END
$function$;
ALTER FUNCTION app_private.current_identity_for_deletion(boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION app_private.current_identity_for_deletion(boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION app_private.guard_beta_shared_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_couple_id uuid;
  v_state text;
BEGIN
  IF app_private.current_request_role() = 'service_role' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  v_couple_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.couple_id ELSE NEW.couple_id END;
  IF app_private.current_identity_is_verified(false) IS NULL THEN
    RAISE EXCEPTION 'private beta access required' USING ERRCODE = '42501';
  END IF;
  SELECT state INTO v_state FROM public.couple_spaces WHERE id = v_couple_id FOR SHARE;
  IF NOT FOUND OR v_state <> 'paired' OR NOT app_private.can_read_shared_records(v_couple_id) THEN
    RAISE EXCEPTION 'active paired couple required' USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END
$function$;
ALTER FUNCTION app_private.guard_beta_shared_mutation() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_beta_shared_mutation() FROM PUBLIC, anon, authenticated, service_role;

DO $guard$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'bucket_list_items','important_dates','plans','plan_tasks',
    'couple_budgets','budget_category_limits','recurring_expense_rules',
    'couple_expenses','expense_receipts','couple_memories','memory_attachments',
    'date_night_ideas','date_night_votes','shared_goals','shared_goal_milestones'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS a_private_beta_scope_guard ON public.%I', v_table);
    EXECUTE format('CREATE TRIGGER a_private_beta_scope_guard BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION app_private.guard_beta_shared_mutation()', v_table);
  END LOOP;
END
$guard$;

CREATE FUNCTION app_private.capture_financial_audit_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_couple_id uuid;
  v_actor uuid;
  v_actor_alias uuid;
  v_opaque_ref uuid;
  v_prior_event uuid;
  v_event_id uuid := gen_random_uuid();
  v_seq bigint;
  v_type text;
  v_amount bigint;
  v_currency text;
  v_exponent smallint;
  v_effective_date date;
BEGIN
  IF app_private.current_request_role() = 'service_role' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  v_couple_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.couple_id ELSE NEW.couple_id END;
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE = '42501'; END IF;
  IF TG_OP = 'UPDATE' AND
     (OLD.amount_minor, OLD.currency_code, OLD.currency_exponent, OLD.occurred_on)
       IS NOT DISTINCT FROM
     (NEW.amount_minor, NEW.currency_code, NEW.currency_exponent, NEW.occurred_on) THEN
    RETURN NEW;
  END IF;

  INSERT INTO app_private.financial_audit_scopes(couple_id)
    VALUES (v_couple_id) ON CONFLICT (couple_id) DO NOTHING;
  SELECT opaque_couple_ref INTO v_opaque_ref
    FROM app_private.financial_audit_scopes WHERE couple_id = v_couple_id FOR UPDATE;
  INSERT INTO app_private.financial_audit_actor_aliases(couple_id,user_id)
    VALUES (v_couple_id,v_actor) ON CONFLICT (couple_id,user_id) DO NOTHING;
  SELECT actor_alias INTO v_actor_alias
    FROM app_private.financial_audit_actor_aliases WHERE couple_id=v_couple_id AND user_id=v_actor;
  SELECT audit_event_id INTO v_prior_event FROM app_private.financial_audit_heads
    WHERE couple_id=v_couple_id AND source_expense_id=CASE WHEN TG_OP='INSERT' THEN NEW.id ELSE OLD.id END;

  IF TG_OP = 'INSERT' THEN
    v_type := 'recorded'; v_amount := NEW.amount_minor; v_currency := NEW.currency_code;
    v_exponent := NEW.currency_exponent; v_effective_date := NEW.occurred_on;
  ELSIF TG_OP = 'DELETE' THEN
    v_type := 'reversed'; v_amount := -OLD.amount_minor; v_currency := OLD.currency_code;
    v_exponent := OLD.currency_exponent; v_effective_date := OLD.occurred_on;
  ELSE
    v_type := 'corrected'; v_amount := NEW.amount_minor - OLD.amount_minor;
    v_currency := NEW.currency_code; v_exponent := NEW.currency_exponent;
    v_effective_date := NEW.occurred_on;
  END IF;
  UPDATE app_private.financial_audit_scopes SET next_sequence=next_sequence+1
    WHERE couple_id=v_couple_id RETURNING next_sequence-1 INTO v_seq;
  INSERT INTO app_private.financial_audit_events(
    audit_event_id,opaque_couple_ref,event_type,actor_alias,amount_minor,
    currency_code,currency_exponent,effective_date,event_sequence,schema_version,correction_reference
  ) VALUES (v_event_id,v_opaque_ref,v_type,v_actor_alias,v_amount,v_currency,
            v_exponent,v_effective_date,v_seq,1,v_prior_event);
  IF TG_OP = 'DELETE' THEN
    DELETE FROM app_private.financial_audit_heads WHERE couple_id=v_couple_id AND source_expense_id=OLD.id;
  ELSE
    INSERT INTO app_private.financial_audit_heads(couple_id,source_expense_id,audit_event_id)
      VALUES(v_couple_id,NEW.id,v_event_id)
      ON CONFLICT(couple_id,source_expense_id) DO UPDATE SET audit_event_id=EXCLUDED.audit_event_id;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END
$function$;
ALTER FUNCTION app_private.capture_financial_audit_event() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.capture_financial_audit_event() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER z_financial_audit_capture
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_expenses
  FOR EACH ROW EXECUTE FUNCTION app_private.capture_financial_audit_event();

CREATE FUNCTION app_private.guard_financial_audit_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF TG_OP='DELETE' AND app_private.current_request_role()='service_role'
     AND current_setting('app_private.audit_expiry_purge',true)='on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'financial audit events are append-only' USING ERRCODE='42501';
END
$function$;
ALTER FUNCTION app_private.guard_financial_audit_append_only() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_financial_audit_append_only() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER financial_audit_immutable BEFORE UPDATE OR DELETE ON app_private.financial_audit_events
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_financial_audit_append_only();

CREATE FUNCTION app_private.content_is_unblocked(p_table text, p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT NOT EXISTS (
    SELECT 1 FROM app_private.privacy_content_blocks b
    WHERE b.target_table = p_table AND b.target_id = p_id
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.ordinary_deleted_records d
    WHERE d.target_table = p_table AND d.target_id = p_id
  )
$function$;
ALTER FUNCTION app_private.content_is_unblocked(text,uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.content_is_unblocked(text,uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.content_is_unblocked(text,uuid) TO authenticated;

CREATE FUNCTION app_private.soft_delete_shared_text()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF app_private.current_request_role()='service_role' THEN RETURN OLD; END IF;
  IF app_private.current_request_role() IS DISTINCT FROM 'authenticated'
     OR app_private.current_identity_is_verified(false) IS NULL
     OR NOT app_private.can_read_shared_records(OLD.couple_id) THEN
    RAISE EXCEPTION 'active paired couple required' USING ERRCODE='42501';
  END IF;
  INSERT INTO app_private.ordinary_deleted_records(couple_id,target_table,target_id,restore_until)
    VALUES(OLD.couple_id,TG_TABLE_NAME,OLD.id,statement_timestamp()+interval '7 days')
    ON CONFLICT(target_table,target_id) DO NOTHING;
  IF NOT FOUND THEN RETURN NULL; END IF;
  INSERT INTO app_private.lifecycle_purge_jobs(job_kind,couple_id,target_table,target_id,due_at)
    VALUES('ordinary_record',OLD.couple_id,TG_TABLE_NAME,OLD.id,statement_timestamp()+interval '7 days')
    ON CONFLICT DO NOTHING;
  IF TG_TABLE_NAME='plans' THEN
    INSERT INTO app_private.ordinary_deleted_records(couple_id,target_table,target_id,parent_table,parent_id,restore_until)
      SELECT couple_id,'plan_tasks',id,'plans',OLD.id,statement_timestamp()+interval '7 days'
       FROM public.plan_tasks WHERE couple_id=OLD.couple_id AND plan_id=OLD.id
      ON CONFLICT(target_table,target_id) DO NOTHING;
    INSERT INTO app_private.lifecycle_purge_jobs(job_kind,couple_id,target_table,target_id,due_at)
      SELECT 'ordinary_record',couple_id,'plan_tasks',id,statement_timestamp()+interval '7 days'
       FROM public.plan_tasks WHERE couple_id=OLD.couple_id AND plan_id=OLD.id
         AND EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records d WHERE d.target_table='plan_tasks' AND d.target_id=plan_tasks.id AND d.parent_id=OLD.id)
      ON CONFLICT DO NOTHING;
  ELSIF TG_TABLE_NAME='shared_goals' THEN
    INSERT INTO app_private.ordinary_deleted_records(couple_id,target_table,target_id,parent_table,parent_id,restore_until)
      SELECT couple_id,'shared_goal_milestones',id,'shared_goals',OLD.id,statement_timestamp()+interval '7 days'
       FROM public.shared_goal_milestones WHERE couple_id=OLD.couple_id AND goal_id=OLD.id
      ON CONFLICT(target_table,target_id) DO NOTHING;
    INSERT INTO app_private.lifecycle_purge_jobs(job_kind,couple_id,target_table,target_id,due_at)
      SELECT 'ordinary_record',couple_id,'shared_goal_milestones',id,statement_timestamp()+interval '7 days'
       FROM public.shared_goal_milestones WHERE couple_id=OLD.couple_id AND goal_id=OLD.id
         AND EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records d WHERE d.target_table='shared_goal_milestones' AND d.target_id=shared_goal_milestones.id AND d.parent_id=OLD.id)
      ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END
$function$;
ALTER FUNCTION app_private.soft_delete_shared_text() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.soft_delete_shared_text() FROM PUBLIC,anon,authenticated,service_role;
DO $soft_delete_triggers$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'bucket_list_items','important_dates','plans','plan_tasks','couple_memories',
    'date_night_ideas','shared_goals','shared_goal_milestones'
  ] LOOP
    EXECUTE format('CREATE TRIGGER z_ordinary_shared_text_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION app_private.soft_delete_shared_text()',v_table);
  END LOOP;
END
$soft_delete_triggers$;

DO $privacy_policies$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'bucket_list_items','important_dates','plans','plan_tasks','couple_budgets',
    'budget_category_limits','recurring_expense_rules','couple_expenses',
    'expense_receipts','couple_memories','memory_attachments','date_night_ideas',
    'shared_goals','shared_goal_milestones'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS private_beta_privacy_block_%1$I ON public.%1$I', v_table);
    EXECUTE format('CREATE POLICY private_beta_privacy_block_%1$I ON public.%1$I AS RESTRICTIVE FOR ALL TO authenticated USING (app_private.content_is_unblocked(%2$L,id)) WITH CHECK (app_private.content_is_unblocked(%2$L,id))', v_table, v_table);
  END LOOP;
END
$privacy_policies$;

CREATE POLICY private_beta_memory_attachment_parent_visibility ON public.memory_attachments AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.content_is_unblocked('couple_memories',memory_id))
  WITH CHECK (app_private.content_is_unblocked('couple_memories',memory_id));
CREATE POLICY private_beta_plan_task_parent_visibility ON public.plan_tasks AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.content_is_unblocked('plans',plan_id))
  WITH CHECK (app_private.content_is_unblocked('plans',plan_id));
CREATE POLICY private_beta_milestone_parent_visibility ON public.shared_goal_milestones AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.content_is_unblocked('shared_goals',goal_id))
  WITH CHECK (app_private.content_is_unblocked('shared_goals',goal_id));
CREATE POLICY private_beta_vote_parent_visibility ON public.date_night_votes AS RESTRICTIVE FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.date_night_ideas i
    WHERE i.id=idea_id AND app_private.content_is_unblocked('date_night_ideas',i.id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.date_night_ideas i
    WHERE i.id=idea_id AND app_private.content_is_unblocked('date_night_ideas',i.id)));

CREATE OR REPLACE FUNCTION app_private.enforce_membership_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_space public.couple_spaces%ROWTYPE;
BEGIN
  IF TG_OP='DELETE' THEN
    IF app_private.current_request_role()='service_role' AND current_setting('app_private.lifecycle_membership_purge',true)='on' THEN
      SELECT * INTO v_space FROM public.couple_spaces WHERE id=OLD.couple_id;
      IF FOUND AND v_space.state='archived' AND v_space.closed_at<=statement_timestamp()-interval '30 days'
        THEN RETURN OLD; END IF;
    END IF;
    RAISE EXCEPTION 'membership history is immutable' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.id<>NEW.id OR OLD.couple_id<>NEW.couple_id OR OLD.user_id<>NEW.user_id OR OLD.seat<>NEW.seat
       OR OLD.created_at<>NEW.created_at THEN
      RAISE EXCEPTION 'immutable membership identity' USING ERRCODE='42501';
    END IF;
    IF OLD.state<>'active' OR NEW.state<>'revoked' THEN
      RAISE EXCEPTION 'membership transition must be active to revoked' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_space FROM public.couple_spaces WHERE id=OLD.couple_id FOR UPDATE;
    IF v_space.state IN ('archived','purging') THEN RAISE EXCEPTION 'closed space membership is immutable' USING ERRCODE='42501'; END IF;
    NEW.revoked_at:=statement_timestamp(); NEW.updated_at:=statement_timestamp(); NEW.revision:=OLD.revision+1;
  ELSIF TG_OP='INSERT' THEN
    IF NEW.state<>'active' OR NEW.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'new memberships must start active' USING ERRCODE='42501'; END IF;
    SELECT state INTO v_space.state FROM public.couple_spaces WHERE id=NEW.couple_id FOR UPDATE;
    IF v_space.state IN ('archived','purging') THEN RAISE EXCEPTION 'closed space cannot accept a member' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.enforce_membership_transition() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.enforce_membership_transition() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.guard_partner_invitation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_closed_at timestamptz; v_state text;
BEGIN
  IF TG_OP='DELETE' THEN
    IF app_private.current_request_role()='service_role' AND current_setting('app_private.lifecycle_membership_purge',true)='on' THEN
      SELECT state,closed_at INTO v_state,v_closed_at FROM public.couple_spaces WHERE id=OLD.couple_id;
      IF v_state='archived' AND v_closed_at<=statement_timestamp()-interval '30 days' THEN RETURN OLD; END IF;
    END IF;
    RAISE EXCEPTION 'invitation history is immutable' USING ERRCODE='42501';
  END IF;
  IF (OLD.id,OLD.couple_id,OLD.issuer_user_id,OLD.token_digest,OLD.recipient_hmac,
      OLD.recipient_hint,OLD.key_version,OLD.expires_at,OLD.created_at)
     IS DISTINCT FROM
     (NEW.id,NEW.couple_id,NEW.issuer_user_id,NEW.token_digest,NEW.recipient_hmac,
      NEW.recipient_hint,NEW.key_version,NEW.expires_at,NEW.created_at)
     OR OLD.state<>'pending' OR NEW.state NOT IN ('accepted','revoked','expired') THEN
    RAISE EXCEPTION 'invalid invitation transition' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_partner_invitation() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_partner_invitation() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.guard_financial_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_budget public.couple_budgets%ROWTYPE; v_seat1 uuid; v_seat2 uuid;
BEGIN
  IF TG_OP='UPDATE' AND TG_TABLE_NAME='couple_expenses' THEN
    IF app_private.current_request_role()='service_role'
       AND current_setting('app_private.lifecycle_membership_purge',true)='on'
       AND OLD.recurring_rule_id IS NOT NULL
       AND NEW.recurring_rule_id IS NULL
       AND NEW.recurrence_key IS NULL THEN
      IF (to_jsonb(OLD)-ARRAY['recurring_rule_id','recurrence_key','revision','updated_at','updated_by'])
         IS DISTINCT FROM
         (to_jsonb(NEW)-ARRAY['recurring_rule_id','recurrence_key','revision','updated_at','updated_by']) THEN
        RAISE EXCEPTION 'invalid lifecycle relationship cleanup' USING ERRCODE='42501';
      END IF;
      NEW.updated_at:=statement_timestamp(); NEW.revision:=OLD.revision+1; NEW.updated_by:=OLD.updated_by;
      RETURN NEW;
    END IF;
  END IF;
  v_actor:=app_private.current_identity_is_verified(false);
  IF TG_OP='INSERT' THEN
    NEW.created_by:=v_actor;
    IF TG_TABLE_NAME='couple_expenses' THEN NEW.updated_by:=v_actor; END IF;
    NEW.created_at:=statement_timestamp(); NEW.updated_at:=NEW.created_at; NEW.revision:=1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'expense identity is server controlled' USING ERRCODE='42501';
    END IF;
    IF TG_TABLE_NAME='couple_expenses' AND OLD.budget_id IS DISTINCT FROM NEW.budget_id THEN
      RAISE EXCEPTION 'expense budget is immutable' USING ERRCODE='42501';
    END IF;
    IF TG_TABLE_NAME='couple_expenses' THEN NEW.updated_by:=v_actor; END IF;
    NEW.updated_at:=statement_timestamp(); NEW.revision:=OLD.revision+1;
  END IF;
  IF TG_TABLE_NAME='couple_expenses' THEN
    SELECT * INTO v_budget FROM public.couple_budgets WHERE id=NEW.budget_id AND couple_id=NEW.couple_id;
    IF NOT FOUND OR (v_budget.currency_code,v_budget.currency_exponent) IS DISTINCT FROM (NEW.currency_code,NEW.currency_exponent)
       OR date_trunc('month',NEW.occurred_on)::date IS DISTINCT FROM v_budget.month_start THEN
      RAISE EXCEPTION 'expense must match its budget' USING ERRCODE='23514';
    END IF;
    IF NEW.split_mode='equal' AND (NEW.split_a_minor<>NEW.amount_minor/2 OR NEW.split_b_minor<>NEW.amount_minor-NEW.split_a_minor) THEN
      RAISE EXCEPTION 'invalid equal split' USING ERRCODE='23514';
    END IF;
  END IF;
  SELECT user_id INTO v_seat1 FROM public.couple_memberships WHERE couple_id=NEW.couple_id AND seat=1 AND state='active';
  SELECT user_id INTO v_seat2 FROM public.couple_memberships WHERE couple_id=NEW.couple_id AND seat=2 AND state='active';
  IF v_seat1 IS NULL OR v_seat2 IS NULL OR NEW.split_a_user_id IS DISTINCT FROM v_seat1
     OR NEW.split_b_user_id IS DISTINCT FROM v_seat2 OR NEW.paid_by_user NOT IN (v_seat1,v_seat2) THEN
    RAISE EXCEPTION 'expense participants must be current couple members' USING ERRCODE='42501';
  END IF;
  IF NEW.split_a_minor+NEW.split_b_minor<>NEW.amount_minor THEN RAISE EXCEPTION 'split must equal expense amount' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_financial_row() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_financial_row() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.restore_my_shared_record(p_table text,p_record_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_couple uuid; v_until timestamptz; v_job app_private.lifecycle_purge_jobs%ROWTYPE;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR p_record_id IS NULL OR p_table NOT IN (
    'bucket_list_items','important_dates','plans','plan_tasks','couple_memories',
    'date_night_ideas','shared_goals','shared_goal_milestones'
  ) THEN RETURN false; END IF;
  SELECT couple_id,restore_until INTO v_couple,v_until FROM app_private.ordinary_deleted_records
    WHERE target_table=p_table AND target_id=p_record_id FOR UPDATE;
  IF NOT FOUND THEN
    EXECUTE format('SELECT couple_id FROM public.%I WHERE id=$1',p_table) INTO v_couple USING p_record_id;
    RETURN v_couple IS NOT NULL AND app_private.can_read_shared_records(v_couple)
      AND app_private.content_is_unblocked(p_table,p_record_id);
  END IF;
  IF v_until<=statement_timestamp() OR NOT app_private.can_read_shared_records(v_couple)
     OR EXISTS(SELECT 1 FROM app_private.privacy_content_blocks WHERE target_table=p_table AND target_id=p_record_id) THEN
    RETURN false;
  END IF;
  PERFORM 1 FROM public.couple_spaces WHERE id=v_couple AND state='paired' FOR SHARE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF EXISTS(SELECT 1 FROM app_private.lifecycle_purge_jobs j
    WHERE j.job_kind='ordinary_record' AND j.state='processing' AND
      ((j.target_table=p_table AND j.target_id=p_record_id) OR
       (p_table='plans' AND j.target_table='plan_tasks' AND EXISTS(
         SELECT 1 FROM app_private.ordinary_deleted_records d WHERE d.target_table='plan_tasks'
          AND d.target_id=j.target_id AND d.parent_table='plans' AND d.parent_id=p_record_id)))) THEN
    RETURN false;
  END IF;
  UPDATE app_private.lifecycle_purge_jobs SET state='cancelled',lease_until=NULL
   WHERE job_kind='ordinary_record' AND state IN ('pending','retry') AND
     ((target_table=p_table AND target_id=p_record_id) OR
      (p_table='plans' AND target_table='plan_tasks' AND EXISTS(
        SELECT 1 FROM app_private.ordinary_deleted_records d WHERE d.target_table='plan_tasks'
         AND d.target_id=lifecycle_purge_jobs.target_id AND d.parent_table='plans' AND d.parent_id=p_record_id)));
  IF p_table IN ('plans','shared_goals') THEN
    DELETE FROM app_private.ordinary_deleted_records
     WHERE parent_table=p_table AND parent_id=p_record_id;
  END IF;
  DELETE FROM app_private.ordinary_deleted_records WHERE target_table=p_table AND target_id=p_record_id;
  RETURN true;
END
$function$;
ALTER FUNCTION public.restore_my_shared_record(text,uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.restore_my_shared_record(text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.restore_my_shared_record(text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_bucket_list_item(p_couple_id uuid,p_item_id uuid,p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.bucket_list_items WHERE couple_id=p_couple_id AND id=p_item_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.bucket_list_items WHERE couple_id=p_couple_id AND id=p_item_id;
  RETURN EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records WHERE target_table='bucket_list_items' AND target_id=p_item_id);
END
$function$;
ALTER FUNCTION public.delete_bucket_list_item(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_bucket_list_item(uuid,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_bucket_list_item(uuid,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_important_date(p_couple_id uuid,p_date_id uuid,p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.important_dates WHERE couple_id=p_couple_id AND id=p_date_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.important_dates WHERE couple_id=p_couple_id AND id=p_date_id;
  RETURN EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records WHERE target_table='important_dates' AND target_id=p_date_id);
END
$function$;
ALTER FUNCTION public.delete_important_date(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_important_date(uuid,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_important_date(uuid,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_plan_task(p_couple_id uuid,p_task_id uuid,p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.plan_tasks WHERE couple_id=p_couple_id AND id=p_task_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.plan_tasks WHERE couple_id=p_couple_id AND id=p_task_id;
  RETURN EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records WHERE target_table='plan_tasks' AND target_id=p_task_id);
END
$function$;
ALTER FUNCTION public.delete_plan_task(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_plan_task(uuid,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_plan_task(uuid,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_plan(p_couple_id uuid,p_plan_id uuid,p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.plans WHERE couple_id=p_couple_id AND id=p_plan_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.plans WHERE couple_id=p_couple_id AND id=p_plan_id;
  RETURN EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records WHERE target_table='plans' AND target_id=p_plan_id);
END
$function$;
ALTER FUNCTION public.delete_plan(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_plan(uuid,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_plan(uuid,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_couple_memory(p_couple_id uuid,p_memory_id uuid,p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.couple_memories WHERE couple_id=p_couple_id AND id=p_memory_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.couple_memories WHERE couple_id=p_couple_id AND id=p_memory_id;
  RETURN EXISTS(SELECT 1 FROM app_private.ordinary_deleted_records WHERE target_table='couple_memories' AND target_id=p_memory_id);
END
$function$;
ALTER FUNCTION public.delete_couple_memory(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_couple_memory(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- No Storage buckets or object policies are provisioned in Private Beta V1.
-- Attachment metadata has no authenticated INSERT grant, and avatar_path is
-- constrained to NULL. Therefore lifecycle manifests are empty; the worker
-- completes purge jobs without invoking Storage. A hosted preflight must
-- verify there are no existing Storage buckets or objects before deployment.

CREATE FUNCTION public.close_my_couple_space(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_couple uuid;
  v_state text;
  v_closed_at timestamptz;
BEGIN
  IF p_operation_id IS NULL THEN RAISE EXCEPTION 'invalid operation' USING ERRCODE = '22023'; END IF;
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE = '42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text || ':' || p_operation_id::text, 0)
  );
  SELECT couple_id INTO v_couple FROM app_private.couple_closure_receipts
   WHERE actor_user_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN RETURN jsonb_build_object('status','closed','couple_id',v_couple); END IF;
  SELECT couple_id INTO v_couple FROM public.couple_memberships
   WHERE user_id=v_actor AND state='active';
  IF v_couple IS NULL THEN RETURN jsonb_build_object('status','no_active_couple'); END IF;
  SELECT state,closed_at INTO v_state,v_closed_at FROM public.couple_spaces WHERE id=v_couple FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_active_couple'); END IF;
  IF v_state NOT IN ('draft','paired') THEN
    RETURN jsonb_build_object('status','closed');
  END IF;
  PERFORM 1 FROM public.couple_memberships
    WHERE couple_id=v_couple AND user_id=v_actor AND state='active' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','closed'); END IF;
  IF EXISTS (SELECT 1 FROM public.couple_memberships WHERE couple_id=v_couple AND state='active' AND user_id<>v_actor)
     AND v_state='draft' THEN
    RAISE EXCEPTION 'invalid draft membership' USING ERRCODE = '23514';
  END IF;
  UPDATE public.couple_memberships SET state='revoked'
    WHERE couple_id=v_couple AND state='active';
  UPDATE public.couple_spaces SET state='archived' WHERE id=v_couple;
  UPDATE app_private.partner_invitations SET state='revoked'
    WHERE couple_id=v_couple AND state='pending';
  DELETE FROM app_private.partner_invitation_receipts WHERE couple_id=v_couple;
  SELECT closed_at INTO v_closed_at FROM public.couple_spaces WHERE id=v_couple;
  INSERT INTO app_private.couple_closure_receipts(actor_user_id,operation_id,couple_id,closed_at)
    VALUES(v_actor,p_operation_id,v_couple,v_closed_at);
  INSERT INTO app_private.lifecycle_purge_jobs(job_kind,couple_id,due_at)
    VALUES('closed_couple',v_couple,v_closed_at+interval '30 days')
    ON CONFLICT DO NOTHING;
  INSERT INTO app_private.financial_audit_retention(opaque_couple_ref,closed_at,expires_at)
    SELECT opaque_couple_ref,v_closed_at,v_closed_at+interval '90 days'
      FROM app_private.financial_audit_scopes WHERE couple_id=v_couple
    ON CONFLICT(opaque_couple_ref) DO NOTHING;
  DELETE FROM app_private.financial_audit_scopes WHERE couple_id=v_couple;
  RETURN jsonb_build_object('status','closed','closed_at',v_closed_at);
END
$function$;
ALTER FUNCTION public.close_my_couple_space(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.close_my_couple_space(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.close_my_couple_space(uuid) TO authenticated;

CREATE FUNCTION public.request_my_account_deletion(p_operation_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_auth_time text := app_private.current_request_auth_time();
  v_request_id uuid;
BEGIN
  v_actor := app_private.current_identity_for_deletion(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE = '42501'; END IF;
  IF p_operation_id IS NULL OR v_auth_time IS NULL OR v_auth_time !~ '^[0-9]{1,12}$'
     OR v_auth_time::bigint > floor(extract(epoch FROM statement_timestamp()))::bigint
     OR v_auth_time::bigint < floor(extract(epoch FROM statement_timestamp()))::bigint - 600 THEN
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

CREATE FUNCTION public.claim_account_deletion(p_request_id uuid)
RETURNS TABLE(request_id uuid,user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  RETURN QUERY UPDATE app_private.account_deletion_requests r
    SET state='processing',failure_code=NULL,lease_until=statement_timestamp()+interval '5 minutes',attempts=r.attempts+1
    WHERE r.request_id=p_request_id AND (r.state IN ('pending','failed') OR
      (r.state='processing' AND r.lease_until<statement_timestamp()))
    RETURNING r.request_id,r.user_id;
END
$function$;
ALTER FUNCTION public.claim_account_deletion(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.claim_account_deletion(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(uuid) TO service_role;

CREATE FUNCTION public.mark_account_deletion_failed(p_request_id uuid,p_failure_code text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  IF p_failure_code NOT IN ('auth_admin_unavailable','auth_delete_rejected','unknown') THEN
    RAISE EXCEPTION 'invalid failure code' USING ERRCODE='22023';
  END IF;
  UPDATE app_private.account_deletion_requests SET state='failed',failure_code=p_failure_code,lease_until=NULL
   WHERE request_id=p_request_id AND state='processing';
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.mark_account_deletion_failed(uuid,text) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.mark_account_deletion_failed(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_account_deletion_failed(uuid,text) TO service_role;

CREATE FUNCTION public.mark_account_deletion_complete(p_request_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_user_id uuid;
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  SELECT user_id INTO v_user_id FROM app_private.account_deletion_requests
    WHERE request_id=p_request_id AND state='processing' FOR UPDATE;
  IF v_user_id IS NULL THEN RETURN false; END IF;
  DELETE FROM public.user_profiles WHERE user_id=v_user_id;
  DELETE FROM app_private.private_beta_allowlist WHERE user_id=v_user_id;
  UPDATE app_private.account_deletion_requests SET state='complete',completed_at=statement_timestamp(),user_id=NULL,failure_code=NULL
    WHERE request_id=p_request_id AND state='processing';
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.mark_account_deletion_complete(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.mark_account_deletion_complete(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_account_deletion_complete(uuid) TO service_role;

CREATE FUNCTION public.record_my_privacy_removal(
  p_operation_id uuid,p_table text,p_record_id uuid,p_field text DEFAULT NULL,p_remove_record boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_couple uuid;
  v_request uuid;
  v_allowed boolean := false;
  v_auth_time text := app_private.current_request_auth_time();
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_record_id IS NULL OR v_auth_time IS NULL OR v_auth_time !~ '^[0-9]{1,12}$'
     OR v_auth_time::bigint > floor(extract(epoch FROM statement_timestamp()))::bigint
     OR v_auth_time::bigint < floor(extract(epoch FROM statement_timestamp()))::bigint - 600 THEN
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

CREATE FUNCTION public.claim_lifecycle_purge_jobs(p_limit integer DEFAULT 20)
RETURNS TABLE(job_id uuid,job_kind text,couple_id uuid,target_table text,target_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_job record;
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  IF p_limit < 1 OR p_limit > 100 THEN RAISE EXCEPTION 'invalid batch size' USING ERRCODE='22023'; END IF;
  FOR v_job IN
    SELECT j.* FROM app_private.lifecycle_purge_jobs j
     WHERE (j.state IN ('pending','retry') OR (j.state='processing' AND j.lease_until<statement_timestamp()))
       AND j.due_at<=statement_timestamp()
       AND j.available_at<=statement_timestamp()
     ORDER BY j.due_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit
  LOOP
    UPDATE app_private.lifecycle_purge_jobs SET state='processing',lease_until=statement_timestamp()+interval '5 minutes',attempts=lifecycle_purge_jobs.attempts+1
      WHERE id=v_job.id;
    job_id:=v_job.id; job_kind:=v_job.job_kind; couple_id:=v_job.couple_id;
    target_table:=v_job.target_table; target_id:=v_job.target_id;
    RETURN NEXT;
  END LOOP;
END
$function$;
ALTER FUNCTION public.claim_lifecycle_purge_jobs(integer) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.claim_lifecycle_purge_jobs(integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_lifecycle_purge_jobs(integer) TO service_role;

CREATE FUNCTION public.finish_lifecycle_purge_job(p_job_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_job app_private.lifecycle_purge_jobs%ROWTYPE;
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_job FROM app_private.lifecycle_purge_jobs WHERE id=p_job_id AND state='processing' FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_job.job_kind IN ('privacy_record','ordinary_record') THEN
    IF v_job.target_table='memory_attachments' THEN DELETE FROM public.memory_attachments WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='expense_receipts' THEN DELETE FROM public.expense_receipts WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='couple_memories' THEN
      DELETE FROM public.memory_attachments WHERE memory_id=v_job.target_id AND couple_id=v_job.couple_id;
      DELETE FROM public.couple_memories WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='plans' THEN
      DELETE FROM public.plan_tasks WHERE plan_id=v_job.target_id AND couple_id=v_job.couple_id;
      DELETE FROM public.plans WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='plan_tasks' THEN DELETE FROM public.plan_tasks WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='date_night_ideas' THEN
      DELETE FROM public.date_night_votes WHERE idea_id=v_job.target_id AND couple_id=v_job.couple_id;
      DELETE FROM public.date_night_ideas WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='shared_goals' THEN
      DELETE FROM public.shared_goal_milestones WHERE goal_id=v_job.target_id AND couple_id=v_job.couple_id;
      DELETE FROM public.shared_goals WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='shared_goal_milestones' THEN DELETE FROM public.shared_goal_milestones WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='couple_expenses' THEN DELETE FROM public.couple_expenses WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='recurring_expense_rules' THEN
      PERFORM set_config('app_private.lifecycle_membership_purge','on',true);
      UPDATE public.couple_expenses SET recurring_rule_id=NULL,recurrence_key=NULL
        WHERE couple_id=v_job.couple_id AND recurring_rule_id=v_job.target_id;
      PERFORM set_config('app_private.lifecycle_membership_purge','off',true);
      DELETE FROM public.recurring_expense_rules WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='bucket_list_items' THEN DELETE FROM public.bucket_list_items WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    ELSIF v_job.target_table='important_dates' THEN DELETE FROM public.important_dates WHERE id=v_job.target_id AND couple_id=v_job.couple_id;
    END IF;
  ELSIF v_job.job_kind='closed_couple' THEN
    DELETE FROM public.memory_attachments WHERE couple_id=v_job.couple_id;
    DELETE FROM public.expense_receipts WHERE couple_id=v_job.couple_id;
    DELETE FROM public.couple_memories WHERE couple_id=v_job.couple_id;
    DELETE FROM public.date_night_votes WHERE couple_id=v_job.couple_id;
    DELETE FROM public.shared_goal_milestones WHERE couple_id=v_job.couple_id;
    DELETE FROM public.date_night_ideas WHERE couple_id=v_job.couple_id;
    DELETE FROM public.shared_goals WHERE couple_id=v_job.couple_id;
    DELETE FROM public.plan_tasks WHERE couple_id=v_job.couple_id;
    DELETE FROM public.plans WHERE couple_id=v_job.couple_id;
    DELETE FROM public.couple_expenses WHERE couple_id=v_job.couple_id;
    DELETE FROM public.recurring_expense_rules WHERE couple_id=v_job.couple_id;
    DELETE FROM public.budget_category_limits WHERE couple_id=v_job.couple_id;
    DELETE FROM public.couple_budgets WHERE couple_id=v_job.couple_id;
    DELETE FROM public.bucket_list_items WHERE couple_id=v_job.couple_id;
    DELETE FROM public.important_dates WHERE couple_id=v_job.couple_id;
    PERFORM set_config('app_private.lifecycle_membership_purge','on',true);
    DELETE FROM app_private.partner_invitation_limits WHERE actor_user_id IN
      (SELECT user_id FROM public.couple_memberships WHERE couple_id=v_job.couple_id);
    DELETE FROM app_private.partner_invitations WHERE couple_id=v_job.couple_id;
    DELETE FROM app_private.partner_invitation_receipts WHERE couple_id=v_job.couple_id;
    DELETE FROM app_private.couple_create_receipts WHERE couple_id=v_job.couple_id;
    DELETE FROM public.couple_memberships WHERE couple_id=v_job.couple_id AND state='revoked';
    PERFORM set_config('app_private.lifecycle_membership_purge','off',true);
  END IF;
  UPDATE app_private.lifecycle_purge_jobs SET state='complete',lease_until=NULL,last_error_code=NULL WHERE id=p_job_id;
  IF v_job.job_kind='ordinary_record' THEN
    DELETE FROM app_private.ordinary_deleted_records WHERE target_table=v_job.target_table AND target_id=v_job.target_id;
    IF v_job.target_table IN ('plans','shared_goals') THEN
      UPDATE app_private.lifecycle_purge_jobs SET state='cancelled',lease_until=NULL
       WHERE job_kind='ordinary_record' AND state IN ('pending','retry') AND target_table IN ('plan_tasks','shared_goal_milestones')
         AND target_id IN (SELECT d.target_id FROM app_private.ordinary_deleted_records d
           WHERE d.parent_table=v_job.target_table AND d.parent_id=v_job.target_id);
      DELETE FROM app_private.ordinary_deleted_records WHERE parent_table=v_job.target_table AND parent_id=v_job.target_id;
    END IF;
  END IF;
  UPDATE app_private.privacy_removal_requests SET state='purged',completed_at=statement_timestamp()
    WHERE target_table=v_job.target_table AND target_id=v_job.target_id AND state='blocked' AND v_job.job_kind='privacy_record';
  DELETE FROM app_private.lifecycle_purge_jobs WHERE id=p_job_id;
  RETURN true;
EXCEPTION WHEN foreign_key_violation OR check_violation THEN
  UPDATE app_private.lifecycle_purge_jobs SET state='retry',lease_until=NULL,
    available_at=statement_timestamp()+interval '15 minutes',last_error_code='row_delete_restricted' WHERE id=p_job_id;
  RETURN false;
END
$function$;
ALTER FUNCTION public.finish_lifecycle_purge_job(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.finish_lifecycle_purge_job(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_lifecycle_purge_job(uuid) TO service_role;

CREATE FUNCTION public.purge_expired_financial_audit()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_count bigint;
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service worker required' USING ERRCODE='42501'; END IF;
  PERFORM set_config('app_private.audit_expiry_purge','on',true);
  DELETE FROM app_private.financial_audit_events e USING app_private.financial_audit_retention r
   WHERE e.opaque_couple_ref=r.opaque_couple_ref AND r.expires_at<=statement_timestamp();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM set_config('app_private.audit_expiry_purge','off',true);
  DELETE FROM app_private.financial_audit_retention WHERE expires_at<=statement_timestamp();
  DELETE FROM app_private.privacy_content_blocks WHERE retain_until<=statement_timestamp()
    AND NOT EXISTS (SELECT 1 FROM app_private.lifecycle_purge_jobs j WHERE j.couple_id=privacy_content_blocks.couple_id AND j.target_table=privacy_content_blocks.target_table AND j.target_id=privacy_content_blocks.target_id AND j.state<>'complete');
  DELETE FROM app_private.lifecycle_purge_jobs WHERE state='complete' AND created_at<statement_timestamp()-interval '31 days';
  DELETE FROM app_private.couple_closure_receipts WHERE closed_at<statement_timestamp()-interval '31 days';
  RETURN v_count;
END
$function$;
ALTER FUNCTION public.purge_expired_financial_audit() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.purge_expired_financial_audit() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.purge_expired_financial_audit() TO service_role;

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.current_identity_is_verified(boolean) TO postgres;
GRANT EXECUTE ON FUNCTION app_private.current_identity_is_verified(boolean),
  app_private.current_identity_for_deletion(boolean) TO twogethera_membership_owner;
GRANT SELECT ON auth.users TO postgres;
REVOKE ALL ON FUNCTION public.close_my_couple_space(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.close_my_couple_space(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.request_my_account_deletion(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_my_account_deletion(uuid) TO authenticated;
COMMIT;
