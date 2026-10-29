-- Isolated CP-004B.4 only; experiment values, not product retention approval.
CREATE SCHEMA cp004b4_ops AUTHORIZATION cp004b2_owner;
REVOKE ALL ON SCHEMA cp004b4_ops FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='cp004b4_maintainer') THEN
 CREATE ROLE cp004b4_maintainer NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
 COMMENT ON ROLE cp004b4_maintainer IS 'twogethera:cp004b4:disposable:v1'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='cp004b4_maintainer' AND NOT rolcanlogin AND NOT rolsuper
 AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
 AND shobj_description(oid,'pg_authid')='twogethera:cp004b4:disposable:v1') OR
 EXISTS(SELECT 1 FROM pg_auth_members WHERE roleid=(SELECT oid FROM pg_roles WHERE rolname='cp004b4_maintainer')
 OR member=(SELECT oid FROM pg_roles WHERE rolname='cp004b4_maintainer')) THEN
 RAISE EXCEPTION 'unsafe_maintainer' USING ERRCODE='42501'; END IF;
END $$;
SET LOCAL ROLE cp004b2_owner;
CREATE TABLE cp004b4_ops.issue_budgets (
 actor uuid NOT NULL REFERENCES cp004b2_private.accounts, bucket bigint NOT NULL,
 used integer NOT NULL CHECK(used BETWEEN 1 AND 5),PRIMARY KEY(actor,bucket)
);
ALTER TABLE cp004b4_ops.issue_budgets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA cp004b4_ops FROM PUBLIC,anon,authenticated,service_role,cp004b4_maintainer;
ALTER TABLE cp004b2_private.receipts ADD COLUMN recorded_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE cp004b2_private.receipts ADD COLUMN expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '1 hour';
ALTER TABLE cp004b2_private.receipts ADD COLUMN retired boolean NOT NULL DEFAULT false;
CREATE INDEX receipt_cleanup ON cp004b2_private.receipts(expires_at,actor) WHERE NOT retired;
-- The B.4 kernel snapshot uses explicit receipt column names for additive metadata.
CREATE OR REPLACE FUNCTION cp004b2_private.replay(op uuid,h bytea) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE r cp004b2_private.receipts%ROWTYPE;
BEGIN
 IF op IS NULL THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='PT400'; END IF;
 SELECT * INTO r FROM cp004b2_private.receipts WHERE actor=auth.uid() AND operation_id=op;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.retired OR r.expires_at<=clock_timestamp() THEN
 RAISE EXCEPTION 'operation_expired' USING ERRCODE='PT409'; END IF;
 IF r.request_hash<>h THEN RAISE EXCEPTION 'operation_id_reused' USING ERRCODE='PT409'; END IF;
 IF NOT cp004b2.can_read(r.couple_id) THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 RETURN r.result;
END $$;
ALTER FUNCTION cp004b2.issue_invitation(uuid,uuid,bigint,text) SET SCHEMA cp004b4_ops;
ALTER FUNCTION cp004b4_ops.issue_invitation(uuid,uuid,bigint,text) RENAME TO issue_core;
REVOKE ALL ON FUNCTION cp004b4_ops.issue_core(uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role,cp004b4_maintainer;
CREATE FUNCTION cp004b2.issue_invitation(p_operation_id uuid,p_space uuid,p_expected_epoch bigint,p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; existed boolean; answer jsonb; slot bigint; n integer;
BEGIN
 a:=cp004b2_private.lock_actor();
 SELECT EXISTS(SELECT 1 FROM cp004b2_private.receipts WHERE actor=a AND operation_id=p_operation_id) INTO existed;
 -- Core validates/replays; quota is charged only for a fresh successful effect.
 -- A quota error rolls the whole call, including pending replacement/receipt, back.
 answer:=cp004b4_ops.issue_core(p_operation_id,p_space,p_expected_epoch,p_email);
 IF NOT existed THEN
  slot:=floor(extract(epoch FROM clock_timestamp())/3600)::bigint;
  SELECT used INTO n FROM cp004b4_ops.issue_budgets WHERE actor=a AND bucket=slot FOR UPDATE;
  IF n>=5 THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='PT429'; END IF;
  INSERT INTO cp004b4_ops.issue_budgets(actor,bucket,used) VALUES(a,slot,1)
   ON CONFLICT(actor,bucket) DO UPDATE SET used=cp004b4_ops.issue_budgets.used+1;
 END IF;
 RETURN answer;
END $$;
GRANT EXECUTE ON FUNCTION cp004b2.issue_invitation(uuid,uuid,bigint,text) TO authenticated;
CREATE FUNCTION cp004b4_ops.set_account_enabled(p_user uuid,p_enabled boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM cp004b2_private.accounts WHERE user_id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF;
 UPDATE cp004b2_private.accounts SET enabled=p_enabled WHERE user_id=p_user;
 RETURN p_enabled;
END $$;
CREATE FUNCTION cp004b4_ops.compact_receipts(p_limit integer DEFAULT 100) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a uuid; changed integer; total integer:=0; cutoff timestamptz:=clock_timestamp();
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>1000 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='PT400'; END IF;
 -- Lock account BEFORE touching receipts, same serialization point as commands.
 -- Skip actors with in-flight operations rather than racing their receipts.
 FOR a IN SELECT u.user_id FROM cp004b2_private.accounts u
 WHERE EXISTS(SELECT 1 FROM cp004b2_private.receipts r WHERE r.actor=u.user_id AND NOT r.retired AND r.expires_at<=cutoff)
 ORDER BY u.user_id FOR UPDATE OF u SKIP LOCKED LIMIT p_limit LOOP
  UPDATE cp004b2_private.receipts SET result='{}'::jsonb,request_hash=decode(repeat('00',32),'hex'),retired=true
   WHERE actor=a AND NOT retired AND expires_at<=cutoff;
  GET DIAGNOSTICS changed=ROW_COUNT; total:=total+changed;
 END LOOP;
 RETURN total;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cp004b4_ops FROM PUBLIC,anon,authenticated,service_role,cp004b4_maintainer;
GRANT USAGE ON SCHEMA cp004b4_ops TO cp004b4_maintainer;
GRANT EXECUTE ON FUNCTION cp004b4_ops.set_account_enabled(uuid,boolean),cp004b4_ops.compact_receipts(integer) TO cp004b4_maintainer;
RESET ROLE;
NOTIFY pgrst,'reload schema';
