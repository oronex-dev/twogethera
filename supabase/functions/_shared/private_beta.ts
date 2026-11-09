import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

type DeletionClaim = {
  request_id: string;
  user_id: string;
  avatar_object_path: string | null;
};

function isMissingStorageObject(error: unknown): boolean {
  const value = error as { statusCode?: string; status?: number; message?: string };
  return value?.statusCode === '404' || value?.status === 404 ||
    (typeof value?.message === 'string' && value.message.toLowerCase().includes('not found'));
}

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

  if (claim.avatar_object_path) {
    if (!claim.avatar_object_path.startsWith(`${claim.user_id}/`)) {
      return await fail('unknown');
    }
    const { error: storageError } = await admin.storage
      .from('profile-photos')
      .remove([claim.avatar_object_path]);
    if (storageError && !isMissingStorageObject(storageError)) {
      return await fail('auth_admin_unavailable');
    }
  }

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
  object_manifest: Array<{ bucket_id: string; object_path: string }>;
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
    let storageRemoved = true;
    const byBucket = new Map<string, string[]>();
    for (const item of job.object_manifest ?? []) {
      const paths = byBucket.get(item.bucket_id) ?? [];
      paths.push(item.object_path);
      byBucket.set(item.bucket_id, paths);
    }
    for (const [bucket, paths] of byBucket) {
      const { error: storageError } = await admin.storage.from(bucket).remove(paths);
      if (storageError && !isMissingStorageObject(storageError)) storageRemoved = false;
    }

    const { data: finished, error: finishError } = await admin.rpc(
      'finish_lifecycle_purge_job',
      {
        p_job_id: job.job_id,
        p_storage_removed: storageRemoved,
        p_error_code: storageRemoved ? null : 'storage_delete_failed',
      },
    );
    if (finishError || finished !== true) failed++;
    else completed++;
  }
  return { claimed: jobs.length, completed, failed };
}
