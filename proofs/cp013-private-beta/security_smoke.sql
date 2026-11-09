-- Transactional local-only security smoke test. All mutations are rolled back.
-- Identity claims are simulated under the restricted authenticated role; this
-- is not evidence of a signed Auth JWT or hosted Supabase behavior.
BEGIN;
DO $fixture$
DECLARE
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_couple uuid;
BEGIN
  SELECT user_id INTO v_a FROM app_private.private_beta_allowlist WHERE slot=1;
  SELECT user_id INTO v_b FROM app_private.private_beta_allowlist WHERE slot=2;
  IF v_a IS NULL OR v_b IS NULL OR v_a=v_b OR
     (SELECT count(*) FROM app_private.private_beta_allowlist)<>2 THEN
    RAISE EXCEPTION 'private beta allowlist must contain exactly two accounts';
  END IF;
  SELECT couple_id INTO v_couple FROM public.couple_memberships
   WHERE user_id=v_a AND state='active';
  IF v_couple IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.couple_memberships
     WHERE couple_id=v_couple AND user_id=v_b AND state='active'
  ) THEN RAISE EXCEPTION 'the existing approved pair is not active'; END IF;
  SELECT id INTO v_c FROM auth.users
   WHERE id NOT IN (v_a,v_b) ORDER BY created_at LIMIT 1;
  IF v_c IS NULL THEN RAISE EXCEPTION 'no unrelated synthetic account exists for denial check'; END IF;
  PERFORM set_config('qa.user_a',v_a::text,true);
  PERFORM set_config('qa.user_b',v_b::text,true);
  PERFORM set_config('qa.user_c',v_c::text,true);
  PERFORM set_config('qa.couple_id',v_couple::text,true);
  PERFORM set_config('request.jwt.claims','{}',true);
END
$fixture$;
SET LOCAL ROLE authenticated;

DO $paired_and_restore$
DECLARE
  v_a uuid := current_setting('qa.user_a')::uuid;
  v_b uuid := current_setting('qa.user_b')::uuid;
  v_couple uuid := current_setting('qa.couple_id')::uuid;
  v_item uuid;
  v_revision bigint;
  v_privacy_item uuid;
  v_claims jsonb;
  v_restored boolean;
BEGIN
  v_claims:=jsonb_build_object(
    'sub',v_a,'role','authenticated',
    'exp',floor(extract(epoch FROM statement_timestamp()))::bigint+600,
    'amr',jsonb_build_array(jsonb_build_object(
      'method','password',
      'timestamp',floor(extract(epoch FROM statement_timestamp()))::bigint
    ))
  );
  PERFORM set_config('request.jwt.claims',v_claims::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_a::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  INSERT INTO public.bucket_list_items(couple_id,title)
    VALUES(v_couple,'CP013 rollback ordinary recovery')
    RETURNING id,revision INTO v_item,v_revision;
  BEGIN
    DELETE FROM public.bucket_list_items WHERE id=v_item;
    RAISE EXCEPTION 'direct bucket-list DELETE unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM public.delete_bucket_list_item(v_couple,v_item,v_revision);
  IF NOT EXISTS (SELECT 1 FROM public.list_my_recoverable_shared_records()
                 WHERE target_table='bucket_list_items' AND target_id=v_item) THEN
    RAISE EXCEPTION 'ordinary delete was not listed for recovery';
  END IF;
  v_restored:=public.restore_my_shared_record('bucket_list_items',v_item);
  IF NOT v_restored OR NOT EXISTS (
    SELECT 1 FROM public.bucket_list_items WHERE id=v_item
  ) THEN RAISE EXCEPTION 'ordinary restore did not make the row visible'; END IF;

  INSERT INTO public.bucket_list_items(couple_id,title)
    VALUES(v_couple,'CP013 rollback privacy removal') RETURNING id INTO v_privacy_item;
  PERFORM public.record_my_privacy_removal(
    gen_random_uuid(),'bucket_list_items',v_privacy_item,NULL,true
  );
  IF EXISTS (SELECT 1 FROM public.bucket_list_items WHERE id=v_privacy_item) THEN
    RAISE EXCEPTION 'privacy-removed content remained visible';
  END IF;
  IF public.restore_my_shared_record('bucket_list_items',v_privacy_item) THEN
    RAISE EXCEPTION 'privacy-removed content was restorable';
  END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_b,'role','authenticated',
    'exp',floor(extract(epoch FROM statement_timestamp()))::bigint+600,
    'amr',jsonb_build_array(jsonb_build_object(
      'method','password',
      'timestamp',floor(extract(epoch FROM statement_timestamp()))::bigint
    ))
  )::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_b::text,true);
  IF NOT EXISTS (SELECT 1 FROM public.bucket_list_items
                 WHERE id=v_item AND title='CP013 rollback ordinary recovery') THEN
    RAISE EXCEPTION 'the other active partner could not read shared data';
  END IF;
END
$paired_and_restore$;

DO $closure_and_allowlist$
DECLARE
  v_a uuid := current_setting('qa.user_a')::uuid;
  v_b uuid := current_setting('qa.user_b')::uuid;
  v_c uuid := current_setting('qa.user_c')::uuid;
  v_operation uuid := gen_random_uuid();
  v_first jsonb;
  v_second jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_a,'role','authenticated',
    'exp',floor(extract(epoch FROM statement_timestamp()))::bigint+600,
    'amr',jsonb_build_array(jsonb_build_object(
      'method','password',
      'timestamp',floor(extract(epoch FROM statement_timestamp()))::bigint
    ))
  )::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_a::text,true);
  v_first:=public.close_my_couple_space(v_operation);
  v_second:=public.close_my_couple_space(v_operation);
  IF v_first->>'status'<>'closed' OR v_second->>'status'<>'closed'
     OR v_first->>'closed_at' IS DISTINCT FROM v_second->>'closed_at' THEN
    RAISE EXCEPTION 'closure was not idempotent';
  END IF;
  IF EXISTS (SELECT 1 FROM public.bucket_list_items) THEN
    RAISE EXCEPTION 'partner A retained shared planner read access after closure';
  END IF;
  BEGIN
    INSERT INTO public.bucket_list_items(couple_id,title)
      VALUES((current_setting('qa.couple_id'))::uuid,'CP013 denied after closure');
    RAISE EXCEPTION 'partner A wrote shared data after closure';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_b,'role','authenticated',
    'exp',floor(extract(epoch FROM statement_timestamp()))::bigint+600,
    'amr',jsonb_build_array(jsonb_build_object(
      'method','password',
      'timestamp',floor(extract(epoch FROM statement_timestamp()))::bigint
    ))
  )::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_b::text,true);
  IF EXISTS (SELECT 1 FROM public.bucket_list_items) THEN
    RAISE EXCEPTION 'partner B retained shared planner read access after closure';
  END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_c,'role','authenticated',
    'exp',floor(extract(epoch FROM statement_timestamp()))::bigint+600,
    'amr',jsonb_build_array(jsonb_build_object(
      'method','password',
      'timestamp',floor(extract(epoch FROM statement_timestamp()))::bigint
    ))
  )::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_c::text,true);
  IF EXISTS (SELECT 1 FROM public.bucket_list_items)
     OR has_table_privilege('authenticated','app_private.financial_audit_events','SELECT') THEN
    RAISE EXCEPTION 'unrelated account or authenticated role reached private beta data';
  END IF;
END
$closure_and_allowlist$;
ROLLBACK;
