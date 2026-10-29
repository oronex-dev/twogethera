#!/usr/bin/env python3
"""CP-004B.2 real local Auth -> JWT -> HTTP/PostgREST -> auth.uid -> RLS.
No third-party dependencies, hand-signed JWTs, client role impersonation or cloud URLs.
Fixture administration and client authorization requests are deliberately separated.
"""
import concurrent.futures
import base64
import html
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE = Path(__file__).resolve().parent
PROJECT = 'twogethera-b2'
SENTINEL = 'twogethera:cp004b2:disposable:v1'
CONTAINER = 'supabase_db_' + PROJECT
API = 'http://127.0.0.1:56321'
MAIL = 'http://127.0.0.1:56324'
DOCKER = shutil.which('docker') or '/Applications/OrbStack.app/Contents/MacOS/xbin/docker'
ENV = dict(os.environ, PATH=str(Path(DOCKER).parent)+':'+os.environ.get('PATH',''))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def proc(args, text=None):
    return subprocess.run(args,input=text,capture_output=True,text=True,env=ENV,timeout=40)


def quote(x):
    return "'"+str(x).replace("'","''")+"'"


def sql(text):
    # Trusted fixture/inspection only; never used to impersonate a client principal.
    p=proc([DOCKER,'exec','-i',CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1',
            '-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],
           "SET log_statement='none'; SET log_min_error_statement='panic'; "
           "SET statement_timeout='10s'; "+text)
    require(p.returncode==0,'Fixture/catalog SQL failed (SQL and credentials suppressed)')
    return p.stdout.strip()


def http(url, method='GET', body=None, headers=None):
    parsed=urllib.parse.urlsplit(url)
    require(parsed.scheme=='http' and parsed.hostname=='127.0.0.1' and parsed.port in (56321,56324),
            'Refusing a nonlocal HTTP target')
    payload=json.dumps(body).encode() if body is not None else None
    h={'Content-Type':'application/json',**(headers or {})}
    request=urllib.request.Request(url,data=payload,headers=h,method=method)
    try:
        response=HTTP.open(request,timeout=12)
    except urllib.error.HTTPError as e:
        response=e
    data=response.read()
    try:
        decoded=json.loads(data) if data else None
    except (json.JSONDecodeError,UnicodeDecodeError):
        decoded=data.decode(errors='replace')
    return response.code,decoded,dict(response.headers)


class Proof:
    def __init__(self):
        self.users={};self.passed=[];self.negative_bodies=[]
        self.run_id=secrets.token_hex(8)

    def preflight(self):
        require(__debug__ and not os.environ.get('PYTHONOPTIMIZE'),'Optimized assertion-disabled execution refused')
        require(not ENV.get('DOCKER_HOST') or ENV['DOCKER_HOST'].startswith('unix://'),'Remote Docker override refused')
        p=proc([DOCKER,'context','inspect','--format','{{.Endpoints.docker.Host}}'])
        require(p.returncode==0 and p.stdout.strip().startswith('unix://'),'Local Docker context required')
        p=proc([DOCKER,'info','--format','{{.Name}} | {{.ServerVersion}}'])
        require(p.returncode==0 and 'orbstack' in p.stdout.lower(),'OrbStack unavailable')
        print('Engine:',p.stdout.strip(),flush=True)
        p=proc(['supabase','status','--workdir',str(HERE),'-o','json'])
        require(p.returncode==0,'Isolated Supabase unavailable; start the documented project first')
        status=json.loads(p.stdout)
        require(status.get('API_URL')==API and '@127.0.0.1:56322/' in status.get('DB_URL',''),'Unexpected proof endpoints')
        self.anon=status.get('ANON_KEY');self.admin=status.get('SERVICE_ROLE_KEY')
        require(bool(self.anon and self.admin),'Local fixture/client keys unavailable (values suppressed)')
        p=proc([DOCKER,'inspect',CONTAINER,'--format','{{json .Config.Labels}}'])
        require(p.returncode==0 and json.loads(p.stdout).get('com.supabase.cli.project')==PROJECT,'Wrong database container')
        # Refuse wildcard/LAN publications before synthetic accounts or schema writes.
        for name in ['supabase_db_','supabase_kong_','supabase_inbucket_']:
            p=proc([DOCKER,'inspect',name+PROJECT,'--format','{{json .NetworkSettings.Ports}}'])
            require(p.returncode==0,'Expected isolated container missing')
            for bindings in (json.loads(p.stdout) or {}).values():
                for binding in bindings or []:
                    require(binding['HostIp'] in ('127.0.0.1','::1'),'Non-loopback port publication refused')
        print('Local project/endpoints/port bindings verified; credentials suppressed.',flush=True)

    def fixture_auth(self,path,body,method='POST'):
        require(path.startswith('/admin/users'),'Fixture admin call outside Auth-user setup refused')
        return http(API+'/auth/v1'+path,method,body,{'apikey':self.anon,'Authorization':'Bearer '+self.admin})

    def client(self,name,path,method='GET',body=None,token=None):
        h={'apikey':self.anon,'Accept-Profile':'cp004b2','Content-Profile':'cp004b2',
           'Prefer':'return=representation'}
        t=token if token is not None else (self.users[name]['token'] if name else None)
        if t:
            require(t!=self.admin and t!=self.anon,'Privileged/API-key token contaminated client request')
            h['Authorization']='Bearer '+t
        return http(API+'/rest/v1/'+path,method,body,h)

    def signin(self,name):
        u=self.users[name]
        code,data,_=http(API+'/auth/v1/token?grant_type=password','POST',
                         {'email':u['email'],'password':u['password']},{'apikey':self.anon})
        require(code==200 and isinstance(data,dict) and bool(data.get('access_token')),'Real password sign-in failed')
        require(data['user']['id']==u['id'] and bool(data['user'].get('email_confirmed_at')),'User was not genuinely verified')
        token=data['access_token'];part=token.split('.')[1];claims=json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
        require(claims['sub']==u['id'] and claims['role']=='authenticated' and json.loads(base64.urlsafe_b64decode(token.split('.')[0]+'='*(-len(token.split('.')[0])%4)))['alg']=='ES256','Wrong actual user JWT claims')
        # Decoding above is inspection only; acceptance is proven by real HTTP below.
        u['token']=token;u['exp']=claims['exp']

    def mark(self,name):
        self.passed.append(name); print('PASS:',name,flush=True)

    def identities(self):
        self.raw_tokens=[]
        for name in 'abcdefgh':
            email='b2-'+self.run_id+'-'+name+'@example.invalid'; password=secrets.token_urlsafe(30)
            code,data,_=self.fixture_auth('/admin/users',{'email':email,'password':password,'email_confirm':True})
            require(code==200 and bool(data.get('id')),'Synthetic Auth setup failed')
            self.users[name]={'id':data['id'],'email':email,'password':password}; self.signin(name)
        self.mark('eight distinct verified synthetic Auth identities; actual ES256 password-grant JWTs')

    def install(self):
        marker=sql("SELECT coalesce(shobj_description(oid,'pg_database'),'') FROM pg_database WHERE datname=current_database()")
        require(marker in ('','default administrative connection database',SENTINEL),'Wrong disposable marker')
        if marker!=SENTINEL:
            require(sql("SELECT count(*) FROM pg_namespace WHERE nspname IN ('cp004b2','cp004b2_private')")=='0','Unmarked schema collision')
            sql('COMMENT ON DATABASE postgres IS '+quote(SENTINEL))
        if sql("SELECT count(*) FROM pg_roles WHERE rolname='cp004b2_owner'")=='0':
            sql('CREATE ROLE cp004b2_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE; COMMENT ON ROLE cp004b2_owner IS '+quote(SENTINEL))
        require(sql("SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND shobj_description(oid,'pg_authid')="+quote(SENTINEL)+" FROM pg_roles WHERE rolname='cp004b2_owner'")=='t','Unsafe owner role')
        require(sql("SELECT count(*) FROM pg_auth_members WHERE roleid=(SELECT oid FROM pg_roles WHERE rolname='cp004b2_owner')")=='0','Assumable owner')
        # Disable parameter/statement error logging before any invitation request.
        # Only this guarded disposable database is affected. Restart its REST pool.
        sql("ALTER DATABASE postgres SET log_statement='none'; ALTER DATABASE postgres SET log_min_error_statement='panic'; ALTER DATABASE postgres SET log_parameter_max_length=0; ALTER DATABASE postgres SET log_parameter_max_length_on_error=0;")
        sql('CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions; GRANT USAGE ON SCHEMA extensions,auth TO cp004b2_owner; REVOKE ALL ON auth.users FROM cp004b2_owner; GRANT REFERENCES(id) ON auth.users TO cp004b2_owner;')
        self.reset()
        code,jwks,_=http(API+'/auth/v1/.well-known/jwks.json')
        require(code==200 and jwks.get('keys') and all(k.get('alg')=='ES256' and 'd' not in k for k in jwks['keys']),'Wrong public JWKS')
        sql('ALTER ROLE authenticator SET pgrst.jwt_secret='+quote(json.dumps(jwks))+"; ALTER ROLE authenticator SET pgrst.db_schemas='cp004b2';")
        require(proc([DOCKER,'restart','supabase_rest_'+PROJECT]).returncode==0,'REST pool restart failed')
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            try:
                code,data,_=self.rpc('a','ensure_account',{})
                if code==200 and data.get('user_id')==self.users['a']['id']:break
            except (urllib.error.URLError,TimeoutError):pass
            time.sleep(.2)
        else:raise RuntimeError('HTTP schema/identity bootstrap unavailable')
        self.mark('guarded isolated schema; JWT principal resolves through Auth-owner current-user-only bridge')

    def reset(self):
        sql("BEGIN; DO $$ BEGIN IF current_database()<>'postgres' OR shobj_description((SELECT oid FROM pg_database WHERE datname=current_database()),'pg_database') IS DISTINCT FROM "+quote(SENTINEL)+" THEN RAISE EXCEPTION 'wrong_proof_database'; END IF; END $$; DROP SCHEMA IF EXISTS cp004b2 CASCADE; DROP SCHEMA IF EXISTS cp004b2_private CASCADE; COMMIT;")
        sql((HERE/'supabase/migrations/20261029000200_commands.sql').read_text())

    def rpc(self,n,command,body):
        return self.client(n,'rpc/'+command,'POST',body)

    def ok(self,response):
        code,data,_=response
        require(code==200,'Expected HTTP 200; received '+str(code)+' / '+str(data.get('code') if isinstance(data,dict) else type(data).__name__))
        return data

    def denied(self,response,status=403,generic=False):
        code,data,_=response
        require(code==status,'Expected HTTP '+str(status)+'; received '+str(code)+' / '+str(data.get('code') if isinstance(data,dict) else type(data).__name__))
        require(isinstance(data,dict),'Missing explicit error envelope')
        if generic:
            require(data.get('message')=='unavailable' and data.get('details') is None and data.get('hint') is None,'Non-generic sensitive error')
        dumped=json.dumps(data)
        for secret in self.raw_tokens+[u['password'] for u in self.users.values()]+[self.admin]:
            require(secret not in dumped,'Secret leaked in error response')
        self.negative_bodies.append(data)

    def create(self,n,op=None):
        return self.ok(self.rpc(n,'create_space',{'p_operation_id':op or str(uuid.uuid4())}))['space_id']

    def issue(self,n,c,target,op=None,epoch=1):
        email=self.users[target]['email'] if target in self.users else target
        d=self.ok(self.rpc(n,'issue_invitation',{'p_operation_id':op or str(uuid.uuid4()),'p_space':c,'p_expected_epoch':epoch,'p_email':email}))
        if 'token' in d:self.raw_tokens.append(d['token'])
        return d

    def accept(self,n,invite,op=None):
        return self.rpc(n,'accept_invitation',{'p_operation_id':op or str(uuid.uuid4()),'p_token':invite['token']})

    def revoke(self,n,invite,op=None):
        return self.rpc(n,'revoke_invitation',{'p_operation_id':op or str(uuid.uuid4()),'p_invitation':invite['invitation_id']})

    def leave(self,n,c,epoch=2):
        return self.rpc(n,'leave_space',{'p_space':c,'p_expected_epoch':epoch})

    def count(self,table,where='true'):
        return int(sql('SELECT count(*) FROM '+table+' WHERE '+where))

    def basic(self):
        for n in 'abcdefgh':
            d=self.ok(self.rpc(n,'ensure_account',{}));require(d=={'user_id':self.users[n]['id']},'Incorrect signed identity')
            require(self.ok(self.rpc(n,'account_context',{}))=={'user_id':self.users[n]['id'],'spaces':[]},'Context must be actor-scoped')
        self.mark('account ensure/context use eight real JWT principals; no caller-supplied member IDs')
        response=self.rpc(None,'create_space',{'p_operation_id':str(uuid.uuid4())})
        self.denied(response,status=401 if response[0]==401 else 403)
        require(self.count('cp004b2.spaces')==0,'Anonymous side effect')
        self.mark('anonymous space creation denied without side effects')
        op=str(uuid.uuid4());c=self.create('a',op)
        require(self.create('a',op)==c and self.count('cp004b2.spaces')==1,'Create replay duplicated')
        self.denied(self.rpc('a','create_space',{'p_operation_id':str(uuid.uuid4())}),409)
        d=self.ok(self.rpc('a','account_context',{}))
        require(d['spaces']==[{'space_id':c,'state':'draft','epoch':1}],'Draft context mismatch')
        self.mark('draft creation and durable replay; second active space rejected')
        iop=str(uuid.uuid4());i=self.issue('a',c,'b',iop)
        require(re.fullmatch('[0-9a-f]{64}',i['token']) is not None,'Token entropy encoding mismatch')
        from datetime import datetime
        ttl=(datetime.fromisoformat(i['expires_at'])-datetime.now().astimezone()).total_seconds()
        require(86380<ttl<=86401,'Invitation not server-issued 24 hours')
        retry=self.issue('a',c,'b',iop)
        require(retry=={k:v for k,v in i.items() if k!='token'} and self.count('cp004b2_private.invitations')==1,'Issue retry contract violated')
        self.mark('32-byte CSPRNG token; 24-hour expiry; retry returns identical metadata without raw token')
        self.denied(self.rpc('a','issue_invitation',{'p_operation_id':iop,'p_space':c,'p_expected_epoch':1,'p_email':self.users['c']['email']}),409)
        self.denied(self.rpc('a','accept_invitation',{'p_operation_id':iop,'p_token':i['token']}),409)
        self.denied(self.rpc('a','create_space',{'p_operation_id':None}),400)
        self.mark('operation ID payload/cross-command reuse rejected; null operation IDs rejected')
        for n in 'ac':self.denied(self.accept(n,i),generic=True)
        for token in ['x','f'*64]:self.denied(self.accept('b',{'token':token}),generic=True)
        self.mark('wrong recipient, issuer, malformed and unknown tokens get generic denial')
        for target in ['a','bad address']:
            self.denied(self.rpc('a','issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':1,'p_email':self.users['a']['email'] if target=='a' else target}),400)
        self.denied(self.rpc('a','issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':99,'p_email':self.users['b']['email']}),generic=True)
        self.mark('self-invitation, invalid email and stale epoch rejected')
        aop=str(uuid.uuid4()); require(self.ok(self.accept('b',i,aop))=={'space_id':c},'Valid acceptance failed')
        require(self.ok(self.accept('b',i,aop))=={'space_id':c} and self.count('cp004b2.memberships')==2,'Acceptance retry duplicated membership')
        self.denied(self.accept('b',i),generic=True);self.denied(self.accept('c',i),generic=True)
        self.mark('verified intended recipient accepts atomically; same operation replays, new operation cannot reuse token')
        # Actor-scoped operation IDs: B may use A's creation ID independently.
        self.denied(self.rpc('b','create_space',{'p_operation_id':op}),409)
        for n in 'ab':
            rows=self.ok(self.client(n,'memberships?select=*'))
            require(len(rows)==2 and {r['user_id'] for r in rows}=={self.users[x]['id'] for x in 'ab'},'Partner membership scope mismatch')
            require(len(self.ok(self.client(n,'spaces?select=*')))==1,'Partner space scope mismatch')
        other=self.create('c',op)
        require(other!=c,'Operation IDs not actor scoped')
        require(self.ok(self.client('c','spaces?select=*&id=eq.'+c))==[],'Cross-couple leak')
        require(self.ok(self.client('d','memberships?select=*'))==[],'Unpaired membership leak')
        self.denied(self.leave('c',c),generic=True)
        self.denied(self.rpc('c','issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':2,'p_email':self.users['d']['email']}),generic=True)
        self.mark('paired member reads and cross-couple RLS isolation; operation IDs scoped per actor')
        for table in ['spaces','memberships']:
            post={'state':'draft'} if table=='spaces' else {'couple_id':c,'user_id':self.users['d']['id'],'seat':2}
            patch={'state':'closed'} if table=='spaces' else {'active':False}
            for method,body in [('POST',post),('PATCH',patch),('DELETE',None)]:
                self.denied(self.client('a',table+'?'+('id' if table=='spaces' else 'couple_id')+'=eq.'+c,method,body))
        require(self.count('cp004b2.memberships')==3,'Direct writes bypassed commands')
        self.mark('direct space/membership INSERT/PATCH/DELETE denied even to members')
        self.denied(self.rpc('a','issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':2,'p_email':self.users['d']['email']}),generic=True)
        self.denied(self.revoke('a',i),generic=True)
        require(self.count('cp004b2.memberships','couple_id='+quote(c))==2,'Third member capacity failed')
        self.mark('paired-space issuance/accepted-invite revocation denied; capacity remains two')
        require(self.ok(self.leave('b',c)) is True,'Either-partner close failed')
        for n in 'ab':
            require(self.ok(self.client(n,'spaces?select=*'))==[],'Revocation read persisted')
            require(self.ok(self.rpc(n,'account_context',{}))['spaces']==[],'Revoked current context')
            self.denied(self.leave(n,c),generic=True)
        self.denied(self.accept('b',i,aop),generic=True)
        self.denied(self.rpc('a','create_space',{'p_operation_id':op}),generic=True)
        self.denied(self.rpc('a','issue_invitation',{'p_operation_id':str(uuid.uuid4()),'p_space':c,'p_expected_epoch':3,'p_email':self.users['d']['email']}),generic=True)
        self.mark('either partner closes; same still-valid JWTs and old receipts cannot restore revoked access')
        require(self.count('cp004b2.memberships','couple_id='+quote(c)+' AND NOT active')==2,'Close erased history')
        require(self.create('a')!=c,'New space reused closed identity')
        self.mark('new draft uses new space ID; closed history retained without archive reads')

    def lifecycle(self):
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        rop=str(uuid.uuid4());d=self.ok(self.revoke('a',i,rop))
        require(self.ok(self.revoke('a',i,rop))==d,'Revoke retry mismatch')
        self.denied(self.accept('b',i),generic=True);self.denied(self.revoke('c',i),generic=True)
        self.mark('revocation and durable revoke replay; foreign revoke and revoked acceptance denied')
        old=self.issue('a',c,'b');i=self.issue('a',c,'b')
        require(i['invitation_id']!=old['invitation_id'],'Replacement reused invitation')
        self.denied(self.accept('b',old),generic=True)
        sql('UPDATE cp004b2_private.invitations SET expires_at=clock_timestamp()-interval \'1 second\' WHERE id='+quote(i['invitation_id']))
        self.denied(self.accept('b',i),generic=True)
        require(self.count('cp004b2.memberships')==1,'Expired accept side effect')
        self.mark('explicit replacement revokes prior token; server-expired invitation rejected')
        self.reset();ca=self.create('a');cb=self.create('c')
        for target in ['b','unregistered-'+self.run_id+'@example.invalid','c']:
            i=self.issue('a',ca,target)
            require(set(i)=={'invitation_id','expires_at','token'},'Registration status disclosure shape')
            if target=='c':self.denied(self.accept('c',i),generic=True)
        self.mark('registered/unregistered/already-occupied recipients share opaque issuance response; capacity checked at acceptance')
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        # Administrative fault injection after genuine sign-in; token remains real.
        sql('UPDATE auth.users SET email_confirmed_at=NULL WHERE id='+quote(self.users['b']['id']))
        try:self.denied(self.accept('b',i),generic=True)
        finally:sql('UPDATE auth.users SET email_confirmed_at=clock_timestamp() WHERE id='+quote(self.users['b']['id']))
        sql('UPDATE auth.users SET email='+quote('changed-'+self.run_id+'@example.invalid')+' WHERE id='+quote(self.users['b']['id']))
        try:self.denied(self.accept('b',i),generic=True)
        finally:sql('UPDATE auth.users SET email='+quote(self.users['b']['email'])+' WHERE id='+quote(self.users['b']['id']))
        self.mark('live Auth confirmation/email checked despite stale genuinely signed email claim')
        sql('UPDATE cp004b2_private.accounts SET enabled=false WHERE user_id='+quote(self.users['a']['id']))
        self.denied(self.rpc('a','ensure_account',{}),generic=True)
        require(self.ok(self.client('a','spaces?select=*'))==[],'Disabled account retained RLS scope')
        self.denied(self.accept('b',i),generic=True)
        self.mark('disabled account cannot re-enable via ensure; issuer disable blocks acceptance and RLS reads')
    def race(self,lock_sql,jobs,while_locked=None):
        """Hold a real row lock, then prove BOTH independent REST transactions wait."""
        p=subprocess.Popen([DOCKER,'exec','-i',CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1',
             '-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=ENV)
        import select
        try:
            p.stdin.write("SET log_statement='none'; SET log_min_error_statement='panic'; SET statement_timeout='10s'; BEGIN;\n\\o /dev/null\n"+lock_sql+";\n\\o\n\\echo HOLD_READY\n");p.stdin.flush()
            require(bool(select.select([p.stdout],[],[],5)[0]) and p.stdout.readline().strip()=='HOLD_READY','Concurrency blocker failed')
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as pool:
                futures=[pool.submit(job) for job in jobs]
                deadline=time.monotonic()+6
                try:
                    while time.monotonic()<deadline:
                        waiting=int(sql("SELECT count(*) FROM pg_stat_activity WHERE usename='authenticator' AND wait_event_type='Lock' AND query LIKE '%cp004b2%'"))
                        if waiting>=len(jobs):break
                        require(not any(f.done() for f in futures),'Race request completed before lock contention')
                        time.sleep(.05)
                    else:raise RuntimeError('Both real HTTP transactions did not reach lock wait')
                    if while_locked:while_locked(p)
                    p.stdin.write('COMMIT;\n');p.stdin.flush()
                finally:
                    if p.poll() is None:
                        p.stdin.write('ROLLBACK;\n');p.stdin.flush()
                results=[f.result(timeout=15) for f in futures]
            return results
        finally:
            if p.poll() is None:
                p.stdin.write('ROLLBACK;\n\\q\n');p.stdin.flush()
                try:p.communicate(timeout=3)
                except subprocess.TimeoutExpired:p.kill();p.communicate()

    def concurrency(self):
        self.reset();self.ok(self.rpc('a','ensure_account',{}))
        lock="SELECT 1 FROM cp004b2_private.accounts WHERE user_id="+quote(self.users['a']['id'])+' FOR UPDATE'
        results=self.race(lock,[lambda:self.rpc('a','create_space',{'p_operation_id':str(uuid.uuid4())}) for _ in range(2)])
        require(sorted(r[0] for r in results)==[200,409] and self.count('cp004b2.spaces')==1,'Concurrent create exceeded active capacity')
        self.mark('concurrent different-operation draft creation: both lock waits observed, one 200/one 409')
        self.reset();c=self.create('a');op=str(uuid.uuid4())
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        results=self.race(lock,[lambda:self.rpc('a','issue_invitation',{'p_operation_id':op,'p_space':c,'p_expected_epoch':1,'p_email':self.users['b']['email']}) for _ in range(2)])
        bodies=[self.ok(r) for r in results]
        for body in bodies:
            if 'token' in body:self.raw_tokens.append(body['token'])
        require(self.count('cp004b2_private.invitations')==1 and sum('token' in d for d in bodies)==1 and bodies[0]['invitation_id']==bodies[1]['invitation_id'],'Concurrent issue replay mismatch')
        self.mark('concurrent same-operation issue returns one raw token and one metadata replay; one invitation')
        i=next(d for d in bodies if 'token' in d)
        results=self.race(lock,[lambda:self.accept('b',i) for _ in range(2)])
        require(sorted(r[0] for r in results)==[200,403] and self.count('cp004b2.memberships','active')==2,'Concurrent different-operation acceptance failed')
        self.mark('concurrent different-operation acceptance: exactly one success; two active seats')
        self.reset();c=self.create('a');i=self.issue('a',c,'b');op=str(uuid.uuid4())
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        results=self.race(lock,[lambda:self.accept('b',i,op) for _ in range(2)])
        require(all(r[0]==200 and r[1]=={'space_id':c} for r in results) and self.count('cp004b2.memberships')==2,'Concurrent acceptance same-ID not deterministic')
        self.mark('concurrent same-operation acceptance: two equal 200 receipts; single membership effect')
        self.reset();c=self.create('a');d=self.create('c');i=self.issue('a',c,'b');j=self.issue('c',d,'b')
        self.ok(self.rpc('b','ensure_account',{}))
        lock='SELECT 1 FROM cp004b2_private.accounts WHERE user_id='+quote(self.users['b']['id'])+' FOR UPDATE'
        results=self.race(lock,[lambda:self.accept('b',i),lambda:self.accept('b',j)])
        require(sorted(r[0] for r in results)==[200,403] and self.count('cp004b2.memberships','user_id='+quote(self.users['b']['id'])+' AND active')==1,'Cross-space acceptance race violated one-active invariant')
        self.mark('two spaces concurrently invite same recipient: only one active membership can commit')
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        results=self.race(lock,[lambda:self.accept('b',i),lambda:self.revoke('a',i)])
        require(sorted(r[0] for r in results)==[200,403],'Revoke/accept race did not have one winner')
        state=sql('SELECT state FROM cp004b2_private.invitations WHERE id='+quote(i['invitation_id']))
        require(state in ('accepted','revoked') and self.count('cp004b2.memberships')==(2 if state=='accepted' else 1),'Revoke/accept partial effects')
        self.mark('concurrent revoke versus accept serializes to one winner; no partial membership')
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        def expire(p):
            p.stdin.write("UPDATE cp004b2_private.invitations SET expires_at=clock_timestamp()-interval '1 second' WHERE id="+quote(i['invitation_id'])+';\n');p.stdin.flush()
        results=self.race(lock,[lambda:self.accept('b',i),lambda:self.accept('b',i)],expire)
        require(all(r[0]==403 for r in results) and self.count('cp004b2.memberships')==1,'Lock wait used stale expiry timestamp')
        self.mark('expiry changed during observed lock wait: both acceptances denied at lock acquisition')

    def additional_boundaries(self):
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        self.denied(self.rpc('c','ensure_account',{'user_id':self.users['a']['id']}),404)
        code,_,_=http(API+'/auth/v1/user','PUT',{'data':{'couple_id':c,'role':'service_role'}},
                       {'apikey':self.anon,'Authorization':'Bearer '+self.users['c']['token']})
        require(code==200,'Synthetic mutable-metadata update failed')
        self.signin('c');self.denied(self.accept('c',i),generic=True)
        require(self.ok(self.client('c','spaces?select=*'))==[],'Mutable metadata granted scope')
        self.mark('caller-supplied identity parameter rejected; real user-metadata edits cannot grant recipient or scope rights')
        lock='SELECT 1 FROM auth.users WHERE id='+quote(self.users['b']['id'])+' FOR UPDATE'
        def unverify(p):
            p.stdin.write('UPDATE auth.users SET email_confirmed_at=NULL WHERE id='+quote(self.users['b']['id'])+';\n');p.stdin.flush()
        try:
            results=self.race(lock,[lambda:self.accept('b',i),lambda:self.rpc('b','account_context',{})],unverify)
            require(all(r[0]==403 for r in results) and self.count('cp004b2.memberships')==1,'Auth confirmation race permitted acceptance')
        finally:sql('UPDATE auth.users SET email_confirmed_at=clock_timestamp() WHERE id='+quote(self.users['b']['id']))
        self.mark('live confirmation removal wins observed Auth-row lock race against acceptance and context')
        lock='SELECT 1 FROM cp004b2.spaces WHERE id='+quote(c)+' FOR UPDATE'
        results=self.race(lock,[lambda:self.accept('b',i),lambda:self.leave('a',c,1)])
        require(sorted(r[0] for r in results)==[200,403],'Close/accept race did not serialize with epoch guard')
        state=sql('SELECT state FROM cp004b2.spaces WHERE id='+quote(c))
        require(state in ('closed','paired') and self.count('cp004b2.memberships','active')==(0 if state=='closed' else 2),'Close/accept partial effects')
        self.mark('unilateral close versus acceptance: one winner, stale epoch/closed scope rejects loser')
        self.reset();c=self.create('a');i=self.issue('a',c,'b');op=str(uuid.uuid4())
        sql("BEGIN; CREATE FUNCTION cp004b2_private.test_fail_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END $$; REVOKE ALL ON FUNCTION cp004b2_private.test_fail_receipt() FROM PUBLIC; CREATE TRIGGER test_receipt_failure BEFORE INSERT ON cp004b2_private.receipts FOR EACH ROW WHEN (NEW.actor="+quote(self.users['b']['id'])+"::uuid) EXECUTE FUNCTION cp004b2_private.test_fail_receipt(); COMMIT;")
        try:
            self.denied(self.accept('b',i,op),generic=True)
            require(self.count('cp004b2.memberships')==1 and sql('SELECT state FROM cp004b2.spaces WHERE id='+quote(c))=='draft' and sql('SELECT state FROM cp004b2_private.invitations WHERE id='+quote(i['invitation_id']))=='pending','Failed receipt left partial mutation')
            require(self.count('cp004b2_private.receipts','actor='+quote(self.users['b']['id']))==0,'Failed transaction persisted receipt')
        finally:sql('DROP TRIGGER test_receipt_failure ON cp004b2_private.receipts; DROP FUNCTION cp004b2_private.test_fail_receipt();')
        require(self.ok(self.accept('b',i,op))=={'space_id':c} and self.count('cp004b2.memberships')==2,'Retry after rollback not recoverable')
        self.mark('injected receipt failure rolls back entire acceptance; same operation succeeds after fault removal')

    def catalog_and_constraints(self):
        self.reset();c=self.create('a');i=self.issue('a',c,'b');self.ok(self.accept('b',i))
        require(self.count("pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace", "n.nspname IN ('cp004b2','cp004b2_private') AND c.relkind='r' AND c.relrowsecurity")==6,'RLS missing')
        require(sql("SELECT NOT rolsuper AND NOT rolbypassrls FROM pg_roles WHERE rolname='authenticated'")=='t','Client bypass')
        require(sql("SELECT NOT has_table_privilege('cp004b2_owner','auth.users','SELECT') AND NOT has_schema_privilege('authenticated','cp004b2_private','USAGE') AND NOT has_function_privilege('authenticated','cp004b2_private.current_email(boolean)','EXECUTE')")=='t','Auth/private grant escaped')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE n.nspname IN ('cp004b2','cp004b2_private') AND x.grantee=0 AND x.privilege_type='EXECUTE'")=='0','PUBLIC execute exposed')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b2','cp004b2_private') AND p.prosecdef AND NOT ('search_path=\"\"'=ANY(p.proconfig))")=='0','Unsafe definer path')
        self.mark('six RLS tables; non-bypass client; no broad Auth reads, private schema access or PUBLIC function execution')
        for table in ['accounts','keys','invitations','receipts','users']:
            self.denied(self.client('a',table+'?select=*'),404)
        for fn in ['current_email','lock_actor','replay','email_hash']:
            self.denied(self.rpc('a',fn,{}),404)
        code,_,_=http(API+'/rest/v1/invitations',headers={'apikey':self.anon,'Authorization':'Bearer '+self.users['a']['token'],'Accept-Profile':'cp004b2_private'})
        require(code==406,'Private schema API exposure')
        self.mark('private Auth bridge, HMAC key, receipts, invitations and internal helpers not HTTP-exposed')
        # Grant DML temporarily to prove RLS itself independently denies client writes.
        sql('GRANT INSERT,UPDATE,DELETE ON cp004b2.spaces,cp004b2.memberships TO authenticated;')
        try:
            self.denied(self.client('a','spaces','POST',{'state':'draft'}))
            for method,body in [('PATCH',{'epoch':99}),('DELETE',None)]:
                require(self.ok(self.client('a','spaces?id=eq.'+c,method,body))==[],'RLS-only write not empty')
        finally:sql('REVOKE INSERT,UPDATE,DELETE ON cp004b2.spaces,cp004b2.memberships FROM authenticated;')
        require(sql('SELECT epoch FROM cp004b2.spaces WHERE id='+quote(c))=='2','RLS-only write side effect')
        self.mark('independent RLS write protection survives temporary DML grants: insert 403, update/delete 200 empty')
        def rejected(q,code):
            p=proc([DOCKER,'exec','-i',CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],"SET log_statement='none'; SET log_min_error_statement='panic'; "+q)
            require(p.returncode!=0 and code in p.stderr,'Expected constraint rejection missing')
        sql('INSERT INTO cp004b2_private.accounts(user_id) VALUES('+quote(self.users['c']['id'])+') ON CONFLICT DO NOTHING')
        rejected('INSERT INTO cp004b2.memberships(couple_id,user_id,seat) VALUES('+quote(c)+','+quote(self.users['c']['id'])+',3)','23514')
        rejected('INSERT INTO cp004b2.memberships(couple_id,user_id,seat) VALUES('+quote(c)+','+quote(self.users['c']['id'])+',2)','23505')
        rejected("INSERT INTO cp004b2.spaces(state) VALUES('paired')",'23514')
        rejected("BEGIN; INSERT INTO cp004b2.spaces(state) VALUES('draft') RETURNING id; INSERT INTO cp004b2.memberships(couple_id,user_id,seat) SELECT id,"+quote(self.users['a']['id'])+",1 FROM cp004b2.spaces WHERE state='draft'; COMMIT",'23505')
        self.mark('privileged constraint probes: seat bounds/uniqueness, one active space, deferred counts reject invalid commits')
        self.ok(self.leave('b',c))
        rejected("UPDATE cp004b2.spaces SET state='draft',closed_at=NULL WHERE id="+quote(c),'23514')
        rejected('UPDATE cp004b2.memberships SET active=true WHERE couple_id='+quote(c),'23514')
        rejected('UPDATE cp004b2.memberships SET user_id='+quote(self.users['c']['id'])+' WHERE couple_id='+quote(c)+' AND seat=2','23514')
        self.mark('closed-space reopening, revoked-seat resurrection and replacement partner blocked by triggers')

    def logging_and_hashes(self):
        self.reset();c=self.create('a');i=self.issue('a',c,'b')
        self.denied(self.accept('c',i),generic=True)
        dump=sql("SELECT row_to_json(t) FROM cp004b2_private.invitations t; SELECT row_to_json(t) FROM cp004b2_private.receipts t;")
        require(all(t not in dump for t in self.raw_tokens),'Plaintext token persisted')
        require(all(u['email'] not in dump and u['password'] not in dump for u in self.users.values()),'Plaintext recipient credential persisted')
        require(sql('SELECT octet_length(token_hash)=32 AND octet_length(recipient_hmac)=32 AND key_version=1 FROM cp004b2_private.invitations')=='t','Digest storage mismatch')
        self.mark('database stores SHA-256 token digests and keyed recipient HMAC; no raw tokens/emails in invitation/receipt rows')
        for name in ['supabase_db_','supabase_rest_','supabase_kong_','supabase_auth_']:
            p=proc([DOCKER,'logs',name+PROJECT])
            require(p.returncode==0,'Log inspection unavailable')
            logs=p.stdout+p.stderr
            require(all(t not in logs for t in self.raw_tokens),'Raw invitation token leaked into local service logs')
            require(self.admin not in logs and all(u['password'] not in logs and u['token'] not in logs for u in self.users.values()),'Auth credential leaked into inspected logs')
        self.mark('database/PostgREST/gateway/Auth log scan: no tested raw invitation tokens, passwords or user JWTs')

    def run(self):
        self.preflight();self.identities();self.install();self.basic();self.lifecycle();self.concurrency();self.additional_boundaries();self.catalog_and_constraints();self.logging_and_hashes()
        print('RESULT:',len(self.passed),'real Auth/HTTP/database scenarios passed; zero mocks/skips.',flush=True)
        print('B.2 proof changes remain uncommitted; no hosted or Flutter integration.',flush=True)


if __name__=='__main__':
    try:Proof().run()
    except Exception as exc:
        print('FAIL:',str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__+' (sensitive detail suppressed)',file=sys.stderr)
        sys.exit(1)
