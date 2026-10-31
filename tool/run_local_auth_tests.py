#!/usr/bin/env python3
"""CP-005A local fixture orchestration. Never passes admin credentials to Flutter.
Usage: python3 tool/run_local_auth_tests.py chrome | <iOS simulator ID> | emulator-<port> [--restart-only] [--adb-reverse]
"""
import re
import time
import http.server
import json
import os
from pathlib import Path
import runpy
import secrets
import select
import signal
import subprocess
import sys
import threading
import urllib.parse

ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
m=runpy.run_path(str(ROOT/'proofs/cp004b4-operations/run_tests.py'))
p=m['Operations']();proc=m['proc'];sql=m['sql'];quote=m['quote'];require=m['require']



def audit_native_storage(target, sensitive, live_tokens=None):
    # Inspect application data surfaces only; never print file contents or values.
    contents=[]
    if target.startswith('emulator-'):
        adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb')
        base=[adb,'-s',target,'exec-out','run-as','com.example.twogethera']
        listing=proc(base+['find','.','-type','f'])
        require(listing.returncode==0,'Native storage inventory unavailable')
        for name in listing.stdout.splitlines():
            if name.startswith(('./files/','./shared_prefs/','./databases/')):
                result=subprocess.run(base+['cat',name],capture_output=True,timeout=30)
                require(result.returncode==0,'Native storage file unreadable')
                contents.append(result.stdout)
    else:
        result=proc(['xcrun','simctl','get_app_container',target,'com.example.twogethera','data'])
        require(result.returncode==0,'Simulator app container unavailable')
        root=Path(result.stdout.strip()).resolve()
        for folder in ('Documents','Library/Preferences','Library/Application Support'):
            for path in (root/folder).rglob('*'):
                if path.is_file() and path.resolve().is_relative_to(root):contents.append(path.read_bytes())
    for data in contents:
        require(not re.search(rb'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',data),'JWT pattern in native application persistence')
        require(all(value.encode() not in data for value in sensitive if value),'Sensitive fixture value in native application persistence')
    print('Native persistence audit: '+str(len(contents))+' application data files inspected; no fixture secret/JWT pattern found. Caches, Keychain and OS forensics are outside this check.',flush=True)
    if live_tokens:
        # The generated access/refresh tokens do not exist in compiled fixtures.
        # Search ALL private app files, including caches, for those exact bytes.
        # This complements (rather than narrows) the scoped pattern scan above.
        tokens=[value.encode() for value in live_tokens]
        count=0
        if target.startswith('emulator-'):
            for name in listing.stdout.splitlines():
                result=subprocess.run(base+['cat',name],capture_output=True,timeout=30)
                require(result.returncode==0,'Full native token scan file unreadable')
                require(all(token not in result.stdout for token in tokens),'Live session token persisted in app data/cache')
                count+=1
        else:
            for path in root.rglob('*'):
                if path.is_file() and path.resolve().is_relative_to(root):
                    with path.open('rb') as stream:
                        carry=b''
                        while True:
                            chunk=stream.read(65536)
                            if not chunk:break
                            data=carry+chunk
                            require(all(token not in data for token in tokens),'Live session token persisted in app data/cache')
                            carry=data[-max(map(len,tokens)):]
                    count+=1
        print('Full private app/cache live-token scan passed: '+str(count)+' files; exact access and refresh tokens absent. External Keychain/OS forensics not claimed.',flush=True)


