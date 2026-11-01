-- CP-006B: verified, single-use partner invitations and atomic pairing.
-- Raw invitation tokens are returned once and are never stored.
BEGIN;

-- The Auth-owned bridge reads only the current caller's verified email. It does
-- not accept a user ID or expose Auth rows to the membership owner.
GRANT USAGE, CREATE ON SCHEMA app_private TO supabase_auth_admin;
CREATE FUNCTION app_private.current_verified_email(p_lock boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_email text;
BEGIN
  IF v_actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated'
     OR app_private.current_identity_is_verified(p_lock) IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_lock THEN
    SELECT u.email INTO v_email
    FROM auth.users AS u
    WHERE u.id = v_actor AND u.email_confirmed_at IS NOT NULL
      AND NOT coalesce(u.is_anonymous, false)
      AND (u.banned_until IS NULL OR u.banned_until <= statement_timestamp())
    FOR SHARE;
  ELSE
    SELECT u.email INTO v_email
    FROM auth.users AS u
    WHERE u.id = v_actor AND u.email_confirmed_at IS NOT NULL
      AND NOT coalesce(u.is_anonymous, false)
      AND (u.banned_until IS NULL OR u.banned_until <= statement_timestamp());
  END IF;
  RETURN v_email;
END
$function$;
ALTER FUNCTION app_private.current_verified_email(boolean) OWNER TO supabase_auth_admin;
REVOKE CREATE ON SCHEMA app_private FROM supabase_auth_admin;
REVOKE ALL ON FUNCTION app_private.current_verified_email(boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION app_private.current_verified_email(boolean) TO twogethera_membership_owner;

GRANT USAGE ON SCHEMA extensions TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION extensions.gen_random_bytes(integer) TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION extensions.hmac(bytea, bytea, text) TO twogethera_membership_owner;
GRANT EXECUTE ON FUNCTION extensions.digest(bytea, text) TO twogethera_membership_owner;
GRANT CREATE ON SCHEMA public TO twogethera_membership_owner;

SET LOCAL ROLE twogethera_membership_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE app_private.invitation_email_keys (
  key_version smallint PRIMARY KEY CHECK (key_version > 0),
  email_key bytea NOT NULL CHECK (octet_length(email_key) = 32),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
INSERT INTO app_private.invitation_email_keys(key_version, email_key)
VALUES (1, extensions.gen_random_bytes(32));

CREATE TABLE app_private.partner_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  issuer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  token_digest bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  recipient_hmac bytea NOT NULL CHECK (octet_length(recipient_hmac) = 32),
  recipient_hint text NOT NULL CHECK (length(recipient_hint) <= 254),
  key_version smallint NOT NULL REFERENCES app_private.invitation_email_keys(key_version),
  state text NOT NULL CHECK (state IN ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  accepted_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_at timestamptz,
  CHECK ((state = 'accepted') = (accepted_by IS NOT NULL)),
  CHECK ((state = 'accepted') = (accepted_at IS NOT NULL))
);
CREATE UNIQUE INDEX partner_invitations_one_pending_per_couple
  ON app_private.partner_invitations(couple_id) WHERE state = 'pending';
CREATE INDEX partner_invitations_couple_created
  ON app_private.partner_invitations(couple_id, created_at DESC);

CREATE TABLE app_private.partner_invitation_receipts (
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  operation_id uuid NOT NULL,
  request_hash bytea NOT NULL CHECK (octet_length(request_hash) = 32),
  couple_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE RESTRICT,
  result jsonb NOT NULL,
  committed_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY (actor_user_id, operation_id)
);

CREATE TABLE app_private.partner_invitation_limits (
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK (action IN ('issue', 'accept')),
  window_started_at timestamptz NOT NULL,
  attempts smallint NOT NULL CHECK (attempts > 0),
  PRIMARY KEY (actor_user_id, action)
);

ALTER TABLE app_private.invitation_email_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.partner_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.partner_invitation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.partner_invitation_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA app_private FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION app_private.normalize_invitation_email(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $function$
DECLARE v_email text := btrim(p_email); v_local text; v_domain text;
BEGIN
  IF v_email IS NULL OR length(v_email) > 254
     OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RETURN NULL;
  END IF;
  v_local := split_part(v_email, '@', 1);
  v_domain := lower(split_part(v_email, '@', 2));
  IF length(v_local) > 64 OR length(v_domain) > 253 THEN RETURN NULL; END IF;
  RETURN v_local || '@' || v_domain;
END
$function$;

CREATE FUNCTION app_private.invitation_email_hmac(p_email text, p_version smallint DEFAULT 1)
RETURNS bytea LANGUAGE sql STABLE SET search_path = '' AS $function$
  SELECT extensions.hmac(convert_to(p_email, 'UTF8'), k.email_key, 'sha256')
  FROM app_private.invitation_email_keys AS k WHERE k.key_version = p_version
$function$;

CREATE FUNCTION app_private.mask_invitation_email(p_email text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $function$
  SELECT left(split_part(p_email, '@', 1), 1) || '•••@' || lower(split_part(p_email, '@', 2))
$function$;

CREATE FUNCTION app_private.record_invitation_attempt(p_actor uuid, p_action text, p_limit smallint)
RETURNS smallint LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_now timestamptz := clock_timestamp(); v_attempts smallint;
BEGIN
  INSERT INTO app_private.partner_invitation_limits(actor_user_id, action, window_started_at, attempts)
  VALUES (p_actor, p_action, v_now, 1)
  ON CONFLICT (actor_user_id, action) DO UPDATE SET
    attempts = CASE
      WHEN app_private.partner_invitation_limits.window_started_at <= v_now - interval '1 hour' THEN 1
      ELSE least(app_private.partner_invitation_limits.attempts + 1, p_limit + 1)::smallint
    END,
    window_started_at = CASE
      WHEN app_private.partner_invitation_limits.window_started_at <= v_now - interval '1 hour' THEN v_now
      ELSE app_private.partner_invitation_limits.window_started_at
    END
  RETURNING attempts INTO v_attempts;
  RETURN v_attempts;
END
$function$;

CREATE FUNCTION app_private.find_invitation_receipt(p_actor uuid, p_operation_id uuid, p_request_hash bytea)
RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $function$
DECLARE v_receipt app_private.partner_invitation_receipts%ROWTYPE;
BEGIN
  IF p_operation_id IS NULL THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT * INTO v_receipt FROM app_private.partner_invitation_receipts
  WHERE actor_user_id = p_actor AND operation_id = p_operation_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v_receipt.request_hash IS DISTINCT FROM p_request_hash
     OR NOT app_private.can_read_couple(v_receipt.couple_id) THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  RETURN v_receipt.result || jsonb_build_object('replayed', true);
END
$function$;

CREATE FUNCTION app_private.guard_partner_invitation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invitation history is immutable' USING ERRCODE = '42501';
  END IF;
  IF (OLD.id, OLD.couple_id, OLD.issuer_user_id, OLD.token_digest, OLD.recipient_hmac,
      OLD.recipient_hint, OLD.key_version, OLD.expires_at, OLD.created_at)
     IS DISTINCT FROM
     (NEW.id, NEW.couple_id, NEW.issuer_user_id, NEW.token_digest, NEW.recipient_hmac,
      NEW.recipient_hint, NEW.key_version, NEW.expires_at, NEW.created_at)
     OR OLD.state <> 'pending'
     OR NEW.state NOT IN ('accepted', 'revoked', 'expired') THEN
    RAISE EXCEPTION 'invalid invitation transition' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER partner_invitation_guard
  BEFORE UPDATE OR DELETE ON app_private.partner_invitations
  FOR EACH ROW EXECUTE FUNCTION app_private.guard_partner_invitation();

CREATE FUNCTION public.ensure_account()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(false);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501'; END IF;
  RETURN jsonb_build_object('user_id', v_actor);
END
$function$;
ALTER FUNCTION public.ensure_account() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.ensure_account() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_account() TO authenticated;

CREATE FUNCTION public.account_context()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(false); v_spaces jsonb;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'space_id', s.id, 'state', s.state, 'epoch', s.authorization_epoch
  ) ORDER BY s.created_at), '[]'::jsonb) INTO v_spaces
  FROM public.couple_spaces AS s
  JOIN public.couple_memberships AS m ON m.couple_id = s.id
  WHERE m.user_id = v_actor AND m.state = 'active' AND s.state IN ('draft', 'paired');
  RETURN jsonb_build_object('user_id', v_actor, 'spaces', v_spaces);
END
$function$;
ALTER FUNCTION public.account_context() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.account_context() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.account_context() TO authenticated;

CREATE FUNCTION public.partner_link_context()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(false);
        v_space public.couple_spaces%ROWTYPE; v_invite app_private.partner_invitations%ROWTYPE;
        v_invitation jsonb := NULL; v_has_space boolean := false;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE = '42501'; END IF;
  SELECT s.* INTO v_space FROM public.couple_spaces AS s
  JOIN public.couple_memberships AS m ON m.couple_id = s.id
  WHERE m.user_id = v_actor AND m.state = 'active' AND s.state IN ('draft', 'paired')
  ORDER BY s.created_at LIMIT 1;
  v_has_space := FOUND;
  IF v_has_space AND v_space.state = 'draft' THEN
    SELECT i.* INTO v_invite FROM app_private.partner_invitations AS i
    WHERE i.couple_id = v_space.id ORDER BY i.created_at DESC LIMIT 1;
    IF FOUND THEN
      v_invitation := jsonb_build_object(
        'id', v_invite.id,
        'state', CASE WHEN v_invite.state = 'pending' AND v_invite.expires_at <= clock_timestamp()
                      THEN 'expired' ELSE v_invite.state END,
        'recipient_hint', v_invite.recipient_hint,
        'expires_at', v_invite.expires_at
      );
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'user_id', v_actor,
    'space', CASE WHEN v_has_space THEN jsonb_build_object(
      'id', v_space.id, 'state', v_space.state, 'epoch', v_space.authorization_epoch
    ) ELSE NULL END,
    'invitation', v_invitation
  );
END
$function$;
ALTER FUNCTION public.partner_link_context() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.partner_link_context() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.partner_link_context() TO authenticated;

CREATE FUNCTION public.issue_partner_invitation(
  p_operation_id uuid, p_couple_id uuid, p_expected_epoch bigint, p_recipient_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(true);
        v_email text; v_normalized text; v_email_hash bytea; v_request_hash bytea;
        v_replay jsonb; v_space public.couple_spaces%ROWTYPE; v_active integer;
        v_id uuid; v_token text; v_expiry timestamptz; v_result jsonb;
BEGIN
  IF v_actor IS NULL THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 0));
  v_normalized := app_private.normalize_invitation_email(p_recipient_email);
  v_email_hash := CASE WHEN v_normalized IS NULL THEN NULL
                       ELSE app_private.invitation_email_hmac(v_normalized, 1::smallint) END;
  v_request_hash := extensions.digest(convert_to(jsonb_build_array(
    'issue-v1', p_couple_id, p_expected_epoch, CASE WHEN v_email_hash IS NULL THEN NULL ELSE encode(v_email_hash, 'hex') END
  )::text, 'UTF8'), 'sha256');
  v_replay := app_private.find_invitation_receipt(v_actor, p_operation_id, v_request_hash);
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;
  IF app_private.record_invitation_attempt(v_actor, 'issue', 5::smallint) > 5 THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  IF p_operation_id IS NULL OR p_couple_id IS NULL OR p_expected_epoch IS NULL OR v_email_hash IS NULL THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  v_email := app_private.current_verified_email(false);
  IF v_email IS NULL OR app_private.invitation_email_hmac(
       app_private.normalize_invitation_email(v_email), 1::smallint
     ) = v_email_hash THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  SELECT * INTO v_space FROM public.couple_spaces WHERE id = p_couple_id FOR UPDATE;
  IF NOT FOUND OR v_space.state <> 'draft' OR v_space.authorization_epoch <> p_expected_epoch
     OR NOT app_private.can_read_couple(p_couple_id) THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  SELECT count(*) INTO v_active FROM public.couple_memberships
  WHERE couple_id = p_couple_id AND state = 'active';
  IF v_active <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.couple_memberships
       WHERE couple_id = p_couple_id AND user_id = v_actor AND seat = 1 AND state = 'active'
     ) THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  UPDATE app_private.partner_invitations SET state = 'expired'
  WHERE couple_id = p_couple_id AND state = 'pending' AND expires_at <= clock_timestamp();
  UPDATE app_private.partner_invitations SET state = 'revoked'
  WHERE couple_id = p_couple_id AND state = 'pending';
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expiry := clock_timestamp() + interval '24 hours';
  INSERT INTO app_private.partner_invitations(
    couple_id, issuer_user_id, token_digest, recipient_hmac, recipient_hint,
    key_version, state, expires_at
  ) VALUES (
    p_couple_id, v_actor, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'),
    v_email_hash, app_private.mask_invitation_email(v_normalized), 1, 'pending', v_expiry
  ) RETURNING id INTO v_id;
  v_result := jsonb_build_object(
    'status', 'created', 'invitation_id', v_id,
    'recipient_hint', app_private.mask_invitation_email(v_normalized), 'expires_at', v_expiry
  );
  INSERT INTO app_private.partner_invitation_receipts(
    actor_user_id, operation_id, request_hash, couple_id, result
  ) VALUES (v_actor, p_operation_id, v_request_hash, p_couple_id, v_result);
  RETURN v_result || jsonb_build_object('token', v_token);
