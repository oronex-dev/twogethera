-- CP-008: private, account-scoped dashboard presentation preferences.
-- Preferences contain no shared planner content and are never stored offline.
BEGIN;

CREATE TABLE public.user_dashboard_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  module_order text[] NOT NULL DEFAULT ARRAY['bucket_list','important_dates','plans']::text[],
  visible_modules text[] NOT NULL DEFAULT ARRAY['bucket_list','important_dates','plans']::text[],
  CONSTRAINT dashboard_module_order_valid CHECK (
    cardinality(module_order) = 3
    AND module_order @> ARRAY['bucket_list','important_dates','plans']::text[]
    AND module_order <@ ARRAY['bucket_list','important_dates','plans']::text[]
  ),
  CONSTRAINT dashboard_visible_modules_valid CHECK (
    cardinality(visible_modules) <= 3
    AND visible_modules <@ ARRAY['bucket_list','important_dates','plans']::text[]
  )
);

ALTER TABLE public.user_dashboard_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_dashboard_preferences FORCE ROW LEVEL SECURITY;

CREATE POLICY user_dashboard_preferences_self_select
  ON public.user_dashboard_preferences FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY user_dashboard_preferences_self_insert
  ON public.user_dashboard_preferences FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY user_dashboard_preferences_self_update
  ON public.user_dashboard_preferences FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

REVOKE ALL ON public.user_dashboard_preferences FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.user_dashboard_preferences TO authenticated;
GRANT INSERT (user_id,module_order,visible_modules)
  ON public.user_dashboard_preferences TO authenticated;
GRANT UPDATE (module_order,visible_modules)
  ON public.user_dashboard_preferences TO authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
