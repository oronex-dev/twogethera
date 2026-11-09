-- CP-013 follow-up: let the trusted maintenance worker discover deletion
-- request IDs without exposing account IDs or private queue rows to clients.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION public.claim_due_account_deletion_ids(p_limit integer DEFAULT 20)
RETURNS SETOF uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
  IF app_private.current_request_role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service worker required' USING ERRCODE='42501';
  END IF;
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'invalid batch size' USING ERRCODE='22023'; END IF;
  RETURN QUERY SELECT r.request_id FROM app_private.account_deletion_requests r
   WHERE r.state IN ('pending','failed') OR
     (r.state='processing' AND r.lease_until<statement_timestamp())
   ORDER BY r.requested_at,r.request_id FOR UPDATE SKIP LOCKED LIMIT p_limit;
END
$function$;
ALTER FUNCTION public.claim_due_account_deletion_ids(integer) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.claim_due_account_deletion_ids(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_due_account_deletion_ids(integer) TO service_role;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
COMMIT;
