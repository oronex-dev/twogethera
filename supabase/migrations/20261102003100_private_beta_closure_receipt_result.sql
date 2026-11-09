-- Return the immutable closure timestamp on idempotent retries as well as the
-- first close, so the client receives one stable lifecycle result.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE OR REPLACE FUNCTION public.close_my_couple_space(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid;
  v_couple uuid;
  v_state text;
  v_closed_at timestamptz;
BEGIN
  IF p_operation_id IS NULL THEN RAISE EXCEPTION 'invalid operation' USING ERRCODE='22023'; END IF;
  v_actor:=app_private.current_identity_is_verified(true);
  IF v_actor IS NULL THEN RAISE EXCEPTION 'private beta access required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text||':'||p_operation_id::text,0)
  );
  SELECT couple_id,closed_at INTO v_couple,v_closed_at
    FROM app_private.couple_closure_receipts
   WHERE actor_user_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    RETURN jsonb_build_object('status','closed','couple_id',v_couple,'closed_at',v_closed_at);
  END IF;
  SELECT couple_id INTO v_couple FROM public.couple_memberships
   WHERE user_id=v_actor AND state='active';
  IF v_couple IS NULL THEN RETURN jsonb_build_object('status','no_active_couple'); END IF;
  SELECT state,closed_at INTO v_state,v_closed_at
    FROM public.couple_spaces WHERE id=v_couple FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_active_couple'); END IF;
  IF v_state NOT IN ('draft','paired') THEN
    RETURN jsonb_build_object('status','closed','closed_at',v_closed_at);
  END IF;
  PERFORM 1 FROM public.couple_memberships
   WHERE couple_id=v_couple AND user_id=v_actor AND state='active' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','closed','closed_at',v_closed_at); END IF;
  IF EXISTS(SELECT 1 FROM public.couple_memberships
     WHERE couple_id=v_couple AND state='active' AND user_id<>v_actor)
     AND v_state='draft' THEN
    RAISE EXCEPTION 'invalid draft membership' USING ERRCODE='23514';
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
   VALUES('closed_couple',v_couple,v_closed_at+interval '30 days') ON CONFLICT DO NOTHING;
  INSERT INTO app_private.financial_audit_retention(opaque_couple_ref,closed_at,expires_at)
   SELECT opaque_couple_ref,v_closed_at,v_closed_at+interval '90 days'
    FROM app_private.financial_audit_scopes WHERE couple_id=v_couple
   ON CONFLICT(opaque_couple_ref) DO NOTHING;
  DELETE FROM app_private.financial_audit_scopes WHERE couple_id=v_couple;
  RETURN jsonb_build_object('status','closed','closed_at',v_closed_at);
END
$function$;
ALTER FUNCTION public.close_my_couple_space(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.close_my_couple_space(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.close_my_couple_space(uuid) TO authenticated;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
COMMIT;
