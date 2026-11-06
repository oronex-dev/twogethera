-- CP-011 Phase 5: paired-only memories with private authenticated media.
-- Objects are never public and no signed bearer URL is issued by the client.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
GRANT USAGE ON SCHEMA storage TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION storage.foldername(text) TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE public.couple_memories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  caption text NOT NULL DEFAULT '' CHECK (char_length(caption) <= 4000),
  personal_notes text NOT NULL DEFAULT '' CHECK (char_length(personal_notes) <= 4000),
  memory_on date NOT NULL,
  category_key text NOT NULL DEFAULT 'everyday' CHECK (category_key IN ('everyday','travel','celebration','milestone','home','other')),
  tags text[] NOT NULL DEFAULT ARRAY[]::text[] CHECK (cardinality(tags) <= 12),
  is_favorite boolean NOT NULL DEFAULT false,
  important_date_id uuid,
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id),
  FOREIGN KEY (couple_id, important_date_id) REFERENCES public.important_dates(couple_id, id) ON DELETE SET NULL (important_date_id)
);
CREATE INDEX couple_memories_scope_date ON public.couple_memories(couple_id, memory_on DESC, id);
CREATE INDEX couple_memories_tags ON public.couple_memories USING gin(tags);

CREATE TABLE public.memory_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  memory_id uuid NOT NULL,
  object_path text NOT NULL UNIQUE,
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 15728640),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  FOREIGN KEY (couple_id, memory_id) REFERENCES public.couple_memories(couple_id, id) ON DELETE CASCADE,
  UNIQUE (couple_id, memory_id, id)
);
CREATE INDEX memory_attachments_parent ON public.memory_attachments(couple_id, memory_id, created_at, id);

CREATE FUNCTION app_private.guard_memory_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(false);
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := v_actor; NEW.updated_by := v_actor;
    NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.revision := 1;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'memory identity is server controlled' USING ERRCODE = '42501';
    END IF;
    NEW.updated_by := v_actor; NEW.updated_at := statement_timestamp(); NEW.revision := OLD.revision + 1;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER couple_memories_guard BEFORE INSERT OR UPDATE ON public.couple_memories
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_memory_row();

CREATE FUNCTION app_private.guard_memory_attachment()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := app_private.current_identity_is_verified(false);
    NEW.created_at := statement_timestamp();
    NEW.object_path := NEW.couple_id::text || '/' || NEW.memory_id::text || '/' || NEW.id::text || '.blob';
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.memory_id IS DISTINCT FROM NEW.memory_id OR OLD.object_path IS DISTINCT FROM NEW.object_path
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
      RAISE EXCEPTION 'attachment identity and object path are immutable' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER memory_attachments_guard BEFORE INSERT OR UPDATE ON public.memory_attachments
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_memory_attachment();

ALTER TABLE public.couple_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_memories FORCE ROW LEVEL SECURITY;
ALTER TABLE public.memory_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_attachments FORCE ROW LEVEL SECURITY;
CREATE POLICY memories_pair_access ON public.couple_memories FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY memories_owner_access ON public.couple_memories FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY memory_attachments_pair_access ON public.memory_attachments FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY memory_attachments_owner_access ON public.memory_attachments FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

CREATE FUNCTION public.delete_couple_memory(p_couple_id uuid, p_memory_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.couple_memories
  WHERE couple_id = p_couple_id AND id = p_memory_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM public.memory_attachments WHERE couple_id = p_couple_id AND memory_id = p_memory_id) THEN
    RAISE EXCEPTION 'remove private attachments before deleting this memory' USING ERRCODE = '23514';
  END IF;
  DELETE FROM public.couple_memories WHERE couple_id = p_couple_id AND id = p_memory_id;
  RETURN FOUND;
END
$function$;
ALTER FUNCTION public.delete_couple_memory(uuid,uuid,bigint) OWNER TO twogethera_membership_owner;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE ALL ON public.couple_memories, public.memory_attachments FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.couple_memories, public.memory_attachments TO authenticated;
GRANT INSERT (couple_id,title,caption,personal_notes,memory_on,category_key,tags,is_favorite,important_date_id) ON public.couple_memories TO authenticated;
GRANT UPDATE (title,caption,personal_notes,memory_on,category_key,tags,is_favorite,important_date_id) ON public.couple_memories TO authenticated;
GRANT INSERT (couple_id,memory_id,content_type,byte_size) ON public.memory_attachments TO authenticated;
GRANT DELETE ON public.memory_attachments TO authenticated;
REVOKE ALL ON FUNCTION public.delete_couple_memory(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_couple_memory(uuid,uuid,bigint) TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('couple-memories', 'couple-memories', false, 15728640, ARRAY['image/jpeg','image/png','image/webp']::text[])
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = false,
  file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY couple_memories_storage_select ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'couple-memories' AND EXISTS (
  SELECT 1 FROM public.memory_attachments a
  WHERE a.object_path = name AND app_private.can_read_shared_records(a.couple_id)
));
CREATE POLICY couple_memories_storage_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'couple-memories' AND EXISTS (
  SELECT 1 FROM public.memory_attachments a
  WHERE a.object_path = name AND a.created_by = app_private.current_identity_is_verified(false)
    AND app_private.can_read_shared_records(a.couple_id)
));
CREATE POLICY couple_memories_storage_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'couple-memories' AND EXISTS (
  SELECT 1 FROM public.memory_attachments a
  WHERE a.object_path = name AND app_private.can_read_shared_records(a.couple_id)
));

COMMIT;
NOTIFY pgrst, 'reload schema';
