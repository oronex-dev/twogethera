#!/usr/bin/env python3
"""Start only the disposable CP-004B.3 project. Never print generated keys."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent
DOCKER=shutil.which('docker') or '/Applications/OrbStack.app/Contents/MacOS/xbin/docker'
ENV=dict(os.environ,PATH=str(Path(DOCKER).parent)+':'+os.environ.get('PATH',''))
NETWORK='twogethera_b3_loopback'


def run(cmd):
    return subprocess.run(cmd,env=ENV,capture_output=True,text=True,timeout=240)


def main():
    if ENV.get('DOCKER_HOST') and not ENV['DOCKER_HOST'].startswith('unix://'):
        raise RuntimeError('Remote Docker override refused')
    p=run([DOCKER,'context','inspect','--format','{{.Endpoints.docker.Host}}'])
    if p.returncode or not p.stdout.strip().startswith('unix://'):
        raise RuntimeError('Local Docker engine required')
    p=run(['supabase','--version'])
    if p.returncode or p.stdout.strip()!='2.122.0':
        raise RuntimeError('Review toolchain first: this proof was tested with CLI 2.122.0')
    local=HERE/'supabase/.local';local.mkdir(mode=0o700,exist_ok=True);local.chmod(0o700)
    key=local/'signing_keys.json'
    if not key.exists():
        p=run(['supabase','gen','signing-key','--algorithm','ES256'])
        if p.returncode:raise RuntimeError('Local signing-key generation failed (output suppressed)')
        value=json.loads(p.stdout)
        # The CLI generator returns a JWK; signing_keys_path consumes a JWK array.
        if isinstance(value,dict) and 'keys' in value:value=value['keys']
        if isinstance(value,dict):value=[value]
        if not isinstance(value,list):raise RuntimeError('Unexpected local key format')
        fd=os.open(key,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(fd,'w') as f:json.dump(value,f)
    key.chmod(0o600)
    p=run([DOCKER,'network','inspect',NETWORK])
    if p.returncode:
        p=run([DOCKER,'network','create','--driver','bridge','--opt',
               'com.docker.network.bridge.host_binding_ipv4=127.0.0.1',NETWORK])
        if p.returncode:raise RuntimeError('Isolated loopback network creation failed')
    p=run([DOCKER,'network','inspect',NETWORK])
    data=json.loads(p.stdout)[0]
    if data['Driver']!='bridge' or data.get('Options',{}).get('com.docker.network.bridge.host_binding_ipv4')!='127.0.0.1':
        raise RuntimeError('Refusing unexpected network binding configuration')
    p=run(['supabase','start','--workdir',str(HERE),'--network-id',NETWORK,'--exclude',
           'studio,postgres-meta,realtime,storage-api,imgproxy,edge-runtime,logflare,vector,supavisor'])
    if p.returncode:raise RuntimeError('Isolated startup failed; no secrets printed, inspect safe service diagnostics')
    print('Isolated CP-004B.3 stack ready; key material and startup credentials suppressed.')
    print('Run: rtk proxy python3 -u proofs/cp004b3-rehearsal/run_tests.py')


if __name__=='__main__':
    try:main()
    except Exception as exc:
        print('FAIL:',str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__+' (sensitive detail suppressed)',file=sys.stderr)
        sys.exit(1)
