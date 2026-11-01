-- PostgREST upsert includes the conflict key in its update privilege check.
-- RLS still requires the old and resulting owner to equal auth.uid().
BEGIN;
GRANT UPDATE (user_id) ON public.user_dashboard_preferences TO authenticated;
COMMIT;
