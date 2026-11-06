-- Enforce the ten-photo per-memory limit in Postgres and serialize concurrent
-- reservations on their parent memory row.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;

CREATE OR REPLACE FUNCTION app_private.guard_memory_attachment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_count integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM public.couple_memories m
     WHERE m.id = NEW.memory_id AND m.couple_id = NEW.couple_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'memory unavailable' USING ERRCODE = '42501'; END IF;
    SELECT count(*) INTO v_count FROM public.memory_attachments a
     WHERE a.couple_id = NEW.couple_id AND a.memory_id = NEW.memory_id;
    IF v_count >= 10 THEN RAISE EXCEPTION 'photo limit reached' USING ERRCODE = '23514'; END IF;
    NEW.created_by := app_private.current_identity_is_verified(false);
    NEW.created_at := statement_timestamp();
    NEW.object_path := NEW.couple_id::text || '/' || NEW.memory_id::text || '/' || NEW.id::text || '.blob';
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.memory_id IS DISTINCT FROM NEW.memory_id OR OLD.object_path IS DISTINCT FROM NEW.object_path
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
      RAISE EXCEPTION 'attachment identity and object path are immutable' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
ALTER FUNCTION app_private.guard_memory_attachment() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.guard_memory_attachment() FROM PUBLIC, anon, authenticated, service_role;

RESET ROLE;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
COMMIT;
