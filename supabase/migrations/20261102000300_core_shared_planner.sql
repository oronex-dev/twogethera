-- CP-007: online-only shared planner MVP.
-- Every row is readable/writable only while the caller is a verified member
-- of a currently paired couple. No Storage, Realtime, offline queue or archive
-- surface is introduced here.
BEGIN;

GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE public.bucket_list_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 4000),
  category_key text NOT NULL DEFAULT 'other'
    CHECK (category_key IN ('travel','home','food','adventure','learning','celebration','other')),
  target_date date,
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (is_completed = (completed_at IS NOT NULL)),
  UNIQUE (couple_id, id)
);
CREATE INDEX bucket_list_items_scope_created
  ON public.bucket_list_items(couple_id, created_at DESC, id);
CREATE INDEX bucket_list_items_scope_category
  ON public.bucket_list_items(couple_id, category_key, is_completed, target_date);

CREATE TABLE public.important_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  kind text NOT NULL CHECK (kind IN ('birthday','anniversary','special')),
  title text NOT NULL CHECK (title = btrim(title) AND length(title) BETWEEN 1 AND 160),
  date_value date NOT NULL,
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 4000),
  recurrence text NOT NULL CHECK (recurrence IN ('once','annual')),
  leap_day_policy text CHECK (leap_day_policy IN ('feb28','skip')),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK ((recurrence = 'annual') = (leap_day_policy IS NOT NULL)),
  CHECK (kind = 'special' OR recurrence = 'annual'),
  UNIQUE (couple_id, id)
);
CREATE INDEX important_dates_scope_date
  ON public.important_dates(couple_id, date_value, id);

CREATE TABLE public.plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 10000),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  location text NOT NULL DEFAULT '' CHECK (length(location) <= 500),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  UNIQUE (couple_id, id)
);
CREATE INDEX plans_scope_starts
  ON public.plans(couple_id, starts_at, id);

CREATE TABLE public.plan_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  title text NOT NULL CHECK (title = btrim(title) AND length(title) BETWEEN 1 AND 240),
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order BETWEEN 0 AND 1000000),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (is_completed = (completed_at IS NOT NULL)),
  UNIQUE (couple_id, id),
  FOREIGN KEY (couple_id, plan_id)
    REFERENCES public.plans(couple_id, id) ON DELETE RESTRICT
);
CREATE INDEX plan_tasks_scope_parent_order
  ON public.plan_tasks(couple_id, plan_id, sort_order, created_at, id);

ALTER TABLE public.bucket_list_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bucket_list_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.important_dates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.important_dates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans FORCE ROW LEVEL SECURITY;
ALTER TABLE public.plan_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_tasks FORCE ROW LEVEL SECURITY;

CREATE POLICY bucket_list_items_paired_select ON public.bucket_list_items
  FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE POLICY bucket_list_items_paired_insert ON public.bucket_list_items
  FOR INSERT TO authenticated WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY bucket_list_items_paired_update ON public.bucket_list_items
  FOR UPDATE TO authenticated USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY bucket_list_items_command_owner ON public.bucket_list_items
  FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

CREATE POLICY important_dates_paired_select ON public.important_dates
  FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE POLICY important_dates_paired_insert ON public.important_dates
  FOR INSERT TO authenticated WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY important_dates_paired_update ON public.important_dates
  FOR UPDATE TO authenticated USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY important_dates_command_owner ON public.important_dates
  FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

CREATE POLICY plans_paired_select ON public.plans
  FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE POLICY plans_paired_insert ON public.plans
  FOR INSERT TO authenticated WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY plans_paired_update ON public.plans
  FOR UPDATE TO authenticated USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY plans_command_owner ON public.plans
  FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

CREATE POLICY plan_tasks_paired_select ON public.plan_tasks
  FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE POLICY plan_tasks_paired_insert ON public.plan_tasks
  FOR INSERT TO authenticated WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY plan_tasks_paired_update ON public.plan_tasks
  FOR UPDATE TO authenticated USING (app_private.can_read_shared_records(couple_id))
  WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY plan_tasks_command_owner ON public.plan_tasks
  FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

CREATE FUNCTION app_private.touch_planner_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := statement_timestamp();
    NEW.updated_at := NEW.created_at;
    NEW.revision := 1;
    RETURN NEW;
  END IF;
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
     OR OLD.revision IS DISTINCT FROM NEW.revision
     OR OLD.updated_at IS DISTINCT FROM NEW.updated_at THEN
    RAISE EXCEPTION 'planner row identity and revision are server controlled' USING ERRCODE = '42501';
  END IF;
  NEW.updated_at := statement_timestamp();
  NEW.revision := OLD.revision + 1;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.sync_planner_completion()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.completed_at := CASE WHEN NEW.is_completed THEN statement_timestamp() ELSE NULL END;
  ELSIF OLD.is_completed IS DISTINCT FROM NEW.is_completed THEN
    NEW.completed_at := CASE WHEN NEW.is_completed THEN statement_timestamp() ELSE NULL END;
  ELSE
    NEW.completed_at := OLD.completed_at;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER bucket_list_items_touch BEFORE INSERT OR UPDATE ON public.bucket_list_items
  FOR EACH ROW EXECUTE FUNCTION app_private.touch_planner_row();
