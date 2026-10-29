#!/usr/bin/env python3
"""Isolated B.4 operational proof. Uses genuine local Auth and unchanged B.2 assertions."""
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('checkpointed_b3',HERE.parent/'cp004b3-rehearsal/run_tests.py')
b3=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(b3)
b3.HERE=HERE;b2=b3.b2
b2.HERE=HERE;b2.PROJECT='twogethera-b4';b2.CONTAINER='supabase_db_'+b2.PROJECT
b2.SENTINEL='twogethera:cp004b4:disposable:v1';b2.API='http://127.0.0.1:58321';b2.MAIL='http://127.0.0.1:58324'
require=b2.require;quote=b2.quote;sql=b2.sql;proc=b2.proc


def local_http(url,method='GET',body=None,headers=None):
    parsed=urllib.parse.urlsplit(url)
    require(parsed.scheme=='http' and parsed.hostname=='127.0.0.1' and parsed.port in (58321,58324),'Nonlocal B.4 request refused')
    request=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type':'application/json',**(headers or {})},method=method)
    try:response=b2.HTTP.open(request,timeout=12)
    except urllib.error.HTTPError as e:response=e
    data=response.read()
    try:decoded=json.loads(data) if data else None
    except (json.JSONDecodeError,UnicodeDecodeError):decoded=data.decode(errors='replace')
    return response.code,decoded,dict(response.headers)

b3.local_http=local_http;b2.http=local_http


