-- CP-004B.1 LOCAL PROTOTYPE ONLY. Not a production/application migration.
-- Installed only by run_tests.py in its separately labelled disposable stack.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'postgres' OR
 shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database')
 IS DISTINCT FROM 'twogethera:cp004b1:disposable:v1' THEN
 RAISE EXCEPTION 'wrong_proof_database'; END IF;
END $$;
CREATE SCHEMA cp004b1 AUTHORIZATION cp004b1_owner;
CREATE SCHEMA cp004b1_private AUTHORIZATION cp004b1_owner;
SET LOCAL ROLE cp004b1_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004b1 REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA cp004b1_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE cp004b1.spaces (
 id uuid PRIMARY KEY, state text NOT NULL CHECK(state IN ('draft','paired','closed')),
 closed_at timestamptz, CHECK((state='closed')=(closed_at IS NOT NULL))
);
CREATE TABLE cp004b1.memberships (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 couple_id uuid NOT NULL REFERENCES cp004b1.spaces,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 seat smallint NOT NULL CHECK(seat IN (1,2)), active boolean NOT NULL DEFAULT true,
 UNIQUE(couple_id,seat), UNIQUE(couple_id,user_id)
);
CREATE UNIQUE INDEX one_active_space ON cp004b1.memberships(user_id) WHERE active;
CREATE INDEX scope_members ON cp004b1.memberships(couple_id,user_id);
CREATE TABLE cp004b1.records (
 id uuid PRIMARY KEY, couple_id uuid NOT NULL REFERENCES cp004b1.spaces,
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 200)
);
CREATE INDEX scope_records ON cp004b1.records(couple_id,id);
CREATE FUNCTION cp004b1_private.authenticated_actor() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 -- Auth verifies/confirm-signs identity; live membership is checked separately.
 -- Do not bypass auth.users RLS or grant an application helper broad Auth reads.
 SELECT auth.uid() IS NOT NULL AND auth.role()='authenticated'
 AND NOT coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
$$;
CREATE FUNCTION cp004b1.can_read(c uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT cp004b1_private.authenticated_actor() AND EXISTS(
 SELECT 1 FROM cp004b1.memberships m JOIN cp004b1.spaces s ON s.id=m.couple_id
 WHERE m.user_id=auth.uid() AND m.couple_id=c AND m.active AND s.state IN ('draft','paired'))
$$;
CREATE FUNCTION cp004b1.whoami() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('uid',auth.uid(),'database_role',current_user)
 WHERE auth.uid() IS NOT NULL
$$;
CREATE FUNCTION cp004b1.leave_space(p_space uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT cp004b1_private.authenticated_actor() THEN
   RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM cp004b1.spaces WHERE id=p_space FOR UPDATE;
 IF NOT FOUND OR NOT cp004b1.can_read(p_space) THEN
   RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF;
 UPDATE cp004b1.memberships SET active=false WHERE couple_id=p_space;
 UPDATE cp004b1.spaces SET state='closed',closed_at=clock_timestamp() WHERE id=p_space;
 RETURN true;
END $$;
CREATE FUNCTION cp004b1_private.guard_space() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF OLD.id<>NEW.id OR (OLD.state='closed' AND NEW IS DISTINCT FROM OLD) THEN
 RAISE EXCEPTION 'closed_or_immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_space BEFORE UPDATE ON cp004b1.spaces
 FOR EACH ROW EXECUTE FUNCTION cp004b1_private.guard_space();
CREATE FUNCTION cp004b1_private.guard_member() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'seat_immutable' USING ERRCODE='23514'; END IF;
 IF (OLD.id,OLD.couple_id,OLD.user_id,OLD.seat) IS DISTINCT FROM (NEW.id,NEW.couple_id,NEW.user_id,NEW.seat)
 OR (NOT OLD.active AND NEW.active) THEN RAISE EXCEPTION 'seat_immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_member BEFORE UPDATE OR DELETE ON cp004b1.memberships
 FOR EACH ROW EXECUTE FUNCTION cp004b1_private.guard_member();
CREATE FUNCTION cp004b1_private.check_counts() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE c uuid; st text; n integer;
BEGIN
 IF TG_TABLE_NAME='spaces' THEN c:=NEW.id; ELSE c:=NEW.couple_id; END IF;
 SELECT state INTO st FROM cp004b1.spaces WHERE id=c;
 SELECT count(*) INTO n FROM cp004b1.memberships WHERE couple_id=c AND active;
 IF NOT ((st='draft' AND n=1) OR (st='paired' AND n=2) OR (st='closed' AND n=0)) THEN
 RAISE EXCEPTION 'state_count' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER space_counts AFTER INSERT OR UPDATE ON cp004b1.spaces
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004b1_private.check_counts();
CREATE CONSTRAINT TRIGGER member_counts AFTER INSERT OR UPDATE ON cp004b1.memberships
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cp004b1_private.check_counts();
ALTER TABLE cp004b1.spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b1.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE cp004b1.records ENABLE ROW LEVEL SECURITY;
CREATE POLICY scoped ON cp004b1.spaces FOR SELECT TO authenticated USING(cp004b1.can_read(id));
CREATE POLICY scoped ON cp004b1.memberships FOR SELECT TO authenticated USING(cp004b1.can_read(couple_id));
CREATE POLICY scoped ON cp004b1.records FOR SELECT TO authenticated USING(cp004b1.can_read(couple_id));
-- Deliberately no client DML grants or policies, including on memberships.
REVOKE ALL ON ALL TABLES IN SCHEMA cp004b1 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cp004b1,cp004b1_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SCHEMA cp004b1_private FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA cp004b1 TO anon,authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA cp004b1 TO authenticated;
GRANT EXECUTE ON FUNCTION cp004b1.can_read(uuid),cp004b1.whoami(),cp004b1.leave_space(uuid) TO authenticated;
COMMIT;
NOTIFY pgrst,'reload schema';
