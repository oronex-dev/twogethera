-- CP-004B.3 rehearsal snapshot of checkpointed B.2 kernel; not production.
-- Object names retained for exact regression reuse on a DIFFERENT local cluster.
-- Atomic transaction and migration ledger are controlled by run_tests.py.
DO $$ BEGIN
 IF current_database()<>'postgres' OR shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database')
 IS DISTINCT FROM 'twogethera:cp004b3:disposable:v1' THEN RAISE EXCEPTION 'wrong_proof_database'; END IF;
END $$;
CREATE SCHEMA cp004b2 AUTHORIZATION cp004b2_owner;
CREATE SCHEMA cp004b2_private AUTHORIZATION cp004b2_owner;
SET LOCAL ROLE cp004b2_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004b2 REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004b2_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE cp004b2_private.accounts (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT, enabled boolean NOT NULL DEFAULT true
);
CREATE TABLE cp004b2.spaces (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), state text NOT NULL CHECK(state IN ('draft','paired','closed')),
 epoch bigint NOT NULL DEFAULT 1 CHECK(epoch>0), closed_at timestamptz,
 CHECK((state='closed')=(closed_at IS NOT NULL))
);
CREATE TABLE cp004b2.memberships (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), couple_id uuid NOT NULL REFERENCES cp004b2.spaces,
 user_id uuid NOT NULL REFERENCES cp004b2_private.accounts, seat smallint NOT NULL CHECK(seat IN (1,2)),
 active boolean NOT NULL DEFAULT true, UNIQUE(couple_id,seat),UNIQUE(couple_id,user_id)
);
CREATE UNIQUE INDEX one_active_space ON cp004b2.memberships(user_id) WHERE active;
CREATE INDEX membership_scope ON cp004b2.memberships(couple_id,user_id);
CREATE TABLE cp004b2_private.keys (
 version integer PRIMARY KEY CHECK(version=1), email_key bytea NOT NULL CHECK(octet_length(email_key)=32)
);
INSERT INTO cp004b2_private.keys VALUES(1,extensions.gen_random_bytes(32));
CREATE TABLE cp004b2_private.invitations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), couple_id uuid NOT NULL REFERENCES cp004b2.spaces,
 issuer uuid NOT NULL REFERENCES cp004b2_private.accounts,
 token_hash bytea UNIQUE NOT NULL CHECK(octet_length(token_hash)=32),
 recipient_hmac bytea NOT NULL CHECK(octet_length(recipient_hmac)=32), key_version integer NOT NULL REFERENCES cp004b2_private.keys,
 expires_at timestamptz NOT NULL, state text NOT NULL CHECK(state IN ('pending','accepted','revoked')),
 accepted_by uuid REFERENCES cp004b2_private.accounts, CHECK((state='accepted')=(accepted_by IS NOT NULL))
);
CREATE UNIQUE INDEX one_pending_invite ON cp004b2_private.invitations(couple_id) WHERE state='pending';
CREATE INDEX invitation_expiry ON cp004b2_private.invitations(state,expires_at);
CREATE TABLE cp004b2_private.receipts (
 actor uuid NOT NULL REFERENCES cp004b2_private.accounts, operation_id uuid NOT NULL,
 request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
 couple_id uuid NOT NULL REFERENCES cp004b2.spaces, result jsonb NOT NULL,
 PRIMARY KEY(actor,operation_id)
);

-- Narrow Auth-owner bridge: current signed-in principal only, no user-ID argument.
-- Auth rows retain their own RLS; application owner never gains Auth SELECT/BYPASSRLS.
RESET ROLE;
CREATE FUNCTION cp004b2_private.current_email(p_lock boolean) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e text;
BEGIN
 IF auth.uid() IS NULL OR auth.role()<>'authenticated' THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 IF p_lock THEN
  SELECT email INTO e FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL
   AND NOT coalesce(is_anonymous,false) AND (banned_until IS NULL OR banned_until<=clock_timestamp()) FOR SHARE;
 ELSE
  SELECT email INTO e FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL
   AND NOT coalesce(is_anonymous,false) AND (banned_until IS NULL OR banned_until<=statement_timestamp());
 END IF;
 IF e IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 RETURN e;
