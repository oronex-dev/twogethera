#!/usr/bin/env python3
"""CP-004B.1 real local Auth -> JWT -> HTTP/PostgREST -> auth.uid -> RLS.
No third-party dependencies, hand-signed JWTs, client role impersonation or cloud URLs.
Fixture administration and client authorization requests are deliberately separated.
"""
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
PROJECT = 'twogethera-b1'
SENTINEL = 'twogethera:cp004b1:disposable:v1'
CONTAINER = 'supabase_db_' + PROJECT
API = 'http://127.0.0.1:55321'
MAIL = 'http://127.0.0.1:55324'
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
    require(parsed.scheme=='http' and parsed.hostname=='127.0.0.1' and parsed.port in (55321,55324),
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
        require(status.get('API_URL')==API and '@127.0.0.1:55322/' in status.get('DB_URL',''),'Unexpected proof endpoints')
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
        h={'apikey':self.anon,'Accept-Profile':'cp004b1','Content-Profile':'cp004b1',
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

    def identities(self):
        for name in 'abcd':
            email='b1-'+self.run_id+'-'+name+'@example.invalid';password=secrets.token_urlsafe(30)
            code,data,_=self.fixture_auth('/admin/users',{'email':email,'password':password,'email_confirm':True,
                         'user_metadata':{'local_proof':'cp004b1'}})
            require(code==200 and isinstance(data,dict) and bool(data.get('id')),'Synthetic Auth fixture creation failed')
            self.users[name]={'id':data['id'],'email':email,'password':password}
            self.signin(name)
        self.mark('four verified synthetic Auth accounts with real password-grant JWTs')
        # E exercises actual signup -> locally captured mail -> verify -> password sign-in.
        name='e';email='b1-'+self.run_id+'-e@example.invalid';password=secrets.token_urlsafe(30)
        code,data,_=http(API+'/auth/v1/signup','POST',{'email':email,'password':password},{'apikey':self.anon})
        require(code==200 and isinstance(data,dict) and bool(data.get('id')),'Real signup failed')
        self.users[name]={'id':data['id'],'email':email,'password':password}
        code,denied,_=http(API+'/auth/v1/token?grant_type=password','POST',{'email':email,'password':password},{'apikey':self.anon})
        require(code in (400,401) and isinstance(denied,dict) and denied.get('error_code')=='email_not_confirmed','Unverified sign-in not rejected as expected')
        self.mark('unconfirmed signup cannot obtain a password-grant user token')
        link=None;deadline=time.monotonic()+15
        while time.monotonic()<deadline and not link:
            code,messages,_=http(MAIL+'/api/v1/messages')
            require(code==200 and isinstance(messages,dict),'Local mail capture unavailable')
            for msg in messages.get('messages',[]):
                if email not in json.dumps(msg):continue
                mid=msg.get('ID') or msg.get('id')
                code,content,_=http(MAIL+'/api/v1/message/'+urllib.parse.quote(mid))
                require(code==200,'Captured confirmation message unavailable')
                text=html.unescape(str(content.get('Text',''))+' '+str(content.get('HTML','')))
                match=re.search(r'http://127\.0\.0\.1:55321/auth/v1/verify\?[^\s"<>]+',text)
                if match:link=match.group(0);break
            if not link:time.sleep(.2)
        require(bool(link),'No local signup confirmation URL found')
        code,_,_=http(link)
        require(code in (200,302,303),'Real email confirmation failed')
        self.signin('e')
        self.mark('real signup and captured-local-email confirmation followed by sign-in')
        self.expired_candidate=self.users['e']['token'];self.expiry=self.users['e']['exp']

    def install(self):
        # Container identity was verified before connecting or resetting these namespaces.
        marker=sql("SELECT coalesce(shobj_description(oid,'pg_database'),'') FROM pg_database WHERE datname=current_database();")
        require(marker in ('','default administrative connection database',SENTINEL),'Disposable database marker mismatch')
        if marker!=SENTINEL:
            require(sql("SELECT count(*) FROM pg_namespace WHERE nspname IN ('cp004b1','cp004b1_private')")=='0','Unmarked prototype schema collision')
            sql('COMMENT ON DATABASE postgres IS '+quote(SENTINEL)+';')
        existing=sql("SELECT count(*) FROM pg_roles WHERE rolname='cp004b1_owner'")
        if existing=='0':
            sql("CREATE ROLE cp004b1_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE; COMMENT ON ROLE cp004b1_owner IS "+quote(SENTINEL)+';')
        require(sql("SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND shobj_description(oid,'pg_authid')="+quote(SENTINEL)+" FROM pg_roles WHERE rolname='cp004b1_owner'")=='t','Unsafe owner role collision')
        require(sql("SELECT count(*) FROM pg_auth_members WHERE roleid=(SELECT oid FROM pg_roles WHERE rolname='cp004b1_owner')")=='0','Owner role unexpectedly assumable')
        sql('DROP SCHEMA IF EXISTS cp004b1 CASCADE; DROP SCHEMA IF EXISTS cp004b1_private CASCADE; '
            'GRANT USAGE ON SCHEMA auth TO cp004b1_owner; '
            'REVOKE SELECT ON auth.users FROM cp004b1_owner; REVOKE SELECT(id,email_confirmed_at,banned_until,is_anonymous) ON auth.users FROM cp004b1_owner; GRANT REFERENCES(id) ON auth.users TO cp004b1_owner;')
        sql((HERE/'supabase/migrations/20261029000100_http_probe.sql').read_text())
        # Restrict PostgREST to this project's public ES256 keys, excluding the
        # CLI's shared legacy development HS256 secret from user-token verification.
        code,jwks,_=http(API+'/auth/v1/.well-known/jwks.json')
        require(code==200 and bool(jwks.get('keys')) and all(k.get('alg')=='ES256' and 'd' not in k for k in jwks['keys']), 'Expected project-specific public ES256 JWKS')
        sql('ALTER ROLE authenticator SET pgrst.jwt_secret='+quote(json.dumps(jwks))+';')
        # Narrow API exposure after schema exists, only within this disposable cluster.
        sql("ALTER ROLE authenticator SET pgrst.db_schemas='cp004b1'; NOTIFY pgrst,'reload config'; NOTIFY pgrst,'reload schema';")
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            code,data,_=self.client('a','rpc/whoami','POST',{})
            if code==200 and isinstance(data,dict) and data.get('uid')==self.users['a']['id']:break
            time.sleep(.1)
        else:raise RuntimeError('PostgREST did not expose installed proof schema')
        self.mark('sentinel-guarded three-table migration and real auth.uid HTTP probe')

    def seed(self):
        self.s1=str(uuid.uuid4());self.s2=str(uuid.uuid4());self.r1=str(uuid.uuid4());self.r2=str(uuid.uuid4())
        self.secret1='SYNTHETIC_AB_'+secrets.token_hex(12);self.secret2='SYNTHETIC_CD_'+secrets.token_hex(12)
        q='BEGIN; INSERT INTO cp004b1.spaces(id,state) VALUES ('+quote(self.s1)+",'paired'),("+quote(self.s2)+",'paired');"
        for scope,names in [(self.s1,'ab'),(self.s2,'cd')]:
            for seat,n in enumerate(names,1):
                q+='INSERT INTO cp004b1.memberships(couple_id,user_id,seat) VALUES ('+quote(scope)+','+quote(self.users[n]['id'])+','+str(seat)+');'
        q+='INSERT INTO cp004b1.records VALUES ('+quote(self.r1)+','+quote(self.s1)+','+quote(self.secret1)+'),('+quote(self.r2)+','+quote(self.s2)+','+quote(self.secret2)+'); COMMIT;'
        sql(q)
        self.mark('two independent synthetic couple fixtures committed with real Auth UUIDs')

    def mark(self,name):
        self.passed.append(name);print('PASS:',name,flush=True)

    def deny(self,response,expected=(403,)):
        code,body,_=response
        require(code in expected,'Expected explicit denial, got HTTP '+str(code))
        text=json.dumps(body)
        for secret in [self.secret1,self.secret2,*[u['password'] for u in self.users.values()],self.admin]:
            require(secret not in text,'Sensitive content leaked in denied API response')
        self.negative_bodies.append(body)

    def tests(self):
        for n in 'abcde':self.signin(n)
        for n in 'abcde':
            code,data,_=self.client(n,'rpc/whoami','POST',{})
            require(code==200 and data=={'uid':self.users[n]['id'],'database_role':'authenticated'},'JWT resolved to incorrect principal/role')
        self.mark('five actual JWTs resolve to distinct auth.uid under authenticated role')
        for n in 'ab':
            code,data,_=self.client(n,'records?select=*')
            require(code==200 and len(data)==1 and data[0]['body']==self.secret1,'Authorized partner read failed')
        self.mark('A and B read the same authorized record via HTTP')
        code,data,_=self.client('c','records?select=*')
        require(code==200 and len(data)==1 and data[0]['body']==self.secret2,'Unrelated couple isolation failed')
        self.mark('C sees its own couple record only')
        for n in 'cde':
            code,data,_=self.client(n,'records?select=*&couple_id=eq.'+self.s1)
            require(code==200 and data==[],'Cross-couple read not RLS-filtered empty')
        self.mark('C/D and verified unpaired E receive HTTP 200 empty cross-couple reads')
        for n in 'ab':
            code,data,_=self.client(n,'memberships?select=*')
            require(code==200 and len(data)==2 and {x['user_id'] for x in data}=={self.users[x]['id'] for x in 'ab'},'Membership read leaked another couple')
            code,data,_=self.client(n,'spaces?select=*')
            require(code==200 and len(data)==1 and data[0]['id']==self.s1,'Space metadata leaked another couple')
        self.mark('membership and space metadata scoped to the JWT principal')
        self.deny(self.client(None,'records?select=*'),expected=(401,403))
        self.deny(self.client(None,'rpc/whoami','POST',{}),expected=(401,403))
        code,_,_=http(API+'/rest/v1/records')
        require(code==401,'Missing API key/request unexpectedly accepted')
        self.mark('no user JWT and no API key produce explicit unauthorized outcomes')
        for method,path,body in [('POST','records',{'id':str(uuid.uuid4()),'couple_id':self.s1,'body':'FORBIDDEN'}),
                                  ('PATCH','records?id=eq.'+self.r1,{'body':'FORBIDDEN'}),
                                  ('DELETE','records?id=eq.'+self.r1,None)]:
            self.deny(self.client('c',path,method,body))
        require(sql('SELECT count(*) FROM cp004b1.records')=='2' and sql('SELECT body FROM cp004b1.records WHERE id='+quote(self.r1))==self.secret1,'Denied writes changed records')
        self.mark('unauthorized HTTP INSERT/PATCH/DELETE forbidden with persisted rows unchanged')
        for method,body in [('POST',{'couple_id':self.s1,'user_id':self.users['e']['id'],'seat':2}),
                            ('PATCH',{'active':False}),('DELETE',None)]:
            self.deny(self.client('a','memberships?couple_id=eq.'+self.s1,method,body))
        require(sql('SELECT count(*) FROM cp004b1.memberships WHERE active')=='4','Membership HTTP mutation bypass')
        self.mark('direct membership mutations denied even to authorized members')
        # Distinguish independent RLS enforcement from lack of DML grants.
        sql('GRANT INSERT,UPDATE,DELETE ON cp004b1.records TO authenticated;')
        try:
            self.deny(self.client('a','records','POST',{'id':str(uuid.uuid4()),'couple_id':self.s1,'body':'BLOCKED_BY_RLS'}))
            for method,body in [('PATCH',{'body':'BLOCKED_BY_RLS'}),('DELETE',None)]:
                code,data,_=self.client('a','records?id=eq.'+self.r1,method,body)
                require(code==200 and data==[],'Expected empty RLS-filtered mutation result')
        finally:sql('REVOKE INSERT,UPDATE,DELETE ON cp004b1.records FROM authenticated;')
        require(sql('SELECT count(*) FROM cp004b1.records')=='2' and sql('SELECT body FROM cp004b1.records WHERE id='+quote(self.r1))==self.secret1,'RLS-only denied mutations changed data')
        self.mark('independent RLS write denial: INSERT forbidden; UPDATE/DELETE HTTP 200 empty with zero effects')
        self.deny(self.client('c','rpc/leave_space','POST',{'p_space':self.s1}))
        require(sql('SELECT count(*) FROM cp004b1.memberships WHERE active')=='4','Denied RPC changed membership')
        self.mark('security-definer leave command cannot target another couple')
        code,data,_=self.client('c','rpc/can_read','POST',{'c':self.s1})
        require(code==200 and data is False,'Read helper leaked/accepted foreign scope')
        for relation in ['identities','users','invitations']:
            self.deny(self.client('a',relation+'?select=*'),expected=(404,))
        code,_,_=http(API+'/rest/v1/records',headers={'apikey':self.anon,'Authorization':'Bearer '+self.users['a']['token'],'Accept-Profile':'auth'})
        require(code==406,'Private Auth schema unexpectedly API-exposed')
        self.mark('private Auth/other schemas and nonexistent prototype surfaces inaccessible')
        segments=self.users['a']['token'].split('.')
        segments[2]=('A' if segments[2][0]!='A' else 'B')+segments[2][1:]
        for bad in ['not-a-jwt',self.users['a']['token'][:-8],'.'.join(segments)]:
            self.deny(self.client('a','records?select=*',token=bad),expected=(401,))
        self.mark('malformed, truncated and corrupted real-token strings rejected by HTTP verifier')
        require(sql("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='cp004b1' AND c.relkind='r' AND c.relrowsecurity")=='3','RLS catalog mismatch')
        require(sql("SELECT NOT rolsuper AND NOT rolbypassrls FROM pg_roles WHERE rolname='authenticated'")=='t','Authenticated role bypasses RLS')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE n.nspname IN ('cp004b1','cp004b1_private') AND x.grantee=0 AND x.privilege_type='EXECUTE'")=='0','Unexpected PUBLIC EXECUTE')
        require(sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004b1','cp004b1_private') AND p.prosecdef AND NOT ('search_path=\"\"'=ANY(p.proconfig))")=='0','Unsafe definer path')
        self.mark('catalog proves RLS, non-bypass authenticated role and explicit definer/public grants')
        # Constraint tests are privileged fixture probes, not client-auth evidence.
        self.constraint_tests()
        for n in 'ab':self.signin(n)
        old_a=self.users['a']['token'];old_b=self.users['b']['token']
        code,data,_=self.client('b','rpc/leave_space','POST',{'p_space':self.s1})
        require(code==200 and data is True,'Authorized noncreator leave failed')
        for n,t in [('a',old_a),('b',old_b)]:
            code,data,_=self.client(n,'records?select=*',token=t)
            require(code==200 and data==[],'Revoked JWT retained shared visibility')
            code,data,_=self.client(n,'rpc/whoami','POST',{},token=t)
            require(code==200 and data['uid']==self.users[n]['id'],'Old real JWT unexpectedly expired during revocation proof')
            self.deny(self.client(n,'rpc/leave_space','POST',{'p_space':self.s1},token=t))
        require(sql('SELECT count(*) FROM cp004b1.records')=='2','Unlink silently destroyed archive data')
        self.mark('same still-valid JWTs lose shared access immediately after committed leave; rows retained')
        self.closed_tests()
        self.expiration_test()

    def constraint_tests(self):
        def rejected(q,code):
            p=proc([DOCKER,'exec','-i',CONTAINER,'psql','-X','-qAt','-w','-h','127.0.0.1','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],
                   "SET log_min_error_statement='panic'; "+q)
            require(p.returncode!=0 and code in p.stderr,'Expected database constraint rejection missing')
        self.reject_fixture=rejected
        rejected('INSERT INTO cp004b1.memberships(couple_id,user_id,seat) VALUES ('+quote(self.s1)+','+quote(self.users['e']['id'])+',3)','23514')
        rejected('INSERT INTO cp004b1.memberships(couple_id,user_id,seat) VALUES ('+quote(self.s1)+','+quote(self.users['e']['id'])+',2)','23505')
        s=str(uuid.uuid4())
        rejected('BEGIN; INSERT INTO cp004b1.spaces(id,state) VALUES ('+quote(s)+",'draft'); INSERT INTO cp004b1.memberships(couple_id,user_id,seat) VALUES ("+quote(s)+','+quote(self.users['a']['id'])+',1); COMMIT;','23505')
        rejected('INSERT INTO cp004b1.spaces(id,state) VALUES ('+quote(str(uuid.uuid4()))+",'paired')",'23514')
        require(sql('SELECT count(*) FROM cp004b1.spaces')=='2','Rejected constraint probe left partial data')
        self.mark('database backstops enforce two seats, one active space and commit-time state counts')

    def closed_tests(self):
        self.reject_fixture("UPDATE cp004b1.spaces SET state='paired',closed_at=NULL WHERE id="+quote(self.s1),'23514')
        self.reject_fixture('UPDATE cp004b1.memberships SET active=true WHERE couple_id='+quote(self.s1),'23514')
        self.reject_fixture('UPDATE cp004b1.memberships SET user_id='+quote(self.users['e']['id'])+' WHERE couple_id='+quote(self.s1)+' AND seat=2','23514')
        self.mark('closed-space reuse, membership resurrection and replacement partner rejected')

    def expiration_test(self):
        # Never fabricate/sign an expired JWT. Wait for this actual Auth-issued one.
        require(self.expiry-time.time()<120,'Test token TTL too long; short-lived isolated Auth config required')
        print('Waiting for genuine Auth-issued token expiry (no forged token or verifier bypass).',flush=True)
        deadline=time.monotonic()+130
        while time.monotonic()<deadline:
            code,body,_=self.client('e','rpc/whoami','POST',{},token=self.expired_candidate)
            if code==401:
                require(time.time()>=self.expiry,'Token rejected before real expiry')
                self.mark('genuine Auth-issued token rejected after natural expiration')
                break
            require(code==200,'Unexpected HTTP failure while awaiting token expiry')
            time.sleep(.5)
        else:raise RuntimeError('Actual expired user JWT was not rejected by verifier')
        self.signin('e')
        code,data,_=self.client('e','rpc/whoami','POST',{})
        require(code==200 and data['uid']==self.users['e']['id'],'New genuine sign-in token failed after old expiry')
        self.mark('fresh Auth sign-in restores identity access after expired-token rejection')

    def run(self):
        self.preflight();self.identities();self.install();self.seed();self.tests()
        print('RESULT:',len(self.passed),'HTTP/Auth/database scenarios passed; zero mocks/skips.',flush=True)
        print('Disposable project only:',PROJECT,'; no hosted or Flutter integration.')


if __name__=='__main__':
    try:Proof().run()
    except Exception as exc:
        print('FAIL:',str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__+' (sensitive detail suppressed)',file=sys.stderr)
        sys.exit(1)
