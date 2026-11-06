-- Prevent deleting attachment metadata while its private Storage object still
-- exists; cleanup must remove the object through Storage first.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
GRANT USAGE ON SCHEMA storage TO twogethera_membership_owner;
GRANT SELECT ON storage.objects TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION public.delete_couple_memory_attachment(p_couple_id uuid, p_attachment_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_path text;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT object_path INTO v_path FROM public.memory_attachments
   WHERE couple_id = p_couple_id AND id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'couple-memories' AND name = v_path) THEN
    RAISE EXCEPTION 'remove private storage object before its metadata' USING ERRCODE = '23514';
  END IF;
  DELETE FROM public.memory_attachments WHERE couple_id = p_couple_id AND id = p_attachment_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_memory_attachment(uuid,uuid) OWNER TO twogethera_membership_owner;

CREATE FUNCTION public.delete_couple_expense_receipt(p_couple_id uuid, p_receipt_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_path text;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT object_path INTO v_path FROM public.expense_receipts
   WHERE couple_id = p_couple_id AND id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'couple-receipts' AND name = v_path) THEN
    RAISE EXCEPTION 'remove private storage object before its metadata' USING ERRCODE = '23514';
  END IF;
  DELETE FROM public.expense_receipts WHERE couple_id = p_couple_id AND id = p_receipt_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_expense_receipt(uuid,uuid) OWNER TO twogethera_membership_owner;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.delete_couple_memory_attachment(uuid,uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_couple_expense_receipt(uuid,uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_couple_memory_attachment(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_couple_expense_receipt(uuid,uuid) TO authenticated;
REVOKE DELETE ON public.memory_attachments, public.expense_receipts FROM authenticated;
COMMIT;
