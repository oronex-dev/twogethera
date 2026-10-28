-- CP-004A synthetic proof only. Run only through run_tests.py's guarded database.
-- This is NOT a production migration. No auth/public/application schemas are changed.
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'twogethera_cp004a_proof'
     OR shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database')
        IS DISTINCT FROM 'twogethera:cp004a:disposable:v1' THEN
    RAISE EXCEPTION 'wrong proof database';
  END IF;
END $$;
DROP SCHEMA IF EXISTS cp004a CASCADE;
DROP SCHEMA IF EXISTS cp004a_private CASCADE;
CREATE SCHEMA cp004a AUTHORIZATION cp004a_owner;
CREATE SCHEMA cp004a_private AUTHORIZATION cp004a_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
SET LOCAL ROLE cp004a_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004a REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004a_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE cp004a_private.identities (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), role_name name UNIQUE NOT NULL,
 email text UNIQUE NOT NULL CHECK (email LIKE '%@example.invalid'), verified boolean NOT NULL
);
CREATE TABLE cp004a.spaces (
 id uuid PRIMARY KEY, state text NOT NULL CHECK(state IN ('draft','paired','closed')),
 epoch bigint NOT NULL DEFAULT 1 CHECK(epoch>0), closed_at timestamptz,
 CHECK ((state='closed')=(closed_at IS NOT NULL))
);
CREATE TABLE cp004a.memberships (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), couple_id uuid NOT NULL REFERENCES cp004a.spaces,
 user_id uuid NOT NULL REFERENCES cp004a_private.identities, seat smallint NOT NULL CHECK(seat IN (1,2)),
 active boolean NOT NULL DEFAULT true,
 UNIQUE(couple_id,seat), UNIQUE(couple_id,user_id)
);
CREATE UNIQUE INDEX one_active_space ON cp004a.memberships(user_id) WHERE active;
CREATE TABLE cp004a_private.invitations (
 id uuid PRIMARY KEY, couple_id uuid NOT NULL REFERENCES cp004a.spaces,
 inviter uuid NOT NULL REFERENCES cp004a_private.identities,
 recipient uuid NOT NULL REFERENCES cp004a_private.identities,
 token_hash bytea UNIQUE NOT NULL CHECK(octet_length(token_hash)=32),
 expires_at timestamptz NOT NULL, state text NOT NULL CHECK(state IN ('pending','accepted','revoked')),
 accepted_by uuid REFERENCES cp004a_private.identities,
 CHECK ((state='accepted')=(accepted_by IS NOT NULL)), CHECK(inviter<>recipient)
);
CREATE UNIQUE INDEX one_pending_invite ON cp004a_private.invitations(couple_id) WHERE state='pending';
CREATE TABLE cp004a.records (
 id uuid PRIMARY KEY, couple_id uuid NOT NULL REFERENCES cp004a.spaces,
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 200), revision bigint NOT NULL CHECK(revision>0)
);
CREATE INDEX records_scope ON cp004a.records(couple_id,id);
CREATE INDEX memberships_scope ON cp004a.memberships(couple_id,user_id);
CREATE TABLE cp004a_private.receipts (
 actor uuid NOT NULL REFERENCES cp004a_private.identities, operation_id uuid NOT NULL,
 request_hash bytea NOT NULL, couple_id uuid NOT NULL REFERENCES cp004a.spaces,
 result jsonb NOT NULL, PRIMARY KEY(actor,operation_id)
);

CREATE FUNCTION cp004a_private.actor() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path='' AS $$ SELECT id FROM cp004a_private.identities WHERE role_name=session_user $$;
CREATE FUNCTION cp004a.can_read(c uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM cp004a.memberships m JOIN cp004a.spaces s ON s.id=m.couple_id
 WHERE m.user_id=cp004a_private.actor() AND m.couple_id=c AND m.active AND s.state IN ('draft','paired'))
$$;
CREATE FUNCTION cp004a_private.guard_space() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF OLD.id<>NEW.id OR (OLD.state='closed' AND NEW IS DISTINCT FROM OLD)
    OR (OLD.closed_at IS NOT NULL AND NEW.closed_at IS DISTINCT FROM OLD.closed_at) THEN
   RAISE EXCEPTION 'closed_or_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_space BEFORE UPDATE ON cp004a.spaces
 FOR EACH ROW EXECUTE FUNCTION cp004a_private.guard_space();
CREATE FUNCTION cp004a_private.guard_member() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'historical_seat_immutable' USING ERRCODE='23514'; END IF;
 IF (OLD.id,OLD.couple_id,OLD.user_id,OLD.seat) IS DISTINCT FROM (NEW.id,NEW.couple_id,NEW.user_id,NEW.seat)
    OR (NOT OLD.active AND NEW.active) THEN
   RAISE EXCEPTION 'historical_seat_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_member BEFORE UPDATE OR DELETE ON cp004a.memberships
 FOR EACH ROW EXECUTE FUNCTION cp004a_private.guard_member();
