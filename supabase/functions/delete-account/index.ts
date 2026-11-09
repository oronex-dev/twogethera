import { createClient } from 'npm:@supabase/supabase-js@2';
import { processAccountDeletion } from '../_shared/private_beta.ts';
import {
  allowedOriginsForEnvironment,
  validateProjectTarget,
} from '../_shared/project_target.mjs';

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
}

const endpoint = required('SUPABASE_URL');
const appEnvironment = Deno.env.get('APP_ENV') ?? 'development';
validateProjectTarget(
  endpoint,
  appEnvironment,
  Deno.env.get('TWOTHERGA_EXPECTED_PROJECT_REF') ?? '',
);
const publishableKey = Deno.env.get('SUPABASE_ANON_KEY') ?? required('SUPABASE_PUBLISHABLE_KEY');
const serviceRoleKey = required('SUPABASE_SERVICE_ROLE_KEY');
const allowedOrigins = allowedOriginsForEnvironment(
  Deno.env.get('PRIVATE_BETA_ALLOWED_ORIGINS'),
  appEnvironment,
);

function corsHeaders(origin: string): HeadersInit {
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
    'Cache-Control': 'no-store',
  };
}

function json(status: number, body: Record<string, string>, origin: string): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get('origin') ?? '';
  if (!allowedOrigins.has(origin)) return new Response(null, { status: 403 });
  if (request.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(origin) });
  if (request.method !== 'POST') return json(405, { code: 'method_not_allowed' }, origin);

  const authorization = request.headers.get('authorization');
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return json(401, { code: 'authentication_required' }, origin);

  let body: { operation_id?: unknown };
  try {
    body = await request.json();
  } catch (_) {
    return json(400, { code: 'invalid_request' }, origin);
  }
  const operationId = body.operation_id;
  if (typeof operationId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(operationId)) {
    return json(400, { code: 'invalid_request' }, origin);
  }

  const userClient = createClient(endpoint, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${bearer}` } },
  });
  const admin = createClient(endpoint, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const { data: authData, error: authError } = await userClient.auth.getUser(bearer);
    if (authError || !authData.user) return json(401, { code: 'authentication_required' }, origin);

    const { data: requestId, error: requestError } = await userClient.rpc(
      'request_my_account_deletion',
      { p_operation_id: operationId },
    );
    if (requestError || typeof requestId !== 'string') {
      const message = requestError?.message.toLowerCase() ?? '';
      if (requestError?.code === '42501' && message.includes('reauthentication')) {
        return json(403, { code: 'recent_sign_in_required' }, origin);
      }
      return json(403, { code: 'deletion_unavailable' }, origin);
    }

    const result = await processAccountDeletion(admin, requestId);
    if (result === 'completed') return json(200, { status: 'completed' }, origin);
    if (result === 'busy') return json(202, { status: 'processing' }, origin);
    return json(503, { code: 'deletion_pending_retry' }, origin);
  } catch (_) {
    return json(503, { code: 'deletion_pending_retry' }, origin);
  } finally {
    await userClient.auth.signOut({ scope: 'local' }).catch(() => undefined);
  }
});
