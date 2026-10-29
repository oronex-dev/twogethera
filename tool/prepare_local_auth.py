#!/usr/bin/env python3
"""Create a review-only synthetic sign-in fixture. Never print its credentials."""
import json
from pathlib import Path
import runpy
import secrets
import sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    m=runpy.run_path(str(ROOT/'tool/run_local_auth_tests.py'));p=m['p'];p.preflight()
    email='cp005a-preview-'+secrets.token_hex(8)+'@example.invalid';password=secrets.token_urlsafe(30)
    code,user,_=p.fixture_auth('/admin/users',{'email':email,'password':password,'email_confirm':True})
    m['require'](code==200 and bool(user.get('id')),'Synthetic preview fixture failed')
    local=ROOT/'.local/cp005a';local.mkdir(parents=True,exist_ok=True,mode=0o700);local.chmod(0o700)
    for name,value in [
        ('app-defines.json',{'LOCAL_AUTH_ENABLED':True,'LOCAL_SUPABASE_ANON_KEY':p.anon}),
        ('preview-credentials.json',{'email':email,'password':password}),
    ]:
        path=local/name;path.touch(mode=0o600);path.chmod(0o600);path.write_text(json.dumps(value))
    print('Prepared synthetic preview fixture. Credentials remain in ignored owner-only .local/cp005a/preview-credentials.json.')
    print('Run: rtk proxy flutter run -d chrome --web-port 8082 --dart-define-from-file=.local/cp005a/app-defines.json')
    print('Open /#/auth/local. No server key is included in the app configuration.')

if __name__=='__main__':
    try:main()
    except Exception:print('FAIL: local preview preparation failed (sensitive details suppressed)',file=sys.stderr);sys.exit(1)