class Operations(b3.Rehearsal):
    def __init__(self):
        b2.Proof.__init__(self);self.operational=[];self.sensitive_tokens=[]
        require(hashlib.sha256((HERE.parent/'cp004b2-membership/run_tests.py').read_bytes()).hexdigest()=='868aab51610c5bcabfc091ec963b21cf02b138734b61543b8f3ddf0ea939348d','Checkpointed regression source changed')
        require(hashlib.sha256((HERE.parent/'cp004b3-rehearsal/run_tests.py').read_bytes()).hexdigest()=='c139caa991f4a1724afae0302e053cf86ec335b42b7ddc4eecb592b63d1f2e68','Checkpointed regression source changed')
        self.manifest=json.loads((HERE/'migrations.json').read_text())
        require(len(self.manifest)==4 and [r['version'] for r in self.manifest]==sorted(r['version'] for r in self.manifest),'Invalid B.4 manifest')
        for r in self.manifest:
            path=(HERE/r['path']).resolve()
            require(path.is_relative_to(HERE) and hashlib.sha256(path.read_bytes()).hexdigest()==r['sha256'],'Migration checksum mismatch')

    def check(self,name):
        self.operational.append(name);print('OPERATIONAL PASS:',name,flush=True)
    def preflight(self):
        require(__debug__ and not os.environ.get('PYTHONOPTIMIZE'),'Optimized Python refused')
        require(not b2.ENV.get('DOCKER_HOST') or b2.ENV['DOCKER_HOST'].startswith('unix://'),'Remote Docker refused')
        p=proc([b2.DOCKER,'context','inspect','--format','{{.Endpoints.docker.Host}}'])
        require(p.returncode==0 and p.stdout.strip().startswith('unix://'),'Local Docker required')
        p=proc([b2.DOCKER,'info','--format','{{.Name}} | {{.ServerVersion}}'])
        require(p.returncode==0 and 'orbstack' in p.stdout.lower(),'OrbStack unavailable')
        print('Engine:',p.stdout.strip(),flush=True)
        require(proc(['supabase','--version']).stdout.strip()=='2.122.0','Unreviewed CLI version')
        p=proc(['supabase','status','--workdir',str(HERE),'-o','json']);require(p.returncode==0,'Start B.4 isolated stack first')
        status=json.loads(p.stdout)
        require(status.get('API_URL')==b2.API and '@127.0.0.1:58322/' in status.get('DB_URL',''),'Wrong endpoints')
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
        print('B.4 container, loopback ports, synthetic-only target and versions verified; credentials suppressed.',flush=True)

    def signin(self,name):
        if self.users[name].get('token'):self.sensitive_tokens.append(self.users[name]['token'])
        b2.Proof.signin(self,name);self.sensitive_tokens.append(self.users[name]['token'])

    def audit_logs(self):
        for name in ['supabase_db_','supabase_rest_','supabase_kong_','supabase_auth_']:
            p=proc([b2.DOCKER,'logs',name+b2.PROJECT]);require(p.returncode==0,'Local log scan unavailable')
            logs=p.stdout+p.stderr
            require(all(value not in logs for value in self.raw_tokens+self.sensitive_tokens+[self.admin]+[u['password'] for u in self.users.values()]),'Sensitive test value leaked into logs')

    def blank(self):
        sql('BEGIN; '+self.guard()+" DROP SCHEMA IF EXISTS cp004b4_ops CASCADE; DROP SCHEMA IF EXISTS cp004b2 CASCADE; DROP SCHEMA IF EXISTS cp004b2_private CASCADE; DROP SCHEMA IF EXISTS cp004b3_rehearsal CASCADE; CREATE SCHEMA cp004b3_rehearsal; REVOKE ALL ON SCHEMA cp004b3_rehearsal FROM PUBLIC,anon,authenticated,service_role; CREATE TABLE cp004b3_rehearsal.applied(version text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT clock_timestamp()); REVOKE ALL ON cp004b3_rehearsal.applied FROM PUBLIC,anon,authenticated,service_role; COMMIT;")

    def maintenance(self,expression):
        return sql('BEGIN; SET LOCAL ROLE cp004b4_maintainer; SELECT '+expression+'; RESET ROLE; COMMIT;')

    def enabled(self,n,value):
        return self.maintenance('cp004b4_ops.set_account_enabled('+quote(self.users[n]['id'])+','+('true' if value else 'false')+')')

    def issue_request(self,n,c,target,op=None):
        return self.rpc(n,'issue_invitation',{'p_operation_id':op or str(uuid.uuid4()),'p_space':c,'p_expected_epoch':1,'p_email':self.users[target]['email']})

    def account_tests(self):
        self.reset();c=self.create('a');i=self.issue('a',c,'b');self.ok(self.accept('b',i))
        old=self.users['a']['token'];require(self.users['a']['exp']>time.time()+30,'JWT too close to expiry')
        require(len(self.ok(self.client('a','spaces?select=*',token=old)))==1,'Normal read failed')
        self.enabled('a',False)
        require(self.ok(self.client('a','spaces?select=*',token=old))==[],'Disabled read leaked')
        require(self.ok(self.client('a','memberships?select=*',token=old))==[],'Disabled membership read leaked')
        for command,body in [('account_context',{}),('ensure_account',{}),('create_space',{'p_operation_id':str(uuid.uuid4())}),
          ('leave_space',{'p_space':c,'p_expected_epoch':2}),('issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':2,'p_email':self.users['c']['email']})]:
            self.denied(self.rpc('a',command,body),generic=True)
        self.denied(self.client('a','memberships?couple_id=eq.'+c,'PATCH',{'active':True}))
        require(self.users['a']['token']==old and len(self.ok(self.client('b','spaces?select=*')))==1,'Active partner affected or token changed')
        self.check('maintenance suspension immediately filters reads and denies commands with same still-valid JWT; active partner unaffected')
        for command,body in [('set_account_enabled',{'p_user':self.users['a']['id'],'p_enabled':True}),('compact_receipts',{})]:
            self.denied(self.rpc('a',command,body),404)
        require(sql('SELECT NOT enabled FROM cp004b2_private.accounts WHERE user_id='+quote(self.users['a']['id']))=='t','Client reactivated account')
        self.enabled('a',True)
        require(len(self.ok(self.client('a','spaces?select=*',token=old)))==1,'Explicit authorized restore failed')
        self.check('no client self-restoration or maintenance RPC; explicitly authorized maintainer restores application gate only')
        self.reset();c=self.create('a');i=self.issue('a',c,'b');self.ok(self.rpc('b','ensure_account',{}))
        self.enabled('b',False);self.denied(self.accept('b',i),generic=True)
        self.enabled('b',True);self.enabled('a',False);self.denied(self.accept('b',i),generic=True)
        require(self.count('cp004b2.memberships')==1,'Disabled invite operation changed membership')
        self.enabled('a',True);self.ok(self.accept('b',i))
        self.check('disabled recipient and disabled issuer block invitation acceptance without partial effects; authorized restoration permits acceptance')

    def quota_tests(self):
        self.reset();c=self.create('a');op=str(uuid.uuid4());first=self.issue('a',c,'b',op)
        for _ in range(3):require(self.issue('a',c,'b',op)=={k:v for k,v in first.items() if k!='token'},'Duplicate changed issue result')
        require(sql('SELECT sum(used) FROM cp004b4_ops.issue_budgets')=='1','Duplicates consumed quota')
        self.check('durable issue retries return same metadata and consume one quota unit')
        latest=first
        for _ in range(4):latest=self.issue('a',c,'b')
        before=self.fingerprint();self.denied(self.issue_request('a',c,'b'),429,generic=True)
        require(self.fingerprint()==before and self.count('cp004b2_private.invitations',"state='pending'")==1,'Quota rejection changed invitation/receipt state')
        self.ok(self.accept('b',latest))
        self.check('five fresh issuances/replacements allowed; sixth generic 429 rolls back replacement and preserves prior usable token')
        self.reset();c=self.create('a');op=str(uuid.uuid4())
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        results=self.race(lock,[lambda:self.issue_request('a',c,'b',op) for _ in range(2)])
        bodies=[self.ok(r) for r in results]
        for body in bodies:
            if 'token' in body:self.raw_tokens.append(body['token'])
        require(sum('token' in r for r in bodies)==1 and sql('SELECT sum(used) FROM cp004b4_ops.issue_budgets')=='1','Concurrent retry double-charged')
        self.check('concurrent same-operation issuance charges once with one raw-token response')
        self.reset();c=self.create('a')
        for _ in range(4):self.issue('a',c,'b')
        results=self.race('SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE',[lambda:self.issue_request('a',c,'b') for _ in range(2)])
        require(sorted(r[0] for r in results)==[200,429] and sql('SELECT sum(used) FROM cp004b4_ops.issue_budgets')=='5','Concurrent fresh quota bypass')
        for r in results:
            if r[0]==200:self.raw_tokens.append(r[1]['token'])
            else:self.denied(r,429,generic=True)
        require(self.count('cp004b2_private.invitations')==5 and self.count('cp004b2_private.invitations',"state='pending'")==1,'Capacity/history mismatch')
        self.check('concurrent new operations at quota boundary: one 200/one 429, five charges, one pending invitation')
        # New scope cannot reset an actor-wide quota within the same bucket.
        self.ok(self.leave('a',c,1));d=self.create('a');self.denied(self.issue_request('a',d,'b'),429,generic=True)
        e=self.create('c');self.issue('c',e,'d')
        self.check('closing/recreating draft does not bypass account quota; unrelated issuer budget unaffected')

        self.reset();c=self.create('a')
        for _ in range(5):self.issue('a',c,'b')
        sql('UPDATE cp004b4_ops.issue_budgets SET bucket=bucket-1')
        self.issue('a',c,'b')
        require(sql('SELECT sum(used) FROM cp004b4_ops.issue_budgets')=='6' and self.count('cp004b4_ops.issue_budgets')==2,'Window rollover accounting failed')
        self.check('server UTC bucket rollover grants a fresh bounded budget; prior bucket history retained')

    def receipt_tests(self):
        self.reset();op=str(uuid.uuid4());c=self.create('a',op);iop=str(uuid.uuid4());i=self.issue('a',c,'b',iop)
        # Fresh receipts cannot be compacted, even by authorized maintenance.
        require(self.maintenance('cp004b4_ops.compact_receipts(100)')=='0','Fresh receipts removed')
        self.check('cleanup preserves unexpired receipt results')
        sql("UPDATE cp004b2_private.receipts SET expires_at=clock_timestamp()-interval '1 second' WHERE actor="+quote(self.users['a']['id']))
        # Real actor lock represents an in-flight command; cleanup must skip it.
        p=subprocess.Popen([b2.DOCKER,'exec','-i',b2.CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1','-U','supabase_admin','-d','postgres'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=b2.ENV)
        try:
            p.stdin.write("SET log_statement='none'; BEGIN;\\o /dev/null\nSELECT 1 FROM cp004b2_private.accounts WHERE user_id="+quote(self.users['a']['id'])+" FOR UPDATE;\n\\o\n\\echo LOCKED\n");p.stdin.flush()
            require(bool(select.select([p.stdout],[],[],5)[0]) and p.stdout.readline().strip()=='LOCKED','Cleanup lock barrier failed')
            require(self.maintenance('cp004b4_ops.compact_receipts(100)')=='0','Cleanup touched actor with in-flight lock')
            require(self.count('cp004b2_private.receipts','retired')==0,'Active receipt compacted')
        finally:
            p.stdin.write('ROLLBACK;\n\\q\n');p.stdin.flush();p.communicate(timeout=5)
        self.check('cleanup skips actor account row held by in-flight operation')
        require(self.maintenance('cp004b4_ops.compact_receipts(100)')=='2' and self.maintenance('cp004b4_ops.compact_receipts(100)')=='0','Cleanup not repeatable')
        require(self.count('cp004b2_private.receipts',"retired AND result='{}'::jsonb")==2,'Payload compaction incomplete')
        self.denied(self.rpc('a','create_space',{'p_operation_id':op}),409)
        self.denied(self.issue_request('a',c,'b',iop),409)
        self.ok(self.leave('a',c,1));self.denied(self.rpc('a','create_space',{'p_operation_id':op}),409)
        require(self.count('cp004b2.spaces')==1 and self.count('cp004b2_private.invitations')==1,'Spent ID produced duplicate effect')
        self.check('expired results compact once; spent operation IDs cannot recreate space or invitation after closure')
        self.reset();c=self.create('a');i=self.issue('a',c,'b');op=str(uuid.uuid4());self.ok(self.accept('b',i,op))
        sql("UPDATE cp004b2_private.receipts SET expires_at=clock_timestamp()-interval '1 second' WHERE actor="+quote(self.users['b']['id']))
        # Replay expiry is enforced even before the cleanup job runs.
        self.denied(self.accept('b',i,op),409);self.maintenance('cp004b4_ops.compact_receipts(100)')
        self.denied(self.accept('b',i,op),409);require(self.count('cp004b2.memberships')==2,'Expired accept duplicated membership')
        self.check('expired acceptance receipt cannot replay before or after cleanup; membership remains exactly two')

        lock='SELECT 1 FROM cp004b2_private.accounts WHERE user_id='+quote(self.users['b']['id'])+' FOR UPDATE'
        results=self.race(lock,[lambda:self.accept('b',i,op) for _ in range(2)])
        require(all(r[0]==409 for r in results) and self.count('cp004b2.memberships')==2,'Expired concurrent retry duplicated membership')
        self.check('two observed concurrent retries after receipt retirement both deny without duplicate membership')

    def privilege_tests(self):
        self.reset();self.refresh_api()
        require(sql("SELECT NOT has_any_column_privilege('cp004b2_owner','auth.users','SELECT') AND NOT has_table_privilege('cp004b4_maintainer','auth.users','SELECT')")=='t','Auth read leaked')
        require(sql("SELECT NOT has_function_privilege('authenticated','cp004b2_private.current_email(boolean)','EXECUTE') AND NOT has_schema_privilege('authenticated','cp004b4_ops','USAGE')")=='t','Private operation escaped')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b2','cp004b2_private','cp004b4_ops') AND p.prosecdef AND NOT ('search_path=\"\"'=ANY(p.proconfig))")=='0','Unsafe definer search path')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE n.nspname IN ('cp004b2','cp004b2_private','cp004b4_ops') AND x.grantee=0 AND x.privilege_type='EXECUTE'")=='0','PUBLIC EXECUTE leaked')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b2','cp004b2_private','cp004b4_ops') AND p.prosecdef")=='12','Unexpected elevated function inventory')
        require(sql("SELECT has_function_privilege('cp004b4_maintainer','cp004b4_ops.set_account_enabled(uuid,boolean)','EXECUTE') AND has_function_privilege('cp004b4_maintainer','cp004b4_ops.compact_receipts(integer)','EXECUTE') AND NOT has_function_privilege('cp004b4_maintainer','cp004b4_ops.issue_core(uuid,uuid,bigint,text)','EXECUTE')")=='t','Maintainer function boundary escaped')
        require(sql("SELECT NOT has_table_privilege('cp004b4_maintainer','cp004b4_ops.issue_budgets','UPDATE') AND NOT has_table_privilege('cp004b4_maintainer','cp004b2.memberships','UPDATE')")=='t','Maintainer table writes escaped')
        for fn,body in [('current_email',{'p_lock':False}),('issue_core',{}),('set_account_enabled',{'p_user':self.users['b']['id'],'p_enabled':True})]:self.denied(self.rpc('a',fn,body),404)
        self.denied(self.rpc('a','account_context',{'user_id':self.users['b']['id']}),404)
        self.check('Auth-owner helper remains current-user-only and private; maintenance/core functions, email columns and forged actor parameters inaccessible')

    def signing_tests(self):
        import base64
        self.reset();self.refresh_api();c=self.create('a');self.signin('a')
        token=self.users['a']['token'];claims=token.split('.')[1]
        expiry=json.loads(base64.urlsafe_b64decode(claims+'='*(-len(claims)%4)))['exp']
        code,current,_=local_http(b2.API+'/auth/v1/.well-known/jwks.json')
        require(code==200 and current.get('keys'),'Current Auth JWKS unavailable')
        p=proc(['supabase','gen','signing-key','--algorithm','ES256'])
        require(p.returncode==0,'Official CLI key generation unavailable')
        new=json.loads(p.stdout)
        if isinstance(new,list):new=new[0]
        if isinstance(new,dict) and 'keys' in new:new=new['keys'][0]
        require(new.get('alg')=='ES256' and new.get('d'),'Expected CLI-generated private ES256 JWK')
        public={k:v for k,v in new.items() if k in ('kty','crv','x','y','kid','alg','use','key_ops')}
        # New private material stays in memory only; no JWT is minted/forged with it.
        public.pop('key_ops',None)
        def trust(jwks):
            require(all('d' not in k for k in jwks['keys']),'Private key in verifier config')
            sql('ALTER ROLE authenticator SET pgrst.jwt_secret='+quote(json.dumps(jwks))+"; NOTIFY pgrst,'reload config';")
        def await_code(expected):
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                response=self.client('a','spaces?select=*',token=token)
                if response[0]==expected:return response
                time.sleep(.1)
            raise RuntimeError('Verifier trust update did not reach expected HTTP status')
        try:
            trust({'keys':current['keys']+[public]})
            require(len(self.ok(await_code(200)))==1,'Overlap lost original Auth token')
            self.check('official CLI generates ES256 material; public-only overlapping verifier trust retains genuine current Auth JWT')
            trust({'keys':[public]});self.denied(await_code(401),401)
            require(expiry>time.time(),'Token expired instead of losing verifier trust')
            self.check('removing original key from actual PostgREST trust rejects the same still-unexpired genuine JWT with HTTP 401')
            trust(current);require(len(self.ok(await_code(200)))==1,'Original trust restoration failed')
            self.enabled('a',False)
            require(self.ok(self.client('a','spaces?select=*',token=token))==[],'Restoring key trust bypassed account suspension')
            self.enabled('a',True)
            require(len(self.ok(self.client('a','spaces?select=*',token=token)))==1,'Authorized account restoration failed')
            self.check('restored verifier trust reaccepts same JWT while live account suspension independently filters reads')
        finally:trust(current)
        print('UNVERIFIED: full Auth signer rollover/managed overlap; local multi-key restart experiment failed and was restored. Verifier tests above are not Auth rotation certification.',flush=True)

    def run(self):
        self.preflight();self.identities();self.install()
        self.basic();self.lifecycle();self.concurrency();self.additional_boundaries();self.catalog_and_constraints();self.logging_and_hashes()
        self.account_tests();self.quota_tests();self.receipt_tests();self.privilege_tests();self.signing_tests();self.audit_logs()
        self.check('tested raw invitation tokens, user JWTs, passwords and admin key absent from inspected logs at final verification')
        print('RESULT:',len(self.passed),'unchanged B.2 scenarios +',len(self.operational),'B.4 operational scenarios passed; zero mocks/skips.',flush=True)


if __name__=='__main__':
    try:Operations().run()
    except Exception as exc:
        print('FAIL:',str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__+' (sensitive details suppressed)',file=sys.stderr);sys.exit(1)
