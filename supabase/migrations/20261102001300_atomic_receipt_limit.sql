-- Serialize receipt reservations on the expense row and maintain the visible
-- count server-side, preventing client edits and concurrent over-reservation.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE OR REPLACE FUNCTION app_private.guard_expense_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_expense uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := app_private.current_identity_is_verified(false);
    NEW.created_at := statement_timestamp();
    NEW.object_path := NEW.couple_id::text || '/' || NEW.expense_id::text || '/' || NEW.id::text || '.blob';
    UPDATE public.couple_expenses e
       SET receipt_count = e.receipt_count + 1
     WHERE e.id = NEW.expense_id AND e.couple_id = NEW.couple_id AND e.receipt_count < 5
     RETURNING e.id INTO v_expense;
    IF v_expense IS NULL THEN
      RAISE EXCEPTION 'receipt limit reached or expense unavailable' USING ERRCODE = '23514';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.expense_id IS DISTINCT FROM NEW.expense_id OR OLD.object_path IS DISTINCT FROM NEW.object_path
       OR OLD.content_type IS DISTINCT FROM NEW.content_type OR OLD.byte_size IS DISTINCT FROM NEW.byte_size
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
      RAISE EXCEPTION 'receipt identity is immutable' USING ERRCODE = '42501';
    END IF;
  ELSE
    UPDATE public.couple_expenses e
       SET receipt_count = greatest(e.receipt_count - 1, 0)
     WHERE e.id = OLD.expense_id AND e.couple_id = OLD.couple_id;
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_expense_receipt() OWNER TO twogethera_membership_owner;
DROP TRIGGER expense_receipts_guard ON public.expense_receipts;
CREATE TRIGGER expense_receipts_guard BEFORE INSERT OR UPDATE OR DELETE ON public.expense_receipts
FOR EACH ROW EXECUTE FUNCTION app_private.guard_expense_receipt();

DROP TRIGGER IF EXISTS expense_receipts_sync_count ON public.expense_receipts;
DROP FUNCTION IF EXISTS app_private.sync_expense_receipt_count();

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
REVOKE UPDATE (receipt_count) ON public.couple_expenses FROM authenticated;
REVOKE ALL ON FUNCTION app_private.guard_expense_receipt() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
