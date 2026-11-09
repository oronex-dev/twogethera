import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  processAccountDeletion,
  processLifecyclePurgeBatch,
} from '../_shared/private_beta.ts';
import { validateProjectTarget } from '../_shared/project_target.mjs';

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
}

function matchesSecret(actual: string, expected: string): boolean {
  const left = new TextEncoder().encode(actual);
  const right = new TextEncoder().encode(expected);
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

const endpoint = required('SUPABASE_URL');
const appEnvironment = Deno.env.get('APP_ENV') ?? 'development';
validateProjectTarget(
  endpoint,
  appEnvironment,
  Deno.env.get('TWOTHERGA_EXPECTED_PROJECT_REF') ?? '',
);

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response(null, { status: 405, headers: { Allow: 'POST' } });
  }
  const expected = required('PRIVATE_BETA_JOB_TOKEN');
  const actual = request.headers.get('x-private-beta-job-token') ?? '';
  if (!matchesSecret(actual, expected)) {
    return new Response(null, { status: 404, headers: { 'Cache-Control': 'no-store' } });
  }

  const admin = createClient(
    endpoint,
    required('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
  try {
    const { data: requestIds, error: claimError } = await admin.rpc(
      'claim_due_account_deletion_ids',
      { p_limit: 20 },
    );
    if (claimError) {
      return Response.json({ code: 'maintenance_unavailable' }, { status: 503 });
    }

    let deletionsCompleted = 0;
    let deletionsFailed = 0;
    for (const requestId of (requestIds ?? []) as string[]) {
      const result = await processAccountDeletion(admin, requestId);
      if (result === 'completed') deletionsCompleted++;
      else if (result === 'failed') deletionsFailed++;
    }

    const purge = await processLifecyclePurgeBatch(admin);
    const { data: auditPurged, error: auditError } = await admin.rpc(
      'purge_expired_financial_audit',
    );
    if (auditError) {
      return Response.json({ code: 'maintenance_unavailable' }, { status: 503 });
    }
    return Response.json({
      deletionsCompleted,
      deletionsFailed,
      purgeClaimed: purge.claimed,
      purgeCompleted: purge.completed,
      purgeFailed: purge.failed,
      auditEventsPurged: Number(auditPurged ?? 0),
    }, { headers: { 'Cache-Control': 'no-store' } });
  } finally {
    await admin.dispose();
  }
});
