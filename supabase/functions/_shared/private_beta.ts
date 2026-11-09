import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

type DeletionClaim = {
  request_id: string;
  user_id: string;
};

export async function processAccountDeletion(
  admin: SupabaseClient,
  requestId: string,
): Promise<'completed' | 'busy' | 'failed'> {
  const { data, error } = await admin.rpc('claim_account_deletion', {
    p_request_id: requestId,
  });
  if (error) return 'failed';
  const claim = (Array.isArray(data) ? data[0] : data) as DeletionClaim | null;
  if (!claim?.request_id || !claim.user_id) return 'busy';

  const fail = async (code: string): Promise<'failed'> => {
    await admin.rpc('mark_account_deletion_failed', {
      p_request_id: claim.request_id,
      p_failure_code: code,
    });
    return 'failed';
  };

  const { error: deleteError } = await admin.auth.admin.deleteUser(claim.user_id);
  const deleteStatus = (deleteError as { status?: number } | null)?.status;
  const deleteCode = (deleteError as { code?: string } | null)?.code;
  if (deleteError && deleteStatus !== 404 && deleteCode !== 'user_not_found') {
    return await fail('auth_delete_rejected');
  }

  const { data: completed, error: completionError } = await admin.rpc(
    'mark_account_deletion_complete',
    { p_request_id: claim.request_id },
  );
  return completionError || completed !== true ? 'failed' : 'completed';
}

type PurgeJob = {
  job_id: string;
  job_kind: string;
  couple_id: string;
  target_table: string | null;
  target_id: string | null;
};

export async function processLifecyclePurgeBatch(
  admin: SupabaseClient,
): Promise<{ claimed: number; completed: number; failed: number }> {
  const { data, error } = await admin.rpc('claim_lifecycle_purge_jobs', {
    p_limit: 20,
  });
  if (error) return { claimed: 0, completed: 0, failed: 1 };
  const jobs = (data ?? []) as PurgeJob[];
  let completed = 0;
  let failed = 0;

  for (const job of jobs) {
    const { data: finished, error: finishError } = await admin.rpc(
      'finish_lifecycle_purge_job',
      { p_job_id: job.job_id },
    );
    if (finishError || finished !== true) failed++;
    else completed++;
  }
  return { claimed: jobs.length, completed, failed };
}