def native_restart_proof(target, fixture_file, fixture, sensitive, state):
    """Actual process death/relaunch, retaining app data and the valid server JWT."""
    adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb')
    android=target.startswith('emulator-')
    witness='cp005b1-restart-'+secrets.token_hex(10)
    root=None
    def checked(args, timeout=20):
        result=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
        require(result.returncode==0,'Native process/storage command failed (details suppressed)')
        return result.stdout.strip()
    def stop():
        if android:checked([adb,'-s',target,'shell','am','force-stop','com.example.twogethera'])
        else:checked(['xcrun','simctl','terminate',target,'com.example.twogethera'])
    def launch():
        # Build/install the test-only target once. Relaunch below uses native OS
        # commands, not Flutter's build/install path, to retain the data container.
        command=['flutter','run','--debug',*(['--no-hot'] if android else []),'--no-resident','--no-pub','-d',target,
                 '-t','test_local/native_restart_probe.dart',
                 '--dart-define-from-file='+str(fixture_file)]
        child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                               bufsize=0,start_new_session=True)
        output=bytearray();pending=b'';seen=set();deadline=time.monotonic()+300
        timed_out=False
        while True:
            if time.monotonic()>deadline:
                timed_out=True;os.killpg(child.pid,signal.SIGTERM)
                try:child.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=5)
                break
            readable,_,_=select.select([child.stdout],[],[],1)
            if readable:
                chunk=os.read(child.stdout.fileno(),65536)
                if not chunk:break
                output.extend(chunk)
                if len(output)>262144:del output[:-262144]
                pending+=chunk
                lines=pending.split(b'\n');pending=lines.pop()
                for line in lines:
                    for pattern,label in [(b'Running Gradle task','building APK'),(b'Built ','built'),
                                          (b'Installing ','installing'),(b'Running Xcode build','building iOS'),
                                          (b'Waiting for another flutter command','waiting SDK startup lock'),
                                          (b'Syncing files','syncing')]:
                        if pattern in line and label not in seen:
                            seen.add(label);print('Native launcher: '+label,flush=True)
            if child.poll() is not None:
                # A detached compiler may retain the pipe. Never do an
                # unbounded blocking drain after the launcher itself exits.
                break
        code=child.wait(timeout=10)
        child.stdout.close()
        if code or timed_out:
            print('Native launcher '+('timed out at 300s' if timed_out else 'exit '+str(code))+'; sanitized tail:',flush=True)
            for line in output.decode(errors='replace').splitlines()[-20:]:
                if any(key in line for key in ('dart-defines','DART_DEFINES','CP005A_FIXTURE')):
                    print('[fixture compiler arguments suppressed]',flush=True);continue
                for value in sensitive:line=line.replace(value,'[redacted]')
                line=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[redacted-jwt]',line)
                line=re.sub(r'(?:http|ws)://127\.0\.0\.1:[0-9]+/[^\s]+','[debug-service-uri]',line)
                line=re.sub(r'[A-Za-z0-9+/=_-]{160,}','[encoded value suppressed]',line)
                print(line,flush=True)
        require(code==0 and not timed_out,'Native restart probe launch failed; see sanitized diagnostics')
    def verify_live_server_token():
        code,data,_=m['local_http'](
            m['b2'].API+'/rest/v1/rpc/account_context','POST',{},
            {'apikey':p.anon,'Authorization':'Bearer '+state['accessToken'],
             'Content-Profile':'cp004b2','Accept-Profile':'cp004b2'})
        require(code==200 and isinstance(data,dict) and data.get('user_id')==fixture['userId'],
                'Original session must remain server-valid across process restart')
    try:
        state['phase']='first';state['ready'].clear();state['passed']=False
        print('Native process proof: launching live-session phase (bounded 300s).',flush=True)
        launch()
        require(state['ready'].wait(45) and state.get('authenticated'),
                'Native live-session probe did not verify real context')
        audit_native_storage(target,sensitive,state['liveTokens'])
        verify_live_server_token()
        if android:
            base=[adb,'-s',target,'exec-out','run-as','com.example.twogethera']
            checked(base+['mkdir','-p','files'])
            checked(base+['touch','files/'+witness])
        else:
            root=Path(checked(['xcrun','simctl','get_app_container',target,'com.example.twogethera','data'])).resolve()
            (root/'Documents').mkdir(exist_ok=True)
            (root/'Documents'/witness).write_text(witness)
        stop()  # No local clear, SDK disposal, logout or Auth revocation first.
        audit_native_storage(target,sensitive,state['liveTokens'])
        print('Native process proof: terminated authenticated process; data retained.',flush=True)
        state['phase']='second';state['ready'].clear()
        if android:
            checked([adb,'-s',target,'shell','am','start','-W','-n','com.example.twogethera/.MainActivity'])
        else:
            checked(['xcrun','simctl','launch',target,'com.example.twogethera'])
        require(state['ready'].wait(45) and state.get('passed'),
                'Relaunched app restored authentication or failed protected-route denial')
        if android:checked(base+['test','-f','files/'+witness])
        else:
            after=Path(checked(['xcrun','simctl','get_app_container',target,'com.example.twogethera','data'])).resolve()
            require(after==root and (after/'Documents'/witness).read_text()==witness,
                    'App data was replaced: restart proof invalid')
        verify_live_server_token()
        audit_native_storage(target,sensitive,state['liveTokens'])
        print('NATIVE RESTART PASS: same data/witness retained; live JWT still server-valid; cold app signed out, protected route/context denied; exact tokens absent from inspected storage.',flush=True)
    finally:
        if root is not None:(root/'Documents'/witness).unlink(missing_ok=True)
        elif android:
            subprocess.run([adb,'-s',target,'exec-out','run-as','com.example.twogethera','rm','-f','files/'+witness],capture_output=True,timeout=20)
        # The debug probe is a test target, not an app feature.
        try:stop()
        except Exception:pass