CREATE FUNCTION cp004a_private.check_counts() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE c uuid; st text; n integer;
BEGIN
 IF TG_TABLE_NAME='spaces' THEN c:=NEW.id; ELSE c:=NEW.couple_id; END IF;
 SELECT state INTO st FROM cp004a.spaces WHERE id=c;
 SELECT count(*) INTO n FROM cp004a.memberships WHERE couple_id=c AND active;
 IF NOT ((st='draft' AND n=1) OR (st='paired' AND n=2) OR (st='closed' AND n=0)) THEN
   RAISE EXCEPTION 'membership_state_count' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER space_counts AFTER INSERT OR UPDATE ON cp004a.spaces
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004a_private.check_counts();
CREATE CONSTRAINT TRIGGER member_counts AFTER INSERT OR UPDATE ON cp004a.memberships
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004a_private.check_counts();

-- Owner is a dedicated NOLOGIN/NOBYPASSRLS role. It bypasses RLS only as table owner
-- inside audited definer commands/helpers. Clients are never members of this role.
ALTER TABLE cp004a.spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004a.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004a.records ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004a_private.identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004a_private.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004a_private.receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_scope ON cp004a.spaces FOR SELECT TO cp004a_client USING(cp004a.can_read(id));
CREATE POLICY own_scope ON cp004a.memberships FOR SELECT TO cp004a_client USING(cp004a.can_read(couple_id));
CREATE POLICY own_scope ON cp004a.records FOR SELECT TO cp004a_client USING(cp004a.can_read(couple_id));
-- No DML policies. Even temporary DML grants must not allow invoker writes.

