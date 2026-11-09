-- Place paired membership scope in restrictive RLS policies so a later
-- permissive policy cannot accidentally broaden access to these tables.
BEGIN;
DROP POLICY IF EXISTS date_night_pair_access ON public.date_night_ideas;
DROP POLICY IF EXISTS date_night_owner_access ON public.date_night_ideas;
DROP POLICY IF EXISTS date_night_authenticated_allow ON public.date_night_ideas;
DROP POLICY IF EXISTS date_night_pair_boundary ON public.date_night_ideas;
CREATE POLICY date_night_authenticated_allow ON public.date_night_ideas FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY date_night_pair_boundary ON public.date_night_ideas AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY date_night_owner_access ON public.date_night_ideas FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS date_night_vote_pair_access ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_pair_select ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_own_insert ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_own_update ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_owner_access ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_authenticated_allow ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_pair_boundary ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_insert_owner_boundary ON public.date_night_votes;
DROP POLICY IF EXISTS date_night_vote_update_owner_boundary ON public.date_night_votes;
CREATE POLICY date_night_vote_authenticated_allow ON public.date_night_votes FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY date_night_vote_pair_boundary ON public.date_night_votes AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY date_night_vote_insert_owner_boundary ON public.date_night_votes AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY date_night_vote_update_owner_boundary ON public.date_night_votes AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY date_night_vote_owner_access ON public.date_night_votes FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS shared_goals_pair_access ON public.shared_goals;
DROP POLICY IF EXISTS shared_goals_owner_access ON public.shared_goals;
DROP POLICY IF EXISTS shared_goals_authenticated_allow ON public.shared_goals;
DROP POLICY IF EXISTS shared_goals_pair_boundary ON public.shared_goals;
CREATE POLICY shared_goals_authenticated_allow ON public.shared_goals FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY shared_goals_pair_boundary ON public.shared_goals AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY shared_goals_owner_access ON public.shared_goals FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS shared_goal_milestones_pair_access ON public.shared_goal_milestones;
DROP POLICY IF EXISTS shared_goal_milestones_owner_access ON public.shared_goal_milestones;
DROP POLICY IF EXISTS shared_goal_milestones_authenticated_allow ON public.shared_goal_milestones;
DROP POLICY IF EXISTS shared_goal_milestones_pair_boundary ON public.shared_goal_milestones;
CREATE POLICY shared_goal_milestones_authenticated_allow ON public.shared_goal_milestones FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY shared_goal_milestones_pair_boundary ON public.shared_goal_milestones AS RESTRICTIVE FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id)) WITH CHECK (app_private.can_read_shared_records(couple_id));
CREATE POLICY shared_goal_milestones_owner_access ON public.shared_goal_milestones FOR ALL TO twogethera_membership_owner USING (true) WITH CHECK (true);
COMMIT;
