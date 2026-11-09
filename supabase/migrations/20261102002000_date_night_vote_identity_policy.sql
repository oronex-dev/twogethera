-- Use PostgREST's signed subject claim for row ownership in RLS. Verified
-- email/current account state is independently enforced by the trigger guard.
BEGIN;
DROP POLICY date_night_vote_pair_access ON public.date_night_votes;
CREATE POLICY date_night_vote_pair_access ON public.date_night_votes FOR ALL TO authenticated
  USING (app_private.can_read_shared_records(couple_id) AND user_id = auth.uid())
  WITH CHECK (app_private.can_read_shared_records(couple_id) AND user_id = auth.uid());
COMMIT;