END
$function$;
ALTER FUNCTION public.issue_partner_invitation(uuid, uuid, bigint, text) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.issue_partner_invitation(uuid, uuid, bigint, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.issue_partner_invitation(uuid, uuid, bigint, text) TO authenticated;

CREATE FUNCTION public.accept_partner_invitation(p_operation_id uuid, p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(true);
        v_request_hash bytea; v_replay jsonb; v_attempt smallint;
        v_invite app_private.partner_invitations%ROWTYPE; v_couple_id uuid;
        v_space public.couple_spaces%ROWTYPE; v_email text; v_email_hash bytea;
        v_active integer; v_result jsonb;
BEGIN
  IF v_actor IS NULL THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 0));
  v_request_hash := extensions.digest(convert_to(jsonb_build_array('accept-v1', p_token)::text, 'UTF8'), 'sha256');
  v_replay := app_private.find_invitation_receipt(v_actor, p_operation_id, v_request_hash);
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;
  v_attempt := app_private.record_invitation_attempt(v_actor, 'accept', 10::smallint);
  IF v_attempt > 10 OR p_operation_id IS NULL OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  SELECT i.couple_id INTO v_couple_id FROM app_private.partner_invitations AS i
  WHERE i.token_digest = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256');
  IF NOT FOUND THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT * INTO v_space FROM public.couple_spaces WHERE id = v_couple_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT * INTO v_invite FROM app_private.partner_invitations
  WHERE couple_id = v_couple_id
    AND token_digest = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256') FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  IF v_invite.state = 'pending' AND v_invite.expires_at <= clock_timestamp() THEN
    UPDATE app_private.partner_invitations SET state = 'expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  v_email := app_private.current_verified_email(false);
  v_email_hash := CASE WHEN v_email IS NULL THEN NULL ELSE app_private.invitation_email_hmac(
    app_private.normalize_invitation_email(v_email), v_invite.key_version
  ) END;
  SELECT count(*) INTO v_active FROM public.couple_memberships
  WHERE couple_id = v_couple_id AND state = 'active';
  IF v_invite.state <> 'pending' OR v_space.state <> 'draft'
     OR v_invite.issuer_user_id = v_actor
     OR v_email_hash IS NULL OR v_invite.recipient_hmac <> v_email_hash
     OR v_active <> 1
     OR NOT EXISTS (SELECT 1 FROM public.couple_memberships
       WHERE couple_id = v_couple_id AND user_id = v_invite.issuer_user_id AND seat = 1 AND state = 'active')
     OR EXISTS (SELECT 1 FROM public.couple_memberships
       WHERE user_id = v_actor AND state = 'active')
     OR EXISTS (SELECT 1 FROM public.couple_memberships
       WHERE couple_id = v_couple_id AND user_id = v_actor) THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  INSERT INTO public.couple_memberships(couple_id, user_id, seat)
  VALUES (v_couple_id, v_actor, 2);
  -- The CP-006A space trigger advances revision and authorization_epoch on the
  -- draft -> paired transition; do not increment the epoch twice here.
  UPDATE public.couple_spaces SET state = 'paired' WHERE id = v_couple_id;
  UPDATE app_private.partner_invitations SET state = 'accepted', accepted_by = v_actor,
    accepted_at = statement_timestamp() WHERE id = v_invite.id;
  v_result := jsonb_build_object('status', 'accepted', 'space_id', v_couple_id);
  INSERT INTO app_private.partner_invitation_receipts(
    actor_user_id, operation_id, request_hash, couple_id, result
  ) VALUES (v_actor, p_operation_id, v_request_hash, v_couple_id, v_result);
  RETURN v_result;
