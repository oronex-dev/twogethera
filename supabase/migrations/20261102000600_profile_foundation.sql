-- CP-009A: personal profile records and a private, partner-readable avatar.
-- This migration does not alter couple membership or archive behavior.
BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

GRANT USAGE ON SCHEMA storage TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION storage.foldername(text)
  TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;

SET LOCAL ROLE twogethera_membership_owner;

CREATE FUNCTION app_private.can_manage_profile(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p_user_id = app_private.current_identity_is_verified(false)
$function$;
ALTER FUNCTION app_private.can_manage_profile(uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.can_manage_profile(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.can_manage_profile(uuid) TO authenticated;

CREATE FUNCTION app_private.can_write_profile_photo(p_object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT app_private.current_identity_is_verified(false) IS NOT NULL
    AND (storage.foldername(p_object_name))[1]
        = app_private.current_identity_is_verified(false)::text
$function$;
ALTER FUNCTION app_private.can_write_profile_photo(text)
  OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.can_write_profile_photo(text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.can_write_profile_photo(text)
  TO authenticated;

CREATE TABLE public.user_profiles (
  user_id uuid PRIMARY KEY,
  display_name text NOT NULL
    CHECK (display_name = btrim(display_name) AND char_length(display_name) BETWEEN 2 AND 64),
  about text NOT NULL DEFAULT '' CHECK (char_length(about) <= 280),
  avatar_path text,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (avatar_path IS NULL OR avatar_path = user_id::text || '/avatar')
);

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles FORCE ROW LEVEL SECURITY;

CREATE POLICY user_profiles_self_select ON public.user_profiles
  FOR SELECT TO authenticated
  USING (app_private.can_manage_profile(user_id));
CREATE POLICY user_profiles_self_insert ON public.user_profiles
  FOR INSERT TO authenticated
  WITH CHECK (app_private.can_manage_profile(user_id));
CREATE POLICY user_profiles_self_update ON public.user_profiles
  FOR UPDATE TO authenticated
  USING (app_private.can_manage_profile(user_id))
  WITH CHECK (app_private.can_manage_profile(user_id));
CREATE POLICY user_profiles_owner_access ON public.user_profiles
  FOR ALL TO twogethera_membership_owner
  USING (true) WITH CHECK (true);

CREATE FUNCTION app_private.touch_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.updated_at := statement_timestamp();
  NEW.revision := OLD.revision + 1;
  RETURN NEW;
END
$function$;
CREATE TRIGGER user_profiles_touch
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION app_private.touch_user_profile();

REVOKE ALL ON public.user_profiles FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.user_profiles TO authenticated;
GRANT INSERT (user_id, display_name, about, avatar_path)
  ON public.user_profiles TO authenticated;
GRANT UPDATE (display_name, about, avatar_path)
  ON public.user_profiles TO authenticated;

CREATE FUNCTION app_private.can_read_partner_profile_photo(p_object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.couple_memberships AS actor
    JOIN public.couple_spaces AS space
      ON space.id = actor.couple_id AND space.state = 'paired'
    JOIN public.couple_memberships AS partner
      ON partner.couple_id = actor.couple_id
     AND partner.state = 'active'
     AND partner.user_id <> actor.user_id
    JOIN public.user_profiles AS profile
      ON profile.user_id = partner.user_id
     AND profile.avatar_path = p_object_name
    WHERE actor.user_id = app_private.current_identity_is_verified(false)
      AND actor.state = 'active'
      AND 2 = (
        SELECT count(*) FROM public.couple_memberships AS active_member
        WHERE active_member.couple_id = actor.couple_id
          AND active_member.state = 'active'
      )
  )
$function$;
ALTER FUNCTION app_private.can_read_partner_profile_photo(text)
  OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION app_private.can_read_partner_profile_photo(text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION app_private.can_read_partner_profile_photo(text)
  TO authenticated;

CREATE FUNCTION public.partner_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := app_private.current_identity_is_verified(false);
  v_profile public.user_profiles%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501';
  END IF;

  SELECT profile.* INTO v_profile
  FROM public.couple_memberships AS actor
  JOIN public.couple_spaces AS space
    ON space.id = actor.couple_id AND space.state = 'paired'
  JOIN public.couple_memberships AS partner
    ON partner.couple_id = actor.couple_id
   AND partner.state = 'active'
   AND partner.user_id <> actor.user_id
  JOIN public.user_profiles AS profile ON profile.user_id = partner.user_id
  WHERE actor.user_id = v_actor
    AND actor.state = 'active'
    AND 2 = (
      SELECT count(*) FROM public.couple_memberships AS active_member
      WHERE active_member.couple_id = actor.couple_id
        AND active_member.state = 'active'
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Return only fields intentionally shared with the current active partner.
  RETURN jsonb_build_object(
    'display_name', v_profile.display_name,
    'avatar_path', v_profile.avatar_path
  );
END
$function$;
ALTER FUNCTION public.partner_profile() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.partner_profile() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.partner_profile() TO authenticated;

CREATE OR REPLACE FUNCTION public.ensure_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := app_private.current_identity_is_verified(false);
  v_name text;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501';
  END IF;
  v_name := app_private.auth_display_name_for_current_user();
  INSERT INTO public.user_profiles(user_id, display_name)
  VALUES (v_actor, coalesce(v_name, 'Twogethera member'))
  ON CONFLICT (user_id) DO NOTHING;
  RETURN jsonb_build_object('user_id', v_actor);
END
$function$;
ALTER FUNCTION public.ensure_account() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.ensure_account() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_account() TO authenticated;

REVOKE ALL ON FUNCTION app_private.touch_user_profile()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.user_profiles TO twogethera_membership_owner;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;

CREATE FUNCTION app_private.auth_display_name_for_current_user()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := app_private.current_identity_is_verified(false);
  v_name text;
BEGIN
  IF v_actor IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT NULLIF(btrim(u.raw_user_meta_data ->> 'display_name'), '')
    INTO v_name FROM auth.users AS u WHERE u.id = v_actor;
  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 2 AND 64 THEN
    RETURN NULL;
  END IF;
  RETURN v_name;
END
$function$;
REVOKE ALL ON FUNCTION app_private.auth_display_name_for_current_user()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION app_private.auth_display_name_for_current_user()
  TO twogethera_membership_owner;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile-photos', 'profile-photos', false, 5242880,
  ARRAY['image/png']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY profile_photos_authenticated_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'profile-photos'
    AND (
      app_private.can_write_profile_photo(name)
      OR app_private.can_read_partner_profile_photo(name)
    )
  );
CREATE POLICY profile_photos_owner_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-photos'
    AND app_private.can_write_profile_photo(name)
  );
CREATE POLICY profile_photos_owner_update
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-photos'
    AND app_private.can_write_profile_photo(name)
  )
  WITH CHECK (
    bucket_id = 'profile-photos'
    AND app_private.can_write_profile_photo(name)
  );
CREATE POLICY profile_photos_owner_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = app_private.current_identity_is_verified(false)::text
  );

COMMIT;
