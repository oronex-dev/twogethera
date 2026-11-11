-- Included by run_tests.py inside a transaction together with migration 034.
-- The runner supplies a random marker and rolls back all DDL and test inserts.
CREATE TEMP TABLE cp034_fixture ON COMMIT DROP AS
SELECT c.id AS couple_id,
       m1.user_id AS seat1_user_id,
       m2.user_id AS seat2_user_id,
       m1.user_id AS actor_user_id,
       b.id AS budget_id,
       b.month_start,
       b.currency_code,
       b.currency_exponent
FROM public.couple_spaces c
JOIN public.couple_memberships m1
  ON m1.couple_id = c.id AND m1.seat = 1 AND m1.state = 'active'
JOIN public.couple_memberships m2
  ON m2.couple_id = c.id AND m2.seat = 2 AND m2.state = 'active'
JOIN app_private.private_beta_allowlist a1
  ON a1.user_id = m1.user_id AND a1.slot = m1.seat
JOIN app_private.private_beta_allowlist a2
  ON a2.user_id = m2.user_id AND a2.slot = m2.seat
JOIN auth.users u1
  ON u1.id = m1.user_id AND u1.email_confirmed_at IS NOT NULL
 AND (u1.banned_until IS NULL OR u1.banned_until <= statement_timestamp())
JOIN auth.users u2
  ON u2.id = m2.user_id AND u2.email_confirmed_at IS NOT NULL
 AND (u2.banned_until IS NULL OR u2.banned_until <= statement_timestamp())
JOIN public.couple_budgets b
  ON b.couple_id = c.id AND b.limit_minor >= 4
WHERE c.state = 'paired'
  AND (SELECT count(*) FROM public.couple_memberships mx
       WHERE mx.couple_id = c.id AND mx.state = 'active') = 2
LIMIT 2;

DO $fixture$
BEGIN
  IF (SELECT count(*) FROM pg_temp.cp034_fixture) <> 1 THEN
    RAISE EXCEPTION 'CP034 requires exactly one eligible local beta fixture';
  END IF;
END
$fixture$;

GRANT SELECT ON TABLE pg_temp.cp034_fixture TO authenticated;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', actor_user_id::text,
    'role', 'authenticated',
    'exp', (floor(extract(epoch FROM statement_timestamp()) + 3600))::bigint::text
  )::text,
  true
)
FROM pg_temp.cp034_fixture;
SELECT set_config('request.jwt.claim.sub', actor_user_id::text, true)
FROM pg_temp.cp034_fixture;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $tests$
DECLARE
  v_table text;
  v_case text;
  v_sql text;
  v_title text;
  v_couple uuid;
  v_seat1 uuid;
  v_seat2 uuid;
  v_budget uuid;
  v_month date;
  v_currency text;
  v_exponent smallint;
  v_a uuid;
  v_b uuid;
  v_payer uuid;
  v_sqlstate text;
  v_rows bigint;
  v_marker text := '__CP034_MARKER__';
BEGIN
  SELECT couple_id, seat1_user_id, seat2_user_id, budget_id,
         month_start, currency_code, currency_exponent
    INTO v_couple, v_seat1, v_seat2, v_budget, v_month, v_currency, v_exponent
    FROM pg_temp.cp034_fixture;

  FOREACH v_table IN ARRAY ARRAY['couple_expenses', 'recurring_expense_rules'] LOOP
    FOREACH v_case IN ARRAY ARRAY[
      'normal_order', 'reversed_order', 'duplicate_participants',
      'outsider_participant', 'nonmember_payer', 'missing_participant'
    ] LOOP
      v_a := v_seat1;
      v_b := v_seat2;
      v_payer := v_seat1;
      IF v_case = 'reversed_order' THEN
        v_a := v_seat2;
        v_b := v_seat1;
      ELSIF v_case = 'duplicate_participants' THEN
        v_b := v_a;
      ELSIF v_case = 'outsider_participant' THEN
        v_a := gen_random_uuid();
      ELSIF v_case = 'nonmember_payer' THEN
        v_payer := gen_random_uuid();
      ELSIF v_case = 'missing_participant' THEN
        v_a := NULL;
      END IF;

      v_title := v_marker || ':' || v_table || ':' || v_case;
      IF v_table = 'couple_expenses' THEN
        v_sql := 'INSERT INTO public.couple_expenses '
          || '(couple_id,budget_id,title,description,amount_minor,currency_code,'
          || 'currency_exponent,occurred_on,category_key,paid_by_user,split_mode,'
          || 'split_a_user_id,split_a_minor,split_b_user_id,split_b_minor) '
          || 'VALUES ($1,$2,$3,'''',2,$4,$5,$6,''other'',$7,''equal'',$8,1,$9,1)';
      ELSE
        v_sql := 'INSERT INTO public.recurring_expense_rules '
          || '(couple_id,title,description,amount_minor,currency_code,currency_exponent,'
          || 'category_key,paid_by_user,split_a_user_id,split_a_minor,split_b_user_id,'
          || 'split_b_minor,frequency,starts_on) '
          || 'VALUES ($1,$2,'''',2,$3,$4,''other'',$5,$6,1,$7,1,''monthly'',$8)';
      END IF;

      IF v_case IN ('normal_order','reversed_order') THEN
        IF v_table = 'couple_expenses' THEN
          EXECUTE v_sql USING v_couple, v_budget, v_title, v_currency, v_exponent,
            v_month, v_payer, v_a, v_b;
        ELSE
          EXECUTE v_sql USING v_couple, v_title, v_currency, v_exponent,
            v_payer, v_a, v_b, v_month;
        END IF;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'CP034 valid participant ordering did not insert';
        END IF;
        RAISE NOTICE 'CP034 PASS: % / %', v_table, v_case;
      ELSE
        v_sqlstate := NULL;
        BEGIN
          IF v_table = 'couple_expenses' THEN
            EXECUTE v_sql USING v_couple, v_budget, v_title, v_currency, v_exponent,
              v_month, v_payer, v_a, v_b;
          ELSE
            EXECUTE v_sql USING v_couple, v_title, v_currency, v_exponent,
              v_payer, v_a, v_b, v_month;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
        END;
        IF v_sqlstate IS DISTINCT FROM '42501' THEN
          RAISE EXCEPTION 'CP034 expected denial missing or incorrect for % / % (SQLSTATE %)',
            v_table, v_case, coalesce(v_sqlstate, 'none');
        END IF;
        RAISE NOTICE 'CP034 PASS: % / % rejected (42501)', v_table, v_case;
      END IF;
    END LOOP;
  END LOOP;
END
$tests$;
