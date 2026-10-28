#!/usr/bin/env python3
"""Real PostgreSQL proof on the existing LOCAL OrbStack/Supabase container.
No third-party Python packages; no network DSNs, hosted CLI calls or app migrations.
Only this sentinel database's cp004a schemas can be reset. Raw tokens never print.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DATABASE = 'twogethera_cp004a_proof'
SENTINEL = 'twogethera:cp004a:disposable:v1'
CONTAINER = 'supabase_db_twogethera'
DOCKER = shutil.which('docker') or '/Applications/OrbStack.app/Contents/MacOS/xbin/docker'
ENV = dict(os.environ, PATH=str(Path(DOCKER).parent) + ':' + os.environ.get('PATH', ''))
ROLES = ['cp004a_test_' + x for x in 'abcdefghijkl']
RESULTS = []
BOOTSTRAPPED = False


def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, env=ENV, timeout=45, **kw)


def preflight():
    if ENV.get('DOCKER_HOST') and not ENV['DOCKER_HOST'].startswith('unix://'):
        raise RuntimeError('Refusing a remote DOCKER_HOST override')
    info = run([DOCKER, 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'])
    if info.returncode or not info.stdout.strip().startswith('unix://'):
        raise RuntimeError('Refusing non-local Docker context')
    info = run([DOCKER, 'info', '--format', '{{.Name}} | {{.ServerVersion}} | {{.OperatingSystem}}'])
    if info.returncode or 'OrbStack' not in info.stdout:
        raise RuntimeError('Expected the existing local OrbStack engine')
    print('Engine:', info.stdout.strip())
    status = run(['supabase', 'status', '-o', 'json'], cwd=ROOT)
    if status.returncode:
        raise RuntimeError('Local supabase status failed (credentials suppressed)')
    data = json.loads(status.stdout)
    if data.get('API_URL') != 'http://127.0.0.1:54321' or '@127.0.0.1:54322/' not in data.get('DB_URL', ''):
        raise RuntimeError('Refusing unexpected Supabase endpoints')
    meta = run([DOCKER, 'inspect', CONTAINER, '--format', '{{json .Config.Labels}}'])
    if meta.returncode or json.loads(meta.stdout).get('com.supabase.cli.project') != 'twogethera':
        raise RuntimeError('Unexpected database container labels')
    print('Supabase CLI:', run(['supabase', '--version']).stdout.strip())
    print('Local endpoints verified; credentials suppressed.')


def command(db=DATABASE, role=None):
    # No URI/password/token supplied as a command argument or environment variable.
    return [DOCKER, 'exec', '-i', CONTAINER, 'psql', '-X', '-qAt', '-w', '-h', '127.0.0.1', '-U', role or 'supabase_admin',
            '-d', db, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate']


def prefix(role=None, app='cp004a_test'):
    # Restricted roles use database-specific logging defaults installed by bootstrap.
    # Admin setup also disables statement/error logging before sending SQL.
    result = ("SET statement_timeout='12s'; SET lock_timeout='10s'; "
              "SET application_name=" + quote(app) + '; ')
    if role:
        if role not in ROLES + ['cp004a_anon']:
            raise ValueError('Unrecognized synthetic role')
    else:
        result = ("SET log_statement='none'; SET log_min_error_statement='panic'; "
                  "SET log_min_duration_statement=-1; SET log_parameter_max_length=0; ") + result

    return result


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql(statement, role=None, db=DATABASE, app='cp004a_test'):
    return run(command(db, role), input=prefix(role, app) + statement + '\n')


def scalar(statement, role=None, db=DATABASE):
    p = sql(statement, role, db)
    if p.returncode:
        raise AssertionError('Unexpected SQL failure: ' + safe_error(p))
    return p.stdout.strip()


def safe_error(p):
    # Never include full stdout/stderr or statement text in a failing test report.
    match = re.search(r'(?:ERROR|FATAL):\s+([0-9A-Z]{5})\b', p.stderr)
    return match.group(1) if match else 'unclassified'


def fail(statement, role=None, code=None):
    p = sql(statement, role)
    assert p.returncode != 0, 'Unexpectedly permitted operation'
    if code:
        assert code in p.stderr, 'Unexpected SQLSTATE: ' + safe_error(p)


def new_id():
    return str(uuid.uuid4())


def call(role, kind, scope, payload=None, op=None, app='cp004a_test'):
    op = op or new_id()
    statement = rpc(op, kind, scope, payload)
    p = sql(statement, role, app=app)
    if p.returncode:
        raise AssertionError('Command denied unexpectedly: ' + safe_error(p))
    return json.loads(p.stdout.strip())


def rpc(op, kind, scope, payload=None):
    return 'SELECT cp004a.command(%s::uuid,%s,%s::uuid,%s::jsonb);' % (
        quote(op), quote(kind), quote(scope), quote(json.dumps(payload or {})))


def expect_call_denied(role, kind, scope, payload=None, op=None, code='42501'):
    fail(rpc(op or new_id(), kind, scope, payload), role, code)


def space(role):
    c = new_id()
    call(role, 'create', c)
    return c


def invite(role, c, recipient):
    return call(role, 'invite', c, {'epoch': 1, 'recipient': recipient + '@example.invalid'})


def pair(a, b):
    c = space(a)
    recipient = b.removeprefix('cp004a_test_')
    token = invite(a, c, recipient)['token']
    call(b, 'accept', c, {'token': token})
    return c


def reset():
    global BOOTSTRAPPED
    # CREATE DATABASE cannot be transactional. Refuse collisions without our sentinel.
    existing = scalar("SELECT shobj_description(oid,'pg_database') FROM pg_database WHERE datname=" + quote(DATABASE), db='postgres')
    exists = scalar('SELECT count(*) FROM pg_database WHERE datname=' + quote(DATABASE), db='postgres')
    if exists == '1':
        if existing != SENTINEL:
            raise RuntimeError('Refusing existing database without exact disposable sentinel')
    else:
        scalar('CREATE DATABASE ' + DATABASE + '; COMMENT ON DATABASE ' + DATABASE + ' IS ' + quote(SENTINEL) + ';', db='postgres')
    if not BOOTSTRAPPED:
        # Roles are cluster-wide but uniquely prefixed sentinel fixtures. Never replace
        # existing unrelated roles or silently strip privileges from preexisting roles.
        for role in ['cp004a_owner', 'cp004a_client', 'cp004a_anon'] + ROLES:
            count = scalar('SELECT count(*) FROM pg_roles WHERE rolname=' + quote(role))
            if count == '0':
                scalar('CREATE ROLE ' + role + ' NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT; '
                       'COMMENT ON ROLE ' + role + ' IS ' + quote(SENTINEL) + ';')
            check = scalar("SELECT (NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication)"
                           " AND shobj_description(oid,'pg_authid')=" + quote(SENTINEL) + ' FROM pg_roles WHERE rolname=' + quote(role))
            if check != 't':
                raise RuntimeError('Unexpected role collision or attributes: ' + role)
            if role in ['cp004a_owner','cp004a_client'] and scalar('SELECT rolcanlogin FROM pg_roles WHERE rolname='+quote(role)) != 'f':
                raise RuntimeError('Owner/group role unexpectedly permits login')
            if role in ROLES + ['cp004a_anon']:
                # Genuine restricted connections over the container-local trusted loopback
                # connection. No password or host authentication flow is created.
                scalar('ALTER ROLE ' + role + " LOGIN PASSWORD NULL; GRANT CONNECT ON DATABASE " + DATABASE + ' TO ' + role + ';')
                for setting, value in [('log_statement','none'),('log_min_error_statement','panic'),
                                       ('log_min_duration_statement','-1'),('log_parameter_max_length','0')]:
                    scalar('ALTER ROLE ' + role + ' IN DATABASE ' + DATABASE + ' SET ' + setting + ' TO ' + quote(value) + ';')

        scalar('REVOKE ALL ON DATABASE ' + DATABASE + ' FROM PUBLIC; GRANT CONNECT ON DATABASE ' + DATABASE + ' TO cp004a_owner;')
        for role in ROLES:
            scalar('GRANT cp004a_client TO ' + role + ';')
        membership = scalar("SELECT count(*) FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member "
                            "JOIN pg_roles p ON p.oid=m.roleid WHERE r.rolname LIKE 'cp004a_%' "
                            "AND NOT (r.rolname ~ '^cp004a_test_[a-l]$' AND p.rolname='cp004a_client')")
        if membership != '0':
            raise RuntimeError('Unexpected role inheritance')
        BOOTSTRAPPED = True
    p = sql((HERE / 'schema.sql').read_text())
    if p.returncode:
        raise RuntimeError('Schema installation failed: ' + safe_error(p))
    for i, role in enumerate(ROLES):
        scalar('INSERT INTO cp004a_private.identities(role_name,email,verified) VALUES (' +
               quote(role) + ',' + quote(role[-1] + '@example.invalid') + ',' + ('false' if i == 11 else 'true') + ');')


def test(name, body):
    reset()
    body()
    RESULTS.append(name)
    print('PASS:', name, flush=True)


def hold(statement, role=None):
    p = subprocess.Popen(command(role=role), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, env=ENV)
    p.stdin.write(prefix(role, 'cp004a_blocker') + 'BEGIN;\n\\o /dev/null\n' + statement + '\n\\o\n\\echo HOLD_READY\n')
    p.stdin.flush()
    # statement_timeout bounds SQL; select bounds a dead container/client too.
    import select
    deadline = time.monotonic() + 18
    while time.monotonic() < deadline:
        ready, _, _ = select.select([p.stdout], [], [], 1)
        if ready:
            line = p.stdout.readline()
            if line.strip() == 'HOLD_READY':
                return p
            if line == '' and p.poll() is not None:
                break
    p.kill()
    raise AssertionError('Blocker failed before deterministic race barrier')


def release(p):
    out, err = p.communicate('COMMIT;\n', timeout=18)
    if p.returncode:
        raise AssertionError('Blocker commit failed (sensitive error suppressed)')


def race(cases, scopes, blocker=None):
    blocker = blocker or hold('SELECT id FROM cp004a.spaces WHERE id IN (' + ','.join(quote(c) for c in scopes) + ') ORDER BY id FOR UPDATE;')
    names = ['cp004a_race_' + str(i) for i in range(len(cases))]
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(cases)) as pool:
            fs = [pool.submit(sql, stmt, role, DATABASE, name) for (role, stmt), name in zip(cases, names)]
            deadline = time.monotonic() + 7
            while time.monotonic() < deadline:
                n = int(scalar("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND application_name IN (" + ','.join(quote(n) for n in names) + ');'))
                if n == len(cases):
                    break
                if any(f.done() for f in fs):
                    raise AssertionError('Race participant did not reach lock barrier')
                time.sleep(.02)
            else:
                raise AssertionError('Independent connections did not overlap at observed DB locks')
            release(blocker)
            blocker = None
            return [f.result(timeout=18) for f in fs]
    finally:
        if blocker:
            blocker.kill()
            blocker.communicate()


def t_roles():
    assert scalar("SELECT NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole FROM pg_roles WHERE rolname=current_user", ROLES[0]) == 't'
    assert scalar('SELECT session_user=current_user AND current_user=' + quote(ROLES[0]), ROLES[0]) == 't'
    fail('SET ROLE cp004a_owner;', ROLES[0], '42501')
    fail('SET SESSION AUTHORIZATION cp004a_test_b;', ROLES[0], '42501')
    fail('SELECT * FROM cp004a_private.identities;', ROLES[0], '42501')
    assert scalar("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('cp004a','cp004a_private') AND c.relkind='r' AND NOT c.relrowsecurity") == '0'
    assert scalar("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('cp004a','cp004a_private') AND p.prosecdef AND NOT ('search_path=\"\"'=ANY(p.proconfig))") == '0'


def t_reads():
    a,b,c,d=ROLES[:4];s=pair(a,b);other=pair(c,d)
    rid=new_id();call(a,'put',s,{'epoch':2,'id':rid,'body':'SYNTHETIC_A'})
    call(c,'put',other,{'epoch':2,'id':new_id(),'body':'SYNTHETIC_OTHER'})
    assert scalar('SELECT count(*) FROM cp004a.records;', b)=='1'
    assert scalar('SELECT count(*) FROM cp004a.records WHERE couple_id='+quote(s)+';', c)=='0'
    assert scalar('SELECT count(*) FROM cp004a.memberships;', a)=='2'
    assert scalar('SELECT count(*) FROM cp004a.spaces;',a)=='1'
    expect_call_denied(c,'edit',s,{'epoch':2,'id':rid,'body':'INTRUSION','revision':1})
    expect_call_denied(c,'remove',s,{'epoch':2,'id':rid,'revision':1})


def t_anon_and_dml():
    s=pair(ROLES[0],ROLES[1])
    call(ROLES[0],'put',s,{'epoch':2,'id':new_id(),'body':'SYNTHETIC_RLS_SENTINEL'})
    fail('SELECT * FROM cp004a.records;', 'cp004a_anon','42501')
    expect_call_denied('cp004a_anon','create',new_id())
    for stmt in ['INSERT INTO cp004a.records VALUES('+quote(new_id())+','+quote(s)+",'x',1);",
                 "UPDATE cp004a.spaces SET epoch=99;", 'DELETE FROM cp004a.memberships;', 'TRUNCATE cp004a.records;']:
        fail(stmt,ROLES[0],'42501')
    # Prove RLS itself also denies mutations, independently of denied DML grants.
    scalar('GRANT INSERT,UPDATE,DELETE ON cp004a.records TO cp004a_client;')
    try:
        fail('INSERT INTO cp004a.records VALUES('+quote(new_id())+','+quote(s)+",'x',1);",ROLES[0],'42501')
        assert scalar("WITH x AS (UPDATE cp004a.records SET body='x' RETURNING *) SELECT count(*) FROM x",ROLES[0])=='0'
        assert scalar('WITH x AS (DELETE FROM cp004a.records RETURNING *) SELECT count(*) FROM x',ROLES[0])=='0'
    finally:
        scalar('REVOKE INSERT,UPDATE,DELETE ON cp004a.records FROM cp004a_client;')
    assert scalar('SELECT count(*) FROM cp004a.records;')=='1'
    assert scalar('SELECT body FROM cp004a.records;',ROLES[0])=='SYNTHETIC_RLS_SENTINEL'


def t_identity():
    a,b,c=ROLES[:3];s=space(a);i=invite(a,s,'b')
    expect_call_denied(c,'accept',s,{'token':i['token']})
    fail("SET request.jwt.claim.sub='spoof'; "+rpc(new_id(),'accept',s,{'token':i['token']}),c,'42501')
    unverified=new_id()
    expect_call_denied(ROLES[11],'create',unverified)
    scalar('UPDATE cp004a_private.identities SET verified=false WHERE role_name='+quote(b)+';')
    expect_call_denied(b,'accept',s,{'token':i['token']})
    scalar('UPDATE cp004a_private.identities SET verified=true WHERE role_name='+quote(b)+';')
    call(b,'accept',s,{'token':i['token']})
    assert scalar('SELECT count(*) FROM cp004a.memberships WHERE active;')=='2'


def t_expiry():
    a,b=ROLES[:2];s=space(a);i=invite(a,s,'b')
    scalar('UPDATE cp004a_private.invitations SET expires_at=clock_timestamp()-interval \'1 second\' WHERE id='+quote(i['invitation'])+';')
    expect_call_denied(b,'accept',s,{'token':i['token']})
    assert scalar('SELECT count(*) FROM cp004a.memberships;')=='1'
    assert scalar("SELECT state FROM cp004a_private.invitations;")=='pending'


def t_retry():
    a,b=ROLES[:2];s=new_id();op=new_id()
    first=call(a,'create',s,op=op);assert call(a,'create',s,op=op)==first
    expect_call_denied(a,'create',new_id(),op=op,code='22023')
    i=invite(a,s,'b');op=new_id();p={'token':i['token']}
    accepted=call(b,'accept',s,p,op);assert call(b,'accept',s,p,op)==accepted
    expect_call_denied(b,'accept',s,p)
    rid=new_id();op=new_id();p={'epoch':2,'id':rid,'body':'SYNTHETIC_ONCE'}
    inserted=call(a,'put',s,p,op);assert call(a,'put',s,p,op)==inserted
    expect_call_denied(a,'put',s,{**p,'body':'CHANGED'},op=op,code='22023')
    assert scalar('SELECT count(*) FROM cp004a.records;')=='1'
    assert scalar('SELECT count(*) FROM cp004a.memberships;')=='2'
    assert scalar('SELECT revision FROM cp004a.records;')=='1'


def t_mutations():
    a,b=ROLES[:2];s=pair(a,b);rid=new_id()
    call(a,'put',s,{'epoch':2,'id':rid,'body':'SYNTHETIC_V1'})
    op=new_id();p={'epoch':2,'id':rid,'body':'SYNTHETIC_V2','revision':1}
    first=call(b,'edit',s,p,op);assert call(b,'edit',s,p,op)==first
    expect_call_denied(a,'edit',s,p,code='40001')
    expect_call_denied(a,'edit',s,{**p,'revision':2,'epoch':1},code='40001')
    op=new_id();p={'epoch':2,'id':rid,'revision':2}
    first=call(a,'remove',s,p,op);assert call(a,'remove',s,p,op)==first
    assert scalar('SELECT count(*) FROM cp004a.records;')=='0'


def t_same_invite():
    a,b=ROLES[:2];s=space(a);token=invite(a,s,'b')['token']
    cases=[(b,rpc(new_id(),'accept',s,{'token':token})) for _ in range(2)]
    result=race(cases,[s]);assert sum(p.returncode==0 for p in result)==1
    assert all(p.returncode==0 or '42501' in p.stderr for p in result)
    assert scalar('SELECT count(*) FROM cp004a.memberships WHERE active;')=='2'
    assert scalar("SELECT count(*) FROM cp004a_private.invitations WHERE state='accepted';")=='1'


def t_same_operation_race():
    a,b=ROLES[:2];s=space(a);token=invite(a,s,'b')['token'];op=new_id()
    result=race([(b,rpc(op,'accept',s,{'token':token}))]*2,[s])
    assert all(p.returncode==0 for p in result)
    assert result[0].stdout==result[1].stdout
    assert scalar('SELECT count(*) FROM cp004a.memberships WHERE active;')=='2'
    assert scalar('SELECT count(*) FROM cp004a_private.receipts WHERE operation_id='+quote(op))=='1'


def t_two_couples():
    a,b,c=ROLES[:3];s1=space(a);s2=space(c)
    t1=invite(a,s1,'b')['token'];t2=invite(c,s2,'b')['token']
    result=race([(b,rpc(new_id(),'accept',s1,{'token':t1})),(b,rpc(new_id(),'accept',s2,{'token':t2}))],[s1,s2])
    assert sum(p.returncode==0 for p in result)==1
    assert scalar('SELECT count(*) FROM cp004a.memberships WHERE user_id=(SELECT id FROM cp004a_private.identities WHERE role_name='+quote(b)+') AND active;')=='1'
    assert scalar("SELECT count(*) FROM cp004a.spaces WHERE state='paired';")=='1'
    assert scalar("SELECT count(*) FROM cp004a_private.invitations WHERE state='pending';")=='1'


def t_constraints():
    a,b,c=ROLES[:3];s=pair(a,b)
    expect_call_denied(c,'accept',s,{'token':'0'*64})
    # Privileged fixture-only SQL proves constraints even with commands bypassed.
    cid=scalar('SELECT id FROM cp004a_private.identities WHERE role_name='+quote(c))
    fail('INSERT INTO cp004a.memberships(couple_id,user_id,seat) VALUES('+quote(s)+','+quote(cid)+',3);',code='23514')
    fail('INSERT INTO cp004a.memberships(couple_id,user_id,seat) VALUES('+quote(s)+','+quote(cid)+',2);',code='23505')
    fail('INSERT INTO cp004a.spaces(id,state) VALUES('+quote(new_id())+",'paired');",code='23514')
    expect_call_denied(a,'create',new_id(),code='23505')
    call(a,'unlink',s,{'epoch':2})
    fail("UPDATE cp004a.spaces SET state='draft',closed_at=NULL WHERE id="+quote(s)+';',code='23514')
    fail('UPDATE cp004a.memberships SET active=true WHERE couple_id='+quote(s)+';',code='23514')
    fail('UPDATE cp004a.memberships SET user_id='+quote(cid)+' WHERE couple_id='+quote(s)+' AND seat=2;',code='23514')
    expect_call_denied(c,'accept',s,{'token':'0'*64})


def t_revocation():
    a,b=ROLES[:2];s=pair(a,b);rid=new_id();op=new_id();p={'epoch':2,'id':rid,'body':'SYNTHETIC_SECRET'}
    call(a,'put',s,p,op)
    call(b,'unlink',s,{'epoch':2})  # either partner, not creator-only
    assert scalar('SELECT count(*) FROM cp004a.records;',b)=='0'
    assert scalar('SELECT count(*) FROM cp004a.records;',a)=='0'
    expect_call_denied(a,'put',s,p,op=op)
    expect_call_denied(b,'put',s,{'epoch':2,'id':new_id(),'body':'LATE'})


def t_revocation_race():
    a,b=ROLES[:2];s=pair(a,b)
    blocker=hold(rpc(new_id(),'unlink',s,{'epoch':2}),b)
    result=race([(a,rpc(new_id(),'put',s,{'epoch':2,'id':new_id(),'body':'TOO_LATE'}))],[s],blocker)
    assert result[0].returncode!=0 and '42501' in result[0].stderr
    assert scalar('SELECT count(*) FROM cp004a.records;')=='0'
    assert scalar('SELECT count(*) FROM cp004a.memberships WHERE active;')=='0'


def t_rollback():
    a,b=ROLES[:2];s=space(a);token=invite(a,s,'b')['token'];op=new_id()
    fail('BEGIN; '+rpc(op,'accept',s,{'token':token})+" SELECT 1/0; COMMIT;",b,'22012')
    assert scalar('SELECT count(*) FROM cp004a.memberships;')=='1'
    assert scalar("SELECT state FROM cp004a_private.invitations;")=='pending'
    assert scalar('SELECT count(*) FROM cp004a_private.receipts WHERE operation_id='+quote(op))=='0'
    call(b,'accept',s,{'token':token},op)


def t_secrets():
    a=ROLES[0];s=space(a);i=invite(a,s,'b')
    assert len(i['token'])==64
    assert scalar("SELECT octet_length(token_hash) FROM cp004a_private.invitations;")=='32'
    assert scalar('SELECT count(*) FROM cp004a_private.receipts WHERE result::text LIKE '+quote('%'+i['token']+'%'))=='0'
    retry_count=scalar('SELECT count(*) FROM cp004a_private.invitations;')
    assert retry_count=='1'
    for table in ['invitations','receipts','identities']:
        fail('SELECT * FROM cp004a_private.'+table+';',a,'42501')
    # Malicious search_path cannot replace qualified helpers/relations.
    assert scalar("SET search_path=pg_temp; SELECT cp004a.can_read("+quote(s)+');',a)=='t'



def t_replaced_invite():
    a,b=ROLES[:2];s=space(a);old=invite(a,s,'b');new=invite(a,s,'b')
    expect_call_denied(b,'accept',s,{'token':old['token']})
    call(b,'accept',s,{'token':new['token']})
    assert scalar("SELECT count(*) FROM cp004a_private.invitations WHERE state='revoked';")=='1'


def t_mutation_race():
    a,b=ROLES[:2];s=pair(a,b);op=new_id();rid=new_id()
    stmt=rpc(op,'put',s,{'epoch':2,'id':rid,'body':'SYNTHETIC_RACE_ONCE'})
    result=race([(a,stmt),(a,stmt)],[s])
    assert all(p.returncode==0 for p in result)
    assert result[0].stdout==result[1].stdout
    assert scalar('SELECT count(*) FROM cp004a.records;')=='1'
    assert scalar('SELECT revision FROM cp004a.records;')=='1'


def t_failed_mutation_atomicity():
    a,b=ROLES[:2];s=pair(a,b);op=new_id();rid=new_id()
    expect_call_denied(a,'put',s,{'epoch':2,'id':rid,'body':''},op=op,code='23514')
    assert scalar('SELECT count(*) FROM cp004a.records;')=='0'
    assert scalar('SELECT count(*) FROM cp004a_private.receipts WHERE operation_id='+quote(op))=='0'
    call(a,'put',s,{'epoch':2,'id':rid,'body':'SYNTHETIC_RETRY_AFTER_ROLLBACK'},op)

def main():
    preflight()
    print('PostgreSQL:',scalar('SHOW server_version;',db='postgres'))
    tests=[('restricted roles and catalog',t_roles),('member reads and cross-couple isolation',t_reads),
           ('anonymous, grants and independent RLS DML denial',t_anon_and_dml),
           ('verified binding and identity-spoof rejection',t_identity),('expired invitation atomic denial',t_expiry),
           ('operation replay and payload collision',t_retry),('authorized mutations and stale preconditions',t_mutations),
           ('database capacity, state and historical-seat constraints',t_constraints),
           ('either-partner unlink and receipt revocation',t_revocation),('transaction rollback and safe retry',t_rollback),
           ('token secrecy and qualified helpers',t_secrets),
           ('replaced invitation token rejection',t_replaced_invite),
           ('failed mutation leaves no effect or receipt',t_failed_mutation_atomicity)]
    for name,fn in tests:
        test(name,fn)
    # Repeat actual independent-connection lock-barrier races across fresh fixtures.
    for i in range(3):
        for name,fn in [('single-use concurrent acceptance',t_same_invite),
                        ('same-operation concurrent acceptance',t_same_operation_race),
                        ('one-account concurrent two-space acceptance',t_two_couples),
                        ('unlink wins blocked shared-write race',t_revocation_race),
                        ('same-operation concurrent shared mutation',t_mutation_race)]:
            test(name+' [round '+str(i+1)+']',fn)
    print('RESULT:',len(RESULTS),'/',len(tests)+15,'test scenarios passed; no skipped tests.')
    print('Only disposable database:',DATABASE,'was reset. Existing Supabase app database unchanged.')


if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        # Avoid printing SQL payloads, tracebacks containing tokens, or local credentials.
        print('FAIL:',type(exc).__name__,str(exc) if isinstance(exc,(RuntimeError,AssertionError)) else 'sensitive detail suppressed',file=sys.stderr)
        sys.exit(1)
