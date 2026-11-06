-- Receipt count is a server-maintained summary, never a client-writable field.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION app_private.sync_expense_receipt_count()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_expense_id uuid;
BEGIN
  v_expense_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_id ELSE NEW.expense_id END;
  UPDATE public.couple_expenses e
     SET receipt_count = (SELECT count(*)::smallint FROM public.expense_receipts r WHERE r.expense_id = v_expense_id)
   WHERE e.id = v_expense_id;
  RETURN NULL;
END
$function$;
ALTER FUNCTION app_private.sync_expense_receipt_count() OWNER TO twogethera_membership_owner;
CREATE TRIGGER expense_receipts_sync_count
AFTER INSERT OR DELETE ON public.expense_receipts
FOR EACH ROW EXECUTE FUNCTION app_private.sync_expense_receipt_count();

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
REVOKE UPDATE (receipt_count) ON public.couple_expenses FROM authenticated;
REVOKE ALL ON FUNCTION app_private.sync_expense_receipt_count() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
