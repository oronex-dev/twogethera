-- Private Beta V1 provisions no attachment Storage or client attachment API.
-- Lifecycle routines retain owner-controlled metadata cleanup. A hosted
-- preflight must confirm there are no pre-existing attachment objects before
-- deployment.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION public.delete_couple_memory_attachment(p_couple_id uuid, p_attachment_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  PERFORM 1 FROM public.memory_attachments
   WHERE couple_id = p_couple_id AND id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  DELETE FROM public.memory_attachments WHERE couple_id = p_couple_id AND id = p_attachment_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_memory_attachment(uuid,uuid) OWNER TO twogethera_membership_owner;

CREATE FUNCTION public.delete_couple_expense_receipt(p_couple_id uuid, p_receipt_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  PERFORM 1 FROM public.expense_receipts
   WHERE couple_id = p_couple_id AND id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  DELETE FROM public.expense_receipts WHERE couple_id = p_couple_id AND id = p_receipt_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_expense_receipt(uuid,uuid) OWNER TO twogethera_membership_owner;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_couple_memory_attachment(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_couple_expense_receipt(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE DELETE ON public.memory_attachments, public.expense_receipts FROM authenticated;
COMMIT;