def main():
    target=sys.argv[1] if len(sys.argv)>1 else 'chrome'
    flags=set(sys.argv[2:])
    restart_only='--restart-only' in flags
    adb_reverse='--adb-reverse' in flags
    require(len(flags)==len(sys.argv[2:]) and flags<= {'--restart-only','--adb-reverse'} and not (restart_only and target=='chrome'),
            'Unsupported test selection')
    android=bool(re.fullmatch(r'emulator-[0-9]+',target))
    require(not adb_reverse or android,'ADB reverse requires a local Android emulator')
    require(target=='chrome' or android or (len(target)==36 and all(c in '0123456789abcdefABCDEF-' for c in target)),'Only Chrome, local Android emulator or explicit iOS simulator UUID supported')
    if android:
        adb=Path.home()/'Library/Android/sdk/platform-tools/adb'
        state=proc([str(adb),'-s',target,'shell','getprop','ro.kernel.qemu'])
        require(state.returncode==0 and state.stdout.strip()=='1','Local Android emulator required')
    started=time.monotonic()
    print('Checking local backend preflight (no credentials printed).',flush=True)
    try:p.preflight()
    except subprocess.TimeoutExpired as error:
        command=Path(error.cmd[0]).name if isinstance(error.cmd,list) else 'subprocess'
        print('Preflight timeout in '+command+'; no command arguments printed.',flush=True)
        raise
    print('Backend preflight seconds: '+str(round(time.monotonic()-started,2)),flush=True)
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
    restart_state={'phase':'first','ready':threading.Event(),'passed':False}

    class Control(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def allowed_origin(self):
            origin=self.headers.get('Origin','')
            parsed=urllib.parse.urlsplit(origin)
            return origin if parsed.scheme=='http' and parsed.hostname in ('127.0.0.1','localhost') else None
        def headers_for(self):
            self.send_header('Content-Type','application/json')
            if self.allowed_origin():self.send_header('Access-Control-Allow-Origin',self.allowed_origin())
            self.send_header('Access-Control-Allow-Headers','content-type,x-local-proof,authorization,apikey,x-client-info,x-supabase-api-version')
            self.send_header('Access-Control-Allow-Methods','POST,OPTIONS')
            self.send_header('Cache-Control','no-store')
        def do_OPTIONS(self):
            print('Test broker CORS requested header names: '+self.headers.get('Access-Control-Request-Headers',''),flush=True)
            self.send_response(204);self.headers_for();self.end_headers()
        def do_POST(self):
            if self.path=='/auth/v1/token?grant_type=password' and self.headers.get('apikey')==nonce:
                # Controlled real HTTP failure, solely to measure UI responsiveness.
                time.sleep(2)
                self.send_response(503);self.headers_for();self.end_headers()
                self.wfile.write(b'{"msg":"Synthetic unavailable endpoint"}')
                return
            if self.headers.get('X-Local-Proof')!=nonce or self.path not in ('/functions/v1/suspend','/functions/v1/restore','/functions/v1/audit','/functions/v1/restart-phase','/functions/v1/restart-ready','/functions/v1/restart-result'):
                self.send_response(403);self.end_headers();return
            try:
                if self.path.startswith('/functions/v1/restart-'):
                    require(target!='chrome','Native restart requires native target')
                    length=int(self.headers.get('Content-Length','0'))
                    require(0<=length<=16384,'Oversized restart proof body')
                    body=json.loads(self.rfile.read(length)) if length else {}
                    reply={'ok':True}
                    if self.path.endswith('/restart-phase'):
                        reply={'phase':restart_state['phase']}
                    elif self.path.endswith('/restart-ready'):
                        require(restart_state['phase']=='first' and body.get('userId')==fixture_id and body.get('protected') is True,
                                'Restart sign-in/context did not pass')
                        for field in ('accessToken','refreshToken'):
                            require(isinstance(body.get(field),str) and bool(body[field]),'Missing live session credential')
                            secrets_to_redact.append(body[field])
                        restart_state['accessToken']=body['accessToken']
                        restart_state['liveTokens']=[body['accessToken'],body['refreshToken']]
                        restart_state['authenticated']=True;restart_state['ready'].set()
                    else:
                        restart_state['passed']=body.get('passed') is True
                        restart_state['ready'].set()
                    self.send_response(200);self.headers_for();self.end_headers()
                    self.wfile.write(json.dumps(reply).encode());return
                # Fixed fixture only: no arbitrary user IDs, SQL or scripts accepted.
                if self.path=='/functions/v1/audit':
                    require(target!='chrome','Native audit requires native target')
                    audit_native_storage(target,secrets_to_redact)
                else:
                    enabled='true' if self.path=='/functions/v1/restore' else 'false'
                    sql('BEGIN; SET LOCAL ROLE cp004b4_maintainer; SELECT cp004b4_ops.set_account_enabled('+quote(fixture_id)+','+enabled+'); RESET ROLE; COMMIT;')
                self.send_response(200);self.headers_for();self.end_headers();self.wfile.write(b'{"ok":true}')
            except Exception:
                self.send_response(500);self.end_headers()
    server=http.server.HTTPServer(('127.0.0.1',0),Control)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    local=ROOT/'.local/cp005a';local.mkdir(parents=True,exist_ok=True,mode=0o700);local.chmod(0o700)
    fixture={'url':m['b2'].API,'key':p.anon,'email':email,'password':password,'userId':fixture_id,'native':target!='chrome',
        'control':'http://127.0.0.1:'+str(server.server_port),'nonce':nonce,
        'unavailableUrl':'http://127.0.0.1:'+str(server.server_port),
        'expiryUrl':b1['API_URL'],'expiryKey':b1['ANON_KEY'],'expiryEmail':short_email,'expiryPassword':short_password}
    if android and not adb_reverse:
        # Android emulator loopback is the guest; this alias reaches the Mac.
        for field in ('url','control','expiryUrl','unavailableUrl'):
            fixture[field]=fixture[field].replace('127.0.0.1','10.0.2.2')
    definitions={'CP005A_FIXTURE':json.dumps(fixture),'LOCAL_AUTH_ENABLED':True,
        'LOCAL_SUPABASE_URL':fixture['url'],'LOCAL_SUPABASE_ANON_KEY':p.anon}
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
    print('Running '+('native restart/storage proof only (functional suite NOT rerun)' if restart_only else 'real SDK/Flutter tests')+' against guarded local fixtures; credentials suppressed.',flush=True)
    reverse_created=[]
    try:
        if adb_reverse:
            base=[str(adb),'-s',target,'reverse']
            listed=subprocess.run(base+['--list'],capture_output=True,text=True,timeout=10)
            require(listed.returncode==0,'Cannot inventory existing ADB reverse mappings')
            used={int(value) for value in re.findall(r'tcp:([0-9]+)',listed.stdout)}
            for port in (58321,55321,server.server_port):
                require(port not in used,'Refusing to overwrite an existing reverse mapping')
                result=subprocess.run(base+['tcp:'+str(port),'tcp:'+str(port)],capture_output=True,text=True,timeout=10)
                require(result.returncode==0,'Local ADB reverse setup failed')
                reverse_created.append(port)
            print('ADB loopback transport active for B.4, B.1 and the fixed-fixture broker; real Auth/RLS unchanged.',flush=True)
        code=0
        if not restart_only:
            child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            for line in child.stdout:
                # Defense in depth; application/test assertions never print tokens.
                for value in secrets_to_redact:line=line.replace(value,'[redacted]')
                line=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[redacted-jwt]',line)
                print(line,end='',flush=True)
            code=child.wait()
        if code==0 and target!='chrome':
            native_restart_proof(target,fixture_file,fixture,secrets_to_redact,restart_state)
    finally:
        for port in reversed(reverse_created):
            result=subprocess.run([str(adb),'-s',target,'reverse','--remove','tcp:'+str(port)],capture_output=True,text=True,timeout=10)
            if result.returncode:print('WARNING: own ADB mapping cleanup needs inspection',flush=True)
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