END $$;
GRANT USAGE,CREATE ON SCHEMA cp004b2_private TO supabase_auth_admin;
ALTER FUNCTION cp004b2_private.current_email(boolean) OWNER TO supabase_auth_admin;
REVOKE CREATE ON SCHEMA cp004b2_private FROM supabase_auth_admin;
REVOKE ALL ON FUNCTION cp004b2_private.current_email(boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION cp004b2_private.current_email(boolean) TO cp004b2_owner;
SET LOCAL ROLE cp004b2_owner;

CREATE FUNCTION cp004b2_private.normal_email(e text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
 e:=btrim(e);
 IF e IS NULL OR length(e)>254 OR e !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
 RAISE EXCEPTION 'invalid_input' USING ERRCODE='PT400'; END IF;
 RETURN split_part(e,'@',1)||'@'||lower(split_part(e,'@',2));
END $$;
CREATE FUNCTION cp004b2_private.email_hash(e text) RETURNS bytea
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT extensions.hmac(convert_to(cp004b2_private.normal_email(e),'UTF8'),email_key,'sha256')
 FROM cp004b2_private.keys WHERE version=1
$$;
CREATE FUNCTION cp004b2_private.lock_actor() RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a uuid:=auth.uid(); en boolean;
BEGIN
 -- Fixed order: actor Auth SHARE, actor account UPDATE, space, invitation.
 PERFORM cp004b2_private.current_email(true);
 INSERT INTO cp004b2_private.accounts(user_id) VALUES(a) ON CONFLICT DO NOTHING;
 SELECT enabled INTO en FROM cp004b2_private.accounts WHERE user_id=a FOR UPDATE;
 IF NOT en THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 RETURN a;
END $$;
CREATE FUNCTION cp004b2.can_read(c uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM cp004b2.memberships m JOIN cp004b2.spaces s ON s.id=m.couple_id
 JOIN cp004b2_private.accounts a ON a.user_id=m.user_id
 WHERE m.user_id=auth.uid() AND a.enabled AND m.active AND s.id=c AND s.state IN ('draft','paired'))
$$;
CREATE FUNCTION cp004b2_private.replay(op uuid,h bytea) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE r cp004b2_private.receipts%ROWTYPE;
BEGIN
 IF op IS NULL THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='PT400'; END IF;
 SELECT * INTO r FROM cp004b2_private.receipts WHERE actor=auth.uid() AND operation_id=op;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.request_hash<>h THEN RAISE EXCEPTION 'operation_id_reused' USING ERRCODE='PT409'; END IF;
 IF NOT cp004b2.can_read(r.couple_id) THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 RETURN r.result;
END $$;
CREATE FUNCTION cp004b2.ensure_account() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RETURN jsonb_build_object('user_id',cp004b2_private.lock_actor()); END $$;
CREATE FUNCTION cp004b2.account_context() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; context jsonb;
BEGIN
 a:=cp004b2_private.lock_actor();
 SELECT coalesce(jsonb_agg(jsonb_build_object('space_id',s.id,'state',s.state,'epoch',s.epoch)), '[]'::jsonb)
 INTO context FROM cp004b2.spaces s JOIN cp004b2.memberships m ON m.couple_id=s.id
 WHERE m.user_id=a AND m.active AND s.state IN ('draft','paired');
 RETURN jsonb_build_object('user_id',a,'spaces',context);
END $$;
CREATE FUNCTION cp004b2.create_space(p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; c uuid; h bytea:=sha256(convert_to('v1:create_space','UTF8')); result jsonb;
BEGIN
 a:=cp004b2_private.lock_actor(); result:=cp004b2_private.replay(p_operation_id,h);
 IF result IS NOT NULL THEN RETURN result; END IF;
 IF EXISTS(SELECT 1 FROM cp004b2.memberships WHERE user_id=a AND active) THEN
 RAISE EXCEPTION 'active_space_exists' USING ERRCODE='PT409'; END IF;
 INSERT INTO cp004b2.spaces(state) VALUES('draft') RETURNING id INTO c;
 INSERT INTO cp004b2.memberships(couple_id,user_id,seat) VALUES(c,a,1);
 result:=jsonb_build_object('space_id',c);
 INSERT INTO cp004b2_private.receipts VALUES(a,p_operation_id,h,c,result);
 RETURN result;
END $$;
CREATE FUNCTION cp004b2.issue_invitation(p_operation_id uuid,p_space uuid,p_expected_epoch bigint,p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; normalized text; rh bytea; h bytea; result jsonb; s cp004b2.spaces%ROWTYPE;
 token text; i uuid; exp timestamptz;
BEGIN
 a:=cp004b2_private.lock_actor(); normalized:=cp004b2_private.normal_email(p_email);
 rh:=cp004b2_private.email_hash(normalized);
 h:=sha256(convert_to(jsonb_build_array('v1:issue',p_space,p_expected_epoch,encode(rh,'hex'))::text,'UTF8'));
 result:=cp004b2_private.replay(p_operation_id,h);
 IF result IS NOT NULL THEN RETURN result; END IF;
 SELECT * INTO s FROM cp004b2.spaces WHERE id=p_space FOR UPDATE;
 IF NOT FOUND OR NOT cp004b2.can_read(p_space) OR s.state<>'draft'
 OR s.epoch IS DISTINCT FROM p_expected_epoch THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 IF rh=cp004b2_private.email_hash(cp004b2_private.current_email(false)) THEN
 RAISE EXCEPTION 'self_invitation' USING ERRCODE='PT400'; END IF;
 -- Do not look up recipient registration/verification/membership at issuance.
 -- Every syntactically valid unrelated email gets the same opaque envelope.
 UPDATE cp004b2_private.invitations SET state='revoked' WHERE couple_id=p_space AND state='pending';
 token:=encode(extensions.gen_random_bytes(32),'hex'); exp:=clock_timestamp()+interval '24 hours';
 INSERT INTO cp004b2_private.invitations(couple_id,issuer,token_hash,recipient_hmac,key_version,expires_at,state)
 VALUES(p_space,a,sha256(convert_to(token,'UTF8')),rh,1,exp,'pending') RETURNING id INTO i;
 result:=jsonb_build_object('invitation_id',i,'expires_at',exp);
 INSERT INTO cp004b2_private.receipts VALUES(a,p_operation_id,h,p_space,result);
 -- Raw token is delivered once only; retries return the same metadata, no duplicate.
 RETURN result||jsonb_build_object('token',token);
END $$;
CREATE FUNCTION cp004b2.accept_invitation(p_operation_id uuid,p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; h bytea; result jsonb; i cp004b2_private.invitations%ROWTYPE; s cp004b2.spaces%ROWTYPE; c uuid;
BEGIN
 a:=cp004b2_private.lock_actor();
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 h:=sha256(convert_to(jsonb_build_array('v1:accept',p_token)::text,'UTF8'));
 result:=cp004b2_private.replay(p_operation_id,h);
 IF result IS NOT NULL THEN RETURN result; END IF;
 SELECT couple_id INTO c FROM cp004b2_private.invitations WHERE token_hash=sha256(convert_to(p_token,'UTF8'));
 IF NOT FOUND THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO s FROM cp004b2.spaces WHERE id=c FOR UPDATE;
 SELECT * INTO i FROM cp004b2_private.invitations WHERE couple_id=c AND token_hash=sha256(convert_to(p_token,'UTF8')) FOR UPDATE;
 IF i.state<>'pending' OR i.expires_at<=clock_timestamp() OR s.state<>'draft'
 OR i.issuer=a OR i.recipient_hmac<>cp004b2_private.email_hash(cp004b2_private.current_email(false))
 OR NOT EXISTS(SELECT 1 FROM cp004b2.memberships m JOIN cp004b2_private.accounts u ON u.user_id=m.user_id
 WHERE m.couple_id=c AND m.user_id=i.issuer AND m.seat=1 AND m.active AND u.enabled)
 OR EXISTS(SELECT 1 FROM cp004b2.memberships WHERE user_id=a AND active) THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 INSERT INTO cp004b2.memberships(couple_id,user_id,seat) VALUES(c,a,2);
 UPDATE cp004b2.spaces SET state='paired',epoch=epoch+1 WHERE id=c;
 UPDATE cp004b2_private.invitations SET state='accepted',accepted_by=a WHERE id=i.id;
 result:=jsonb_build_object('space_id',c);
 INSERT INTO cp004b2_private.receipts VALUES(a,p_operation_id,h,c,result);
 RETURN result;
END $$;
CREATE FUNCTION cp004b2.revoke_invitation(p_operation_id uuid,p_invitation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; h bytea; result jsonb; c uuid; i cp004b2_private.invitations%ROWTYPE;
BEGIN
 a:=cp004b2_private.lock_actor();
 h:=sha256(convert_to(jsonb_build_array('v1:revoke',p_invitation)::text,'UTF8'));
 result:=cp004b2_private.replay(p_operation_id,h);
 IF result IS NOT NULL THEN RETURN result; END IF;
 SELECT couple_id INTO c FROM cp004b2_private.invitations WHERE id=p_invitation;
 IF NOT FOUND THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM cp004b2.spaces WHERE id=c FOR UPDATE;
 SELECT * INTO i FROM cp004b2_private.invitations WHERE id=p_invitation FOR UPDATE;
 IF NOT cp004b2.can_read(c) OR i.issuer<>a OR i.state='accepted' THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 UPDATE cp004b2_private.invitations SET state='revoked' WHERE id=p_invitation;
 result:=jsonb_build_object('invitation_id',p_invitation,'revoked',true);
 INSERT INTO cp004b2_private.receipts VALUES(a,p_operation_id,h,c,result);
 RETURN result;
END $$;
CREATE FUNCTION cp004b2.leave_space(p_space uuid,p_expected_epoch bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; e bigint;
BEGIN
 a:=cp004b2_private.lock_actor();
 SELECT epoch INTO e FROM cp004b2.spaces WHERE id=p_space FOR UPDATE;
 IF NOT FOUND OR NOT cp004b2.can_read(p_space) OR e IS DISTINCT FROM p_expected_epoch THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 UPDATE cp004b2.memberships SET active=false WHERE couple_id=p_space;
 UPDATE cp004b2.spaces SET state='closed',closed_at=clock_timestamp(),epoch=epoch+1 WHERE id=p_space;
 UPDATE cp004b2_private.invitations SET state='revoked' WHERE couple_id=p_space AND state='pending';
 RETURN true;
END $$;

CREATE FUNCTION cp004b2_private.guard_space() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF OLD.id<>NEW.id OR (OLD.state='closed' AND NEW IS DISTINCT FROM OLD) THEN
 RAISE EXCEPTION 'closed_or_immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_space BEFORE UPDATE ON cp004b2.spaces
 FOR EACH ROW EXECUTE FUNCTION cp004b2_private.guard_space();
CREATE FUNCTION cp004b2_private.guard_member() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'seat_immutable' USING ERRCODE='23514'; END IF;
 IF (OLD.id,OLD.couple_id,OLD.user_id,OLD.seat) IS DISTINCT FROM (NEW.id,NEW.couple_id,NEW.user_id,NEW.seat)
 OR (NOT OLD.active AND NEW.active) THEN RAISE EXCEPTION 'seat_immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_member BEFORE UPDATE OR DELETE ON cp004b2.memberships
 FOR EACH ROW EXECUTE FUNCTION cp004b2_private.guard_member();
CREATE FUNCTION cp004b2_private.check_counts() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE c uuid; st text; n integer;
BEGIN
 IF TG_TABLE_NAME='spaces' THEN c:=NEW.id; ELSE c:=NEW.couple_id; END IF;
 SELECT state INTO st FROM cp004b2.spaces WHERE id=c;
 SELECT count(*) INTO n FROM cp004b2.memberships WHERE couple_id=c AND active;
 IF NOT ((st='draft' AND n=1) OR (st='paired' AND n=2) OR (st='closed' AND n=0)) THEN
 RAISE EXCEPTION 'state_count' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER space_counts AFTER INSERT OR UPDATE ON cp004b2.spaces
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004b2_private.check_counts();
CREATE CONSTRAINT TRIGGER member_counts AFTER INSERT OR UPDATE ON cp004b2.memberships
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004b2_private.check_counts();

ALTER TABLE cp004b2.spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b2.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b2_private.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b2_private.keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b2_private.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b2_private.receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY scoped ON cp004b2.spaces FOR SELECT TO authenticated USING(cp004b2.can_read(id));
CREATE POLICY scoped ON cp004b2.memberships FOR SELECT TO authenticated USING(cp004b2.can_read(couple_id));
REVOKE ALL ON ALL TABLES IN SCHEMA cp004b2,cp004b2_private FROM PUBLIC,anon,authenticated,service_role;
-- Do not overwrite the Auth bridge's explicit grant to application owner.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cp004b2,cp004b2_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SCHEMA cp004b2_private FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA cp004b2 TO anon,authenticated;
GRANT SELECT ON cp004b2.spaces,cp004b2.memberships TO authenticated;
GRANT EXECUTE ON FUNCTION cp004b2.can_read(uuid),cp004b2.ensure_account(),cp004b2.account_context(),
 cp004b2.create_space(uuid),cp004b2.issue_invitation(uuid,uuid,bigint,text),cp004b2.accept_invitation(uuid,text),
 cp004b2.revoke_invitation(uuid,uuid),cp004b2.leave_space(uuid,bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
