-- CP-010: extend existing account-owned dashboard preferences with personal
-- appearance settings. Existing forced owner-only RLS remains unchanged.
BEGIN;

ALTER TABLE public.user_dashboard_preferences
  ADD COLUMN appearance_mode text NOT NULL DEFAULT 'system'
    CHECK (appearance_mode IN ('system', 'light', 'dark')),
  ADD COLUMN appearance_theme text NOT NULL DEFAULT 'rose_gold'
    CHECK (appearance_theme IN (
      'rose_gold', 'emerald', 'amethyst', 'champagne', 'ocean_blue', 'midnight_slate'
    )),
  ADD COLUMN appearance_custom_hex text
    CHECK (appearance_custom_hex IS NULL OR appearance_custom_hex ~ '^#[0-9A-Fa-f]{6}$');

GRANT INSERT (
  user_id, module_order, visible_modules,
  appearance_mode, appearance_theme, appearance_custom_hex
) ON public.user_dashboard_preferences TO authenticated;
GRANT UPDATE (
  appearance_mode, appearance_theme, appearance_custom_hex
) ON public.user_dashboard_preferences TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
