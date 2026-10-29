#!/usr/bin/env python3
"""CP-005A local fixture orchestration. Never passes admin credentials to Flutter.
Usage: python3 tool/run_local_auth_tests.py chrome | <iOS simulator ID>
"""
import hashlib
import http.server
import json
import os
from pathlib import Path
import runpy
import secrets
import subprocess
import sys
import threading
import urllib.parse

ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
m=runpy.run_path(str(ROOT/'proofs/cp004b4-operations/run_tests.py'))
p=m['Operations']();proc=m['proc'];sql=m['sql'];quote=m['quote'];require=m['require']


def main():
    target=sys.argv[1] if len(sys.argv)>1 else 'chrome'
    require(target=='chrome' or (len(target)==36 and all(c in '0123456789abcdefABCDEF-' for c in target)),'Only Chrome or explicit local simulator UUID supported')
    p.preflight()
    require(sql("SELECT count(*) FROM cp004b3_rehearsal.applied")=='4','Install B.4 proof before CP-005A tests')
    run=secrets.token_hex(8);password=secrets.token_urlsafe(30)
    email='cp005a-'+run+'@example.invalid'
    code,user,_=p.fixture_auth('/admin/users',{'email':email,'password':password,'email_confirm':True})
    require(code==200 and user.get('id'),'B.4 synthetic fixture setup failed')
    fixture_id=user['id']
    # B.1 is used only for a genuine short-lived (60s) Auth token expiry case.
    state=proc(['supabase','status','--workdir',str(ROOT/'proofs/cp004b1-http'),'-o','json'])
    require(state.returncode==0,'B.1 short-lived local Auth stack unavailable')
    b1=json.loads(state.stdout);require(b1['API_URL']=='http://127.0.0.1:55321','Wrong B.1 target')
    inspect=proc([m['b2'].DOCKER,'inspect','supabase_auth_twogethera-b1','--format','{{json .Config.Labels}}'])
    require(inspect.returncode==0 and json.loads(inspect.stdout).get('com.supabase.cli.project')=='twogethera-b1','Wrong B.1 container')
    # Use B.1's loopback-only HTTP helper; never forge a token or impersonate SQL roles.
    b1m=runpy.run_path(str(ROOT/'proofs/cp004b1-http/run_tests.py'))
    short_email='cp005a-expiry-'+run+'@example.invalid';short_password=secrets.token_urlsafe(30)
    code,short_user,_=b1m['http'](b1['API_URL']+'/auth/v1/admin/users','POST',
        {'email':short_email,'password':short_password,'email_confirm':True},
        {'apikey':b1['ANON_KEY'],'Authorization':'Bearer '+b1['SERVICE_ROLE_KEY']})
    require(code==200,'Short-lived Auth fixture setup failed')
    nonce=secrets.token_urlsafe(32)

    class Control(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def allowed_origin(self):
            origin=self.headers.get('Origin','')
            parsed=urllib.parse.urlsplit(origin)
            return origin if parsed.scheme=='http' and parsed.hostname in ('127.0.0.1','localhost') else None
        def headers_for(self):
            if self.allowed_origin():self.send_header('Access-Control-Allow-Origin',self.allowed_origin())
            self.send_header('Access-Control-Allow-Headers','content-type,x-local-proof,authorization,apikey,x-client-info')
            self.send_header('Access-Control-Allow-Methods','POST,OPTIONS')
            self.send_header('Cache-Control','no-store')
        def do_OPTIONS(self):
            self.send_response(204);self.headers_for();self.end_headers()
        def do_POST(self):
            if self.headers.get('X-Local-Proof')!=nonce or self.path not in ('/functions/v1/suspend','/functions/v1/restore'):
                self.send_response(403);self.end_headers();return
            try:
                # Fixed fixture only: no arbitrary user IDs, SQL or scripts accepted.
                enabled='true' if self.path=='/functions/v1/restore' else 'false'
                sql('BEGIN; SET LOCAL ROLE cp004b4_maintainer; SELECT cp004b4_ops.set_account_enabled('+quote(fixture_id)+','+enabled+'); RESET ROLE; COMMIT;')
                self.send_response(200);self.headers_for();self.end_headers();self.wfile.write(b'{"ok":true}')
            except Exception:
                self.send_response(500);self.end_headers()
    server=http.server.HTTPServer(('127.0.0.1',0),Control)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    local=ROOT/'.local/cp005a';local.mkdir(parents=True,exist_ok=True,mode=0o700);local.chmod(0o700)
    fixture={'url':m['b2'].API,'key':p.anon,'email':email,'password':password,'userId':fixture_id,
        'control':'http://127.0.0.1:'+str(server.server_port),'nonce':nonce,
        'expiryUrl':b1['API_URL'],'expiryKey':b1['ANON_KEY'],'expiryEmail':short_email,'expiryPassword':short_password}
    definitions={'CP005A_FIXTURE':json.dumps(fixture),'LOCAL_AUTH_ENABLED':True,
        'LOCAL_SUPABASE_URL':m['b2'].API,'LOCAL_SUPABASE_ANON_KEY':p.anon}
    fixture_file=local/'test-defines.json';fixture_file.touch(mode=0o600);fixture_file.chmod(0o600)
    fixture_file.write_text(json.dumps(definitions))
    # App config contains PUBLIC API identification only, no passwords/admin keys.
    app_file=local/'app-defines.json';app_file.touch(mode=0o600);app_file.chmod(0o600)
    app_file.write_text(json.dumps({k:v for k,v in definitions.items() if k not in ('CP005A_FIXTURE','LOCAL_SUPABASE_URL')}))
    secrets_to_redact=[password,short_password,p.admin,b1['SERVICE_ROLE_KEY'],nonce,p.anon,b1['ANON_KEY']]
    generated=ROOT/'test/cp005a_live_test.dart'
    require(not generated.exists(),'Another local browser test entry already exists')
    if target=='chrome':
        generated.write_text((ROOT/'test_local/browser_entry.dart').read_text().replace('../test/support/','support/'))
        command=['flutter','test','--platform','chrome','test/cp005a_live_test.dart']
    else:command=['flutter','test','integration_test/local_auth_test.dart','-d',target]
    command+=['--dart-define-from-file='+str(fixture_file),'--reporter','expanded']
    print('Running real SDK/Flutter tests against guarded local fixtures; credentials suppressed.',flush=True)
    try:
        child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        for line in child.stdout:
            # Defense in depth; application/test assertions never print tokens.
            for value in secrets_to_redact:line=line.replace(value,'[redacted]')
            import re
            line=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[redacted-jwt]',line)
            print(line,end='',flush=True)
        code=child.wait()
    finally:
        server.shutdown();server.server_close();fixture_file.unlink(missing_ok=True);generated.unlink(missing_ok=True)
        # Restore only this synthetic fixture gate; no other user is touched.
        try:sql('BEGIN; SET LOCAL ROLE cp004b4_maintainer; SELECT cp004b4_ops.set_account_enabled('+quote(fixture_id)+',false); COMMIT;')
        except Exception:pass
        # Retire only our synthetic fixture passwords; cached test bundles cannot reuse them.
        try:p.fixture_auth('/admin/users/'+fixture_id,{'password':secrets.token_urlsafe(36)},'PUT')
        except Exception:pass
        try:b1m['http'](b1['API_URL']+'/auth/v1/admin/users/'+short_user['id'],'PUT',{'password':secrets.token_urlsafe(36)},
            {'apikey':b1['ANON_KEY'],'Authorization':'Bearer '+b1['SERVICE_ROLE_KEY']})
        except Exception:pass
    require(code==0,'Local Flutter integration tests failed; see sanitized outcomes above')
    print('Local fixture secrets removed; public debug app configuration remains ignored.',flush=True)


if __name__=='__main__':
    try:main()
    except Exception as error:
        print('FAIL:',str(error) if isinstance(error,RuntimeError) else type(error).__name__+' (details suppressed)',file=sys.stderr);sys.exit(1)