END
$function$;
ALTER FUNCTION public.accept_partner_invitation(uuid, text) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.accept_partner_invitation(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.accept_partner_invitation(uuid, text) TO authenticated;

CREATE FUNCTION public.revoke_partner_invitation(p_operation_id uuid, p_invitation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_actor uuid := app_private.current_identity_is_verified(true);
        v_hash bytea; v_replay jsonb; v_couple_id uuid; v_space public.couple_spaces%ROWTYPE;
        v_invite app_private.partner_invitations%ROWTYPE; v_result jsonb;
BEGIN
  IF v_actor IS NULL THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 0));
  v_hash := extensions.digest(convert_to(jsonb_build_array('revoke-v1', p_invitation_id)::text, 'UTF8'), 'sha256');
  v_replay := app_private.find_invitation_receipt(v_actor, p_operation_id, v_hash);
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;
  IF p_operation_id IS NULL OR p_invitation_id IS NULL THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT couple_id INTO v_couple_id FROM app_private.partner_invitations WHERE id = p_invitation_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT * INTO v_space FROM public.couple_spaces WHERE id = v_couple_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status', 'unavailable'); END IF;
  SELECT * INTO v_invite FROM app_private.partner_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF v_invite.issuer_user_id <> v_actor OR v_invite.state <> 'pending'
     OR v_space.state <> 'draft' OR NOT app_private.can_read_couple(v_couple_id) THEN
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  IF v_invite.expires_at <= clock_timestamp() THEN
    UPDATE app_private.partner_invitations SET state = 'expired' WHERE id = p_invitation_id;
    RETURN jsonb_build_object('status', 'unavailable');
  END IF;
  UPDATE app_private.partner_invitations SET state = 'revoked' WHERE id = p_invitation_id;
  v_result := jsonb_build_object('status', 'revoked', 'invitation_id', p_invitation_id);
  INSERT INTO app_private.partner_invitation_receipts(
    actor_user_id, operation_id, request_hash, couple_id, result
  ) VALUES (v_actor, p_operation_id, v_hash, v_couple_id, v_result);
  RETURN v_result;
END
$function$;
ALTER FUNCTION public.revoke_partner_invitation(uuid, uuid) OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.revoke_partner_invitation(uuid, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_partner_invitation(uuid, uuid) TO authenticated;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM twogethera_membership_owner;
COMMIT;
NOTIFY pgrst, 'reload schema';