CREATE FUNCTION cp004a.command(op uuid, kind text, scope uuid, payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 a uuid; ah cp004a_private.identities%ROWTYPE; s cp004a.spaces%ROWTYPE;
 inv cp004a_private.invitations%ROWTYPE; receipt cp004a_private.receipts%ROWTYPE;
 h bytea; answer jsonb; tok text; target uuid; iid uuid; rid uuid; v bigint;
BEGIN
 a:=cp004a_private.actor();
 IF a IS NULL OR op IS NULL OR scope IS NULL OR kind IS NULL OR payload IS NULL
    OR jsonb_typeof(payload)<>'object' OR octet_length(payload::text)>4096 THEN
   RAISE EXCEPTION 'denied' USING ERRCODE='42501';
 END IF;
 -- Per-actor serialization prevents parallel joins into different spaces and op-key races.
 SELECT * INTO ah FROM cp004a_private.identities WHERE id=a FOR UPDATE;
 IF NOT ah.verified THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF;
 h:=sha256(convert_to(jsonb_build_array(kind,scope,payload)::text,'UTF8'));
 SELECT * INTO receipt FROM cp004a_private.receipts WHERE actor=a AND operation_id=op;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RAISE EXCEPTION 'operation_id_reused' USING ERRCODE='22023'; END IF;
   IF NOT cp004a.can_read(receipt.couple_id) THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF;
   RETURN receipt.result;
 END IF;
 IF kind='create' THEN
   IF payload<>'{}'::jsonb THEN RAISE EXCEPTION 'invalid_payload' USING ERRCODE='22023'; END IF;
   IF EXISTS(SELECT 1 FROM cp004a.memberships WHERE user_id=a AND active) THEN
     RAISE EXCEPTION 'already_paired' USING ERRCODE='23505';
   END IF;
   INSERT INTO cp004a.spaces(id,state) VALUES(scope,'draft');
   INSERT INTO cp004a.memberships(couple_id,user_id,seat) VALUES(scope,a,1);
   answer:=jsonb_build_object('scope',scope,'epoch',1);
 ELSE
   -- All business effects, including unlink, serialize at the same scope row.
   SELECT * INTO s FROM cp004a.spaces WHERE id=scope FOR UPDATE;
   IF NOT FOUND OR s.state='closed' THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
   IF kind='accept' THEN
     IF NOT (payload ? 'token') OR payload - 'token'<>'{}'::jsonb
        OR length(payload->>'token')<>64 THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
     SELECT * INTO inv FROM cp004a_private.invitations
      WHERE couple_id=scope AND token_hash=sha256(convert_to(payload->>'token','UTF8')) FOR UPDATE;
     IF NOT FOUND OR inv.state<>'pending' OR inv.recipient<>a OR inv.inviter=a
       OR inv.expires_at<=clock_timestamp() OR s.state<>'draft'
       OR NOT EXISTS(SELECT 1 FROM cp004a.memberships WHERE couple_id=scope AND user_id=inv.inviter AND active AND seat=1)
       OR EXISTS(SELECT 1 FROM cp004a.memberships WHERE user_id=a AND active) THEN
       RAISE EXCEPTION 'unavailable' USING ERRCODE='42501';
     END IF;
     INSERT INTO cp004a.memberships(couple_id,user_id,seat) VALUES(scope,a,2);
     UPDATE cp004a.spaces SET state='paired',epoch=epoch+1 WHERE id=scope RETURNING epoch INTO v;
     UPDATE cp004a_private.invitations SET state='accepted',accepted_by=a WHERE id=inv.id;
     answer:=jsonb_build_object('scope',scope,'epoch',v);
   ELSE
     IF NOT cp004a.can_read(scope) THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF;
     IF (payload->>'epoch')::bigint IS DISTINCT FROM s.epoch THEN
       RAISE EXCEPTION 'stale_epoch' USING ERRCODE='40001';
     END IF;
     IF kind='invite' THEN
       IF s.state<>'draft' OR payload - ARRAY['epoch','recipient']<>'{}'::jsonb THEN
         RAISE EXCEPTION 'invalid_state_or_payload' USING ERRCODE='22023'; END IF;
       SELECT id INTO target FROM cp004a_private.identities WHERE email=payload->>'recipient';
       IF target IS NULL OR target=a THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
       UPDATE cp004a_private.invitations SET state='revoked' WHERE couple_id=scope AND state='pending';
       -- Hash three independent CSPRNG UUIDv4 values (366 random input bits)
       -- to a 256-bit token; avoid persisting or logging the raw token.
       tok:=encode(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text||gen_random_uuid()::text,'UTF8')),'hex'); iid:=gen_random_uuid();
       INSERT INTO cp004a_private.invitations(id,couple_id,inviter,recipient,token_hash,expires_at,state)
        VALUES(iid,scope,a,target,sha256(convert_to(tok,'UTF8')),clock_timestamp()+interval '24 hours','pending');
       answer:=jsonb_build_object('invitation',iid);
     ELSIF kind='unlink' THEN
       IF payload - 'epoch'<>'{}'::jsonb OR s.state<>'paired' THEN
         RAISE EXCEPTION 'invalid_state_or_payload' USING ERRCODE='22023'; END IF;
       UPDATE cp004a.memberships SET active=false WHERE couple_id=scope;
       UPDATE cp004a.spaces SET state='closed',closed_at=clock_timestamp(),epoch=epoch+1 WHERE id=scope;
       UPDATE cp004a_private.invitations SET state='revoked' WHERE couple_id=scope AND state='pending';
       answer:=jsonb_build_object('closed',true);
     ELSIF kind IN ('put','edit','remove') THEN
       IF s.state<>'paired' OR payload - ARRAY['epoch','id','body','revision']<>'{}'::jsonb THEN
         RAISE EXCEPTION 'invalid_state_or_payload' USING ERRCODE='22023'; END IF;
       rid:=(payload->>'id')::uuid;
       IF rid IS NULL THEN RAISE EXCEPTION 'invalid_payload' USING ERRCODE='22023'; END IF;
       IF kind='put' THEN
         INSERT INTO cp004a.records VALUES(rid,scope,payload->>'body',1);v:=1;
       ELSE
         SELECT revision INTO v FROM cp004a.records WHERE id=rid AND couple_id=scope FOR UPDATE;
         IF NOT FOUND OR v IS DISTINCT FROM (payload->>'revision')::bigint THEN
           RAISE EXCEPTION 'stale_revision' USING ERRCODE='40001'; END IF;
         v:=v+1;
         IF kind='edit' THEN UPDATE cp004a.records SET body=payload->>'body',revision=v WHERE id=rid;
         ELSE DELETE FROM cp004a.records WHERE id=rid; END IF;
       END IF;
       answer:=jsonb_build_object('id',rid,'revision',v);
     ELSE RAISE EXCEPTION 'invalid_command' USING ERRCODE='22023';
     END IF;
   END IF;
 END IF;
 INSERT INTO cp004a_private.receipts VALUES(a,op,h,scope,answer);
 -- Token is returned once, but never stored in receipts or test logs.
 IF tok IS NOT NULL THEN RETURN answer||jsonb_build_object('token',tok); END IF;
 RETURN answer;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA cp004a,cp004a_private FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cp004a,cp004a_private FROM PUBLIC;
GRANT USAGE ON SCHEMA cp004a TO cp004a_client,cp004a_anon;
GRANT SELECT ON cp004a.spaces,cp004a.memberships,cp004a.records TO cp004a_client;
GRANT EXECUTE ON FUNCTION cp004a.can_read(uuid),cp004a.command(uuid,text,uuid,jsonb) TO cp004a_client;
COMMIT;
