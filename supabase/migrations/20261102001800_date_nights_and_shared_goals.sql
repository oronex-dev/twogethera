-- CP-012: Date Night Planner and shared goals. Online-only, paired-only,
-- non-destructive lifecycle. Dates are calendar dates; no timezone conversion
-- or recurring schedule is introduced.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA app_private TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION app_private.can_read_shared_records(uuid) TO twogethera_membership_owner;
SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE public.date_night_ideas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 4000),
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','selected','scheduled','completed','cancelled')),
  scheduled_on date,
  estimated_amount_minor bigint CHECK (estimated_amount_minor IS NULL OR estimated_amount_minor BETWEEN 0 AND 9000000000000),
  estimated_currency_code text CHECK (estimated_currency_code IS NULL OR estimated_currency_code ~ '^[A-Z]{3}$'),
  location text NOT NULL DEFAULT '' CHECK (char_length(location) <= 500),
  shared_notes text NOT NULL DEFAULT '' CHECK (char_length(shared_notes) <= 4000),
  plan_id uuid,
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id),
  FOREIGN KEY (couple_id, plan_id) REFERENCES public.plans(couple_id, id) ON DELETE RESTRICT,
  CHECK ((estimated_amount_minor IS NULL) = (estimated_currency_code IS NULL)),
  CHECK (status NOT IN ('scheduled','completed') OR scheduled_on IS NOT NULL)
);
CREATE INDEX date_night_ideas_scope_status_date ON public.date_night_ideas(couple_id, status, scheduled_on, created_at DESC);

CREATE TABLE public.date_night_votes (
  couple_id uuid NOT NULL,
  idea_id uuid NOT NULL,
  user_id uuid NOT NULL,
  response text NOT NULL CHECK (response IN ('interested','not_for_me')),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY (idea_id, user_id),
  FOREIGN KEY (couple_id, idea_id) REFERENCES public.date_night_ideas(couple_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.shared_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 4000),
  category text NOT NULL DEFAULT 'relationship' CHECK (category = btrim(category) AND char_length(category) BETWEEN 1 AND 48),
  target_on date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed')),
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id)
);
CREATE INDEX shared_goals_scope_status_target ON public.shared_goals(couple_id, status, target_on, created_at DESC);

CREATE TABLE public.shared_goal_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  goal_id uuid NOT NULL,
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
  target_on date,
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order BETWEEN 0 AND 1000000),
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  UNIQUE (couple_id, id),
  FOREIGN KEY (couple_id, goal_id) REFERENCES public.shared_goals(couple_id, id) ON DELETE RESTRICT,
  CHECK (is_completed = (completed_at IS NOT NULL))
);
CREATE INDEX shared_goal_milestones_parent_order ON public.shared_goal_milestones(couple_id, goal_id, sort_order, created_at, id);

CREATE FUNCTION app_private.guard_cp012_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL OR NOT app_private.can_read_shared_records(NEW.couple_id) THEN
    RAISE EXCEPTION 'active couple membership required' USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'date_night_ideas' THEN NEW.created_by := v_actor; END IF;
    IF TG_TABLE_NAME IN ('date_night_ideas','shared_goals','shared_goal_milestones') THEN
      NEW.created_by := v_actor; NEW.updated_by := v_actor;
      NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.revision := 1;
    END IF;
  ELSE
    IF OLD.id IS DISTINCT FROM NEW.id OR OLD.couple_id IS DISTINCT FROM NEW.couple_id
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at IS DISTINCT FROM NEW.created_at
       OR OLD.revision IS DISTINCT FROM NEW.revision THEN
      RAISE EXCEPTION 'identity and revision are server controlled' USING ERRCODE = '42501';
    END IF;
    NEW.updated_by := v_actor; NEW.updated_at := statement_timestamp(); NEW.revision := OLD.revision + 1;
  END IF;
  IF TG_TABLE_NAME = 'shared_goal_milestones' THEN
    IF TG_OP = 'INSERT' OR OLD.is_completed IS DISTINCT FROM NEW.is_completed THEN
      NEW.completed_at := CASE WHEN NEW.is_completed THEN statement_timestamp() ELSE NULL END;
    ELSE
      NEW.completed_at := OLD.completed_at;
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.guard_date_night_vote()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid;
BEGIN
  v_actor := app_private.current_identity_is_verified(false);
  IF v_actor IS NULL OR NEW.user_id IS DISTINCT FROM v_actor
     OR NOT app_private.can_read_shared_records(NEW.couple_id) THEN
    RAISE EXCEPTION 'only a current couple member may record their own response' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.date_night_ideas i WHERE i.id = NEW.idea_id AND i.couple_id = NEW.couple_id AND i.status = 'proposed') THEN
    RAISE EXCEPTION 'responses are available only for proposed ideas' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := statement_timestamp();
  RETURN NEW;