CREATE TRIGGER bucket_list_items_completion BEFORE INSERT OR UPDATE ON public.bucket_list_items
  FOR EACH ROW EXECUTE FUNCTION app_private.sync_planner_completion();
CREATE TRIGGER important_dates_touch BEFORE INSERT OR UPDATE ON public.important_dates
  FOR EACH ROW EXECUTE FUNCTION app_private.touch_planner_row();
CREATE TRIGGER plans_touch BEFORE INSERT OR UPDATE ON public.plans
  FOR EACH ROW EXECUTE FUNCTION app_private.touch_planner_row();
CREATE TRIGGER plan_tasks_touch BEFORE INSERT OR UPDATE ON public.plan_tasks
  FOR EACH ROW EXECUTE FUNCTION app_private.touch_planner_row();
CREATE TRIGGER plan_tasks_completion BEFORE INSERT OR UPDATE ON public.plan_tasks
  FOR EACH ROW EXECUTE FUNCTION app_private.sync_planner_completion();

-- Hard deletion is available only through scoped, revision-checked server
-- commands. Parent plans are locked and their tasks removed before the parent.
CREATE FUNCTION public.delete_bucket_list_item(p_couple_id uuid, p_item_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.bucket_list_items
  WHERE couple_id = p_couple_id AND id = p_item_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.bucket_list_items WHERE couple_id = p_couple_id AND id = p_item_id;
  RETURN FOUND;
END
$function$;

CREATE FUNCTION public.delete_important_date(p_couple_id uuid, p_date_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.important_dates
  WHERE couple_id = p_couple_id AND id = p_date_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.important_dates WHERE couple_id = p_couple_id AND id = p_date_id;
  RETURN FOUND;
END
$function$;

CREATE FUNCTION public.delete_plan_task(p_couple_id uuid, p_task_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.plan_tasks
  WHERE couple_id = p_couple_id AND id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.plan_tasks WHERE couple_id = p_couple_id AND id = p_task_id;
  RETURN FOUND;
END
$function$;

CREATE FUNCTION public.delete_plan(p_couple_id uuid, p_plan_id uuid, p_expected_revision bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid; v_revision bigint;
BEGIN
  v_actor := app_private.current_identity_is_verified(true);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(p_couple_id) THEN RETURN false; END IF;
  SELECT revision INTO v_revision FROM public.plans
  WHERE couple_id = p_couple_id AND id = p_plan_id FOR UPDATE;
  IF NOT FOUND OR v_revision IS DISTINCT FROM p_expected_revision THEN RETURN false; END IF;
  DELETE FROM public.plan_tasks WHERE couple_id = p_couple_id AND plan_id = p_plan_id;
  DELETE FROM public.plans WHERE couple_id = p_couple_id AND id = p_plan_id;
  RETURN FOUND;
END
$function$;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE ALL ON public.bucket_list_items, public.important_dates, public.plans, public.plan_tasks
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.bucket_list_items, public.important_dates, public.plans, public.plan_tasks TO authenticated;
GRANT INSERT (couple_id,title,description,category_key,target_date,is_completed)
  ON public.bucket_list_items TO authenticated;
GRANT UPDATE (title,description,category_key,target_date,is_completed)
  ON public.bucket_list_items TO authenticated;
GRANT INSERT (couple_id,kind,title,date_value,notes,recurrence,leap_day_policy)
  ON public.important_dates TO authenticated;
GRANT UPDATE (kind,title,date_value,notes,recurrence,leap_day_policy)
  ON public.important_dates TO authenticated;
GRANT INSERT (couple_id,title,description,starts_at,ends_at,location)
  ON public.plans TO authenticated;
GRANT UPDATE (title,description,starts_at,ends_at,location)
  ON public.plans TO authenticated;
GRANT INSERT (couple_id,plan_id,title,sort_order)
  ON public.plan_tasks TO authenticated;
GRANT UPDATE (plan_id,title,is_completed,sort_order)
  ON public.plan_tasks TO authenticated;

REVOKE ALL ON FUNCTION public.delete_bucket_list_item(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_important_date(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_plan_task(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_plan(uuid,uuid,bigint) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_bucket_list_item(uuid,uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_important_date(uuid,uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_plan_task(uuid,uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_plan(uuid,uuid,bigint) TO authenticated;
REVOKE ALL ON FUNCTION app_private.touch_planner_row() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app_private.sync_planner_completion() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
