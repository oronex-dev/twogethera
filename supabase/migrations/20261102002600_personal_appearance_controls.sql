-- Add account-owned font scale and visual gradient preferences.
-- Existing owner-only RLS on user_dashboard_preferences is unchanged.
BEGIN;

ALTER TABLE public.user_dashboard_preferences
  ADD COLUMN appearance_font_size text NOT NULL DEFAULT 'default'
    CHECK (appearance_font_size IN ('small', 'default', 'large')),
  ADD COLUMN appearance_gradient_preset text NOT NULL DEFAULT 'rose_dawn'
    CHECK (appearance_gradient_preset IN (
      'rose_dawn', 'soft_lilac', 'champagne_glow', 'ocean_mist',
      'emerald_morning', 'custom'
    )),
  ADD COLUMN appearance_gradient_start_hex text
    CHECK (
      appearance_gradient_start_hex IS NULL
      OR appearance_gradient_start_hex ~ '^#[0-9A-Fa-f]{6}$'
    ),
  ADD COLUMN appearance_gradient_end_hex text
    CHECK (
      appearance_gradient_end_hex IS NULL
      OR appearance_gradient_end_hex ~ '^#[0-9A-Fa-f]{6}$'
    ),
  ADD COLUMN appearance_gradient_direction text NOT NULL DEFAULT 'diagonal'
    CHECK (appearance_gradient_direction IN ('diagonal', 'horizontal', 'vertical'));

GRANT INSERT (
  user_id, appearance_font_size, appearance_gradient_preset,
  appearance_gradient_start_hex, appearance_gradient_end_hex,
  appearance_gradient_direction
) ON public.user_dashboard_preferences TO authenticated;
GRANT UPDATE (
  appearance_font_size, appearance_gradient_preset,
  appearance_gradient_start_hex, appearance_gradient_end_hex,
  appearance_gradient_direction
) ON public.user_dashboard_preferences TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