END
$function$;

CREATE TRIGGER date_night_ideas_guard BEFORE INSERT OR UPDATE ON public.date_night_ideas FOR EACH ROW EXECUTE FUNCTION app_private.guard_cp012_row();
CREATE TRIGGER shared_goals_guard BEFORE INSERT OR UPDATE ON public.shared_goals FOR EACH ROW EXECUTE FUNCTION app_private.guard_cp012_row();
CREATE TRIGGER shared_goal_milestones_guard BEFORE INSERT OR UPDATE ON public.shared_goal_milestones FOR EACH ROW EXECUTE FUNCTION app_private.guard_cp012_row();
CREATE TRIGGER date_night_votes_guard BEFORE INSERT OR UPDATE ON public.date_night_votes FOR EACH ROW EXECUTE FUNCTION app_private.guard_date_night_vote();

ALTER TABLE public.date_night_ideas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.date_night_ideas FORCE ROW LEVEL SECURITY;
ALTER TABLE public.date_night_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.date_night_votes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.shared_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_goals FORCE ROW LEVEL SECURITY;
ALTER TABLE public.shared_goal_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_goal_milestones FORCE ROW LEVEL SECURITY;

CREATE POLICY date_night_pair_access ON public.date_night_ideas FOR ALL TO authenticated USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY date_night_vote_pair_select ON public.date_night_votes FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE POLICY date_night_vote_own_insert ON public.date_night_votes FOR INSERT TO authenticated WITH CHECK (app_private.can_read_shared_records(couple_id) AND user_id = auth.uid());
CREATE POLICY date_night_vote_own_update ON public.date_night_votes FOR UPDATE TO authenticated USING (app_private.can_read_shared_records(couple_id) AND user_id = auth.uid()) WITH CHECK (app_private.can_read_shared_records(couple_id) AND user_id = auth.uid());
CREATE POLICY shared_goals_pair_access ON public.shared_goals FOR ALL TO authenticated USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY shared_goal_milestones_pair_access ON public.shared_goal_milestones FOR ALL TO authenticated USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY date_night_owner_access ON public.date_night_ideas FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY date_night_vote_owner_access ON public.date_night_votes FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY shared_goals_owner_access ON public.shared_goals FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
CREATE POLICY shared_goal_milestones_owner_access ON public.shared_goal_milestones FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
REVOKE CREATE ON SCHEMA app_private FROM twogethera_membership_owner;
REVOKE ALL ON public.date_night_ideas, public.date_night_votes, public.shared_goals, public.shared_goal_milestones FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.date_night_ideas, public.date_night_votes, public.shared_goals, public.shared_goal_milestones TO authenticated;
GRANT INSERT (couple_id,title,description,status,scheduled_on,estimated_amount_minor,estimated_currency_code,location,shared_notes,plan_id) ON public.date_night_ideas TO authenticated;
GRANT UPDATE (title,description,status,scheduled_on,estimated_amount_minor,estimated_currency_code,location,shared_notes,plan_id) ON public.date_night_ideas TO authenticated;
GRANT INSERT (couple_id,idea_id,user_id,response) ON public.date_night_votes TO authenticated;
GRANT UPDATE (response) ON public.date_night_votes TO authenticated;
GRANT INSERT (couple_id,title,description,category,target_on,status) ON public.shared_goals TO authenticated;
GRANT UPDATE (title,description,category,target_on,status) ON public.shared_goals TO authenticated;
GRANT INSERT (couple_id,goal_id,title,description,target_on,is_completed,sort_order) ON public.shared_goal_milestones TO authenticated;
GRANT UPDATE (title,description,target_on,is_completed,sort_order) ON public.shared_goal_milestones TO authenticated;
REVOKE ALL ON FUNCTION app_private.guard_cp012_row() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION app_private.guard_date_night_vote() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
NOTIFY pgrst, 'reload schema';
