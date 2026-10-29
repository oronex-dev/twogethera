#!/usr/bin/env python3
"""Local B.3 migration runner + unchanged B.2 real JWT regression methods.
Nothing here is a production migration tool. No hosted URL or deployment support.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('checkpointed_b2',HERE.parent/'cp004b2-membership/run_tests.py')
b2=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(b2)
b2.HERE=HERE;b2.PROJECT='twogethera-b3';b2.CONTAINER='supabase_db_'+b2.PROJECT
b2.SENTINEL='twogethera:cp004b3:disposable:v1';b2.API='http://127.0.0.1:57321';b2.MAIL='http://127.0.0.1:57324'
require=b2.require;quote=b2.quote;sql=b2.sql;proc=b2.proc


def local_http(url,method='GET',body=None,headers=None):
    parsed=urllib.parse.urlsplit(url)
    require(parsed.scheme=='http' and parsed.hostname=='127.0.0.1' and parsed.port in (57321,57324),'Nonlocal rehearsal HTTP refused')
    payload=json.dumps(body).encode() if body is not None else None
    request=urllib.request.Request(url,data=payload,headers={'Content-Type':'application/json',**(headers or {})},method=method)
    try:response=b2.HTTP.open(request,timeout=12)
    except urllib.error.HTTPError as e:response=e
    data=response.read()
    try:decoded=json.loads(data) if data else None
    except (json.JSONDecodeError,UnicodeDecodeError):decoded=data.decode(errors='replace')
    return response.code,decoded,dict(response.headers)

b2.http=local_http


class Rehearsal(b2.Proof):
    def __init__(self):
        super().__init__();self.rehearsal=[]
        require(hashlib.sha256((HERE.parent/'cp004b2-membership/run_tests.py').read_bytes()).hexdigest()=='868aab51610c5bcabfc091ec963b21cf02b138734b61543b8f3ddf0ea939348d','Checkpointed B.2 regression source changed; review required')
        self.manifest=json.loads((HERE/'migrations.json').read_text())
        require(len(self.manifest)==3 and [x['version'] for x in self.manifest]==sorted(x['version'] for x in self.manifest),'Invalid ordered manifest')
        for row in self.manifest:
            path=(HERE/row['path']).resolve()
            require(path.is_relative_to(HERE) and hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],'Migration checksum/path mismatch')

    def check(self,name):
        self.rehearsal.append(name);print('REHEARSAL PASS:',name,flush=True)

    def preflight(self):
        require(__debug__ and not os.environ.get('PYTHONOPTIMIZE'),'Optimized Python refused')
        require(not b2.ENV.get('DOCKER_HOST') or b2.ENV['DOCKER_HOST'].startswith('unix://'),'Remote Docker refused')
        p=proc([b2.DOCKER,'context','inspect','--format','{{.Endpoints.docker.Host}}'])
        require(p.returncode==0 and p.stdout.strip().startswith('unix://'),'Local Docker required')
        p=proc([b2.DOCKER,'info','--format','{{.Name}} | {{.ServerVersion}}'])
        require(p.returncode==0 and 'orbstack' in p.stdout.lower(),'OrbStack unavailable')
        print('Engine:',p.stdout.strip(),flush=True)
        require(proc(['supabase','--version']).stdout.strip()=='2.122.0','Unreviewed CLI version')
        p=proc(['supabase','status','--workdir',str(HERE),'-o','json']);require(p.returncode==0,'Start B.3 isolated stack first')
        status=json.loads(p.stdout)
        require(status.get('API_URL')==b2.API and '@127.0.0.1:57322/' in status.get('DB_URL',''),'Wrong endpoints')
        self.anon=status.get('ANON_KEY');self.admin=status.get('SERVICE_ROLE_KEY');require(self.anon and self.admin,'Fixture keys missing')
        for name in ['supabase_db_','supabase_kong_','supabase_inbucket_']:
            p=proc([b2.DOCKER,'inspect',name+b2.PROJECT,'--format','{{json .Config}}|{{json .NetworkSettings.Ports}}'])
            require(p.returncode==0,'Missing rehearsal container')
            config,ports=p.stdout.split('|',1)
            require(json.loads(config)['Labels'].get('com.supabase.cli.project')==b2.PROJECT,'Wrong project label')
            for bindings in (json.loads(ports) or {}).values():
                require(all(x['HostIp'] in ('127.0.0.1','::1') for x in bindings or []),'Unsafe published address')
        marker=sql("SELECT coalesce(shobj_description(oid,'pg_database'),'') FROM pg_database WHERE datname=current_database()")
        require(marker in ('','default administrative connection database',b2.SENTINEL),'Wrong marker')
        require(sql("SELECT count(*) FROM auth.users WHERE email IS NULL OR email NOT LIKE '%@example.invalid'")=='0','Non-synthetic Auth data: refusing mutation')
        if marker!=b2.SENTINEL:
            require(sql("SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'cp004%'")=='0','Unmarked proof collision')
            require(sql("SELECT count(*) FROM pg_tables WHERE schemaname='public'")=='0','Unexpected public data')
            sql('COMMENT ON DATABASE postgres IS '+quote(b2.SENTINEL))
        sql("ALTER DATABASE postgres SET log_statement='none'; ALTER DATABASE postgres SET log_min_error_statement='panic'; ALTER DATABASE postgres SET log_parameter_max_length=0; ALTER DATABASE postgres SET log_parameter_max_length_on_error=0;")
        print('B.3 container, loopback ports, synthetic-only target and versions verified; credentials suppressed.',flush=True)

    def guard(self):
        return "DO $$ BEGIN IF current_database()<>'postgres' OR shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database') IS DISTINCT FROM "+quote(b2.SENTINEL)+" THEN RAISE EXCEPTION 'wrong_rehearsal_database'; END IF; END $$;"

    def blank(self):
        # This runner never drops a database, Auth users or any other stack.
        sql('BEGIN; '+self.guard()+" DROP SCHEMA IF EXISTS cp004b2 CASCADE; DROP SCHEMA IF EXISTS cp004b2_private CASCADE; DROP SCHEMA IF EXISTS cp004b3_rehearsal CASCADE; CREATE SCHEMA cp004b3_rehearsal; REVOKE ALL ON SCHEMA cp004b3_rehearsal FROM PUBLIC,anon,authenticated,service_role; CREATE TABLE cp004b3_rehearsal.applied(version text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT clock_timestamp()); REVOKE ALL ON cp004b3_rehearsal.applied FROM PUBLIC,anon,authenticated,service_role; COMMIT;")

    def applied(self):
        return json.loads(sql("SELECT coalesce(json_agg(json_build_object('version',version,'sha256',sha256) ORDER BY version),'[]') FROM cp004b3_rehearsal.applied"))

    def apply(self,index,extra=''):
        current=self.applied()
        expected=[{k:x[k] for k in ('version','sha256')} for x in self.manifest]
        require(current==expected[:len(current)],'Applied migration checksum drift')
        if index<len(current):return False
        require(index==len(current),'Out-of-order migration refused')
        row=self.manifest[index];path=HERE/row['path']
        require(hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],'Migration content changed')
        # DDL + ledger update + grants commit as one transaction per ordered slice.
        sql('BEGIN; '+self.guard()+path.read_text()+'\nRESET ROLE; '+extra+
            'INSERT INTO cp004b3_rehearsal.applied(version,sha256) VALUES('+quote(row['version'])+','+quote(row['sha256'])+'); COMMIT;')
        return True

    def reset(self):
        self.blank()
        for i in range(len(self.manifest)):self.apply(i)

    def refresh_api(self):
        code,jwks,_=local_http(b2.API+'/auth/v1/.well-known/jwks.json')
        require(code==200 and jwks.get('keys') and all(k.get('alg')=='ES256' and 'd' not in k for k in jwks['keys']),'Wrong local JWKS')
        sql('ALTER ROLE authenticator SET pgrst.jwt_secret='+quote(json.dumps(jwks))+"; ALTER ROLE authenticator SET pgrst.db_schemas='cp004b2';")
        require(proc([b2.DOCKER,'restart','supabase_rest_'+b2.PROJECT]).returncode==0,'B.3 REST restart failed')
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            try:
                code,d,_=self.rpc('a','ensure_account',{})
                if code==200 and d.get('user_id')==self.users['a']['id']:return
            except (urllib.error.URLError,TimeoutError):pass
            time.sleep(.15)
        raise RuntimeError('B.3 PostgREST schema unavailable')

    def install(self):
        self.reset();self.refresh_api()
        self.mark('guarded isolated schema; JWT principal resolves through Auth-owner current-user-only bridge')

    def reject_sql(self,body,state):
        p=proc([b2.DOCKER,'exec','-i',b2.CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],"SET log_statement='none'; SET log_min_error_statement='panic'; SET statement_timeout='10s'; "+body)
        require(p.returncode!=0 and state in p.stderr,'Expected SQL rejection missing')

    def migration_tests(self):
        self.blank()
        try:self.apply(1)
        except RuntimeError as e:require(str(e)=='Out-of-order migration refused','Wrong ordering failure')
        else:raise RuntimeError('Out-of-order migration accepted')
        require(not self.applied() and sql("SELECT count(*) FROM pg_namespace WHERE nspname='cp004b2'")=='0','Ordering refusal changed state')
        self.check('kernel-before-prerequisites refused without DDL or ledger effects')
        self.apply(0)
        # Real SQL failure AFTER kernel creation and grants, within the migration transaction.
        try:self.apply(1,"DO $$ BEGIN RAISE EXCEPTION 'injected_migration_failure'; END $$; ")
        except RuntimeError:pass
        else:raise RuntimeError('Injected migration failure did not fail')
        require(len(self.applied())==1 and sql("SELECT count(*) FROM pg_namespace WHERE nspname IN ('cp004b2','cp004b2_private')")=='0','Failed kernel left schema/grants/ledger')
        self.check('injected kernel migration failure rolls back schemas, functions, grants and ledger atomically')
        self.apply(1)
        # Rehearse genuine B.2 defaults on the isolated N-1 environment only.
        sql('BEGIN; SET LOCAL ROLE cp004b2_owner; ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC; COMMIT;')
        # Prove the discovered B.2 default-ACL weakness before hardening.
        q="BEGIN; SET LOCAL ROLE cp004b2_owner; CREATE FUNCTION cp004b2.future_canary() RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS 'SELECT true'; RESET ROLE; SELECT has_function_privilege('authenticated','cp004b2.future_canary()','EXECUTE'); ROLLBACK;"
        require(sql(q)=='t','B.2 default-execution finding not reproduced')
        self.check('B.2 future-function PUBLIC EXECUTE gap reproduced in rollback-only canary')
        # N-1 populated upgrade: create/accept, capture rows/key/receipts, then additive hardening.
        self.refresh_api();c=self.create('a');i=self.issue('a',c,'b');self.ok(self.accept('b',i))
        before=self.fingerprint()
        self.apply(2)
        require(self.fingerprint()==before and len(self.applied())==3,'Hardening altered existing membership/key/receipt data')
        require(len(self.ok(self.client('a','memberships?select=*')))==2,'Upgrade broke authenticated RLS reads')
        require(self.ok(self.client('c','spaces?select=*'))==[],'Upgrade leaked foreign scope')
        self.check('populated N-1 kernel to hardening upgrade preserves data/key/receipts and HTTP isolation')
        self.future_default_test()
        require(all(self.apply(i) is False for i in range(3)) and self.fingerprint()==before,'Repeat migration run reapplied or changed data')
        self.check('unchanged migration rerun is a no-op with durable checksummed ledger')
        sql("UPDATE cp004b3_rehearsal.applied SET sha256=repeat('0',64) WHERE version="+quote(self.manifest[0]['version']))
        try:self.apply(0)
        except RuntimeError as e:require(str(e)=='Applied migration checksum drift','Wrong drift error')
        else:raise RuntimeError('Checksum drift accepted')
        sql('UPDATE cp004b3_rehearsal.applied SET sha256='+quote(self.manifest[0]['sha256'])+' WHERE version='+quote(self.manifest[0]['version']))
        require(self.fingerprint()==before,'Drift rejection changed data')
        self.check('ledger checksum drift rejected without touching membership data')
        # Repeat fresh schema rebuild twice. Auth users are never reset.
        for _ in range(2):
            self.reset();require(len(self.applied())==3 and self.count('cp004b2.spaces')==0,'Fresh reconstruction failed')
        self.check('two fresh isolated application-schema reconstructions from three version-controlled slices')
        require(sql("SELECT extversion FROM pg_extension WHERE extname='pgcrypto'")=='1.3' and sql('SHOW server_version').startswith('17.'),'Unreviewed DB/extension version')
        self.check('PostgreSQL 17 and pgcrypto 1.3 prerequisites verified')

    def fingerprint(self):
        # Return only a digest. Never print random HMAC material or raw rows.
        parts=[]
        for table in ['cp004b2.spaces','cp004b2.memberships','cp004b2_private.accounts','cp004b2_private.invitations','cp004b2_private.receipts','cp004b2_private.keys']:
            parts.append(sql('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),\'[]\'::jsonb) FROM '+table+' t'))
        return hashlib.sha256('\n'.join(parts).encode()).hexdigest()

    def future_default_test(self):
        sql("BEGIN; SET LOCAL ROLE cp004b2_owner; CREATE FUNCTION cp004b2.future_canary() RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS 'SELECT true'; COMMIT;")
        try:
            require(sql("SELECT NOT has_function_privilege('authenticated','cp004b2.future_canary()','EXECUTE') AND NOT has_function_privilege('anon','cp004b2.future_canary()','EXECUTE')")=='t','Future function default exposed')
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                response=self.rpc('a','future_canary',{})
                if response[0]==403:break
                time.sleep(.1)
            self.denied(response)
        finally:sql('DROP FUNCTION cp004b2.future_canary();')
        self.check('hardened future definer function has no client EXECUTE: catalog false and real HTTP 403')

    def hardening_tests(self):
        self.reset()
        # Role membership in EITHER direction must block bootstrap, even NOLOGIN/NOBYPASSRLS.
        for grant in ['GRANT authenticated TO cp004b2_owner','GRANT cp004b2_owner TO authenticated']:
            sql(grant)
            try:
                self.reject_sql('BEGIN; '+(HERE/self.manifest[0]['path']).read_text()+' COMMIT;','42501')
            finally:sql(grant.replace('GRANT','REVOKE',1).replace(' TO ',' FROM '))
        self.check('bootstrap rejects inbound owner impersonation AND outbound inherited-role escalation')
        # Even a privileged fixture cannot make a normal client bypass the narrow helper.
        funcs=json.loads(sql("SELECT json_agg(json_build_object('name',n.nspname||'.'||p.proname,'owner',r.rolname,'definer',p.prosecdef,'config',p.proconfig) ORDER BY n.nspname,p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner WHERE n.nspname IN ('cp004b2','cp004b2_private')"))
        elevated=[f for f in funcs if f['definer']]
        require(len(elevated)==9 and all('search_path=""' in f['config'] for f in elevated),'Definer inventory mismatch')
        require(sum(f['owner']=='supabase_auth_admin' for f in elevated)==1 and all(f['owner'] in ('cp004b2_owner','supabase_auth_admin') for f in elevated),'Unexpected definer owner')
        require(sql("SELECT NOT has_schema_privilege('supabase_auth_admin','cp004b2_private','CREATE') AND NOT has_schema_privilege('authenticated','cp004b3_rehearsal','USAGE') AND NOT has_table_privilege('cp004b2_owner','auth.users','SELECT')")=='t','Ownership boundary escaped')
        self.check('all nine elevated functions inventoried: eight app-owner, one current-user Auth-owner bridge; safe paths and grants')
        surface=json.loads(sql("SELECT json_agg(p.proname ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b2','cp004b2_private') AND has_function_privilege('authenticated',p.oid,'EXECUTE')"))
        require(surface==sorted(['can_read','ensure_account','account_context','create_space','issue_invitation','accept_invitation','revoke_invitation','leave_space']),'Unexpected executable surface')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b2','cp004b2_private') AND has_function_privilege('anon',p.oid,'EXECUTE')")=='0','Anon function surface')
        self.check('exact eight authenticated RPC/helper grants; zero anonymous function EXECUTE including invoker helpers')
        self.refresh_api();c=self.create('a');i=self.issue('a',c,'b')
        # Loss and replacement: original issuance response is deliberately discarded by caller.
        op=str(uuid.uuid4());lost=self.issue('a',c,'b',op);retry=self.issue('a',c,'b',op)
        require('token' not in retry and retry['invitation_id']==lost['invitation_id'],'Lost-response recovery disclosed secret')
        replacement=self.issue('a',c,'b')
        self.denied(self.accept('b',i),generic=True);self.denied(self.accept('b',lost),generic=True)
        self.ok(self.accept('b',replacement))
        self.check('lost issuance response returns metadata only; explicit replacement invalidates every old pending token')
        self.reset();c=self.create('a')
        for _ in range(12):self.issue('a',c,'b')
        require(self.count('cp004b2_private.invitations')==12 and self.count('cp004b2_private.invitations',"state='pending'")==1,'Burst behavior changed')
        self.check('abuse limitation reproduced: twelve fresh issue operations succeed; one pending token but no command rate quota')
        i=self.issue('a',c,'b');self.ok(self.accept('b',i))
        # Ban denies commands but DOES NOT invalidate already-issued JWT reads in this prototype.
        sql("UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id="+quote(self.users['a']['id']))
        try:
            self.denied(self.rpc('a','account_context',{}),generic=True)
            require(len(self.ok(self.client('a','spaces?select=*')))==1,'Ban/read limitation unexpectedly changed')
            sql('UPDATE cp004b2_private.accounts SET enabled=false WHERE user_id='+quote(self.users['a']['id']))
            require(self.ok(self.client('a','spaces?select=*'))==[],'Live disable failed')
        finally:sql('UPDATE auth.users SET banned_until=NULL WHERE id='+quote(self.users['a']['id']))
        self.check('explicit session limitation reproduced: ban denies commands; live account gate required for immediate JWT read denial')

    def run(self):
        self.preflight();self.identities();self.install();self.migration_tests();self.hardening_tests()
        # Exact inherited assertions run against B.3 hardened migrations, never edited/disabled.
        self.reset();self.basic();self.lifecycle();self.concurrency();self.additional_boundaries();self.catalog_and_constraints();self.logging_and_hashes()
        print('RESULT:',len(self.passed),'unchanged B.2 Auth/HTTP scenarios +',len(self.rehearsal),'B.3 rehearsal scenarios passed; zero mocks/skips.',flush=True)
        print('Local-only B.3 proof; no automatic B.3 commit, push or Flutter changes.',flush=True)


if __name__=='__main__':
    try:Rehearsal().run()
    except Exception as exc:
        print('FAIL:',str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__+' (sensitive details suppressed)',file=sys.stderr);sys.exit(1)
